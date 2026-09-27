# v10 boot log analysis (2026-09-25/26): crash confirmed fixed, two new findings, one fixed in v11

## Provenance

v10 (the `&xo_board`/`&sleep_clk`/`&qupv3_id_0` fix, see `../2026-09-23-pcie-opp-crash/findings.md`) was
booted for the first time on 2026-09-25. The on-screen paginated `log-replay` tool (v9's init script,
unchanged in v10) produced 189 pages; the user photographed all of them (phone camera, `2026-09-25-03-44-18`
through `2026-09-25-04-09-31`) since the flash-log fallback came back empty (explained below — not a new
bug). The user then read all 189 photos by hand (not OCR, which they found unreliable on this dense
monospace text) and wrote up three findings, uploaded as `dm1q-boot-log-findings.md` and also pushed to
`https://github.com/MrCamel-Baraa/ai-sharing.git` (the raw photos + a GitHub Actions OCR workflow). The
verbatim upload is reproduced below unedited; my own follow-up is in the sections after it.

---

## User's original report (verbatim)

**Device:** Samsung Galaxy S23 (dm1q, SM8550/kalama)
**Kernel:** 7.3.0-rc3-g40280c9205c1-dirty, built Thu Sep 24 21:19:12 EEST 2026
**Source:** 189 phone-camera photos of the device screen running a `log-replay` tool that paginated the
full dmesg buffer (4674 lines total, 25 lines/page). Photos span 2026-09-25 03:44:18 to 04:09:31.
**Repo:** https://github.com/MrCamel-Baraa/ai-sharing.git

**Overall result:** The kernel boots all the way to a userspace shell — there is **no panic, no Oops, no
kernel crash** anywhere in this capture. The log ends normally with a cascade of expected
`sync_state() pending` deferred-probe housekeeping messages, then:
```
[log-replay] done.
sh: can't access tty; job control turned off
#_
```
So the actual problems below are all *why certain devices never finish probing*, not why the kernel dies.

### Finding 1 — One PMIC fails to probe over SPMI (real hardware/DT issue)

At t≈0.117s the SPMI PMIC arbiter hits a channel transaction failure while probing one specific PMIC child
device, throws a `WARN_ON` with a full backtrace, and that PMIC's probe ultimately fails outright. PMICs at
SPMI addresses **0-00, 0-01, 0-05** all probe successfully; only the PMIC at **SPMI address 0-07** fails
with **-EIO (-5)** because its channel-status register (`reg: 0x3228`) reports a failed transaction. Call
trace bottoms out in `pmic_spmi_probe+0x120/0x2e4` → `regmap_read` → `regmap_spmi_ext_read` →
`pmic_arb_read_cmd` → `pmic_arb_check_chnl_status_v1` (WARN at spmi-pmic-arb.c:316). Worth checking which
physical PMIC chip sits at USID 7.

*Source photos: `2026-09-25-04-03-00-914.jpg`, `2026-09-25-04-03-09-646.jpg`, `2026-09-25-04-03-17-772.jpg`, `2026-09-25-04-03-25-129.jpg`*

### Finding 2 — UFS and USB permanently stuck in probe-deferral (traced root cause)

Right before the log ends (t≈10.46–10.48s, the global deferred-probe timeout), the last words on UFS, USB
and their dependency chain:
```
[  10.465049] arm-smmu 3da0000.iommu: deferred probe timeout, ignoring dependency
[  10.469600] probe of a600000.usb with driver dwc3-qcom returned -517 after 2 usecs
[  10.470179] probe of 1d84000.ufshc with driver ufshcd-qcom returned -517 after 6 usecs
[  10.475218] probe of 0-004f with driver ptn3222 returned -517 after 19 usecs
[  10.477139] platform 1d84000.ufshc: deferred probe pending: platform: wait for supplier /soc@0/rsc@17a00000/regulators-0/ldo17
[  10.481840] platform 88e3000.phy: deferred probe pending: platform: supplier 0-004f not ready
[  10.482913] i2c 0-004f: deferred probe pending: i2c: wait for supplier /soc@0/rsc@17a00000/regulators-0/ldo5
```
**Read:** UFS (`1d84000.ufshc`) waits directly on regulator **`ldo17`**; USB (`a600000.usb`) waits on its
eUSB2 PHY, which waits on the **ptn3222** repeater at `0-004f`, which waits on regulator **`ldo5`**. Both
trace back to the same category: regulator child nodes `ldo17`/`ldo5` under
`/soc@0/rsc@17a00000/regulators-0` that never actually register. `arm-smmu 3da0000.iommu` separately hits
the global deferred-probe timeout and hard-fails with -110 (expected — that's `adreno_smmu`, GPU is out of
scope). `qcom-cpufreq-hw` fails on `"Failed to find icc paths"` (interconnect, separate). PCIe falls back to
dummy regulators for `vdda`/`vddpe-3v3` (degraded, not fatal).

