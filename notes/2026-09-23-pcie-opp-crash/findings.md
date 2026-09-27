# 2026-09-23 — `qcom_pcie_probe` NULL-deref (OPP path) + UFS still no `sda*`: findings

> **Provenance / status of this file.** Restored on 2026-09-24 from the
> session handoff prompt, which is the authoritative record of the 2026-09-23
> investigation. `docs/01-phase1-workplan.md` already has two 2026-09-23 log
> entries (the UFS `=m` fix / v7, and the v8+v9 replay tool with the
> `adreno_smmu` red-herring correction), but they do NOT contain the
> addr2line / OPP call-chain trace below, the `_set_opp()` next step, the
> upstream-immaturity finding for the PCIe OPP feature, or the stale
> `kernel/config/dm1q.fragment` note. That gap means the original in-session
> save of these findings did not land (tool outage mid-session).
>
> Everything between the two horizontal rules is the handoff block, text
> unchanged (only the section labels were turned into headings). Anything
> learned afterwards is appended under "Follow-up" at the bottom and is
> labelled with its date; it is deliberately kept out of the verbatim block.

---

## CONTEXT

initramfs-based diagnostics (init_boot v8, then v9) were built to
capture dmesg via the framebuffer console/flash, since UFS storage and USB
gadget are both still non-functional, blocking every other log-capture
method. v8 (paginated on-screen dmesg replay) froze completely partway
through page 1 at kernel uptime ~10.46-10.47s. v9 (same, but reordered so
a flash-log background job starts before any console output, plus a
15s-delayed snapshot to span the freeze point) was built and flashed
(sha256 207474c1422c048bd4f94fd900a9783dc9390ccf86e7405f4a7fe31f36af31ad)
but had NOT been booted/tested yet as of this handoff — that's the first
thing to check.

## ROOT CAUSE, TRACED SO FAR (not yet fully resolved)

This freeze is the same NULL-pointer-dereference oops first caught (garbled,
via corrupted pstore) on 2026-09-22, ESR 0x96000004 (DABT), stack trace
bottoming out in `qcom_pcie_probe+0x1a8/0x414` via an async
`driver_probe_device` workqueue. On 2026-09-22 it did NOT panic (no
oops=panic on cmdline) and boot continued ~0.4s further; as of 2026-09-23
(v8/v9) it appears to fully freeze the system instead — unconfirmed why,
working theory is the oops happens while a lock the console subsystem also
needs (e.g. console_lock) is held, wedging all further printk/write() to
the screen. The `arm-smmu 3da0000.iommu: deferred probe timeout` /
`probe ... failed with error -110` lines that print right around the same
timestamp are a RED HERRING — 3da0000.iommu is `adreno_smmu` (confirmed
against sm8550.dtsi), the GPU's IOMMU. GPU/display was deliberately never
wired up in this project, so that SMMU sitting deferred-forever is expected
behavior, not a new bug — it's just coincidentally printing at the same
global ~10s deferred_probe_timeout mark as the real, unrelated crash.

Using the actual build artifacts at ../_scratch/linux-build/out/ (vmlinux +
System.map — confirmed to be the EXACT currently-flashed v7 kernel by
timestamp match, "Wed Sep 23 02:37:19 EEST 2026" matches the boot banner
seen on-screen), llvm-addr2line (NOT gnu addr2line — that gives a "mangled
line number section" DWARF error on this clang-built kernel, llvm-addr2line
works fine) was used to resolve the crash address:

    qcom_pcie_probe base:  0xffff8000807c4084  (System.map)
    crash offset:          +0x1a8
    crash address:         0xffff8000807c422c
    llvm-addr2line result: drivers/pci/controller/dwc/pcie-qcom.c:2246

Disassembly (llvm-objdump -d) of that address confirms it is the
RETURN ADDRESS immediately after `bl qcom_pcie_set_max_opp` — i.e. this is
qcom_pcie_probe's stack frame showing where it would resume, meaning the
actual fault is deeper, inside qcom_pcie_set_max_opp() or something it
calls. The disassembly immediately before that call also shows the
`devm_pm_opp_of_add_table()` return value being checked against -ENODEV
(`cmn w0, #0x13` / `b.eq <icc_init path>`) — that branch is NOT taken at
runtime, meaning devm_pm_opp_of_add_table() returns 0 (success) for our
&pcie0 device, DESPITE neither sm8550.dtsi nor dm1q.dts defining an
`operating-points-v2` property on the pcie0 node (grepped both, zero
matches for operating-points-v2/opp-table anywhere touching pcie0). This is
the crux of the mystery: why does the OPP-table lookup succeed with no
actual table data to find?

