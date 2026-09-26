# Phase 1 workplan — devicetree bring-up

Goal of Phase 1: a `dm1q.dts` that boots mainline (or near-mainline) Linux far
enough to attempt display + storage + basic input, built from a clear
understanding of what's SoC-baseline vs. board-specific.

## Step 0 — Verify assumptions before writing any code

These gate everything below. Do these first; don't start diffing devicetrees
until they're answered.

- [x] Confirm dm1q's bootloader can actually be OEM-unlocked / already is.
      **Done 2026-09-13**: standard Samsung method — Developer Options →
      OEM unlock toggle, then unlock confirmed via Download Mode. No
      device-specific quirks reported.
- [x] Confirm dm1q pmaports package: kernel type, maintainer, last activity —
      **answer as of 2026-09-13: no such package exists in current pmaports**
      (searched live repo directly, zero matches for dm1q/dm2q/dm3q/kalama/
      sm8550). Contradicts an earlier "confirmed by hand in pmbootstrap init"
      note — see docs/02-open-questions-and-risks.md item 1b for the open
      follow-up (re-run `pmbootstrap init` interactively to resolve the
      discrepancy). Either way, there's no existing package to pull
      kernel-type/maintainer/activity info from.
- [x] Confirm the WCN Wi-Fi/BT chip in dm1q's crDroid kernel tree. **Done
      2026-09-13, and it's a CORRECTION, not a confirmation**: real source
      shows **QCA6490**, not WCN6855 as previously assumed from teardowns.
      See docs/02-open-questions-and-risks.md item 1 (corrected) for detail.
- [x] Identify the exact PMIC part(s) paired with dm1q. **Done 2026-09-13**:
      PM8550 (main), PM8550B, PM8550VE, PM8550VS, PM8010, PM8350C — see
      docs/02-open-questions-and-risks.md item 2 (resolved).
- [x] Note the panel driver/compatible string and touch controller vendor.
      **Done 2026-09-13**: dual-sourced panel — Samsung S6E3FAC (cell
      AMB606AW01) primary, Silicon Works LX83118 (cell CM002) alternate.
      Touch: Goodix Berlin (`goodix-berlin@5d`). See
      docs/02-open-questions-and-risks.md item 3b (resolved).

## Step 1 — Get reference materials in one place

- [x] Clone the Tab S9 Ultra pmOS repo (see 03-references.md) into a scratch
      location (originally kept uncommitted, moved into this repo under
      `../_scratch/` on 2026-09-14 — see `../_scratch/README.md`). Done
      2026-09-13: `../_scratch/gts9u-pmos-ref` and `../_scratch/gts9u-ubuntu-ref`.
- [x] Pull a recent mainline kernel tree (or at least `arch/arm64/boot/dts/qcom/`)
      to get the baseline `sm8550*.dtsi` files. Done 2026-09-13: sparse
      partial clone of `torvalds/linux` into `../_scratch/linux-mainline`,
      checked out to just `arch/arm64/boot/dts/qcom/` (~25MB total —
      slower than expected to fetch even with `blob:none`, since git still
      walks the full tree-object graph for one commit, but data-light on
      actual bytes transferred).
- [x] Extract dm1q's downstream device tree / kernel source from crDroid.
      **Done 2026-09-13**: real Samsung downstream `.dts` files (10 board
      revisions, `dm1q_eur_openx_w00_r01` through `r13`) from
      `crdroidandroid/android_kernel_samsung_sm8550-devicetrees` (the real,
      official crDroid devicetree-only repo — much smaller and more direct
      than pulling a full kernel source tree), cloned into
      `../_scratch/crdroid-dm1q-dts` (~96MB). This is the ground truth used
      for the WCN/PMIC/panel/touch answers above.

## Step 2 — The diff

**[x] First pass done 2026-09-13** — see
`docs/04-gts9u-vs-mainline-devicetree-diff.md` for the actual categorized
label list (105 board-specific labels found, grouped into SoC-blocks-being-
enabled / PMIC-regulator-definitions / pinctrl-states / tablet-only-ICs).
That was a regex heuristic diff, not DT-semantics-aware — good enough to
plan from, not to build blindly on. The general split below still holds and
is now backed by that real data rather than assumption alone:

**Transfers directly (SoC-level):**
- Core sm8550 dtsi include — clocks, GCC/RPMH, interconnects, CPU/cluster topology
- Adreno 740 GPU node + Turnip/Mesa userspace config
- UFS controller node (protocol-level — storage *layout* still device-specific)
- USB controller (DWC3) core setup
- PCIe controller *core* structure (bus/link setup transfers; the WiFi
  endpoint device node itself does not — dm1q is QCA6490/ath11k (corrected
  2026-09-13, was previously wrongly assumed to be WCN6855) while the
  Tab S9 Ultra reference is WCN7850/ath12k, see Step 0 and
  docs/02-open-questions-and-risks.md item 1)

**Needs full rebuild (board-level, source from crDroid tree):**
- Display panel driver — dual-sourced: Samsung S6E3FAC (cell AMB606AW01)
  and Silicon Works LX83118 (cell CM002), confirmed 2026-09-13. Different
  IC from the tablet reference either way — needs its own DSI panel
  driver(s) from scratch.
- Touch controller driver — Goodix Berlin (`goodix-berlin@5d`), confirmed
  2026-09-13.
- PMIC regulator mapping (rail names/voltages are per-board-schematic —
  the single most Samsung-model-specific piece)
- Battery fuel gauge, charger IC
- Pinctrl/GPIO mapping
- GPU/CPU OPP tables — SM8550-AC is a factory-tested higher bin than
  reference kalama, so voltage/frequency points likely need retuning,
  not copy-pasting

## Step 3 — First boot attempt

Follow the standard pattern used across sdm845/qcom mainlining efforts
(see the "crosshatch mainlining" reference in 03-references.md for the
canonical version of this checklist):

1. Build kernel with a stub DT, confirm it reaches `start_kernel` and reboots
   cleanly (proves boot chain / boot.img format is right before debugging actual hardware).
2. Add regulator + clock nodes, confirm no hangs.
3. Bring up UART/USB early console for real debug output.
4. Bring up display last, once everything upstream of it is confirmed stable.

## Log

*(append dated entries here as work happens)*

**Note (2026-09-14):** `../_scratch/` **was moved from a sibling, uncommitted location into this repo (with** `.git` **stripped from each cloned subfolder) and is now documented in** `../_scratch/README.md` **and the main README. Log entries below that describe it as "sibling to this repo, not committed
here" were accurate at the time they were written — treat them as history,
not current layout.**

- 2026-09-13: Repo created, workplan drafted from initial research. No boot
  attempt yet. Step 0 items outstanding.
- 2026-09-13 (later same day): Fact-check pass on all docs. Found and
  corrected two significant errors: (1) dm1q/dm2q actually use WCN6855 (ath11k), not an open question resolvable only by guesswork — confirmed via teardown + community sourcing that only the S23 Ultra (dm3q) matches the Tab S9 Ultra reference's WCN7850/ath12k chip; (2) pmaports lives at gitlab.postmarketos.org now, not gitlab.com (migrated Oct 2024) — explains why earlier GitLab searches for dm1q found nothing. See docs/02-open-questions-and-risks.md items 1, 6, 8, 9 for full detail and what still needs re-checking.

- 2026-09-13 (later still): Ran the actual pmaports check from Step 0 using
  Desktop Commander (shell access) instead of `pmbootstrap init`, via a data-light sparse partial clone (`git clone --filter=blob:none --depth=1 --no-checkout`) of the live repo into `../_scratch/pmaports` (sibling to this repo, not committed here). Searched the full tree directly with `git ls-tree -r` for dm1q/dm2q/dm3q/kalama/sm8550 — **zero matches anywhere**, including device/main. This contradicts the earlier "confirmed by hand in pmbootstrap init" note. Corrected 00-overview.md and open-questions item 1b accordingly. Still need an interactive `pmbootstrap init` run to fully resolve the discrepancy, but the working assumption going forward is: no existing dm1q package, from-scratch port.