*Source photo: `2026-09-25-04-09-11-283.jpg`*

### Finding 3 — WCN and display: confirmed absent, not broken

No WCN/WiFi/Bluetooth driver activity anywhere in the log (consistent with the already-documented WCN chip
risk — not wired up yet, no new information). Display never gets past `simpledrm` (the bootloader
framebuffer passthrough) — no `sde_`/`dpu`/`mdss`/panel-probe activity, as expected (display driver work
hasn't started).

### Appendix — how the report was produced

Extracted by viewing the original phone-camera photos directly, not by trusting OCR (unreliable on this
dense monospace text — confused `0`/`8`, `1`/`l`, lost minus signs at line-wrap boundaries). A rough OCR
pass across all 189 photos was used only as a search index to locate candidate pages, then every excerpt was
re-read directly from the source image before being included.

---

## Follow-up (2026-09-25/26)

**Headline: the crash is confirmed fixed.** v10's `xo_board`/`sleep_clk` fix (see the sibling
`2026-09-23-pcie-opp-crash/findings.md`) worked exactly as predicted there — no oops, kernel reaches a
shell. This is the first mainline boot on dm1q that gets this far.

**Why the flash-log came back empty (not a new bug).** The v9/v10 flash-log mechanism writes through a UFS
block device; Finding 2 shows UFS (`1d84000.ufshc`) never got a working block device this boot either (now
blocked on `ldo17` instead of the old `=m`-module issue) — so the empty flash-log pull is just Finding 2
again, not a third problem. On-screen photos were the only channel that could have worked this boot, and
they did.

**Finding 1 — SPMI USID 7 (PM8550B): SID confirmed CORRECT, root cause still open.** Cross-checked against
two independent real-hardware sources: (a) `../../_scratch/crdroid-dm1q-dts/samsung/dm1q_eur_openx_w00_r13.dts`
(the real Samsung downstream board file, r13, our established reference) has `qcom,pm8550b@7` —
PM8550B genuinely is wired at SPMI USID 7 on real dm1q hardware; (b) mainline's `pm8550b.dtsi` hardcodes
`reg = <0x7 SPMI_USID>` for the exact same reason (it's not board-specific, this is standard-issue silicon
convention). So this is NOT a wrong-SID devicetree bug — pm8550b.dtsi is a stock, unmodified upstream file
and dm1q.dts doesn't touch USID assignment at all. The transaction genuinely fails at the electrical/register
level for a reason not yet identified — candidates: a real hardware/power-sequencing quirk specific to this
Samsung board (PM8550B needing something enabled before it responds on SPMI, the way several other chips on
this board have turned out to need a board-specific GPIO/regulator prerequisite mainline's generic reference
files don't know about), or something intermittent (this is only one boot's worth of evidence — not yet
known whether it fails every time). **Not fixed, not blocking anything else**: PM8550B's *regulators* are
reached through the separate RPMH/RSC path (Finding 2), not through this direct SPMI read, and nothing else
in dm1q.dts currently depends on PM8550B's own SPMI-mapped GPIO/haptics/etc. functions. Left open;
next step if revisited is checking whether it reproduces on every boot before chasing further.

**Finding 2 — root cause found and FIXED in v11: a non-existent compatible string.**
`dm1q.dts`'s `&apps_rsc { regulators-0 { ... } }` (PM8550B's RPMH regulators — `ldo15`/`ldo17`/`ldo5`, i.e.
exactly the two consumers Finding 2 names) used:
```
compatible = "qcom,pm8550b-rpmh-regulators";
```
**This string does not exist anywhere in mainline.** Checked two independent sources, both authoritative:
- `Documentation/devicetree/bindings/regulator/qcom,rpmh-regulator.yaml`'s top-level `compatible: enum:` —
  for the PM8550 chip family it lists exactly `qcom,pm8550-rpmh-regulators`, `qcom,pm8550ve-rpmh-regulators`,
  `qcom,pm8550vs-rpmh-regulators`. No `...pm8550b...` entry.
