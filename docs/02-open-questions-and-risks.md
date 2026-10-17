# Open questions and risks

Things flagged as "verify, don't assume" during planning. Resolved items stay
here with their answer and source, and are also reflected in 00-overview.md.

## Resolved

1. **WCN Wi-Fi/BT chip — CORRECTED 2026-09-13 (second pass, overturns the
   teardown-based "resolved" verdict below).**
   Ground-truth check against dm1q's actual Samsung downstream devicetree
   source (`crdroidandroid/android_kernel_samsung_sm8550-devicetrees`, real
   `.dts` files, all 10 available board revisions r01–r13) shows dm1q uses
   **QCA6490** (`qcom,cnss-qca6490`, `bt_qca6490`), not WCN6855. Zero of the
   10 revisions reference WCN6855; all 10 reference QCA6490. This is
   directly from real hardware-description source, not teardown/community
   inference — treat as settled, higher confidence than the item below it.
   Good news buried in the correction: QCA6490 is still `ath11k`-family
   (same mainline driver as WCN6855) and was actually mainlined *earlier*,
   so driver maturity is likely equal or better than assumed. Practical
   effect: use QCA6490's specific compatible strings/firmware naming, not
   WCN6855's, when building the WLAN/BT devicetree nodes and picking
   firmware blobs. dm2q/dm3q not re-checked against real source — the item
   below may still hold for dm3q specifically, but shouldn't be trusted for
   dm1q anymore.
   *(Original "resolved" text, now superseded, kept for history:)*
   dm1q/dm2q (S23, S23+) use Qualcomm FastConnect 6900 (WCN6855-class,
   Wi-Fi 6E, `ath11k`). dm3q (S23 Ultra) uses FastConnect 7800
   (WCN7850/WCN7851-class — same chip family as the Tab S9 Ultra reference
   device — Wi-Fi 7 silicon software-limited to 6E, `ath12k`). This was
   sourced from iFixit teardown + community reporting, not dm1q's own
   kernel source — exactly the kind of secondary-source claim that turned
   out to need the direct check above.

## High priority — blocks Step 1 of the workplan