Following the call chain further: qcom_pcie_set_max_opp() (pcie-qcom.c,
originally ~line 1747) calls dev_pm_opp_find_freq_floor() then
dev_pm_opp_set_opp(). Repeated the same addr2line technique on
dev_pm_opp_set_opp (System.map: 0xffff800080df66a8) — the earlier garbled
2026-09-22 pstore dump had independently mentioned "dev_pm_opp_set_opp"
near a "+0x4c/0xc0"-shaped offset, which lines up with this exact call
chain. 0xffff800080df66a8+0x4c = 0xffff800080df66f4, which llvm-addr2line
resolves to drivers/opp/core.c:1485 — the `if (IS_ERR(opp_table))` check
right after `_find_opp_table(dev)`, immediately followed (per disassembly)
by `bl _set_opp` at 0xffff800080df6710. So the fault is most likely INSIDE
`_set_opp()` (drivers/opp/core.c, symbol at 0xffff800080df620c) —
THIS FUNCTION HAD NOT YET BEEN READ/DISASSEMBLED when this session ended.
That is the concrete next step: read `_set_opp()` in
../_scratch/linux-build/full/drivers/opp/core.c, and/or disassemble
0xffff800080df620c onward, to find exactly which field is NULL when
_set_opp() is called for a device whose "successful" OPP table has no real
entries.

A web search this session found that the whole "OPP support to scale
[PCIe interconnect] performance" feature in pcie-qcom.c is new and under
very active bugfixing upstream — multiple real patches from the past few
months through as recently as ~12 days before 2026-09-23, including at
least one already-fixed error-pointer-dereference bug in a *different*
function in the same feature (qcom_pcie_icc_opp_update, commit 9553636,
"PCI: qcom: Prevent potential error pointer dereference" — NOT the same bug
as ours, ours is in qcom_pcie_set_max_opp's path, but same feature area,
same general immaturity). This raises real suspicion that we've hit a
genuine, not-yet-upstreamed kernel bug (devm_pm_opp_of_add_table returning 0
instead of -ENODEV when there's truly no operating-points-v2 table, or
_set_opp() not handling an empty/table-less opp correctly) rather than
something wrong in our own devicetree — but this is NOT yet confirmed,
just a working hypothesis. Do not assume it's a kernel bug without first
ruling out a devicetree explanation.

## ALSO CONFIRMED THIS SESSION (not the crash, but relevant open context)

- &pcie0 and &pcie0_phy in dm1q.dts are BYTE-IDENTICAL to
  sm8550-samsung-q5q.dts (deliberately copied 2026-09-15/16) — so a
  straight devicetree diff against that known-upstream board found no
  differences to explain this. Worth widening the comparison beyond just
  these two nodes (e.g. interconnect provider nodes, rpmhpd, the OPP
  tables of OTHER devices that might interact) since the direct comparison
  came up empty.