- `drivers/regulator/qcom-rpmh-regulator.c`'s own `rpmh_regulator_match_table[]` (the actual
  `of_device_id` table the driver binds against): same three strings, confirmed by direct grep of the
  built kernel tree. No `pm8550b` variant compiled in either.

The real mainline pattern (already used correctly elsewhere in this same file — `regulators-1`/`regulators-2`
both use ONE shared `"qcom,pm8550vs-rpmh-regulators"` compatible for PM8550VS instances "e" and "g",
disambiguated purely by `qcom,pmic-id`) is: **one compatible string per chip family, `qcom,pmic-id` selects
the instance.** PM8550B is simply the "b" instance of the PM8550 family, so it should use the SAME
`qcom,pm8550-rpmh-regulators` compatible as a hypothetical PM8550 "a" instance, with `qcom,pmic-id = "b"`
doing the disambiguation — exactly like VS's "e"/"g" already do.

**Effect of the bug:** since no `of_device_id` entry matched `"qcom,pm8550b-rpmh-regulators"`,
`rpmh_regulator_probe()` was never called for this node at all — not deferred, not retried, just never
invoked — so none of its three children (`ldo15`, `ldo17`, `ldo5`) ever became real `regulator_dev`
instances. `ldo17` is UFS's `vcc-supply` (PM8550B L17, resolved back on 2026-09-16); `ldo5` is the eUSB2
repeater's `vdd3-supply` (PM8550B L5, resolved 2026-09-15). This alone fully explains Finding 2's whole
UFS+USB deferral chain. A plain `dtc` compile can't catch this class of bug (an unrecognized compatible
string is syntactically valid devicetree; it just never matches a driver) — would need `dtbs_check`/
`dt_binding_check` against the real schema to catch it automatically, which this project's build recipe
doesn't currently run.

**Fix applied (`dts/dm1q/dm1q.dts`):** `compatible = "qcom,pm8550b-rpmh-regulators"` →
`compatible = "qcom,pm8550-rpmh-regulators"` (one line; `qcom,pmic-id = "b"` unchanged). Nothing else in the
node needed to change. Checked the sibling groups while in there: `regulators-1`/`regulators-2`
(`qcom,pm8550vs-rpmh-regulators`) and `regulators-3` (`qcom,pm8550ve-rpmh-regulators`) both already match
real entries in the same driver table — only `regulators-0` had this bug.