- 2026-09-13 (evening): User pushed back on the "discredited" verdict for
  the agcarbajo Tab S9 Ultra repos, correctly — that verdict was wrong. Re-investigated properly (cloned both repos in a separate sandbox first, per user's request, before touching this machine): confirmed the repos are real, legitimate, technically competent unmerged personal pmOS/kernel ports, not fabricated. The earlier "false provenance" reasoning had wrongly assumed "pmaports package" meant "merged into official upstream pmaports" when it actually referred to the repos' own local pmaports-formatted staging folder — a normal, unremarkable setup for an unmerged community port. Verified with hard checks: real deviceinfo conventions matching the device's actual spec, a real resolvable commit hash cited from actual pmaports history, and real correct V4L2 kernel patch code against mainline drivers/media/i2c/hi847.c. Full correction and reasoning logged in docs/03-references.md and docs/02-open-questions-and-risks.md item 4. Both repos now cloned (shallow, depth=1, \~9.7MB total) into `../_scratch/gts9u-pmos-ref` and `../_scratch/gts9u-ubuntu-ref` (siblings to this repo, not committed here) for actual use as SM8550 reference material going forward. Next real step: use these — particularly `gts9u-pmos-ref/pmaports/device/testing/{device,linux}-samsung-gts9uwifi*`and `gts9u-ubuntu-ref/kernel/dts/sm8550-samsung-gts9uwifi.dts` — as the structural template for building dm1q's own device+kernel pmaports packages, adapting board-specific bits (panel, PMIC regulator names, sensors, pinctrl) using the crDroid downstream tree for real hardware values.

- 2026-09-13 (night, session close): Pulled real mainline
  `arch/arm64/boot/dts/qcom/` (sparse clone, `../_scratch/linux-mainline`) and diffed the gts9u board devicetree against the four upstream files it includes (`sm8550.dtsi`, `pm8550.dtsi`, `pm8550vs.dtsi`, `pmk8550.dtsi`). Full categorized result in the new `docs/04-gts9u-vs-mainline-devicetree-diff.md`. Headline: 105 board-specific labels, cleanly grouped into (1) SoC-level buses/blocks just being enabled for this board — same kind of work needed for dm1q with different values, (2) PMIC regulator rail definitions — confirmed as normal upstream practice by spot-checking real sm8550-hdk/sm8550-qrd reference boards, not gts9u-specific oddity, (3) board pinctrl/GPIO states — genuinely per-board, and (4) tablet-only third-party ICs not relevant to dm1q. Useful independent cross-check: gts9u's devicetree confirms it uses WCN7850, matching what this project's docs already had for the *Ultra*variant specifically — consistent with, not contradicting, the earlier WCN6855-for-dm1q/dm2q finding. **Status at end of session: Phase 1 Step 0 is \~60% done (pmaports check done; WCN/PMIC/panel checks against dm1q's own crDroid tree still outstanding). Step 1 (reference materials) is done. Step 2 has a first-pass structural map done, but zero real dm1q-specific values yet — nothing here has touched dm1q's actual kernel source tree. Step 3 (first boot attempt) hasn't started.** The single actual next blocker, unchanged by tonight's work: pull real values out of dm1q's downstream crDroid kernel/DT source (WCN chip confirmation, PMIC part number, panel/touch compatible strings, real pinctrl/GPIO/regulator values) to fill into the gts9u-derived skeleton. Nothing else meaningfully progresses until that happens.

- 2026-09-14: **Phase 1 Step 0 fully complete.** Found the real crDroid
  devicetree-only repo (`crdroidandroid/android_kernel_samsung_sm8550-devicetrees`, official, much smaller than a full kernel tree) and pulled dm1q's actual Samsung downstream `.dts` files (10 board revisions, \~96MB, into `../_scratch/crdroid-dm1q-dts`). This resolved every remaining Step 0 item with ground truth rather than inference:

  - **WCN chip corrected**: dm1q uses QCA6490, not WCN6855 (all 10 revisions
    checked, zero WCN6855 references). Still ath11k-family, mainlined earlier than WCN6855 if anything. Memory and docs 00/01/02/04 updated.
  - **PMIC confirmed**: PM8550, PM8550B, PM8550VE, PM8550VS, PM8010,
    PM8350C — a multi-PMIC setup, not the single part previously assumed.
  - **Panel confirmed**: dual-sourced — Samsung S6E3FAC (AMB606AW01) and
    Silicon Works LX83118 (CM002).
  - **Touch confirmed**: Goodix Berlin (`goodix-berlin@5d`).
  - **Bootloader unlock confirmed** (user-reported, not from source):
    standard Samsung OEM-unlock toggle + Download Mode, no quirks. Full detail in docs/02-open-questions-and-risks.md items 1, 2, 3b. **Step 0 is the first fully-closed step in this project.** Next real work is filling dm1q's real values (now in hand) into the gts9u/mainline skeleton from Step 2 — i.e., actually starting to write dm1q's own devicetree, not just planning it.

- 2026-09-14 (continued): Deeper extraction pass on the real dm1q crDroid
  devicetree source (`../_scratch/crdroid-dm1q-dts`), per user request for full regulator/pinctrl/GPIO tables. Wrote two small extraction scripts (`notes/extract_regulators.py`, `notes/extract_pinctrl.py`) since the source is a dtc-decompiled DTB (numeric phandles, lost labels) rather than hand-written source. Findings written up in the new `docs/05-dm1q-real-hardware-values.md`:

  - Found a previously-unknown IC: **s2mpb02**, a Samsung LSI sub-PMIC with
    18 LDOs + 2 bucks + 1 buck-boost, likely dedicated to camera/display rails.
  - Real GPIO numbers for touch (Goodix reset=GPIO24, irq=GPIO25) and
    WLAN/BT (QCA6490 enable/reset=GPIO80/81, sw-ctrl=GPIO82, xo-clk=GPIO204) and panel (reset=GPIO125, TE=GPIO86/87 for the two panel paths).
  - Full 663-entry pinctrl state table in `notes/dm1q-pinctrl-table.txt`.
  - **Honest limitation, not resolved**: the actual PM8550-family SPMI
    regulator channel-to-consumer mapping wasn't recoverable via text extraction — those subnodes don't carry descriptive names in this decompiled file. Flagged as a follow-up for when writing those specific consumer nodes, not a blocker.

- 2026-09-14 (continued, deep dive at user's request to "do it right, no
  corners cut" on PM8550 regulator mapping): Investigated whether the full PM8550 SPMI regulator channel-to-consumer mapping could be recovered from the downstream source. Found a genuine architectural wall: Qualcomm's downstream Android driver models PMIC regulators via an RPMh ARC voting layer (`kalama-regulators.dtsi`, internal codenames like `pm_v6e_l1`) — architecturally different from mainline's `qcom,rpmh-regulator` binding (`vreg_l1b`-style). No clean automatic translation exists between them, which is fine, since the mainline devicetree needs mainline's convention regardless. Resolved the QCA6490 WLAN/BT case specifically and completely by finding Samsung's own DTB+DTBO overlay fixup tables directly in dm1q's real source (`grep 'qcom,cnss-qca6490:.*-supply'`) — direct evidence, not inference: `vdd-wlan-io-supply`→L15B, `vdd-wlan-dig-supply`→S4E, `vdd-wlan-rfa1-supply`→S6G, `vdd-wlan-rfa2-supply`→S4G, `vdd-wlan-aon-supply`→S2G. Cross-confirmed against gts9u's independently- verified mainline mapping for the same RPMh resource IDs (S2G/S4E/S4G/S6G match exactly) and against dm1q's own separate WLAN PDC voting table (same resource IDs again) — three independent pieces of evidence agreeing. **Also corrected a wrong assumption made earlier in the same investigation**: initially assumed QCA6490 would use gts9u's WCN7850 7-supply naming scheme (vdd/vddio/vddio1p2/vddaon/vdddig/vddrfa1p2/ vddrfa1p8). Real evidence shows QCA6490's actual downstream driver only has 5 named supplies — genuinely different (simpler) binding, not a smaller version of the same one. Caught and fixed before it could get baked into a wrong devicetree later. Full writeup in docs/05-dm1q-real-hardware-values.md. Same fixup-table method is available for other consumers (panel, touch, etc.) on an as-needed basis when actually writing those specific nodes, rather than as a blanket upfront task.

- 2026-09-14 (night): **First real devicetree draft written: dts/dm1q/dm1q.dts**.Structural template from gts9uwifi + the real SM8450-HDK reference board (same QCA6490 chip, better match than gts9uwifi's WCN7850 for this specific node). Content: model/compatible/msm-id/board-id (CONFIRMED real values), the 5 real PM8550-family regulators behind dm1q's WLAN/BT (L15B/S2G/S4G/S4E/S6G, channel identities CONFIRMED, voltages INFERRED from platform-constant reasoning), the QCA6490 wcn6855-pmu node with real GPIO80/81/82/204 and the resolved supply mapping, and a touch controller placeholder (Goodix Berlin, real GPIO24/25, bus instance NOT yet confirmed). Display/PCIe/UFS/USB/camera deliberately left out -- explicitly marked, not silently missing. **Compiled and verified with real tooling, not just eyeballed**: `cpp`(for the #include/dt-bindings macros) piped into `dtc -@ -I dts -O dtb`, using the real mainline sm8550.dtsi/pm8550\*.dtsi as includes. Exit code 0, produces a valid .dtb. Caught and fixed two real bugs this way before they could sit undetected in the file: (1) an invalid, fabricated `label: &node-ref {}` override syntax for the L15B regulator that isn't valid devicetree at all; (2) a wrong PMIC assignment -- confused PM8550VS-E (an *instance letter* of PM8550VS) with PM8550VE (a *different chip*) for the S4E regulator. Both corrected by checking gts9uwifi's actual real structure rather than guessing. Needed two extra dependency fetches to get `dtc`/`cpp` working: `include/dt-bindings/` (7.7MB) and the one transitively-missing `linux-event-codes.h` target file -- both fetched into a genuinely separate `/tmp` location first, then copied in as plain files (same pattern as everything else in `../_scratch/`), not git-cloned directly into `../_scratch/linux-mainline` itself.

- 2026-09-14 (night, incident during the above): **Real, well-understood
  accident, fully recovered, documented for transparency and to prevent recurrence.** While trying to fetch missing dt-bindings headers, ran `git sparse-checkout` commands with cwd inside `../_scratch/linux-mainline`. **Root cause:** `../_scratch/linux-mainline` **(and everything else under** `../_scratch/`**) has no** `.git` **of its own** -- deliberately stripped before committing these as plain files into the outer repo (see `../_scratch/README.md`). Any `git` command run from inside those directories doesn't fail -- it silently walks up and operates on the **outer dm1q-mainline repo's `.git` instead**, since that's the nearest real one. This happened twice in a row before being correctly diagnosed, twice leaving the outer repo's `core.sparseCheckout` config stuck `true`with a cone-mode pattern excluding all subdirectories -- `docs/`, `notes/`, and most of `../_scratch/` disappeared from the working directory (but were NEVER at risk in git history/objects -- `git log` showed all commits intact throughout, and `git ls-tree HEAD` always showed the full file list). Fully recovered via `git sparse-checkout disable` (had to be run twice, since the first recovery attempt itself triggered the second incident the same way) and verified thoroughly afterward: tracked file count matches exactly between `git ls-tree HEAD` and the actual working directory (6895 = 6895), `git diff --stat` empty, directory sizes sane. **Lesson for future sessions: NEVER run** `git` **commands with cwd inside any** `../_scratch/` **subdirectory. If external repo content needs fetching or updating, do it in a genuinely separate location (e.g.** `/tmp/`**) and copy the needed files in afterward** -- exactly the pattern used successfully for the dt-bindings fetch right after this incident, and the same pattern already used (correctly) for every other addition to `../_scratch/` so far.

- 2026-09-15: `_scratch/` **moved back OUT of the repo, to a sibling location (**`../_scratch/` **from the repo root), not tracked in git**.Reverses the 2026-09-14 decision to commit it. Reasoning: the incident earlier this session (see the "Real, well-understood accident" entry above) happened specifically because `_scratch/`'s subdirectories have no `.git` of their own while living *inside* a git-tracked working tree -- any `git` command run there silently walks up and hits the outer repo's `.git` instead of failing cleanly. Confirmed `~/Documents/GitHub` itself is not a git repository (`git rev-parse --is-inside-work-tree` -&gt; "not a git repository, stopping at filesystem boundary"), so as a sibling location, the same mistake would now fail loudly and safely instead of silently damaging the repo. User's call, given they're the only person using this repo and `_scratch/` is genuinely just a workspace: prefer the sibling location; bring specific files back into the repo "in a more organized manner" later, once actually needed for something durable (e.g. once the real research file is settled, not the whole 90MB+ reference dump). Added `.gitignore` (`_scratch/`) to prevent accidentally re-tracking it. Fixed all path references in docs/README/dts (were `_scratch/...`, now `../_scratch/...` for files at repo root depth, or the correct relative depth for `dts/dm1q/dm1q.dts` specifically). Verified nothing broke: recompiled `dm1q.dts` from its new required path and got a byte-identical `.dtb` (same SHA256) as before the move.

- 2026-09-15 (continued): **Fixed the first-boot-relevant TODOs in
  dm1q.dts, starting from the user's request to investigate GPU/CPU OPP retuning.**

  - **OPP/CPR investigation (see docs/02-open-questions-and-risks.md item 3 for full detail): resolved favorably, no devicetree changes needed**.Mainline's SM8550 CPU OPP tables use EPSS hardware-driven voltage scaling (real per-chip fuse calibration at runtime), not static devicetree voltages — confirmed by reading the actual opp-table entries in sm8550.dtsi (opp-hz only, no opp-microvolt). The "SM8550-AC bin" concern doesn't threaten boot reliability; worst case is underclocking.
  - **UART console (uart7) confirmed and enabled.** Cross-checked GPIO26/27
    + function name in dm1q's real source against mainline's uart7 pinctrl
    — exact match. Added the missing `&uart7 { status = "okay"; }` override — sm8550.dtsi disables it by default, so without this there would be zero boot console output regardless of the aliases/chosen nodes already in the file. This was a real, silent first-boot blocker.
  - **microSD (sdhc_2) alias — corrected twice, see below for the final
    answer.** First pass: initially assumed dm1q might lack SD support (later S-series phones often do), then wrongly "corrected" to assume it DOES have SD support based on a real card-detect GPIO12 found in dm1q's downstream source. **Both were wrong. Final correction (2026-09-15, from the user, who physically owns the device): the Galaxy S23 has no microSD slot at all.** The card-detect GPIO12 is real data but doesn't mean what it was assumed to mean — it's evidently a leftover/shared definition from Samsung's common devicetree base, not populated hardware on this device. Lesson: real hardware ground truth from someone who owns the device beats devicetree-archaeology inference, however well-evidenced the inference seemed. `mmc1` alias removed entirely, `sdhc_2` left disabled permanently (not "deferred" — this is settled, not open).
  - **UFS (actual boot/root storage) substantially wired up.** Real
    fixup-table cross-referencing (same method as the QCA6490 regulator resolution) confirmed: reset-gpios = GPIO210 (exact match with gts9uwifi), vccq-supply = PM8550VS-G L1, vdda-pll-supply = PM8550VS-E L3, vdda-phy-supply = PM8550VS-E L1 (downstream property name differs — "vdda-qref-supply" — but same physical rail, confirmed by channel match). All channel identities confirmed via dm1q's own fixup tables, all four exactly matching gts9uwifi's channel assignments (strong platform-fixed-channel cross-confirmation, same pattern as WLAN). **vcc-supply (main UFS power) deliberately left unresolved, not guessed**: dm1q's fixup table shows it fed by a PMIC instance letter ("humu") that doesn't appear anywhere in Qualcomm's own reference kalama-pmic-overlay.dtsi — a Samsung-specific addition, not one of the chips already in this file. Blindly copying gts9uwifi's vreg_l17b_2p5 (PM8550B) would have wired UFS main power to the wrong physical chip. UFS host controller node stays `status = "disabled"` until this is resolved — better to boot without storage working than to guess wrong on the main power rail for the boot device. Verified throughout with real `cpp`+`dtc` compilation, not just written and assumed correct — caught and fixed one real syntax bug (an orphaned comment block from a bad find-replace) during this pass. Final state: exit code 0, only the two already-known/flagged placeholder warnings (wcn6855-pmu, i2c-touchscreen — both have missing reg/ranges by design, since they're intentionally incomplete) plus mainline's own upstream warnings (duplicate i2c/spi unit addresses — normal Qualcomm QUP pattern, not something to fix here). **Still open after this pass**: UFS vcc-supply identity, touch controller's I2C bus instance, display/panel (deferred, needs real driver work). microSD is settled (no slot exists), not open.

- 2026-09-15 (continued): **UFS vcc-supply resolved via live hardware
  measurement — a new technique for this project.** Gained root on the physical device via KernelSU (whitelisted the `shell` identity for adb), then read `/sys/class/regulator/` directly. Found `regulator.44`(`pm_humu_l17`) has a consumer symlink literally naming the UFS host controller's exact address — fully unambiguous. Live values: state=enabled, 2.504V (fixed), 1 consumer, fast mode. Also checked real kernel mailing list patches for PM8350C's documented regulator range, which partially matches "humu"'s BOB capability but not its full channel count — concluded "humu" is likely an RPMh domain aggregating multiple PMICs (2× PM8010 + PM8350C), not a single chip, and didn't force a wrong single-chip identification. dm1q.dts now models this as a `regulator-fixed` node at the real measured voltage rather than the unresolved real PMIC chain — a deliberate, evidenced choice (UFS holds boot media, so firmware must already enable this rail before Linux starts; live num_users=1 confirms no dynamic sharing to misrepresent). `&ufs_mem_hc` now `status = "okay"`. Full writeup in docs/05-dm1q-real-hardware-values.md. **This live-device measurement technique is now available for other stuck items** — worth reaching for earlier next time static source analysis hits a genuine wall, rather than only as a last resort. Verified via real compilation as always: exit code 0, no new errors.

- 2026-09-15 (continued): **Full live-hardware verification pass on every
  remaining "INFERRED" regulator value in dm1q.dts.** Checked all 8 gts9uwifi-inferred voltages (L15B, L3E, L1E, L1G, S4G, S6G, S4E, S2G) against the real physical device via adb/KernelSU root. Also independently cross-confirmed all 5 WLAN channel identities via `/sys/class/devlink/` consumer symlinks (a second, more direct method than the downstream fixup-table approach used earlier). **Result: every single inferred value either matched exactly or fell within the real confirmed range** — strong validation of the cross-referencing methodology used throughout this project. Updated dm1q.dts to use real min/max ranges (rather than the originally-guessed single fixed points) for the genuinely multi-corner ARC-voted rails (S2G, S4G, S6G, S4E, L1E, L1G) — more accurate and matches how real mainline reference boards represent these. L15B and L3E stay fixed single values since the real device confirms they genuinely are fixed (min=max). Full comparison table in docs/05-dm1q-real-hardware-values.md. Fixed one duplicate-label bug introduced mid-edit (caught before commit via the usual cpp+dtc compile check, exit 0 clean).

- 2026-09-15 (continued): **Two corrections from the user, plus the touch controller I2C bus resolved**.User corrected (ground truth, physically owns the device): the Galaxy S23 has no microSD slot at all. This overturns an earlier "confirmed" conclusion in this same file that took a real card-detect GPIO12 in dm1q's source as sufficient evidence for SD support — it wasn't; that GPIO is evidently a leftover/shared definition from Samsung's common devicetree base. `mmc1` alias removed from dm1q.dts entirely, `sdhc_2`now documented as permanently N/A rather than "deferred." Real hardware ground truth from the device owner overrides devicetree-archaeology inference, however well-evidenced the inference seemed at the time. **Touch controller I2C bus — resolved via the live device's own booted devicetree** (`/sys/firmware/devicetree/base/`, not inference): address 0xa90000 matches mainline's `&i2c4` exactly. Also cross-checked reset-gpio/irq-gpio/irq-flags directly from the live tree — all matched the earlier fixup-table-based extraction exactly, good corroboration of that method too. dm1q.dts updated to use the real `&i2c4` bus instead of a placeholder container; this also removed a real compile warning (missing reg/ranges), not just resolved a TODO comment. Verified via cpp+dtc as always: exit 0, one fewer warning than before.

- 2026-09-15 (continued): **USB fully wired up (HS PHY, SS PHY, real eUSB2 repeater), using the same live-evidence methodology as UFS/WLAN**.Confirmed QCA6490 is genuinely PCIe-attached (`qcom,wlan-rc-num = <0x00>`in dm1q's real source, "rc-num" = PCIe Root Complex number) before starting PCIe work next. New PMIC channels identified: L5B (PM8550B, 3.104V, eUSB2 repeater vdd3) and L3F (PM8550VE, 0.912V, USB SS PHY vdda-pll) -- the latter required finally adding `pm8550ve.dtsi` with its real confirmed SID (5), resolving a TODO left over from the very first devicetree draft. eUSB2 repeater resolved via real kernel dmesg (not just static devicetree): of two candidate repeater nodes in the tree (PMIC-SPMI vs. NXP-I2C), only the NXP one shows real probe activity on the live device. Its full real init register sequence was read directly from the device's own booted devicetree and cross-matched dmesg byte-for-byte. Obtained Samsung's own official GPL kernel source (opensource.samsung.com, SM-S911B, \~3.5GB) for the display driver investigation -- confirmed real, substantial panel driver logic exists, but the exact raw DCS byte table wasn't located this session (see the dedicated section in docs/05 for the full trail and where to look next). Also downloaded crDroid's full kernel source (not just -devicetrees) to check for panel driver code there -- confirmed it does NOT contain Samsung's proprietary panel framework (only generic Qualcomm DPU controller code), consistent with that framework being distributed as a vendor module rather than GPL kernel source in crDroid's build. Verified via cpp+dtc throughout: exit 0, no new errors, only expected warnings (own placeholder + mainline's own upstream duplicate-address warnings).

- 2026-09-15 (continued): **PCIe0 wired up — the bus QCA6490 actually
  attaches over.** Confirmed genuinely needed (dm1q's real qcom,wlan-rc-num=0, and the live device's actual PCI bus topology shows exactly one populated domain with the QCA6490 endpoint at the expected vendor/device ID). pcie1 exists but is unused on this board. **Major discovery: sm8550-samsung-q5q.dts (Z Fold5) already exists in real, already-upstream mainline Linux** (named Linaro/community contributors, not something needing the same scrutiny as the earlier agcarbajo situation). Its real values for PCIe (GPIOs, regulators) exactly match what we'd already independently confirmed via live measurement on dm1q -- genuinely strong cross-validation from two independent methods landing on the same answer. **Follow-up identified, not yet done**: worth cross-checking q5q against everything already wired in dm1q.dts (WLAN, UFS, USB) as additional free confirmation, given it's a real, same-family, already-upstream reference we didn't know existed until now. Should happen before or alongside the actual boot attempt. Verified via cpp+dtc: exit 0, no new errors, only expected warnings.

- 2026-09-16: **Cross-checked dm1q.dts against sm8550-samsung-q5q.dts (Z
  Fold5, real already-upstream mainline), per the follow-up flagged at the end of the PCIe work.** WLAN and USB not comparable (q5q doesn't have those wired up in this mainline state). UFS comparison genuinely improved the file:

  - Added the missing `vdd-hba-supply` (L3G) -- a real gap, not just a
    confirmation.
  - **Properly resolved `vcc-supply`**, replacing the workaround
    fixed-regulator with the real PM8550B L17 subnode. q5q's real value exactly matched the live-measured channel from the earlier UFS investigation -- this also retroactively confirms "humu" (the previously-unidentified PMIC codename) is PM8550B's own internal RPMh codename.
  - One genuine discrepancy found and correctly left alone:
    `vdda-phy-supply` is L1E for dm1q (direct evidence from dm1q's own fixup table) vs. L1D for q5q -- reasoned through as an expected board-to-board SPMI-instance-letter difference (different physical PCB layouts, foldable vs. slab phone), not a contradiction requiring a fix. Removed the now-dead `vreg_ufs_vcc_2p5` workaround regulator definition. Verified via cpp+dtc: exit 0, no new errors. User caught and corrected a mix-up during this session: an earlier reply mistakenly implied the user had told Claude the touch controller was Goodix -- it was actually found independently from dm1q's own real devicetree (twice: static source + live confirmation). Also flagged a real discrepancy worth recording: an iFixit teardown identifies the touch controller as STMicroelectronics for the S23 *Ultra*specifically -- confirmed via the user's own further research that the base S23 (dm1q) does use Goodix, resolving the apparent conflict as a variant difference, not an error in either source.

- 2026-09-19: **Checked kernel defconfig against postmarketOS's real
  kconfigcheck.toml spec** (fetched fresh from pmaports, "community" category -- the full real target checklist). Wrote notes/check_kconfig.py to parse the TOML (handles version/arch ranges) and cross-check against our actual .config, since manual comparison against 475 option requirements isn't practical by hand. **Result: 313 of 475 don't match.** Mostly not concerning for right now -- the bulk is accessibility (SPEAKUP screen reader), containers/ Waydroid netfilter rules, exotic filesystems (exFAT/F2FS/XFS/EROFS), and hardening/CFI -- all genuinely needed for a real, polished, submittable pmOS device port, but not relevant to the immediate goal (prove the devicetree boots to a shell). **Applied narrowly**: only UEVENT_HELPER=y and NULL_TTY=m -- cheap, harmless, genuinely useful for device-node robustness even in a minimal initramfs, verified via scripts/config + olddefconfig. Confirmed DEVTMPFS/DEVTMPFS_MOUNT/TMPFS/SERIAL_QCOM_GENI_CONSOLE were already on by default, covering what's actually load-bearing for the shell itself. **Deliberately deferred**: the other \~311 items. Revisit once basic boot is proven and an actual pmaports submission is the goal, not before. kconfigcheck.toml and kconfig-generic.toml fetched to /tmp during this check (not persisted anywhere in-repo since they're a live upstream spec, easy to re-fetch when needed again).

- 2026-09-20: **First real kernel build + boot image assembly — materials
  ready for a real flash/boot attempt, not yet flashed.**

  **Scope clarified up front**: this builds a real upstream mainline kernel with dm1q.dts, plus a bare-minimum custom initramfs (busybox + a one-line shell /init). This is NOT postmarketOS -- no Alpine userspace, no pmaports packaging, no init system. It's the smallest possible thing that can prove "does this kernel initialize dm1q's real hardware," deliberately separated from the actual pmOS work.

  **Safety planning first**: user's device is their daily driver, so walked through real risk before touching anything. Corrected an early wrong assumption of mine: Samsung phones do NOT support fastboot at all (confirmed via web search) -- they use their own proprietary Odin/ Download Mode protocol exclusively (heimdall on Linux). No temporary/non-persistent boot option exists the way fastboot boot offers on other Android devices -- any real test requires an actual persistent flash. Real risk assessment: true hard-bricking is rare for boot-partition-only testing, since Download Mode lives in the PBL (protected boot ROM) entirely separate from anything being flashed, and is specifically designed to survive a bad kernel/bootloader. Real risks are wrong-partition-targeting and power loss mid-flash, not kernel badness itself. User has stock firmware, crDroid, OrangeFox, and confirmed Download Mode access as the recovery path. User will do the actual flashing themselves via Heimdall GUI.

  **Kernel build**: full shallow clone of torvalds/linux (2.1GB, `../_scratch/linux-build/full`), built with clang/LLVM (already available, no separate cross-toolchain needed -- matches what real Android GKI kernels use). arm64 defconfig already had everything needed for SM8550 (CONFIG_INTERCONNECT_QCOM_SM8550=y confirmed, all PHY/UFS/USB/PCIe/ATH11K/regulator drivers present). Kernel version built: 7.3.0-rc3.

  **Checked against postmarketOS's real kconfigcheck.toml spec**(per user's specific request) -- see the 2026-09-19 entry above for the full detail. Applied only the two genuinely load-bearing-adjacent options (UEVENT_HELPER, NULL_TTY); deferred the other \~311 (real pmOS submission work, not relevant to this first boot test).

  **dm1q.dtb built through the real Kbuild system** (not just our standalone cpp+dtc check used throughout earlier devicetree work) -- genuine additional validation that it integrates cleanly with the full kernel build, not just standalone dtc. 120176 bytes.

  **Initramfs**: real Alpine busybox-static (v1.37.0-r30, aarch64, fetched directly from dl-cdn.alpinelinux.org -- thematically apt given the eventual pmOS/Alpine target) plus a minimal /init that mounts proc/sys/devtmpfs and execs a shell. 657KB gzip-compressed cpio.

  **Real boot image structure discovered, not assumed**: pulled the actual current boot/init_boot/vendor_boot partitions directly off the device via adb+dd (root via KernelSU) -- this doubles as a complete, exact backup of the working boot state before any flash is attempted. unpack_bootimg revealed a true 3-way GKI split (boot=kernel only, init_boot=generic ramdisk, vendor_boot=vendor ramdisk+dtb), header version 4, matching gts9uwifi's real deviceinfo (header_version=4, flash_pagesize=4096) exactly. Extracted real parameters: kernel load 0x8000, ramdisk load 0x1000000, dtb load 0x1f00000, real vendor cmdline, os_version 16.0.0, patch level 2026-07.

  **Built three replacement images** with mkbootimg, verified by re-unpacking each and diffing against the originals -- everything identical except the intentional swaps (our kernel in boot_new.img, our initramfs in init_boot_new.img, our dtb -- 120176 bytes, replacing Samsung's 1.8MB multi-board-revision blob -- in vendor_boot_new.img, vendor ramdisk otherwise byte-identical). Both raw .img and img2simg-converted .simg versions produced, since it wasn't certain which format this Heimdall GUI expects (Heimdall/Odin traditionally expects raw, sparse is more of an AOSP/fastboot convention) -- left the choice to the user rather than guessing.

  All materials in `../_scratch/boot-backup-20260920/`: the three original partition dumps (backup/recovery path), the three new replacement images (raw + sparse), and the unpacked component directories for reference.

  **Status: ready for the user to flash via Heimdall. Not yet flashed, not yet tested on real hardware.** Next real milestone: an actual boot/flash attempt.

- 2026-09-21: **First flash attempt did NOT boot — phone dropped to Download Mode with an AVB/vbmeta error. Diagnosis in progress; nothing settled yet**.User-reported (ground truth): (1) flashed the three raw `*_new.img` via recovery (recovery is its own partition on this device) -&gt; phone went to Download Mode showing phone info, no indication of which partition failed. (2) Then flashed the `*_new.simg` sparse versions via Heimdall -&gt; Download Mode now shows `partition vbmeta` / `Reason CUSTOM vbmeta`. **Found while checking the backup dir (**`avbtool info_image` **on the originals):** the stock-on-device images are LineageOS/crDroid-built (fingerprint `samsung/lineage_dm1q/dm1q:16/...release-keys`) and each carries an AVB hash footer at the very end of the partition (Algorithm NONE, Flags 0, sha256 hash descriptor naming the partition; e.g. boot.img: 48054272-byte image inside a 100663296-byte partition). **Our** `*_new.img`**have no footer at all** (tail is zeros) — built with mkbootimg only. The 2026-09-20 "verified against originals" check used unpack_bootimg diffs, which cannot see an AVB footer, so this gap was missed. **Second gap: the `vbmeta` partition itself was never backed up** in `boot-backup-20260920` (only boot/init_boot/vendor_boot). **Still unknown:** vbmeta's current flags/descriptors; whether "CUSTOM vbmeta" is simply the normal crDroid state or something the flash changed; whether sparse-vs-raw contributed (raw failed first, so it isn't the sole cause). Do not treat any of these as diagnosed. **Plan:** (a) restore the three original raw dumps via Heimdall and boot crDroid; (b) dump `vbmeta` (and `vbmeta_system` if present) from the running device and `avbtool info_image` it; (c) then choose between adding matching hash footers to the new images (`avbtool add_hash_footer`) and flashing a verification-disabled vbmeta — decided by what (b) shows.

- 2026-09-21 (later, phone reconnected via adb): **Phone is booted and healthy
  — crDroid 12.11 (build 20260704, Android 16, kernel 5.15.206), Magisk 30.7 root (**`su` **context** `u:r:magisk:s0`**; earlier entries said KernelSU — observed now, not investigated why).** Assessed read-only, then backed up everything relevant to `../_scratch/boot-backup-20260921-restored/` (vbmeta, vbmeta_system, boot, init_boot, vendor_boot, recovery, dtbo; sha256 recorded by `sha256sum` at the time). This closes the "vbmeta never backed up" gap. **Gotcha worth remembering: `getprop` lies about boot state.** Props show `verifiedbootstate=green`, `device_state=locked`, `flash.locked=1`, `warranty_bit=0`, and stock fingerprints — all spoofed (Play Integrity style). The bootloader-provided truth is in `/proc/cmdline`/bootconfig: `androidboot.verifiedbootstate="orange"` (unlocked). Use that, not getprop, when judging lock state. Partition layout is non-A/B (no `_a/_b` on boot partitions; `vbmeta`, `vbmeta_system`, `recovery` all exist). **vbmeta findings (`avbtool info_image`):** `vbmeta.img` is Samsung's stock vbmeta (SHA256_RSA4096, Samsung-era props os_version 13) but with **Flags: 3** (verity + verification disabled) — i.e. a patched stock vbmeta, which is presumably what the bootloader labels "CUSTOM vbmeta". It has non-chained hash descriptors for stock boot/abl/hyp/etc. `vbmeta_system.img`is crDroid's (lineage_dm1q fingerprints, own key). Currently installed boot/init_boot/vendor_boot are crDroid images with AVB hash footers (Algorithm NONE) but are **not byte-identical** to the 2026-09-20 dumps (e.g. boot original size 47853568 vs 48054272) — the phone was restored by some route other than flashing those dumps back; how is unrecorded. **Open, not diagnosed:** with vbmeta Flags=3 the missing footer *shouldn't*matter to libavb, yet Samsung's abl still rejected the images and named vbmeta. So the footer is the one known difference, not a proven cause. **Prepared for next attempt (nothing flashed):** footer-bearing copies of the test images in `../_scratch/boot-backup-20260920/avb-footered/`(`*_new_avb.img`, `avbtool add_hash_footer`, Algorithm NONE, padded to exact partition sizes 96M/8M/96M; payloads verified byte-identical to `*_new.img`). Changes only one variable vs. the failed attempt. Flash raw via Heimdall, not sparse, and not through recovery, so a failure is attributable.

- 2026-09-21 (attempt 3 result + prior-art finding + v2 build): **Flashed** `avb-footered/*_new_avb.img` **raw via Heimdall (BOOT/INIT_BOOT/VENDOR_BOOT) — upload OK, phone landed back in Download Mode with NO vbmeta message**(user-reported; identical symptom to attempt 1). Tally: attempt 1 raw/no footer/via recovery -&gt; silent DL; attempt 2 sparse/no footer/Heimdall -&gt; "vbmeta CUSTOM"; attempt 3 raw/footer/Heimdall -&gt; silent DL. **Correction to the entry above: the vbmeta message tracks the sparse flash, not the missing footer, and the footer did not change the outcome.** The real failure is silent and sits elsewhere. USB log: after the flash the device never showed any ID other than Samsung Download Mode (04e8:685d), \~20 s after leaving the flash session — consistent with rejection in ABL or a silent kernel (our initramfs has no USB gadget, so USB can't distinguish them). **Heimdall quirk (user-observed): a Download Mode session accepts ONE command.** `print-pit` consumes it; reboot to Download Mode again before the real flash. `detect` did not consume it. **Prior art that explains this class of failure — gts9uwifi (same SoC, same Samsung ABL family),** `../_scratch/gts9u-pmos-ref/docs/{boot-strategy, testing-mainline-v0,porting-log}.md` **+** `scripts/build-android-v4-bundle.sh`**:**

  * ABL filters the DTB by downstream `qcom,msm-id`/`qcom,board-id`; no match -&gt; "No match found for Soc Dtb type" -&gt; "Launching odin" (= Download Mode). dm1q.dts already carries the real msm-id (4 pairs) and board-id `<0x10008 0x0d>` + the three `qcom,kalama-mtp/kalama/mtp` compatibles, matching downstream r13. **Not yet cross-checked against the live device tree of THIS unit's board revision — do that from /proc/device-tree next time the phone is booted.**
  * Then ABL applies the stock `dtbo` overlays with Samsung's ufdt fork. That
    fails on a mainline DTB even for no-op overlays with selectors and /**symbols** ("ApplyOverlay: ufdt apply overlay failed ... Launching odin"). **The proven workaround: make** `dtbo` **NOT a valid Android DT table (zero-prefixed image + AVB footer, padded to 16 MiB); ABL then skips overlay and uses a DTB appended to the kernel (**`Image.gz` **+ raw DTB concatenated).** ABL takes DtbOffset from the end of the gzip member.
  * Their generic ramdisk had to be legacy LZ4 (stock format); gzip was rejected
    by Linux ("invalid magic at start of compressed archive"). Their kernel is Image.gz. Their `vbmeta` flags=2; ours is 3 (also fine).
  * Not a factor here (checked): SEANDROIDENFORCE trailer is absent from the
    working crDroid boot.img too; the working crDroid kernel is a raw `Image`; Samsung's vendor ramdisk has no top-level `/init` (only first_stage_ramdisk and lib), so it can't shadow ours. **Our images had none of the three fixes** — stock 10-entry \~1 MB dtbo left in place, DTB only in vendor_boot, gzip initramfs. Most likely cause of every silent Download Mode drop so far, but UNTESTED on dm1q (different device, same ABL family). Also note early console is unreliable: ABL can inject `console=null`; no microSD on dm1q, so no rootfs-on-SD diagnostics either. **v2 built, nothing flashed:** `../_scratch/boot-backup-20260920/ v2-appended-dtb/{boot,init_boot,vendor_boot,dtbo}_v2.img`. boot = gzip(Image)


  + dm1q.dtb appended (gzip member end verified to be followed by FDT magic,
  DTB byte-identical, decompressed Image identical to prior build); init_boot ramdisk = same cpio re-compressed to legacy LZ4; vendor_boot = unchanged; dtbo = 4096 zero bytes; all four with AVB hash footers verified by `avbtool verify_image`. **First time `dtbo` is touched** — rollback image is `boot-backup-20260921-restored/dtbo.img` (stock 10-entry table as installed). Next visibility step if v2 boots but shows nothing: add a configfs USB gadget (ACM/ECM) to the initramfs so a running kernel enumerates on the PC, and ramoops in the DT so a crash can be read back from crDroid afterwards.

- 2026-09-21 (attempt 4, v2 flashed — FIRST TIME PAST ABL): flashed
  `v2-appended-dtb/{boot,init_boot,vendor_boot,dtbo}_v2.img` raw via Heimdall (all four uploads OK, sha256s from the run: boot 90354b32…, init_boot eb7affe1…, vendor_boot b0554a35…, dtbo 63852b23…). **User-reported result: bootloops — i.e. no more Download Mode, ABL now accepts the images and hands off.** This confirms the sister-device diagnosis: the stock dtbo/ufdt overlay path was what ABL choked on; invalid-dtbo + appended-DTB gets through. (Not proven which of the three v2 changes mattered — dtbo, appended DTB, LZ4 ramdisk — all went in together.) Host USB log: nothing enumerated after the flash session disconnected (05:22:11) — expected, initramfs has no gadget. **Why it probably loops (unverified, from gts9uwifi history + our files)**:gts9uwifi v0.4/v0.5 also "ran Linux" then TrustZone reset the SoC on a fatal NoC error; fixed with Samsung carveouts + disabling a provider. Gaps in ours: (1) `dm1q.dts` has NO `reserved-memory` carveouts beyond mainline defaults and no simple-framebuffer; (2) vendor cmdline is still crDroid's (`androidboot.* printk.devkmsg=on firmware_class.path=… bootconfig`) — no `clk_ignore_unused pd_ignore_unused regulator_ignore_unused`, no `console=`/ `earlycon`, no `panic=`. The reference bring-up cmdline uses all of those. **Next steps:** (a) boot recovery (key combo, recovery partition untouched) and pull `/proc/last_kmsg`, `/sys/fs/pstore/*` — the reference got the next XBL's reset diagnostics (`restart_reason`, PSHOLD, NoC fatal) that way; (b) after restoring crDroid, dump the LIVE `/proc/device-tree/ reserved-memory` + `memory` nodes and diff against mainline sm8550.dtsi to build the Samsung carveout map from ground truth (same live-device method as UFS/WLAN/USB); also read live `qcom,board-id`/`qcom,msm-id` to confirm the 0x0d selector for this unit; (c) add the bring-up cmdline flags to vendor_boot in the next build. **Rollback set (known good):** `boot-backup-20260921-restored/{boot, init_boot,vendor_boot,dtbo}.img` — flash all four raw via Heimdall from Download Mode (Vol Down + Vol Up + cable).

- 2026-09-21 (v2 crash diagnosed from recovery; v3 built, NOT flashed): user
  booted the (untouched) recovery partition; adb root works there. Raw dumps in `notes/2026-09-21-v2-bootloop/` (`last_kmsg.txt`, `live-reserved-memory.txt`, `recovery-misc.txt` — device serial / EM DID redacted). **Result:** `/proc/last_kmsg` **(XBL log of the boot after our crash) says** `restart_reason = 0xfae99986`**,** `upload_cause = TZBSP_ERR_FATAL_NOC_ERROR`**, reset by PSHOLD.** Same fatal the gts9uwifi port hit v0.4–v0.7. The NoC master/slave detail is in the encrypted TZ log ("tz log is encrypted or not parsed yet!"), so it can't be attributed to a driver from this log alone. **Most likely trigger (by analogy, untested on dm1q): TLMM GPIOs reserved for TrustZone.** On gts9uwifi, `sm8550-tlmm` probe touching GPIO 36–39 caused exactly this; `gpio-reserved-ranges = <36 4>` removed the fatal (they then got a normal kernel panic = next problem). dm1q's downstream r13 overlay has `qcom,gpios-reserved = <0x24 0x25 0x26 0x27 0x32 0x33>` (= GPIO 36–39 and 50–51), identical to already-upstream `sm8550-samsung-q5q.dts`(`<36 4>, <50 2>`). `dm1q.dts` had none. (Downstream property is `qcom,gpios-reserved`, so a plain grep for `gpio-reserved-ranges` in the downstream source finds nothing — easy to miss.) **Live-tree confirmations from recovery:** `qcom,board-id = <0x10008 0x0d>`and the 4-pair `qcom,msm-id` exactly match `dm1q.dts` (this unit really is rev 0x0d). Live reserved-memory map dumped (≈70 nodes); the Samsung bootloader/debug carveouts are at the same addresses as gts9uwifi (sec_log_buf 0x880200000/2 MiB, splash 0xb8000000/0x2b00000, kaslr 0xb01ff000, chipinfo 0x81cf4000, …) except uh_guest_region = 0xb1000000/ 0x3000000 on dm1q. `splash_region` really carries `label = "cont_splash_region"`. **v3 changes (all in `dts/dm1q/dm1q.dts` + `kernel/`):** (1) `&tlmm { gpio-reserved-ranges = <36 4>, <50 2>; }`; (2) board carveouts as `reserved-memory` children from the live values (+ `/delete-node/ &adspslpi_mem` and redefine at the live size), 62 static ranges checked, 0 overlaps in the compiled DTB; (3) persistent console: new driver `drivers/soc/qcom/samsung-sec-log.c`(patch: `kernel/patches/0001-…patch`, config `CONFIG_SAMSUNG_SEC_LOG=y` in `kernel/config/dm1q.fragment`) writing printk into the Samsung `sec_log_buf`ring (LOGM header) so the NEXT failure is readable from recovery as `/proc/last_kmsg`. Adapted from the gts9uwifi patch (GPL-2.0, credited in the file) but registered from `early_initcall` so it captures before the pinctrl/regulator probes; `previous_index` mirrored on every write. Built on kernel 7.3.0-rc3 in 16 s incremental; `sec_log_init`/`sec_log_write` present in System.map; (4) vendor cmdline: `console=ttyMSM0,115200n8 loglevel=7 log_buf_len=4M clk_ignore_unused pd_ignore_unused regulator_ignore_unused` + `androidboot.*`/`bootconfig` kept; deliberately NO `earlycon` (uart7 clocks are probably off under ABL → an early write could itself fault the bus) and NO `panic=` (hang instead of reboot loop, easier to observe). **Files:** `../_scratch/boot-backup-20260920/v3-tlmm-seclog/{boot,vendor_boot} _v3.img` (changed), `init_boot_v3.img`/`dtbo_v3.img` (= v2, unchanged). boot = gzip(Image)+dtb appended (verified), vendor_boot dtb byte-identical to built dtb, Samsung vendor ramdisk fragment byte-identical, AVB footers verified. sha256: boot_v3 8f44fda3…, vendor_boot_v3 1f7e08d4…. **Flash path note:** recovery gives adb root, so changed partitions can be written from recovery with `dd` + sha256 readback (as the gts9uwifi port does) instead of Download Mode's one-command-per-session Heimdall; only boot + vendor_boot changed vs v2. Rollback: v2 set, or the crDroid set in `boot-backup-20260921-restored/`. **Caveats:** the tlmm fix is a strong-but-analogical hypothesis; v3 may hit the next problem (X910's next failure was a plain kernel panic). Carveouts were not the trigger on X910 but are correct to have.

- 2026-09-21 08:42 (v3 flashed from recovery via adb `dd`): before writing, the
  installed boot/vendor_boot sha256 matched `boot_v2.img`/`vendor_boot_v2.img`exactly (so the v2 files are the rollback copy). Pushed `boot_v3.img` + `vendor_boot_v3.img` to recovery /tmp (device sha256 == host), `dd conv=fsync` to `/dev/block/sda25` (boot) and `/dev/block/sda28`(vendor_boot), both partitions 100663296 bytes; readback sha256 verified, re-verified after `drop_caches` (boot 8f44fda3…, vendor_boot 1f7e08d4…). Then `adb reboot`. **Observed on host: for 90 s after reboot no Samsung USB device enumerated at all — not Download Mode (ABL accepted the images), and no gadget (expected, initramfs has none).** Screen behaviour not yet reported. Next: force off, boot recovery, pull `/proc/last_kmsg` — first real test of the sec_log persistent console (look for `sec_log: persistent console at`and how far the kernel got) and whether upload_cause is still TZBSP_ERR_FATAL_NOC_ERROR.

- 2026-09-21 (v3 result read from recovery; v4 built): user reported "stuck on
  splash" after v3. Raw data: `notes/2026-09-21-v3-splash/` (`last_kmsg.txt`, `reset_history.txt`). **What the Samsung ring shows (recovery `/proc/last_kmsg`, boot #2 = v3):** XBL(2) starts with `Reset by PSHOLD / Hard Reset / PON by CBLPWR` (= the normal `adb reboot` from recovery), ABL runs to `Shutting Down UEFI Boot Services: 5494 ms` (hand-off to Linux at \~5.5 s), and the next XBL(3) starts with `PON by PWR key DEB` = the user's manual key reset. **No TZ fatal / warm reset between them, so v3 did NOT die with TZBSP_ERR_FATAL_NOC_ERROR the way v2 did** (reset_history shows three consecutive TZBSP_ERR_FATAL_NOC_ERROR at RWC 90–92, each \~14 s after XBL start, from the v2 loop; nothing newer). User's reading (booted, just no display to overwrite the splash) is consistent with this, but "hung early" cannot be excluded — a hang and a healthy no-output boot look identical from here. **Why nothing was observable even if v3 ran (found while reading configs)**:the kernel config was an arm64 defconfig with DRM=m, no simpledrm, no fbcon font, and **all USB pieces as modules** (eUSB2 PHY, PTN3222 repeater, GENI I2C, libcomposite/configfs) while the initramfs contains only busybox and no modules — so no display and no USB could ever come up. Also, **the sec_log ring shows NO kernel output between XBL(2) and XBL(3)**: my console driver did not deliver anything visible (either the kernel never got to early_initcall, or the ring hand-off differs from gts9uwifi's). Unresolved. **Bug found in dm1q.dts (USB could never have worked):** the eUSB2 repeater node used `compatible = "nxp,eusb2-repeater"` with `vdd18-supply`/`vdd3-supply`(downstream names). Mainline only has `phy-nxp-ptn3222.c`: compatible `nxp,ptn3222`, supplies `vdd3v3`/`vdd1v8`. Fixed (same rails L5B/L15B). Also `sm8550.dtsi`'s usb node defaults to `usb-role-switch` (dr_mode otg), which waits forever for a role provider we don't have. User suggested forcing `dr_mode = "peripheral"` — I had not done it; it was the right idea but not sufficient on its own (see above). **v4 = v3 + (all offline-verified, `../_scratch/boot-backup-20260920/v4-fb-usb/`):** DTS: `simple-framebuffer` over ABL's splash (0xb8000000, 1080x2340, stride 4320 = 1080\*4, a8r8g8b8 — stride/format are ASSUMPTIONS), `&usb_1dr_mode="peripheral"`, `maximum-speed="high-speed"`, role-switch removed, HS PHY only (`usb_dp_qmpphy` disabled for now), repeater fixed as above. Config (`kernel/config/dm1q.fragment`): DRM/SIMPLEDRM/SYSFB_SIMPLEFB/fbcon + FONT_TER16x32 built-in; USB configfs+ACM, eUSB2 PHY, PTN3222, GENI I2C built-in. (Gotcha: `scripts/config` upper-cases names; `FONT_TER16x32` needs `--keep-case` or it silently does nothing.) initramfs (`kernel/initramfs/ init-v4`, legacy LZ4): configfs ACM gadget in the background, shell on `/dev/ttyGS0` -&gt; `/dev/ttyACM0` on the host. Cmdline: `console=tty0 console=ttyMSM0,115200n8 fbcon=font:TER16x32 loglevel=7 log_buf_len=4M initcall_debug clk_ignore_unused pd_ignore_unused regulator_ignore_unused`

  + androidboot.\*/bootconfig. `initcall_debug` is for reading the last line on screen if it hangs; remove once stable. dtbo unchanged (invalid table). sha256: boot 92efbac8…, init_boot 865f5ee5…, vendor_boot ae604b81…. **Expected outcomes to interpret:** kernel text on screen = fb path works (garbled/skewed = fix stride/format); `lsusb` shows 1d6b:0104 and `/dev/ttyACM0` appears = full USB path works; screen frozen on the last initcall = that initcall is the culprit.

- 2026-09-21 (MILESTONE — first mainline Linux boot on the S23) **[CORRECTED
  ~09:25: the boot with the visible log was v4 (fb+USB build, cmdline with
  `fbcon=font:TER16x32 initcall_debug`, confirmed by the ABL cmdline line in
  the recovery ring and by the installed partition hashes), NOT v3 — v3 had no
  framebuffer node and was "stuck on splash" per the entry above. This entry
  was written before I had read the 09:00 v4 entry; original text kept
  unedited below]**: **v3 boots
  mainline Linux 7.3.0-rc3 on dm1q and the kernel log is visible on the phone's screen** (user-reported, first successful boot after four failed attempts). Confirms in order: (1) ABL needs the invalid-dtbo + appended-DTB path (stock dtbo overlay chokes on a mainline DTB); (2) the silent Download-Mode failures were ABL rejecting the image, NOT AVB — the vbmeta message was tied to the sparse flash; (3) the TrustZone `TZBSP_ERR_FATAL_NOC_ERROR` reset was removed by v3's changes, most likely the TLMM `gpio-reserved-ranges = <36 4>, <50 2>` (as on gts9uwifi; the carveouts/cmdline flags went in together so which one mattered most is not isolated). What is NOT yet known: where the log ends (panic/hang/deferred probes), whether the sec_log ring captured it, what the framebuffer path is (we did not add a simple-framebuffer node — check how the log is being displayed). Host side: phone shows no USB device while running (no gadget in the initramfs yet). **Next:** capture the log end (photo of screen and/or `/proc/last_kmsg` from recovery), then work down the first errors: USB gadget in initramfs for a shell/log channel, UFS, regulators/PMICs, display.

- 2026-09-22 (v4 crash diagnosed; v5 built with ramoops; flashed from
  recovery): two new photos of the phone screen from a v4 boot (`otg-keyboard.jpg`:
  oops tail ending in `qcom_pcie_probe+0x1a8/0x414` via an async
  `driver_probe_device` workqueue; `not_connected.jpg` /
  `2026-09-22-10-31-02-091.jpg`: fuller capture of the SAME event —
  `arm-smmu 3da0000.iommu: deferred probe timeout` / `probe ... failed with
  error -110` immediately followed by `Unable to handle kernel NULL pointer
  dereference`, ESR 0x96000004 (DABT), at ~10.47s uptime). **This oops does
  NOT panic** (no `oops=panic` in v4's cmdline) — the earlier photo shows the
  kernel logging well past it (to ~10.82s), so it is not what looked like a
  freeze.
  **What actually looked like a freeze:** `init-v4`'s gadget script polls
  `/sys/class/udc/*` in a silent 1 s loop for up to 300 s with ZERO output
  until either success or the final timeout message — so if no UDC appears,
  the screen goes dark/static for up to 5 minutes with the kernel fully
  alive. User confirmed the visible screen state varies slightly boot to
  boot (async probe ordering), consistent with this rather than a hard hang.
  Root cause of the missing UDC is still unknown — dwc3/PHY probe messages
  scroll off the framebuffer's visible window before reaching the shell
  prompt, so nothing in the photos confirms or rules out a dwc3 probe
  failure. `PHY_NXP_PTN3222=y`, `PHY_SNPS_EUSB2=y`, `USB_DWC3_QCOM=y`,
  `I2C_QCOM_GENI=y` are all confirmed built-in (not the problem, or at least
  not a missing-driver problem).
  **Lesson on the debug method: recovery is NOT a safe log reader.**
  `/proc/last_kmsg` pulled from recovery this time turned out to be
  RECOVERY's OWN downstream boot console (`msm-dwc3`/`factory_adsp_init`/
  `sensors_core.ko` — Samsung's own driver names, never produced by our
  kernel), not the preceding v4 boot. Recovery is itself a downstream
  Android-derived environment that writes into the same physical
  `sec_log_buf` ring on every one of its own boots, and can overwrite our
  data before we get to read it — this only worked for v2/v3 because those
  crashed in well under a second of log volume. **Do not use recovery + this
  ring to inspect anything beyond a very early crash going forward.**
  **Fix: mainline `pstore`/`ramoops`, not recovery, going forward.** Added a
  `ramoops` reserved-memory node to `dm1q.dts`, 4 MiB at `0xb4000000` — a
  64 MiB gap confirmed empty in the live reserved-memory map between
  `uh_guest_mem` (ends `0xb4000000`) and `splash_region` (starts
  `0xb8000000`); 63 static ranges checked, 0 overlaps in the compiled DTB.
  This RAM is known only to our own kernel, so it survives a plain reset
  straight back into the SAME mainline image — the ONLY thing that can
  destroy it is booting a DIFFERENT OS (recovery/crDroid/Download Mode) in
  between, since those don't know the region is reserved and may reuse it.
  Kernel config gaps found and fixed: `CONFIG_PSTORE_RAM` was `=m` (initramfs
  has no module loader — dead weight) → `=y`; `CONFIG_PSTORE_CONSOLE` was
  unset (console output was never being captured at all) → `=y`;
  `CONFIG_PSTORE_PMSG=y` also enabled. `init-v5` (new, `kernel/initramfs/
  init-v5`) mounts pstore and cats `console-ramoops-0` (the PREVIOUS boot's
  console) to the screen before starting the USB gadget wait, and the gadget
  loop now prints `[gadget] still waiting for a UDC (Ns)...` every 10 s
  instead of staying silent for up to 300 s, so a genuine hang is
  distinguishable from a busy wait on sight, without needing pstore at all.
  **v5 files:** `../_scratch/boot-backup-20260920/v5-ramoops/{boot,init_boot,
  vendor_boot,dtbo}_v5.img`. boot = gzip(Image)+dtb appended (verified
  byte-identical payload); vendor_boot dtb identical to built dtb, cmdline
  unchanged from v4; init_boot is the FIRST change to that partition since
  v2 — new initramfs (busybox + init-v5), legacy LZ4, magic byte-identical
  format to v4's working one (`02 21 4c 18`, confirmed by direct comparison,
  not by a wrong assumed magic — see correction in this same entry); dtbo
  unchanged (still the invalid-table workaround). AVB footers verified.
  sha256: boot c75bdb77…, init_boot 0d9805a6…, vendor_boot 024e53eb…, dtbo
  unchanged (63852b23…, same as v4).
  **Flashed from recovery** (adb push -> dd conv=fsync -> sha256 readback,
  all four partitions verified) while the phone was still in recovery from
  the v4 debugging session — this IS a recovery detour, but it's the last
  one needed for this line of investigation: from here on, a plain
  power-cycle back into v5 should be enough to read the previous boot's
  console via pstore, no recovery required.
  **Next:** power-cycle (not recovery) into v5 twice — first boot populates
  ramoops with whatever happens (crash or gadget timeout), second boot
  prints it on screen automatically. That tells us whether the UDC ever
  appears and, if not, what the dwc3/PHY probe actually logged.

- 2026-09-22 (v5 result: pstore corrupted; root cause found; v6 built —
  logs to flash instead, no reboot-survival needed): user power-cycled v5
  twice as instructed and photographed the SECOND boot's screen
  (`second_boot.jpg`). **The previous-boot console pstore printed was badly
  corrupted** — scrambled/interleaved characters within otherwise-recognizable
  words (e.g. `dev_pm_opp_set_opp` came out as `dev[Pm_npp_Pa4 kpp+0x&c/0pc`),
  worsening further down, mixed with block/graphic glyphs.
  **Root cause (my mistake in the instructions, not a driver bug): the "hard
  reset" button-hold I told the user to use is very likely a full PMIC power
  cycle on this device, not a warm/software reset.** ramoops RAM is only
  guaranteed to survive a reset that keeps DRAM in self-refresh the whole
  time (a kernel-initiated reboot, or a TZ/watchdog-triggered reset — the
  latter is confirmed to preserve Samsung's OWN sec_log_buf ring across the
  v2 TZBSP_ERR_FATAL_NOC_ERROR resets earlier). A long power-button hold is
  commonly a true power-off + power-on, which can lose DRAM content
  entirely; partial/scrambled recovery (rather than all-zero or all-garbage)
  is consistent with some cells losing state during a brief unrefreshed
  window. Also confirmed dead ends while investigating: recovery has no
  `/dev/mem` node (raw physical memory isn't readable from there at all, so
  recovery can never be used to inspect ramoops directly even in principle).
  **Fix, matching the user's own ask ("write it to a file, save it in
  storage"): stop depending on cross-reset RAM survival altogether.** `v6`
  (`kernel/initramfs/init-v6`, boot/vendor_boot/dtbo UNCHANGED from v5 —
  only `init_boot` differs) adds a background loop, started immediately at
  boot, that runs `dmesg > /tmp/klog.txt` and `dd`-writes that snapshot to
  **unused padding inside the already-flashed `dtbo` partition** every 3 s
  — real content there is only the first 4096 bytes plus a 512-byte AVB
  vbmeta blob (`avbtool info_image`: `VBMeta offset: 4096`, `VBMeta size:
  512 bytes`, footer is the last 64 bytes of the 16 MiB partition); we write
  at the 1 MiB offset, nowhere near either, and the AVB hash descriptor for
  dtbo only covers the declared 4096-byte "Original image size", so writes
  past that don't affect any hash check. This turns "read the log" into a
  flash read, immune to power-cycle RAM loss, needs no USB/ramoops/photo:
  `adb shell dd if=/dev/block/by-name/dtbo bs=1M skip=1 count=4 2>/dev/null
  | tr -d '\0' > klog.txt`, from recovery or any later boot, at any time.
  **v6 files:** `../_scratch/boot-backup-20260920/v6-flashlog/
  init_boot_v6.img` only; same busybox + LZ4 ramdisk format as v5 (magic
  `02 21 4c 18` confirmed identical), AVB footer verified. sha256:
  fc772037…. Flashed from recovery (push+dd+sha256 readback, verified).
  **Next:** power on normally (any reset method is now fine — no more
  cross-boot RAM dependency), wait ~30–60 s, then pull the log with the `dd`
  command above from ANY boot (recovery, or even a later mainline boot) —
  no more photographing the screen for this.

- 2026-09-22 (v6 first boot: flash-log came back EMPTY, real bug found +
  fixed, v6b flashed): user's first v6 boot (~40 s, into system then back
  to recovery) produced a completely empty scratch region (`dd
  if=/dev/block/by-name/dtbo bs=1M skip=1 count=4` from recovery -> 4 MiB of
  all zero). **Root cause: our minimal busybox initramfs has no udev/mdev,
  so `/dev/block/by-name/dtbo` never exists there** — v6's flush loop wrote
  to `of=/dev/block/by-name/dtbo`, which silently failed every 3 s (stderr
  was redirected to /dev/null in that exact command, hiding it). Recovery
  can see `/dev/block/by-name/*` because it runs its OWN Android-based
  userspace with ueventd; our kernel's minimal rootfs does not.
  **Also flagged, not yet acted on:** even if by-name existed, recovery's
  own device-node numbering (`dtbo -> /dev/block/sda37`, queried this
  session) is from a DIFFERENT kernel and isn't guaranteed to match how our
  mainline kernel enumerates the same UFS LUNs.
  **Fix (v6, same version — `init_boot` re-flashed, `init-v6` patched in
  place, boot/vendor_boot/dtbo still unchanged since v5):** look the device
  up from the kernel's OWN GPT parser instead of any userspace helper —
  `CONFIG_EFI_PARTITION` exposes `PARTNAME=` per-partition in
  `/sys/class/block/*/uevent` independent of udev/mdev. The flush loop now
  scans for `PARTNAME=dtbo`, reads `DEVNAME=` from the same file, and uses
  that. Added `cut` to the initramfs's busybox applet symlinks (needed for
  this parsing, wasn't in v6's original list). Also stopped swallowing dd's
  stderr in this path, so any real error is visible on screen now instead
  of failing silently again.
  **Files:** `../_scratch/boot-backup-20260920/v6-flashlog/
  init_boot_v6b.img` (only file that changed). Same ramdisk format as
  v5/v6 (LZ4 magic `02 21 4c 18`), AVB footer verified. sha256: 8de6110d….
  Flashed from recovery (push+dd+sha256 readback, verified).
  **Next:** boot into system again, wait similarly (~40 s+ is fine), back to
  recovery, pull the log the same way. The `[flashlog] dtbo device: ...`
  line at the very top of the on-screen log will also confirm on-screen
  whether the lookup itself succeeded, independent of the flash pull.

- 2026-09-22 (v6b still empty — real bug was a RACE, not a wrong name; v6c
  flashed): pulled the full 16 MiB `dtbo` partition this time instead of
  just the scratch window, to rule out a wrong-offset assumption. Confirmed
  by a byte-precise scan (my first coarse per-MiB check falsely flagged
  every block as non-zero — that was a Python operator-precedence bug in my
  own analysis script, `i+1<<20` parses as `(i+1)<<20` not `i+(1<<20)`,
  nothing wrong on the device) that the partition is STILL exactly its
  original v5 state: only the 4096-byte stub + 512-byte vbmeta blob near the
  start and the 64-byte AVB footer at the very end. The scratch write still
  never happened, even with v6b's PARTNAME-based lookup, which was
  independently confirmed correct (recovery's own `/sys/class/block/*/
  uevent` shows `PARTNAME=dtbo` at `sda37`, same lookup method v6b used).
  **Real bug: the device lookup only ran ONCE, before entering the write
  loop.** UFS partition/block-device enumeration is asynchronous and has
  been slow to appear in every log so far (interconnect/clock `sync_state()
  pending` spam tied to `1d84000.ufshc` throughout boot). If
  `/sys/class/block/*/uevent` isn't fully populated at that one early
  moment, `D` stays empty for the rest of the boot and the loop silently
  skips every write forever after — a race, not a wrong name or wrong
  offset.
  **Fix (v6, same version again — `init_boot` re-flashed once more,
  `init-v6` patched in place):** moved the lookup inside the write loop so
  it retries every 3 s until it succeeds, instead of a single one-shot
  attempt before the loop starts.
  **Files:** `../_scratch/boot-backup-20260920/v6-flashlog/
  init_boot_v6c.img` (only file changed). Same ramdisk format as before,
  AVB footer verified. sha256: 23302ae8…. Flashed from recovery
  (push+dd+sha256 readback, verified).
  **Next:** same test again — system, wait, back to recovery, pull. If this
  still comes back empty, stop iterating blind on the flash-log mechanism
  itself and get a physical photo of the live screen instead, so we can see
  directly whether `[flashlog] dtbo device: ...` and `[gadget] still
  waiting for a UDC` lines are appearing at all.

- 2026-09-23 (MAJOR FINDING — UFS never worked at all, real cause found +
  fixed, v7 flashed): the v6d diagnostic (`[diag] /sys/class/block/*` +
  `/proc/partitions`, printed early in boot, photographed) showed
  **`loop0`-`loop7` ONLY — no `sda*`, no block device from UFS at all, in
  ANY boot we have ever captured.** This reframes everything from
  2026-09-21 onward: the repeated `gcc-sm8550 ...: sync_state() pending due
  to 1d84000.ufshc` spam in every single log wasn't noise, it was the
  actual signal — in the fw_devlink dependency model that message means the
  SUPPLIER (gcc) can't finish because a CONSUMER (ufshc) has never finished
  probing, i.e. ufshc itself is what's stuck. All the flash-log debugging
  from the last several entries (v6/v6b/v6c) was chasing a symptom of this:
  writing to `dtbo` via a block device path was never going to work while
  no block device existed at all.
  **Root cause: three drivers dm1q.dts's `&ufs_mem_hc`/`&ufs_mem_phy` nodes
  need were all built as loadable modules** (same class of bug as the
  earlier `PSTORE_RAM=m` miss) **and our initramfs has zero module-loading
  capability** — generic platform-bus code binds the DT node fine (which is
  why we see `platform 1d84000.ufshc: Adding to iommu group 1` etc.), but
  the actual driver that would DO anything with it never loads, so probe
  never completes, never fails outright, and never times out either — it
  just sits forever, matching every symptom seen since 2026-09-21 exactly.
  `CONFIG_SCSI_UFS_QCOM=m` (controller) and `CONFIG_QCOM_INLINE_CRYPTO_ENGINE=m`
  (ICE, which UFS crypto depends on) were the first two found. Flipping
  `PHY_QCOM_QMP_UFS` (the UFS PHY, also required before the controller can
  do anything) hit a second layer: it lives inside an `if PHY_QCOM_QMP ...
  endif` block in Kconfig, so a child symbol can never be more built-in
  than its enclosing menuconfig symbol — `olddefconfig` silently reverted
  it back to `=m` until the PARENT `PHY_QCOM_QMP` was also set `=y`. All
  four now confirmed `=y` in `out/.config` AND confirmed actually linked in
  (`ufs_qcom_probe` and `qcom_ice_program_key` both present in
  `System.map`, `phy-qcom-qmp-ufs.o` compiled into `built-in.a` this
  build).
  **Lesson for the rest of this bring-up:** any `=m` driver for something
  our DTS actually references is a silent, non-failing dead end in this
  environment — worth a proactive `grep '=m'` sweep across drivers our DTS
  touches, not just reacting to visible failures, since this class of bug
  produces NO error message at all, just permanent silence.
  **v7 files:** `../_scratch/boot-backup-20260920/v7-ufs/{boot,
  vendor_boot}_v7.img` — only these two changed (new kernel Image + dtb);
  `init_boot` stays v6d exactly (already correct, diagnostic lines and
  fixed flashlog device-lookup both still in place), `dtbo` stays v5's
  invalid-table image. boot = gzip(Image)+dtb appended, verified
  byte-identical; vendor_boot dtb identical, cmdline unchanged from v6.
  AVB footers verified. sha256: boot 8e63d9d0…, vendor_boot 6064eb3a….
  Flashed from recovery (push+dd+sha256 readback, verified).
  **Next:** boot into system, wait, back to recovery (or just check
  `[diag] /sys/class/block/*` on screen directly) — looking for an `sda*`
  entry this time, and if present, the flash-log mechanism (already fixed
  in v6c/v6d) should finally start working too, since it was blocked by
  the same missing storage the whole time.

- 2026-09-23 (v8 built + user-flashed: dmesg replay tool works, but caught
  the SAME 2026-09-22 crash — this time it appears to take the whole system
  down; v9 built to isolate it, flashed): built `init-v8` (paginated,
  timed replay of `dmesg` back onto the framebuffer screen, 25 lines/8s per
  page, since dmesg lives in RAM and needs neither UFS nor USB — every
  earlier log-capture method depended on one of those, which is exactly
  what's still broken). User flashed it themselves. **Result: page 1
  printed fine (see below), then two LIVE kernel lines interleaved with the
  static replay at ~10.46-10.47s — `arm-smmu 3da0000.iommu: deferred probe
  timeout, ignoring dependency` / `probe with driver arm-smmu failed with
  error -110` — and the screen never advanced again, even after minutes.**
  **Corrected identification: `3da0000.iommu` is `adreno_smmu` (the GPU's
  IOMMU, confirmed against `sm8550.dtsi`), NOT PCIe's.** GPU/display was
  deliberately never wired up in this project, so that SMMU sitting
  deferred-forever is *expected*, not a new bug — it's printing its timeout
  message at the same global ~10s `deferred_probe_timeout` mark as
  everything else still deferred, purely coincidentally adjacent in the log
  to the real problem. **The real problem is almost certainly the SAME
  crash already diagnosed on 2026-09-22**: a NULL-pointer-dereference oops
  bottoming out in `qcom_pcie_probe+0x1a8/0x414` via an async
  `driver_probe_device` workqueue, ESR 0x96000004 (DABT), also seen right
  around the ~10.47s mark that day. Back then it didn't panic (no
  `oops=panic` on the cmdline) and the kernel kept logging for another
  ~0.4s. This time nothing more ever appears — most likely explanation:
  the oops this time happens while something (plausibly a lock the
  crashing workqueue thread held, e.g. `console_lock`) is held, wedging the
  whole console subsystem so every later `write()` to the screen — ours
  included — blocks forever, silently. Unconfirmed, not yet proven.
  **`&pcie0`/`&pcie0_phy` in `dm1q.dts` were checked against
  `sm8550-samsung-q5q.dts` and are byte-identical** (deliberately copied
  from it back on 2026-09-15/16) — so the devicetree-level PCIe setup isn't
  the differentiator vs. q5q; either q5q hits the same crash in practice
  (no reference log available to check) or something else about our build
  differs. Not resolved.
  **Also confirmed from v8's `[diag]` block: UFS STILL shows only
  `loop0`-`loop7`, no `sda*`, even on v7's kernel** (UFS drivers `=y`)
  — independent of this crash, storage is still not coming up. Not
  explained yet.
  **New, previously-unseen, low-priority items from page 1:**
  `[Firmware Bug]: Kernel image misaligned at boot, please fix your
  bootloader!` (arm64 wants the Image 2 MiB-aligned; our appended-DTB/ABL
  chain isn't giving it that — usually non-fatal, kernel self-relocates,
  not investigated further yet); `'bootconfig' found on the kernel command
  line but CONFIG_BOOT_CONFIG is not set` (cosmetic, leftover from the
  inherited vendor cmdline). **Checked and ruled out as a bug**: `OF:
  reserved mem: ... failed to reserve memory` for `uh-heap@b0200000`
  (shows "size 0 MiB" — actually 256 KiB, 0.25 MiB rounds down in the
  integer-MiB print) and `uh-guest@b1000000` (48 MiB) are followed
  immediately by successful reservation of the exact same ranges under
  their region names (`uh_heap_region`, `uh_guest_region`) — this is
  normal double-registration behavior (early raw memblock scan vs. the
  real `of_reserved_mem` walk), not a devicetree defect; sizes cross-checked
  against `dm1q.dts` and match exactly.
  **Real bug found in v8's OWN script, fixed in v9**: the flash-log
  background job (writes `dmesg` to spare space in the `dtbo` partition,
  the one channel that survives a console freeze since it never touches
  the screen) was placed *after* the long on-screen replay loop in the
  script. Since the replay froze, that job never even started — v8 had no
  working fallback once the screen died. **v9** (`init_boot` only,
  `boot`/`vendor_boot`/`dtbo` unchanged from v7/v5) reorders the script:
  the flash-log and USB-gadget background jobs now start immediately,
  before any console-writing diagnostics, so they should keep running
  independently even if the foreground replay later hangs. Also delays the
  dmesg snapshot used for the on-screen replay by a fixed 15 s (past the
  known ~10.46 s crash point) so that snapshot — unlike v8's, taken at
  ~0.3 s — actually spans the crash if one happens, whether or not the
  screen survives to show it.
  **Files:** `../_scratch/boot-backup-20260920/v9-crash-window/
  init_boot_v9.img`. Same ramdisk format as v6d-v8 (LZ4 magic
  `02 21 4c 18`), AVB footer verified (Algorithm NONE, 8 MiB partition).
  sha256: 207474c1…. Flashed from recovery (push+dd+sha256 readback,
  verified; pre-flash readback of the installed `init_boot` confirmed it
  was v8's `69e95cfe…`, as expected).
  **Next:** boot into system, wait at least ~20-30 s past the crash point,
  then EITHER read the flash-log from recovery (`adb shell dd
  if=/dev/block/by-name/dtbo bs=1M skip=1 count=4 | tr -d '\0' >
  klog.txt`, unaffected by any screen freeze) OR photograph whatever the
  screen still manages to show. Either way we should finally get the full
  oops/stack trace for the `qcom_pcie_probe` crash, which is the next real
  thing to fix — UFS's `sda*` absence may or may not be related to it,
  unclear yet. **Do not start actual pmOS/Alpine userspace work before
  this is resolved** — the kernel isn't reaching a stable running state
  yet (freezes ~10-15 s in), so there's nothing for a real rootfs to boot
  into reliably regardless of how well the initramfs itself now works.

- 2026-09-24 (**ROOT CAUSE FOUND for the ~10.47 s oops — board-devicetree omissions, NOT a kernel bug; v10 built + flashed, not yet booted**):
  Continued the crash trace from the 2026-09-23 handoff. Full write-up, corrections and evidence photos:
  `notes/2026-09-23-pcie-opp-crash/findings.md` (the 2026-09-23 OPP/addr2line trace had never been saved into this
  log before). **Localised:** photo `otg-keyboard.jpg` gives the real trace tail (`dev_pm_opp_set_opp+0x6c/0xcc` ←
  `qcom_pcie_set_max_opp+0x4c/0x88` ← `qcom_pcie_probe+0x1a8/0x414`; the handoff's `+0x4c/0xc0` was a misread of the
  corrupted pstore photo) plus the `Code:` line; matching the `Code:` bytes against the flashed v7 vmlinux (one unique
  hit) puts the fault at `__clk_rcg2_shared_set_rate+0x84` — `f->src` read with `f == NULL` (clk-rcg2.c), reached through the
  OPP core's `clk_set_rate()` on pcie0's first clock. **Not an OPP bug:** pcie0 really has a 6-entry OPP table in
  sm8550.dtsi (the earlier "no operating-points-v2" grep was wrong).
  **Root cause:** `dm1q.dts` never gave `&xo_board` (76.8 MHz) or `&sleep_clk` (32764 Hz) a `clock-frequency` — every upstream
  sm8550 board does; without it `of_fixed_clk_setup()` fails, the XO never registers and the whole RPMh-XO/GCC PLL+RCG tree
  computes 0 Hz. `clk_set_rate()` then walks every XO child, and a parked floor-policy RCG (sdcc2/4) gets rate 0 →
  `qcom_find_freq_floor()` = NULL → oops. (Enabler: an upstream regression dropped the `if (!f)` check when
  `clk_rcg2_shared_floor_ops` was added — separate upstream patch candidate, not applied here.) Widening the DT comparison
  against `sm8550-samsung-q5q.dts` also showed `&qupv3_id_0` (geniqup@ac0000: i2c4 touch, **i2c6 eUSB2 repeater**, uart7) was
  never enabled — so the USB HS PHY could never probe: the likely real reason for "still waiting for a UDC".
  Retracted: the "genuine kernel bug in OPP" hypothesis. Open/untested: whether UFS's missing `sda*` (and the freeze) share
  this root cause. Also: v9's flash-log channel needs a UFS block device, so it could never have worked while `sda*` was absent.
  **v10** (same tree, kernel banner `#7`): `dm1q.dts` + `&xo_board`, `&sleep_clk`, `&qupv3_id_0`; `CONFIG_QCOM_GPI_DMA=y` (was `=m`;
  GENI I2C may need GPI DMA and nothing loads modules); vendor cmdline without `console=ttyMSM0,115200n8` (uart7 is real now — a
  115200-baud console on unconnected pads would throttle the boot; effective console stays tty0-only as in v4–v9). `init_boot`
  (v9) and `dtbo` (v5) unchanged. Decompiled-DTB diff v7→v10 is exactly the three intended changes.
  **Files:** `../_scratch/boot-backup-20260920/v10-xo-geni/{boot_v10.img,vendor_boot_v10.img,Image.gz,Image.gz-dtb}`.
  sha256: boot_v10 `022b3688…`, vendor_boot_v10 `2db4170f…`. The assembly recipe was proven first by rebuilding v7's images from
  their own unpacked parts (byte-identical); AVB footers verified. **Flashed from recovery** (pre-flash readback == v7 set, as
  expected; push → device sha256 == host; conv=fsync write to boot/sda25 + vendor_boot/sda28; readback verified, re-verified after
  `drop_caches`; init_boot still `207474c1…`, dtbo still `63852b23…`). Rollback: v7 set in `v7-ufs/` (boot `8e63d9d0…`,
  vendor_boot `6064eb3a…`).
  **Next:** boot v10 and look for: no oops at ~10.47 s; a CDC-ACM device on the host (`/dev/ttyACM0` → initramfs shell →
  `dmesg`); UFS `sda*` (or a now-visible error). If USB works, stop photographing and read dmesg over ACM. Still **no
  pmOS/Alpine userspace work** until the kernel stays up.