- v8's on-screen [diag] block (and presumably v9's too, once tested) still
  shows ONLY loop0-loop7 in /sys/class/block/*, NO sda* — i.e. UFS is
  STILL not producing a working block device even on the v7 kernel with
  CONFIG_SCSI/CONFIG_BLK_DEV_SD/CONFIG_SCSI_UFS_QCOM/CONFIG_PHY_QCOM_QMP_UFS/
  CONFIG_QCOM_INLINE_CRYPTO_ENGINE all confirmed =y in the actual .config
  used for that build, and the &ufs_mem_hc/&ufs_mem_phy DT nodes confirmed
  near-identical to q5q's (only the expected vdda-phy-supply board
  difference). Root cause for THIS is still completely open — not yet
  connected to the PCIe crash, but worth at least stating a hypothesis
  explicitly (e.g.: could the qcom_pcie_probe crash, if it corrupts shared
  driver-core state like the deferred-probe workqueue or a global lock,
  be blocking OTHER unrelated deferred probes like UFS's own retries from
  ever completing? Untested, likely worth checking by seeing whether UFS
  starts working on a build where the PCIe crash is fixed, before chasing
  UFS as a fully separate bug).
- kernel/config/dm1q.fragment in the repo is STALE — it only has the v1-v4
  config additions in comment/CONFIG_ form. The v5 (pstore/ramoops) and v7
  (UFS: SCSI_UFS_QCOM, PHY_QCOM_QMP_UFS, QCOM_INLINE_CRYPTO_ENGINE, etc.)
  config additions were applied directly to the build tree's .config and
  only recorded as prose in docs/01-phase1-workplan.md, never written back
  into this fragment file. This should be fixed so the fragment is an
  accurate, rebuildable record — do this as a small, separate, low-risk
  cleanup, not blocking the main crash investigation.

---

## Follow-up

*(dated entries below — added after the verbatim block above was saved)*

### 2026-09-24 — RESOLVED IN SOURCE: root cause is a board-devicetree omission, not a kernel bug (v10 built + flashed, NOT yet boot-tested)

Method: static analysis only (photos, vmlinux/System.map, kernel source, compiled DTBs). Everything below about
*runtime* behaviour is derived from source + binary, not observed on hardware — the v10 boot is the experiment
that confirms or refutes it.

**Corrections to the handoff block above** (each checked against the actual artifacts):

1. *Frame offset.* The real trace tail is on `evidence/otg-keyboard.jpg` (v4-era boot):
   `dev_pm_opp_set_opp+0x6c/0xcc`, `qcom_pcie_set_max_opp+0x4c/0x88`, `qcom_pcie_probe+0x1a8/0x414`, …
   The handoff's `+0x4c/0xc0` was read out of the corrupted pstore replay (`evidence/second_boot.jpg`), so the
   "return address after `_find_opp_table`" reasoning built on it (0xffff800080df66f4) was off by 0x20. With the real
   offset, `dev_pm_opp_set_opp+0x6c` = 0xffff800080df6714, the instruction right after `bl _set_opp` (0x…6710). Symbol
   sizes in the flashed-v7 vmlinux match the photo exactly (qcom_pcie_probe 0x414, qcom_pcie_set_max_opp 0x88,
   dev_pm_opp_set_opp 0xcc), so offsets from the v4-era photo transfer to the v7 vmlinux.
2. *"`devm_pm_opp_of_add_table()` returns 0 although no `operating-points-v2` exists" was a false premise* (the
   earlier grep was truncated). The compiled DTB's `pcie@1c00000` has `operating-points-v2` with an embedded
   opp-table of 6 entries (opp-2500000-1 … opp-16000000-3; each has required-opps / opp-peak-kBps / opp-level),
   inherited from sm8550.dtsi. Returning 0 is correct; there is no OPP-core bug to find. `qcom_pcie_set_max_opp()`
   selects the 16 MHz entry.
3. *The fault is in the clock layer below `_set_opp()`, not in OPP code.*

**Exact fault site.** Oops `Code:` line `2a1f03e6 9409333d 14000012 f85f0261 (394022a2)` decodes to
`mov w6,wzr; bl <regmap_update_bits_base>; b .+0x48; ldur x1,[x19,#-16]; [ldrb w2,[x21,#8]]`. Searching the v7 `.text` for
the layout-independent words (the `bl` displacement differs between builds) gives exactly ONE match:
`__clk_rcg2_shared_set_rate+0x84` (0xffff8000808b1330, drivers/clk/qcom/clk-rcg2.c), and the four instructions before
it match one-for-one. `ldrb w2,[x21,#8]` is `f->src` (`struct freq_tbl { unsigned long freq; u8 src; … }`) with
`f == NULL` → fault address 0x8, matching "NULL pointer dereference, ESR 0x96000004". It is the branch taken when
`clk_hw_is_enabled(hw)` is false (parked RCG). The CEIL wrappers (`clk_rcg2_shared_set_rate*`) load `w2 = 1` before the
`bl`, the FLOOR wrappers (`clk_rcg2_shared_set_floor_rate*`) `w2 = 0`; in gcc-sm8550.c only `gcc_sdcc2_apps_clk_src` and
`gcc_sdcc4_apps_clk_src` use the floor ops (all other shared RCGs have non-NULL tables, so CEIL can't yield NULL).
Tool: `find_code_pattern.py` (this directory).

**Root-cause chain.**
1. `dm1q.dts` never set `&xo_board { clock-frequency = <76800000>; }` nor `&sleep_clk { clock-frequency = <32764>; }`.
   sm8550.dtsi declares both as `fixed-clock` nodes without a frequency and every upstream board file supplies them
   (checked: sm8550-hdk, -mtp, -qrd, -samsung-q5q, sony-xperia-yodo-pdx234 — all five). Without `clock-frequency`,
   `of_fixed_clk_setup()` returns -EIO and the clock is never registered; the compiled v7 DTB confirms `xo-board` and
   `sleep-clk` had no `clock-frequency`. The RPMh clock controller should still probe (its parent is a lazy
   `fw_name = "xo"` lookup; `clk_rpmh_probe()` does not `clk_get` it) but its `RPMH_CXO_CLK` is an orphan at 0 Hz, so
   the DT `bi_tcxo_div2`, every GCC PLL and every XO/PLL-parented RCG computes 0 Hz.
2. `qcom_pcie_set_max_opp()` → `dev_pm_opp_set_opp()` → `_set_opp()` → `_opp_config_clk_single()` calls
   `clk_set_rate(<pcie0's first clock>, 16000000)`: the OPP core takes `clk_get_optional(dev, NULL)` = the first `clocks`
   entry = `gcc_pcie_0_aux_clk`. (The PCIe OPP table's `opp-hz` values are abstract link-speed keys, not clock rates; on a
   healthy board the requested rate rounds to the aux clock's current 19.2 MHz and `clk_set_rate()` returns early.)
3. With the XO at 0 Hz the topmost "changing" clock becomes `bi_tcxo_div2` itself, and `clk_change_rate()` recurses through
   ALL its descendants, calling each one's `set_rate()` with a recomputed rate of 0. For a disabled/parked floor-policy
   RCG (sdcc2/sdcc4) `qcom_find_freq_floor(tbl, 0)` returns NULL and `__clk_rcg2_shared_set_rate()` dereferences it.
   (The other XO-child RCGs — CEIL policy, lowest table entry for rate 0 — would already have been re-programmed before
   the oops, so pre-fix boots were not "clean" even where nothing crashed.)
4. Upstream regression that turns this into an oops: the commit adding `clk_rcg2_shared_floor_ops` (lore: "[PATCH v4
   06/11] clk: qcom: rcg2: add clk_rcg2_shared_floor_ops", merged late 2024) split `clk_rcg2_shared_set_rate()` into
   `__clk_rcg2_shared_set_rate(..., policy)` and, while replacing the lookup with a `switch (policy)`, dropped the old
   `if (!f) return -EINVAL;` (the switch's `default:` reuses the `return -EINVAL`). `_freq_tbl_determine_rate()` still
   checks `f`. With a correct XO the path is never reached, which is why upstream boards don't oops. Worth an upstream
   patch (NULL-check `f` after the switch) — NOT applied locally; the DT fix removes the trigger.

**Second omission found by widening the comparison (as the handoff suggested).** `&qupv3_id_0` (geniqup@ac0000) is
`status = "disabled"` in sm8550.dtsi; q5q enables it, `dm1q.dts` never did. It is the wrapper for i2c4 (touch), i2c6
(the NXP PTN3222 eUSB2 repeater) and uart7 — none of them could ever probe → no repeater → USB HS PHY deferred forever →
no UDC (the "`[gadget] still waiting for a UDC`" symptom). Other nodes q5q enables that dm1q lacks (not needed yet):
pm8550vs_c/d/e/g SPMI nodes, pon_pwrkey/pon_resin, i2c_master_hub_0, remoteproc adsp/cdsp/mpss, dispcc.

**Kernel-config sweep (`=m` is a silent dead end in a module-less initramfs).** `QCOM_GPI_DMA=m` — GENI I2C needs GPI DMA when
the SE's FIFO interface is disabled by firmware (unknown for this SE) → built in for v10 as insurance;
`PHY_QCOM_QMP_PCIE=m` — pcie0 can't finish probing (harmless until WLAN work); `PHY_QCOM_QMP_USB`/`_COMBO=m` (SS PHY is disabled in
the DTS); `SM_DISPCC/GPUCC/VIDEOCC/CAMCC_8550=m`, `POWER_SEQUENCING_QCOM_WCN=m`, `QCOM_LLCC=m`, remoteproc `QCOM_Q6V5_*=m` (not needed yet).
Confirmed `=y`: SM_GCC_8550, SM_TCSRCC_8550, QCOM_CLK_RPMH, PHY_SNPS_EUSB2, PHY_NXP_PTN3222, USB_DWC3_QCOM, I2C_QCOM_GENI, QCOM_GENI_SE,
SCSI_UFS_QCOM, PHY_QCOM_QMP_UFS, QCOM_INLINE_CRYPTO_ENGINE, REGULATOR_QCOM_RPMH.

**Hypothesis bookkeeping.**
- RETRACTED: "genuine untriaged kernel bug in `devm_pm_opp_of_add_table()` / OPP core".
- STILL OPEN, untested: (a) "UFS `sda*` absence is downstream of the same cause" — plausible (0 Hz PLLs also break `clk_set_rate()` /
  `assigned-clock-rates` for UFS, USB, PCIe consumers) but unproven until v10 boots; (b) the console-lock freeze theory — the freeze may
  simply be this clock cascade; re-evaluate after v10.
- Note: v9's flash-log channel writes through the UFS block device, so it could not have worked while UFS had no `sda*`.

**v10 = v9 + this fix (built + flashed 2026-09-24; not yet booted).** Decompiled-DTB diff v7 → v10 is exactly:
`xo-board` gains `clock-frequency = <0x493e000>` (76.8 MHz), `sleep-clk` gains `<0x7ffc>` (32764 Hz), `geniqup@ac0000`
`status` disabled → okay; nothing else.
- `dts/dm1q/dm1q.dts`: `&xo_board`, `&sleep_clk`, `&qupv3_id_0` (commented inline).
- `.config`: `CONFIG_QCOM_GPI_DMA=y` (the only diff vs the v7 config). Kernel: same tree, incremental rebuild (banner `#7`).
- vendor cmdline: dropped `console=ttyMSM0,115200n8` — uart7 is real now; a live 115200-baud console on unconnected pads
  would throttle the boot. Effective console stays tty0-only, exactly as in v4–v9.
- `init_boot` (v9) and `dtbo` (v5) unchanged.
- Files: `../_scratch/boot-backup-20260920/v10-xo-geni/{boot_v10.img,vendor_boot_v10.img,Image.gz,Image.gz-dtb}`.
  sha256 boot_v10 `022b3688c4f1d309a8d85de333b6774f5ffabc4a7f265da8ef557c0b9eca5593`,
  vendor_boot_v10 `2db4170fa3e06be4290cc238e9335b547fab5b160c0197150004dce1c29ed669`, embedded DTB `72584829…`.
- Verification: the assembly recipe was first proven by rebuilding v7's boot/vendor_boot from their own unpacked parts
  (byte-identical pre-AVB regions); v10: kernel payload == Image.gz-dtb, `Image.gz` decompresses to the built Image, vendor
  ramdisk fragment + bootconfig byte-identical to v7, `avbtool verify_image` OK on both.
- Flashed from recovery: pre-flash readback == v7 set; push, device sha256 == host; write with conv=fsync to boot (sda25) and
  vendor_boot (sda28); readback verified and re-verified after `drop_caches`; init_boot still `207474c1…`, dtbo still `63852b23…`.
  Rollback = v7 set in `v7-ufs/` (boot `8e63d9d0…`, vendor_boot `6064eb3a…`).

**What the first v10 boot should show (predictions to test, not results).** No oops at ~10.47 s; `ttyMSM0`/i2c buses appear (GENI
wrapper probes); repeater + HS PHY + dwc3 probe → a UDC exists → host sees a CDC-ACM device (`/dev/ttyACM0`) with the
initramfs shell; UFS either probes (→ `sda*`, and the flash-log channel finally works) or fails with a *visible* error;
pcie0 no longer oopses but should still fail to finish probing (QMP PCIe PHY is `=m`). If any of that is wrong, the
comparison list above (qupv3, PHY `=m`, remaining q5q-only nodes) is the next place to look.

---

### 2026-09-25 -- CONFIRMED: v10 boots with no crash. Investigation continues in a new file.

v10 booted for real on 2026-09-25 (189-page on-screen dmesg capture, user-transcribed by hand). **No oops,
no panic anywhere in the log -- the predicted fix worked.** The kernel reaches a userspace shell. Two new,
unrelated findings from that same boot (an SPMI PMIC read failure, and a wrong `regulator` compatible string
blocking UFS/USB) are written up, and one of them fixed in v11, in
`../2026-09-25-v10-boot-log-analysis/findings.md` -- that file is now where this investigation continues.
This file (the OPP/clock crash itself) is closed.