2. **PMIC part number match — RESOLVED 2026-09-13.**
   Confirmed directly from dm1q's real Samsung downstream devicetree source
   (same repo/method as the WCN correction above): dm1q uses **PM8550
   (main), PM8550B, PM8550VE, PM8550VS, PM8010, and PM8350C** — a
   multi-PMIC setup, not a single part. This is ground truth, not inferred.
   The Tab S9 Ultra reference used PM8550/PM8550VS/PMK8550 — overlapping but
   not identical (no PM8550B/PM8550VE/PM8010/PM8350C on the tablet, at least
   not visible in that board's devicetree). Regulator *names* will need
   verifying node-by-node against dm1q's real rail usage rather than assumed
   1:1 from the tablet reference. See
   `../_scratch/crdroid-dm1q-dts/samsung/dm1q_eur_openx_w00_r13.dts` for the
   real source.

3. **GPU/CPU OPP table retuning — RESOLVED (favorably) 2026-09-15.**
   Checked mainline's actual `sm8550.dtsi` CPU OPP tables directly rather
   than assuming: they specify `opp-hz` (frequency) and `opp-peak-kBps`
   (memory bandwidth) only — **no `opp-microvolt` at all**. Mainline uses
   `qcom,sm8550-cpufreq-epss` (Qualcomm's EPSS hardware), which reads
   per-chip voltage calibration from silicon fuses at runtime rather than
   using static devicetree voltage values. Checked dm1q's own downstream
   source for comparison: zero `opp-table`/`opp-hz`/`opp-microvolt` entries
   found at all, consistent with Android's downstream driver also relying
   on runtime calibration, not static per-board tables.
   **Practical conclusion: the "SM8550-AC bin" concern is not a
   boot-reliability risk.** EPSS will read dm1q's actual chip's real fused
   calibration regardless of which marketing bin it is, so voltage
   correctness isn't at stake. The real (much smaller) risk is a
   *frequency ceiling* mismatch — if dm1q's AC bin is fused for higher max
   frequencies than generic reference kalama, using the stock mainline OPP
   table would simply leave performance on the table (safe, just
   suboptimal), not risk instability. Not a first-boot blocker. Revisit
   only once basic boot is working and performance tuning becomes the
   actual goal — not before.

3b. **Panel driver and touch controller — RESOLVED 2026-09-13.**
   From the same real dm1q devicetree source: dm1q is **dual-sourced** for
   the display panel — primary is Samsung's own `S6E3FAC` panel driver IC
   (cell part `AMB606AW01`), with `LX83118` (Silicon Works, cell
   `CM002`) as an alternate/second-source panel. Both will realistically
   need their own DSI panel driver work — dual-sourcing on flagship phones
   is normal but means two drivers, not one, if full hardware coverage
   matters (unclear yet whether crDroid/OneUI treat these as
   interchangeable at the DT level or select one via board-revision
   fragments — worth checking which is more common in retail units before
   prioritizing). Touch controller is **Goodix Berlin**
   (`goodix-berlin@5d`, I2C address 0x5d) — a real, known touch IC family
   with some existing mainline Linux interest elsewhere, worth checking for
   upstream driver status separately.

## Medium priority — affects scope/expectations, not immediately blocking

4. **Camera: RE-UPGRADED 2026-09-13 (second pass) — credible prior art
   confirmed real, one specific claim still worth checking.**
   Full history: this item went no-known-support → briefly "credible" →
   "discredited as likely fabricated" → **corrected back to credible**, all
   within 2026-09-13. The "discredited" verdict was itself wrong — see
   03-references.md for the full correction. Verified directly: real V4L2
   driver patch code against actual mainline `drivers/media/i2c/hi847.c`,
   real pmOS deviceinfo conventions, a real citation of an actual resolvable
   commit hash in pmaports history. This is legitimate, technically
   competent work, not fabrication.
   **Still open:** the specific claim of *full* camera support (4 cameras,
   autofocus, flash all working) is unusually strong even for legitimate
   projects — worth reading `docs/hardware-status.md` from
   `ubuntu-galaxy-tab-s9-ultra` directly for the evidence behind that claim
   before assuming it's fully solved. dm1q's own sensors (S5KGN3/IMX564/
   S5K3K1) differ from the Tab S9 Ultra's (hi847/hi1337) regardless, so even
   fully-confirmed camera work there is a methodology/pattern reference for
   dm1q, not drop-in code.

5. **Modem: unpredictable, device-specific.**
   No basis for predicting dm1q's modem prospects from any reference device
   checked so far (Tab S9 Ultra has no modem at all). Historical pattern
   across other Samsung pmOS ports: modem success/failure doesn't correlate
   cleanly with Wi-Fi/BT/camera success — it's its own separate effort.

## High priority — contradicts a prior "confirmed" claim

1b. **dm1q pmaports package: does not exist in current pmaports — CONFIRMED
   AND CLOSED 2026-09-13.**
   Directly confirmed by running `pmbootstrap init` interactively and
   selecting `samsung-dm1q`: pmbootstrap itself returned "The specified
   device ('samsung-dm1q') could not be found in existing ports" and offered
   to launch its new-device-port wizard (postmarketos.org/porting/). This
   matches the earlier `git ls-tree` search exactly — no fuzzy-match
   artifact, no branch issue (pmbootstrap's error message covers the "did
   you mean the edge branch" case explicitly and it still didn't find it).
   **Conclusion: the original "confirmed by hand" note was simply wrong** —
   likely a misremembering, or confused with a different device/session.
   Not worth further investigation. This is a ground-up port; see
   docs/01-phase1-workplan.md for the updated Step 0/1 sequencing that
   follows from this.
   (Prior text, kept for history:)
   Previously (see old item 6 below) this was treated as settled because the
   user had directly observed dm1q in `pmbootstrap init`. On 2026-09-13 a
   sparse partial clone of the live pmaports repo (main branch, HEAD
   `1c99c07`) was searched directly with `git ls-tree -r` for `dm1q`, `dm2q`,
   `dm3q`, `kalama`, and `sm8550` across every device tier
   (main/testing/community/archived/downstream) — **zero matches, all
   terms**. This is hard evidence against a real dm1q package existing right
   now. Two things can be true at once: pmaports migrated hosts in 2024 (see
   00-overview.md), AND the device may simply not be there. Needs a fresh,
   carefully-observed interactive `pmbootstrap init` session — type `dm1q`
   into the device search and record verbatim what appears (real match /
   fuzzy near-match / nothing) — to find out whether the original observation
   was a typo/fuzzy-match artifact or something else. Until resolved: treat
   Phase 1 as a from-scratch port with no existing dm1q package to reference,
   which doesn't change the plan (Tab S9 Ultra was always just an
   SM8550-family reference) but does mean don't expect to find a
   maintainer/kernel-type/last-commit-date to record, because there may be no
   package to have those.

## Low priority / just for the record

6. *(superseded 2026-09-13 by item 1b above — kept for history)*
   **dm1q pmaports package provenance unconfirmed by me.**
   Explanation upgraded 2026-09-13: postmarketOS moved `pmaports` from
   `gitlab.com` to a self-hosted `gitlab.postmarketos.org` in Oct 2024, and
   the new host isn't well-crawled by web search either, so a negative search
   result there means little. The user has directly observed dm1q in
   `pmbootstrap init`, which is authoritative (pmbootstrap clones pmaports.git
   directly). Confirm and record details (kernel type, maintainer, last
   commit) in 00-overview.md once checked locally against
   `gitlab.postmarketos.org/postmarketOS/pmaports`.

7. **postmarketOS wiki page content unread.**
   wiki.postmarketos.org blocks automated fetches (Anubis anti-bot); Wayback
   Machine and search-engine snippets also failed to surface the page content
   as of 2026-09-13. The "Samsung Galaxy S23" wiki category entry exists but
   its content — maintainer, status table, whether it even lists dm1q's
   codename — hasn't been read by anyone on this project yet. Needs a human
   to open it in a browser.

8. **Camera/Fairphone 6/camss claim and Waydroid mechanics — not re-verified
   in the 2026-09-13 pass.** These came from single sources checked when the
   project started and were not re-cross-checked during the most recent fact
   review (time/effort was spent on the WCN chip and GitLab migration findings
   instead, since those were higher-impact corrections). Treat as "probably
   still accurate" but lower-confidence than the WCN finding above until
   someone re-checks them specifically.

9. **Kupfer's exact current device count/list — not freshly re-checked.**
   Confirmed the *general pattern* holds (Kupfer's own 2022–2023 blog posts
   describe "three currently supported SDM845 devices": OnePlus 6/6T, Poco F1,
   plus SHIFT6mq mentioned elsewhere), consistent with "SDM845-and-older only."
   The exact current number/list in 00-overview.md ("~10 devices") was not
   re-verified live against `kupfer.gitlab.io/devices/` on 2026-09-13 — treat
   that specific figure as dated until checked again.

## Newly raised — bootloader method (2026-09-15)

10. **dm1q bootloader/flash method — open, but a promising low-effort
   candidate exists.** Not yet tested against dm1q specifically. Two
   candidates identified so far:
   - `heimdall-bootimg` (no intermediate bootloader; stock SBL loads a
     standard Android boot.img directly) — confirmed working on a real
     comparable Samsung Qualcomm device (A70q/SDM670, see 03-references.md
     for the full case study and deviceinfo evidence). Worth trying first
     given it avoids all U-Boot chainload work.
   - U-Boot chainload — the default assumption discussed earlier in this
     project, consistent with general Samsung/Qualcomm mainlining precedent
     and the separate A70q U-Boot porting project, but not yet confirmed
     necessary for dm1q specifically.
   Decision deferred until bootloader-stage work begins; test
   heimdall-bootimg first since it's the lower-effort path if it works.

11. **Kupfer U-Boot/aboot gap — only matters if dm1q needs U-Boot.**
   Kupferbootstrap currently only produces aboot-style boot images; it does
   not yet integrate `boot-deploy` for U-Boot targets. If item 10 above
   resolves to U-Boot being necessary for dm1q, Kupfer bring-up will need
   this upstream gap closed first (not resolvable within this repo). If
   heimdall-bootimg (the no-intermediate-bootloader approach) works instead,
   this gap likely doesn't apply. See 03-references.md for detail.

## Newly raised and resolved -- 2026-10-01

12. **Kernel rebuilds vs. the pmOS rootfs' modules (module-signing key) --
   fixed in the kernel config 2026-10-01; confirmed on hardware 2026-10-02.**
   pmaports' `config-mainline.aarch64` signs modules with a per-build random
   key and forces kernel lockdown (integrity). The rootfs (and the
   `/lib/modules` in it) is built once, so every rebuilt kernel refused every
   module -- which presented as "`&pcie0` never probes whenever the devicetree
   changes" (full evidence: docs/07 "ROOT CAUSE FOUND 2026-10-01").
   Fix: `CONFIG_LOCK_DOWN_KERNEL_FORCE_NONE=y` in the dm1q config fragment.
   Residual risk: no `MODVERSIONS` here, so a rootfs whose modules came from a
   materially different kernel *config* is no longer refused at load time --
   refresh the rootfs' modules after config changes
   (`scripts/check-kernel-module-key.py` shows the mismatch).
   **UPDATE 2026-10-11 (docs/07 15.12): the guard that does exist is BTF -- and it bit.** Any kernel
   *code* change (not only config) makes the old module tree fail BTF validation and the kernel refuses
   all of it (r5: 23 modules, no PCIe PHY, no wlan0). Rule extended in docs/06; tool:
   `scripts/refresh-phone-modules.sh`. Undecided: `CONFIG_MODULE_ALLOW_BTF_MISMATCH=y` in the fragment.

13. **WLAN pwrseq consumer wiring -- reworked in the DTS 2026-10-01;
   confirmed on hardware 2026-10-04 (pwrctrl binds, PCIe link up, endpoint
   17cb:1103 enumerates); chip boot still blocked -- suspect: the PMU input rails sit at
   their DT minimum (docs/07 section 13), fix prepared as the v8 image set.** The first `wifi@0` (r2/r3) could never have bound
   `pci-pwrctrl-pwrseq` even with modules loading: its supplies pointed at board
   rails instead of the PMU's own `regulators { ldoN }` outputs, the PMU node
   had no `regulators` node (binding: required), the compatible was 1101 (the
   live device is 17cb:1103), and it sat under the host bridge instead of
   `&pcie0_port0`. Now fixed and statically checked
   (`scripts/check-wlan-dtb.py`). Still unknown: whether ath11k finds usable
   firmware + board data for the S23's QCA6490 (linux-firmware `ath11k/WCN6855`
   files, `board-2.bin` variant / `qcom,calibration-variant`), and whether the
   shared Bluetooth half of the PMU needs anything on top. See docs/07 sections
   6-9.

   **UPDATE 2026-10-09:** the rails suspect above did not cure the stall (v8, flashed 2026-10-05) and
   is not supported as its cause -- see item 14 and docs/07 section 14. The wiring/pwrctrl/link
   findings in this item stand.

## Newly raised -- 2026-10-09

14. **PCIe BDF-to-SID table mis-programmed by 7.3-rc3 (upstream regression) -- fix carried as a
   patch (kernel r5) plus a DT-only test image (v9); NOT yet verified on hardware.**
   `qcom_pcie_config_sid_1_9_0()` (pcie-qcom.c) parses the DT `iommu-map` as four-cell entries;
   `sm8550.dtsi` has had five-cell entries since the 2026-07-30 DT series (the SMMU has
   `#iommu-cells = <2>`), so for dm1q's two-entry map the controller's BDF-to-SID table gets one
   garbage slot and **no entry for the QCA6490 (RID 0x0100)**. Its stream ID / ITS DeviceID are then
   wrong, which fits the 20 s MHI stall with zero interrupts on the endpoint's MSI vectors while the
   root port's own vector counted. Fixed upstream 2026-09-17 ("PCI: qcom: Honor IOMMU provider's
   #iommu-cells in qcom_pcie_config_sid_1_9_0()", tested on an ATH11k board); not in 7.3-rc3.
   Evidence, the model of the table, test plan and what would falsify it: docs/07 section 14 and
   `notes/2026-10-08-pcie-bdf-sid-regression/`. Open until the v9 collection (table dump +
   endpoint interrupt counts + ath11k getting past MHI) is in. If the table is right and the stall
   remains, the register sampler (rewritten 2026-10-08) is the next measurement; the unchecked
   AOSS/PDC and power-up-sequence hypotheses (docs/07 14.6) come after that.
   Still unknown after MHI works: firmware/board-data lookups for this QCA6490 (item 13).

   **UPDATE 2026-10-10: CONFIRMED on hardware (v9).** Same kernel and images as v8, only the DTB's
   `iommu-map` in the legacy 4-cell form: the chip boots in 0.7 s, ath11k probes, `wlan0` associates
   and gets DHCP; the controller's table read back from the phone is `slot 0x15 = 0x01000100`, as
   modelled. This also closes item 13's "chip boot still blocked". Still open here: kernel **r5**
   (the upstream patch; DTS back to canonical; the same collection must show the same table and no
   `1-cell entries` warning) and the optional control read of the table in the failing state.
   docs/07 section 15.
   **UPDATE 2026-10-11:** r5 is built (patches applied, kernel verified to contain the fix) and its
   image set with the canonical DTS is ready in `_scratch/pmos-v10-r5-pcifix/`; waiting for the
   flash + first-boot check (docs/07 15.11). Once that passes, the v9 workaround is retired.
   **UPDATE 2026-10-11 (docs/07 15.12): first boot of r5 had no wlan0 -- not the fix, the module tree:**
   the kernel refused every old module (BTF mismatch). Next: `scripts/refresh-phone-modules.sh --reboot`
   (modules from the r5 APK), then re-check; the PCIe fix itself is still unjudged.
   **CLOSED 2026-10-11 (docs/07 15.13): confirmed on hardware.** Canonical DTS + r5: no warning, table
   identical to v9's, chip up in 0.77 s, `wlan0` associated with an IP. v9 workaround retired.

15. **WLAN link quality and DNS -- open (first association 2026-10-10).** `wlan0` joins the AP and
   DHCP works, but ping loss is 69 % (gateway) / 80 % (1.1.1.1) with 19-59 ms RTT to a local hop, and
   DNS lookups fail. Hypotheses, none checked: power save / DTIM, generic board data (`board_id 0xff`:
   no Samsung calibration or antenna configuration), band/channel, resolver configuration. Data:
   `scripts/phone-wlan-probe.sh` now records capabilities, regdomain, scan, link, station dump,
   power save, `ip -s link`, resolver and a gateway ping. docs/07 15.5.
   **UPDATE 2026-10-10 14:00 (first measurements, docs/07 15.8):** signal -46 dBm (strong) but per
   chain [-80, -46]; `tx failed` 1558 of 2225 frames (70 %) -- the loss is on the transmit side;
   power save off fixes latency (RTT 158 -> 54 ms) but not the loss (65 % -> 55 %). Suspects: generic
   board data / antenna path, 2.4 GHz interference, DMA coherency (`dma-coherent` on pcie0). Next:
   distance, 5 GHz and chain-mask experiments; Samsung's own board data if the RF suspect holds.
   **UPDATE 2026-10-10 16:15 (docs/07 15.9):** the loss did NOT reproduce: 80/80 pings, `tx failed`
   0, fresh association, power save off (since the first look), user next to the router. The
   chain-mask experiment is void (`iw ... set antenna` -> `Not supported`). Cause of the morning's
   loss open: power save vs distance vs association age. Next: power-save A/B, then a long logger.
   **UPDATE 2026-10-11 (docs/07 15.10): WLAN is usable; the morning episode is unexplained.** 25 min
   logger: 1.2 % ping loss, `tx failed` 1.1 %; power-save A/B: 160/160 pings, 0 failed, power save only
   costs ~13 ms. Power save is excluded as the cause. Left: DNS check; if the loss returns, run
   `scripts/phone-wlan-log.sh` and note the phone's position. Board-data / DMA-coherency suspects
   stay parked.
   Also seen 2026-10-11 (15.13): the first 20 gateway pings ~3 s after association averaged 422 ms
   (max 1.6 s, 0 % loss, rx rate still 1 Mbit/s, power save on); later logs clean.
   **DNS works (2026-10-11 ~17:55, user's paste): `ping google.com` 3/3, ~66 ms.** WLAN is functionally done;
   what remains is the unexplained morning loss (parked) and the board data question.

16. **No input devices -- open; findings of 2026-10-12 (docs/05 "Touch controller" correction).**
   - **Keys** (Samsung's downstream DT, `_scratch/crdroid-dm1q-dts/samsung/dm1q_eur_openx_w00_r13.dts`):
     power = PMK8550 PON `pwrkey` (`qcom,pmk8350-pwrkey`, KEY_POWER); volume down = PON `resin`
     (`qcom,pmk8350-resin`, code 114 = KEY_VOLUMEDOWN); volume up = `gpio-keys` on PM8550 **gpio 6**
     (active low, pull-up, power-source 1, KEY_VOLUMEUP, debounce 15 ms, wakeup). That is exactly the
     mainline `sm8550-qrd.dts` arrangement (`&pon_pwrkey` / `&pon_resin` okay + `gpio-keys` on
     `&pm8550_gpios` 6). `dm1q.dts` already includes `pm8550.dtsi` and `pmk8550.dtsi`; none of it is enabled.
   - **Touch: the Goodix-on-I2C reading of docs/05 is the wrong part for this unit.** The serial engine at
     `a90000` runs SPI firmware (protocol 1), which is why `i2c-qcom-geni` refuses it (`Invalid proto 1`).
     Samsung's DT has a second overlay fragment (`fragment@68`): `touchscreen@0`, `compatible =
     "stm,stm_ts_spi"` -- an STMicroelectronics FTS2BA61Y on SPI (10 MHz, `sec,irq_gpio` = GPIO25, the same
     pin the Goodix node uses; `sec,gpio_spi_cs` = GPIO47; firmware `tsp_stm/fts2ba61y_dm1q{,_boe}.bin`;
     `trusted-touch-io-bases` lists `0xa90000`). Both fragments are `status = "ok"` in the overlay (two
     hardware variants); the SE's protocol decides -- here SPI. So **no SE-firmware loader is needed**
     (the idea of 2026-10-09 was wrong): `sm8550.dtsi` already has `spi4: spi@a90000`. What is missing is a
     **driver**: 7.3-rc3 has `stmfts.c` (I2C) but nothing for the FTS2BA61Y over SPI; Samsung's GPL driver
     (sec_input / stm) is in `_scratch/samsung-opensource-s911b`. Also open: the touch supplies
     (`tsp_io_ldo`, `tsp_avdd_ldo`) -- find them with the fixup-table method of docs/05.
   docs/07 15.6.
   **UPDATE 2026-10-12 (docs/08):** keys are DT-only (config checked: `KEYBOARD_GPIO=y`,
   `INPUT_PM8941_PWRKEY=y`, `PINCTRL_QCOM_SPMI_PMIC=y`, `INPUT_EVDEV=m`). `dm1q.dts` now enables
   `pon_pwrkey`, `pon_resin` (KEY_VOLUMEDOWN) and a `gpio-keys` volume-up on `pm8550_gpios` 6; image set
   `_scratch/pmos-v11-keys/` built and verified against the r5 reference (only those nodes differ).
   **KEYS CONFIRMED ON HARDWARE 2026-10-12 (v11-keys):** three input devices, one correct event per key
   (volume up 115, power 116, volume down 114). Evidence `notes/2026-10-12-v11-keys/`.
   **Touch scoping 2026-10-12 (docs/08 section 2):** an FTS2BA61Y/SPI driver exists upstream-bound (Eric
   Goncalves' RFC, 2025-09; not in 7.3-rc3, final status unverified). Samsung's SPI pins/CS match mainline's
   `spi4` groups exactly (gpio44-47). Supplies: `tsp_io_ldo` = L12B 1.8 V, `tsp_avdd_ldo` = L16B 3.0 V (neither
   added to `dm1q.dts` 2026-10-12). Found in the compiled DTB: `gpi_dma1` was disabled (spi4's `dmas` target; the
   r0q SPI-dead-on-probe thread asked exactly that). Plan: DT-only spidev proof first (B1), then port the driver
   (B2, r6).
   **B1 PASSED on hardware 2026-10-12 (v12-touch, docs/08 2.7):** with `gpi_dma1` on, spi4 on, L12B/L16B up, the
   FTS2BA61Y answers over SPI mode 0 at 1 and 10 MHz (opcode echo, controller-ready record `49 00 10`, soft reset
   OK). spi4 probes with -517 until `gpi` loads (the gpi_dma1 dependency, confirmed). Open: the driver (B2), the
   IRQ line, the `_boe` panel firmware question. Evidence `notes/2026-10-12-v12-touch/touch.txt`.
   **B2 prepared 2026-10-12 (docs/08 2.8):** the driver is carried as `kernel/patches/0002-...patch` (package r6, not
   built, not flashed). Differences from the RFC include a vendor-checked bug fix (touch-type bits 1:0 live in byte 7
   bits 7:6) and the slot count (10, not the TX channel count).
   **TOUCH WORKS ON HARDWARE 2026-10-13 (docs/08 2.9, `notes/2026-10-13-v13-touch-driver/`):** r6 + canonical DTS, probe OK
   (`resolution 4095x4095, 16 TX x 34 RX`, matches Samsung's `sec,max_coords` 4096x4096 normalized space), input device
   `event3`, gpio25 level interrupt firing, press / move / release decoded correctly. Open: multi-touch, palm,
   suspend/resume (needs a display driver first), `_boe` panel variant.
   **Corner test 2026-10-13 (docs/08 2.10):** orientation correct with no DT flags (X right, Y down, full 0..4095).
   **RISK, unexplained:** one later boot had no touch (device present, probe clean, gpio25 interrupt count flat at 2
   through a touch); re-running `refresh-phone-modules.sh` + reboot made it work and it has worked since. Candidate
   cause (untested): chip state surviving a warm reboot; Samsung's driver sets scan mode `A0 00 01` and calibrates after
   reset, ours does not. Next step if it recurs: docs/08 2.10.

17. **ADSP/CDSP remoteprocs never start -- open.** No battery/charger data, USB-C role handling,
   audio or sensors until the ADSP boots (firmware from the vendor partitions). docs/07 15.6.

18. **Display is still only the bootloader framebuffer (item 3b).** A mobile desktop is deliberately
   not the next step: on `simpledrm` it tests nothing about the display and there is no input.
   docs/07 15.7.
   **UPDATE 2026-10-13 (docs/09, research only, nothing flashed):** this unit's panel is the **S6E3FAC /
   AMB606AW01** (XBL log: DDI ID 0x810225, `Selected ... S6E3FAC_AMB606AW01_FHD_dsc_`), so item 3b's
   dual-source question is settled for this unit (LX83118 not needed). The DCS init sequence **was found**
   (downstream DT properties referenced by `$name`, and the bootloader's own DSI packet log; they agree) --
   docs/05's "not found" was wrong. Link: DSI0, 4 lanes, command mode + TE (GPIO86), DSC 1.1 (2 slices
   540x117, 8 bpp), 1080x2340@120, 951.08 Mbit/s/lane. Rails: panel_vdd3/vci/vddr = GPIO fixed regulators
   (TLMM 21/20/187), reset TLMM125; AVDD 5.5 V is not GPIO-driven (live pin dump: PM8550 gpio11 is an input;
   source unknown). No upstream S6E3FAC driver; gts9uwifi (same SoC/ABL, Samsung cmd-mode DSC panel) works
   on upstream msm.
   **UPDATE 2026-10-14:** panel driver written (kernel/patches/0003, compiles as a module, W=1), DT nodes merged
   into dts/dm1q/dm1q.dts, package r7 prepared with `DRM_MSM=m` (decision and comparison: docs/09 section 8),
   `collect-phone-state.sh --display` added. Not built, not flashed. Open: AVDD source, packet type (DCS vs
   generic long write), IRC byte, running r6 config/cmdline, first light itself (docs/09 sections 10-11).
   **UPDATE 2026-10-15: FIRST LIGHT CONFIRMED (docs/09 sections 13-14).** r7 built and flashed: msm bound, DSI-1
   connected 1080x2340@120, `panel id 81 02 25`, no DSI/DPU errors. Pixel test (`drm-fill`, user-reported, evidence
   `notes/2026-10-15-drm-test/`): colour bars + grey gradient, red, green, blue, white, console restored, no flicker
   or noise. This closes the DCS-vs-generic-write question (DCS works), the DSC topology question (2 encoders into
   one DSI works) and the display half of this item; the "only the bootloader framebuffer" statement above is
   history. Still open: AVDD source (unexplained), IRC byte 5, brightness range/default, warm-reboot and suspend/resume,
   MDP clock under load (dispcc `rcg didn't update its configuration` WARN, harmless so far), 60 Hz/VRR modes, GPU
   (`&gpu` disabled), upstreaming.
   **New in r7 (open, cause is INFERENCE):** 20 `arm-smmu 15000000.iommu: Unhandled context fault` lines (cbfrsynra
   0x1c00, cb=4, iova 0xb80xxxxx, 0.33-5.5 s; 0 in the r6 baseline `notes/2026-10-12-v12-touch`), consistent with
   `&mdss` joining an SMMU group while the bootloader scans out the splash buffer at 0xb8000000. Proposed DT fix
   (identity-mapped splash region via `iommu-addresses` + `&mdss` `memory-region`) applied and tested on hardware 2026-10-16 (DT-only, v17): faults 20 -> 3 (all within ~1.5 ms of the group join), `direct` region present, no warnings, msm + panel id fine; merged into the canonical DTS 2026-10-17, package r8 not built yet (docs/09 15.3).
   Boot-log noise (5625 lines in `notes/2026-10-15-drm-test/dmesg.txt`, of which 4471 are `initcall_debug`
   lines); the endless text on the console after a successful boot was the `dtbo-logger.sh` background loop running in the deleted initramfs: fixed in the script, tested on the PC, patched init_boot flashed and confirmed on hardware 2026-10-17: flood gone (docs/09 section 16).