**v11 = v10 + this one-line fix.** Same kernel tree, kernel banner unchanged (`#7` — Image itself is
byte-identical to v10's, sha256 `51dd5c09…`, since nothing in kernel C source changed); only the compiled
`dm1q.dtb` differs, and only in that one `compatible` string (confirmed via decompiled-dtb diff, single
line changed). `init_boot` (v9) and `dtbo` (v5) unchanged; vendor cmdline unchanged from v10 (no
`console=ttyMSM0,...`, `initcall_debug` still on).
- Files: `../_scratch/boot-backup-20260920/v11-rpmh-fix/{boot_v11.img,vendor_boot_v11.img,Image.gz,Image.gz-dtb}`.
  sha256: boot_v11 `aeec5b27aac5aa0a1f1ee12115e9359e9afb3e0c9237247e22d98dbc52782187`,
  vendor_boot_v11 `84ecd1a079a5a341fa0df623b596c0676b18e7fc9d003feb134f9c317ed0681b`, dtb `5b0620a4…`.
- Verified same way as v10: kernel payload == Image.gz-dtb, Image.gz decompresses to the built Image, vendor
  ramdisk fragment + bootconfig byte-identical to v7 (untouched), `avbtool verify_image` OK on both.
- Flashed from recovery: pre-flash readback == v10 set (as expected — nothing else had been flashed since);
  push, device sha256 == host; write with conv=fsync to boot/sda25 + vendor_boot/sda28; readback verified and
  re-verified after `drop_caches`; `init_boot` still `207474c1…`, `dtbo` still `63852b23…`. Rollback = v10
  set in `v10-xo-geni/` (boot `022b3688…`, vendor_boot `2db4170f…`).

**Build-environment note, for future sessions.** Mid-session, one edit to the build tree's copy of
`dm1q.dts` (`../_scratch/linux-build/full/arch/arm64/boot/dts/qcom/dm1q.dts`) silently reverted between a
`cp`+`cmp`-verified step and the next command — the repo's own copy under `dts/dm1q/dm1q.dts` was never
affected, and the rebuild that used the stale tree copy was caught before flashing (the decompiled dtb still
showed the old string). Cause not identified (not a symlink, not a second stray copy, not tracked in the
`full/` clone's own git). Re-doing the copy+verify+rebuild as one single shell invocation (instead of spread
across separate tool calls) went through cleanly and was independently re-verified end to end, so v11's
actual flashed content is confirmed correct — but if a future rebuild's output doesn't match an edit that
was just made, re-copy and rebuild in one shot before trusting the result, rather than assuming a prior
"verified" copy is still there.

**Predictions for the v11 boot (to test, not yet observed as of this writing).** No SPMI USID-7 warning fix
(Finding 1 not addressed) — expect it again. UFS should get a real block device (`sda*`) this time, and with
it the flash-log mechanism should finally start working on its own. The eUSB2 repeater should stop deferring
on `ldo5`, so the USB HS PHY chain should get further — whether that's enough to reach a bound UDC depends on
what's downstream of the repeater succeeding, not yet known. PCIe's dummy-regulator fallback
(`vdda`/`vddpe-3v3`) is untouched by this fix and should still appear.

---

## v11 confirmed (2026-09-26): UFS fully works, USB gets one step further, one new bug found + fixed in v12

v11 was booted and its dmesg pulled straight off the `dtbo` flash-log partition from recovery immediately
after — **no photos needed this time**, and the pull itself is proof the fix worked: the flash-log
mechanism writes through a UFS block device, and it succeeded (4749 lines, clean pull, 336824 non-NUL
bytes).

**No oops/panic** (same clean boot as v10). **SPMI USID 7 (PM8550B) fails identically** to the v10 log —
same `-EIO`, same WARN backtrace, same register (`0x3228`). Confirms Finding 1 is a stable, reproducible
failure (not intermittent) and is genuinely unrelated to the regulators-0 fix, exactly as reasoned. Still
open.

**UFS: completely fixed.** `probe of 1d84000.ufshc with driver ufshcd-qcom returned 0` — real SCSI host,
all six LUNs attached (`sda`..`sdf`), full GPT partition table visible (`sda1`..`sda41`). `regulators-0`
itself now probes clean (`probe of 17a00000.rsc:regulators-0 ... returned 0`). (Note: `regulators-3`,
PM8550VE "f", -EPROBE_DEFER's once early then succeeds on retry — normal deferred-probe behaviour, not a
bug.)

**USB: got one step further, hit a NEW wall.** The eUSB2 repeater (`ptn3222`) and HS PHY
(`snps-eusb2-hsphy`) BOTH now probe clean (Finding 2's `ldo5` fix worked exactly as predicted) — but then:
```
dwc3-qcom a600000.usb: DWC3 controller soft reset failed.
dwc3-qcom a600000.usb: error -ETIMEDOUT: failed to initialize core
dwc3-qcom a600000.usb: error -ETIMEDOUT: failed to register DWC3 Core
dwc3-qcom a600000.usb: probe with driver dwc3-qcom failed with error -110
```
**Root cause traced via `drivers/usb/dwc3/dwc3-qcom.c` source, not guessed**: `dwc3_qcom_probe()` reads a
`qcom,select-utmi-as-pipe-clk` device property; if set, it calls `dwc3_qcom_select_utmi_clk()`, whose own
comment says exactly what our situation is: *"Configure dwc3 to use UTMI clock as PIPE clock not present"*.
`dm1q.dts`'s `&usb_1` override deliberately disabled `&usb_dp_qmpphy` (the SS PHY) for this HS-only
bring-up (a 2026-09-21 decision, see the workplan log) — with no SS PHY there is no real PIPE clock source
at all, and without this property DWC3's internal clock-select register bits (`PIPE_UTMI_CLK_SEL`,
`PIPE3_PHYSTATUS_SW`) are never configured, leaving the core's internal state inconsistent enough that its
own soft-reset polling times out. This was invisible until now because the repeater/PHY probe failures
(Finding 2) always masked it — DWC3 itself never got far enough to hit this.

**Fix (`dts/dm1q/dm1q.dts`, `&usb_1`)**: added `qcom,select-utmi-as-pipe-clk;`. One property, no other
changes.

**v12 = v11 + this fix.** Same kernel tree (Image byte-identical, sha256 `51dd5c09…`, same as v10/v11);
only the dtb differs (confirmed: decompiled dtb shows exactly the one new property line, right after
`maximum-speed`). `init_boot` (v9) and `dtbo` (v5, though its scratch region now legitimately differs —
see below) unchanged; vendor cmdline unchanged.
- Files: `../_scratch/boot-backup-20260920/v12-utmi-pipe-clk/{boot_v12.img,vendor_boot_v12.img,Image.gz,Image.gz-dtb}`.
  sha256: boot_v12 `c2976091051267066c2e49f7405776b6072c8968f88ee359d5ce29dad6b8aebc`,
  vendor_boot_v12 `f0a76cf1dc69c801daf1bbf35b4292dc94ca8aa0d98da22498b9676f2fdee6c5`.
- Verified the same way as v10/v11 (payload/decompress/ramdisk-fragment/bootconfig checks, `avbtool
  verify_image` on both).
- Flashed from recovery: pre-flash readback == v11 set; push → device sha256 == host; `dd conv=fsync` to
  boot/sda25 + vendor_boot/sda28; readback verified and re-verified after `drop_caches`. `init_boot` still
  `207474c1…`. **`dtbo`'s sha256 has changed from the original v5 value** (`63852b23…` → `a459f416…`)
  — this is expected and correct, not a regression: it's the flash-log mechanism's own scratch-region
  writes from the v11 boot session landing inside the same partition (1 MiB offset, well clear of the
  4096-byte AVB-hashed region), the first real evidence the flash-log write path is genuinely active now
  that UFS works. Rollback = v11 set in `v11-rpmh-fix/` (boot `aeec5b27…`, vendor_boot `84ecd1a0…`).
- Rebooted into v12; no USB gadget observed on the host within the first ~50 s (unlike the flash-log route,
  this depends on the full repeater→PHY→DWC3→UDC→configfs-script chain succeeding end to end, not just
  the one property). **Not yet confirmed** whether the pipe-clk fix resolved the soft-reset timeout —
  next step is pulling v12's dmesg from recovery via the flash-log, exactly as done for v11, rather than
  guessing from USB enumeration alone.

**Cumulative status after v12**: kernel boots clean to a shell, UFS fully functional, PMIC/regulators
working except the one open SPMI USID-7 item, USB progressed two probe stages further with the DWC3 fix
unverified. PCIe still deferred (`PHY_QCOM_QMP_PCIE=m`, unrelated, already known). WCN/display still not
wired up (expected, unrelated).

---

## v12 CONFIRMED LIVE over USB (2026-09-26): full shell access, ~5h stable uptime, DWC3 fix verified

Connected directly: `lsusb -v` showed a real bound gadget (idVendor/idProduct 1d6b:0104, iManufacturer
"dm1q mainline", iProduct "dm1q initramfs console" -- our own configfs gadget strings). After the host
loaded `cdc_acm` and the device node permissions were opened up, connected with `socat - /dev/ttyACM0,raw,
echo=0,b115200` straight into the initramfs busybox shell -- a genuine live, interactive console over USB,
the first of this whole project.

**DWC3 fix fully confirmed**: `probe of a600000.usb with driver dwc3-qcom returned 0 after 31325 usecs` --
no soft-reset failure, no ETIMEDOUT, anywhere in this boot's dmesg. `/sys/class/udc/*/state` reads
"configured". The only other dwc3-qcom lines are harmless ("remote wakeup not configured", expected with
no wakeup support wired up).

**Stability**: `/proc/uptime` read **17502s (~4h51m)** at the time of connecting -- this kernel has been
running continuously and correctly since the v12 flash, not just booting and idling.

**Re-confirmed live, not just from the flash-log snapshot**: no oops/panic anywhere in dmesg (the only
"Call trace:" is the known SPMI USID-7 WARN, not a crash); SPMI USID 7 (PM8550B) still fails exactly once,
consistent with Findings so far -- genuinely reproducible, still open; full UFS block layout intact
(`/proc/partitions` -- 106 entries across sda/sdb/sdc/sdd/sde/sdf and their partitions).

**Cumulative status**: kernel boots clean, stays up for hours, has working storage AND a working interactive
console over USB. Remaining known gaps: SPMI USID-7 (PM8550B, Finding 1, open), PCIe (deferred, PHY `=m`,
unrelated to anything fixed today), WLAN/display (not wired up yet, out of scope so far). This is the first
point in the project where the kernel itself looks stable enough that userspace (pmOS/Alpine) work is worth
considering as the next phase -- that decision is the user's to make, not started here.

