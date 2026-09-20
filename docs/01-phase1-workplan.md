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
   cleanly (proves boot chain / boot.img format is right before debugging
   actual hardware).
2. Add regulator + clock nodes, confirm no hangs.
3. Bring up UART/USB early console for real debug output.
4. Bring up display last, once everything upstream of it is confirmed stable.

## Log

_(append dated entries here as work happens)_

**Note (2026-09-14): `../_scratch/` was moved from a sibling, uncommitted
location into this repo (with `.git` stripped from each cloned subfolder)
and is now documented in `../_scratch/README.md` and the main README. Log
entries below that describe it as "sibling to this repo, not committed
here" were accurate at the time they were written — treat them as history,
not current layout.**

- 2026-09-13: Repo created, workplan drafted from initial research. No boot
  attempt yet. Step 0 items outstanding.
- 2026-09-13 (later same day): Fact-check pass on all docs. Found and
  corrected two significant errors: (1) dm1q/dm2q actually use WCN6855
  (ath11k), not an open question resolvable only by guesswork — confirmed via
  teardown + community sourcing that only the S23 Ultra (dm3q) matches the
  Tab S9 Ultra reference's WCN7850/ath12k chip; (2) pmaports lives at
  gitlab.postmarketos.org now, not gitlab.com (migrated Oct 2024) — explains
  why earlier GitLab searches for dm1q found nothing. See
  docs/02-open-questions-and-risks.md items 1, 6, 8, 9 for full detail and
  what still needs re-checking.

- 2026-09-13 (later still): Ran the actual pmaports check from Step 0 using
  Desktop Commander (shell access) instead of `pmbootstrap init`, via a
  data-light sparse partial clone (`git clone --filter=blob:none --depth=1
  --no-checkout`) of the live repo into `../_scratch/pmaports` (sibling to
  this repo, not committed here). Searched the full tree directly with
  `git ls-tree -r` for dm1q/dm2q/dm3q/kalama/sm8550 — **zero matches
  anywhere**, including device/main. This contradicts the earlier "confirmed
  by hand in pmbootstrap init" note. Corrected 00-overview.md and
  open-questions item 1b accordingly. Still need an interactive
  `pmbootstrap init` run to fully resolve the discrepancy, but the working
  assumption going forward is: no existing dm1q package, from-scratch port.

- 2026-09-13 (evening): User pushed back on the "discredited" verdict for
  the agcarbajo Tab S9 Ultra repos, correctly — that verdict was wrong.
  Re-investigated properly (cloned both repos in a separate sandbox first,
  per user's request, before touching this machine): confirmed the repos
  are real, legitimate, technically competent unmerged personal pmOS/kernel
  ports, not fabricated. The earlier "false provenance" reasoning had
  wrongly assumed "pmaports package" meant "merged into official upstream
  pmaports" when it actually referred to the repos' own local
  pmaports-formatted staging folder — a normal, unremarkable setup for an
  unmerged community port. Verified with hard checks: real deviceinfo
  conventions matching the device's actual spec, a real resolvable commit
  hash cited from actual pmaports history, and real correct V4L2 kernel
  patch code against mainline drivers/media/i2c/hi847.c. Full correction
  and reasoning logged in docs/03-references.md and
  docs/02-open-questions-and-risks.md item 4.
  Both repos now cloned (shallow, depth=1, ~9.7MB total) into
  `../_scratch/gts9u-pmos-ref` and `../_scratch/gts9u-ubuntu-ref` (siblings
  to this repo, not committed here) for actual use as SM8550 reference
  material going forward. Next real step: use these — particularly
  `gts9u-pmos-ref/pmaports/device/testing/{device,linux}-samsung-gts9uwifi*`
  and `gts9u-ubuntu-ref/kernel/dts/sm8550-samsung-gts9uwifi.dts` — as the
  structural template for building dm1q's own device+kernel pmaports
  packages, adapting board-specific bits (panel, PMIC regulator names,
  sensors, pinctrl) using the crDroid downstream tree for real hardware
  values.

- 2026-09-13 (night, session close): Pulled real mainline
  `arch/arm64/boot/dts/qcom/` (sparse clone, `../_scratch/linux-mainline`)
  and diffed the gts9u board devicetree against the four upstream files it
  includes (`sm8550.dtsi`, `pm8550.dtsi`, `pm8550vs.dtsi`, `pmk8550.dtsi`).
  Full categorized result in the new
  `docs/04-gts9u-vs-mainline-devicetree-diff.md`. Headline: 105 board-specific
  labels, cleanly grouped into (1) SoC-level buses/blocks just being enabled
  for this board — same kind of work needed for dm1q with different values,
  (2) PMIC regulator rail definitions — confirmed as normal upstream
  practice by spot-checking real sm8550-hdk/sm8550-qrd reference boards, not
  gts9u-specific oddity, (3) board pinctrl/GPIO states — genuinely
  per-board, and (4) tablet-only third-party ICs not relevant to dm1q.
  Useful independent cross-check: gts9u's devicetree confirms it uses
  WCN7850, matching what this project's docs already had for the *Ultra*
  variant specifically — consistent with, not contradicting, the earlier
  WCN6855-for-dm1q/dm2q finding.
  **Status at end of session: Phase 1 Step 0 is ~60% done (pmaports check
  done; WCN/PMIC/panel checks against dm1q's own crDroid tree still
  outstanding). Step 1 (reference materials) is done. Step 2 has a first-pass
  structural map done, but zero real dm1q-specific values yet — nothing here
  has touched dm1q's actual kernel source tree. Step 3 (first boot attempt)
  hasn't started.** The single actual next blocker, unchanged by tonight's
  work: pull real values out of dm1q's downstream crDroid kernel/DT source
  (WCN chip confirmation, PMIC part number, panel/touch compatible strings,
  real pinctrl/GPIO/regulator values) to fill into the gts9u-derived
  skeleton. Nothing else meaningfully progresses until that happens.

- 2026-09-14: **Phase 1 Step 0 fully complete.** Found the real crDroid
  devicetree-only repo (`crdroidandroid/android_kernel_samsung_sm8550-devicetrees`,
  official, much smaller than a full kernel tree) and pulled dm1q's actual
  Samsung downstream `.dts` files (10 board revisions, ~96MB, into
  `../_scratch/crdroid-dm1q-dts`). This resolved every remaining Step 0 item
  with ground truth rather than inference:
  - **WCN chip corrected**: dm1q uses QCA6490, not WCN6855 (all 10 revisions
    checked, zero WCN6855 references). Still ath11k-family, mainlined
    earlier than WCN6855 if anything. Memory and docs 00/01/02/04 updated.
  - **PMIC confirmed**: PM8550, PM8550B, PM8550VE, PM8550VS, PM8010,
    PM8350C — a multi-PMIC setup, not the single part previously assumed.
  - **Panel confirmed**: dual-sourced — Samsung S6E3FAC (AMB606AW01) and
    Silicon Works LX83118 (CM002).
  - **Touch confirmed**: Goodix Berlin (`goodix-berlin@5d`).
  - **Bootloader unlock confirmed** (user-reported, not from source):
    standard Samsung OEM-unlock toggle + Download Mode, no quirks.
  Full detail in docs/02-open-questions-and-risks.md items 1, 2, 3b.
  **Step 0 is the first fully-closed step in this project.** Next real work
  is filling dm1q's real values (now in hand) into the gts9u/mainline
  skeleton from Step 2 — i.e., actually starting to write dm1q's own
  devicetree, not just planning it.

- 2026-09-14 (continued): Deeper extraction pass on the real dm1q crDroid
  devicetree source (`../_scratch/crdroid-dm1q-dts`), per user request for
  full regulator/pinctrl/GPIO tables. Wrote two small extraction scripts
  (`notes/extract_regulators.py`, `notes/extract_pinctrl.py`) since the
  source is a dtc-decompiled DTB (numeric phandles, lost labels) rather
  than hand-written source. Findings written up in the new
  `docs/05-dm1q-real-hardware-values.md`:
  - Found a previously-unknown IC: **s2mpb02**, a Samsung LSI sub-PMIC with
    18 LDOs + 2 bucks + 1 buck-boost, likely dedicated to camera/display
    rails.
  - Real GPIO numbers for touch (Goodix reset=GPIO24, irq=GPIO25) and
    WLAN/BT (QCA6490 enable/reset=GPIO80/81, sw-ctrl=GPIO82,
    xo-clk=GPIO204) and panel (reset=GPIO125, TE=GPIO86/87 for the two
    panel paths).
  - Full 663-entry pinctrl state table in `notes/dm1q-pinctrl-table.txt`.
  - **Honest limitation, not resolved**: the actual PM8550-family SPMI
    regulator channel-to-consumer mapping wasn't recoverable via text
    extraction — those subnodes don't carry descriptive names in this
    decompiled file. Flagged as a follow-up for when writing those specific
    consumer nodes, not a blocker.

- 2026-09-14 (continued, deep dive at user's request to "do it right, no
  corners cut" on PM8550 regulator mapping): Investigated whether the full
  PM8550 SPMI regulator channel-to-consumer mapping could be recovered from
  the downstream source. Found a genuine architectural wall: Qualcomm's
  downstream Android driver models PMIC regulators via an RPMh ARC voting
  layer (`kalama-regulators.dtsi`, internal codenames like `pm_v6e_l1`) —
  architecturally different from mainline's `qcom,rpmh-regulator` binding
  (`vreg_l1b`-style). No clean automatic translation exists between them,
  which is fine, since the mainline devicetree needs mainline's convention
  regardless.
  Resolved the QCA6490 WLAN/BT case specifically and completely by finding
  Samsung's own DTB+DTBO overlay fixup tables directly in dm1q's real
  source (`grep 'qcom,cnss-qca6490:.*-supply'`) — direct evidence, not
  inference: `vdd-wlan-io-supply`→L15B, `vdd-wlan-dig-supply`→S4E,
  `vdd-wlan-rfa1-supply`→S6G, `vdd-wlan-rfa2-supply`→S4G,
  `vdd-wlan-aon-supply`→S2G. Cross-confirmed against gts9u's independently-
  verified mainline mapping for the same RPMh resource IDs (S2G/S4E/S4G/S6G
  match exactly) and against dm1q's own separate WLAN PDC voting table
  (same resource IDs again) — three independent pieces of evidence
  agreeing.
  **Also corrected a wrong assumption made earlier in the same
  investigation**: initially assumed QCA6490 would use gts9u's WCN7850
  7-supply naming scheme (vdd/vddio/vddio1p2/vddaon/vdddig/vddrfa1p2/
  vddrfa1p8). Real evidence shows QCA6490's actual downstream driver only
  has 5 named supplies — genuinely different (simpler) binding, not a
  smaller version of the same one. Caught and fixed before it could get
  baked into a wrong devicetree later.
  Full writeup in docs/05-dm1q-real-hardware-values.md. Same fixup-table
  method is available for other consumers (panel, touch, etc.) on an
  as-needed basis when actually writing those specific nodes, rather than
  as a blanket upfront task.

- 2026-09-14 (night): **First real devicetree draft written: dts/dm1q/dm1q.dts.**
  Structural template from gts9uwifi + the real SM8450-HDK reference board
  (same QCA6490 chip, better match than gts9uwifi's WCN7850 for this
  specific node). Content: model/compatible/msm-id/board-id (CONFIRMED real
  values), the 5 real PM8550-family regulators behind dm1q's WLAN/BT
  (L15B/S2G/S4G/S4E/S6G, channel identities CONFIRMED, voltages INFERRED
  from platform-constant reasoning), the QCA6490 wcn6855-pmu node with real
  GPIO80/81/82/204 and the resolved supply mapping, and a touch controller
  placeholder (Goodix Berlin, real GPIO24/25, bus instance NOT yet
  confirmed). Display/PCIe/UFS/USB/camera deliberately left out --
  explicitly marked, not silently missing.
  **Compiled and verified with real tooling, not just eyeballed**: `cpp`
  (for the #include/dt-bindings macros) piped into `dtc -@ -I dts -O dtb`,
  using the real mainline sm8550.dtsi/pm8550*.dtsi as includes. Exit code 0,
  produces a valid .dtb. Caught and fixed two real bugs this way before they
  could sit undetected in the file: (1) an invalid, fabricated
  `label: &node-ref {}` override syntax for the L15B regulator that isn't
  valid devicetree at all; (2) a wrong PMIC assignment -- confused
  PM8550VS-E (an *instance letter* of PM8550VS) with PM8550VE (a
  *different chip*) for the S4E regulator. Both corrected by checking
  gts9uwifi's actual real structure rather than guessing.
  Needed two extra dependency fetches to get `dtc`/`cpp` working:
  `include/dt-bindings/` (7.7MB) and the one transitively-missing
  `linux-event-codes.h` target file -- both fetched into a genuinely
  separate `/tmp` location first, then copied in as plain files (same
  pattern as everything else in `../_scratch/`), not git-cloned directly into
  `../_scratch/linux-mainline` itself.

- 2026-09-14 (night, incident during the above): **Real, well-understood
  accident, fully recovered, documented for transparency and to prevent
  recurrence.** While trying to fetch missing dt-bindings headers, ran `git
  sparse-checkout` commands with cwd inside `../_scratch/linux-mainline`.
  **Root cause: `../_scratch/linux-mainline` (and everything else under
  `../_scratch/`) has no `.git` of its own** -- deliberately stripped before
  committing these as plain files into the outer repo (see
  `../_scratch/README.md`). Any `git` command run from inside those
  directories doesn't fail -- it silently walks up and operates on the
  **outer dm1q-mainline repo's `.git` instead**, since that's the nearest
  real one. This happened twice in a row before being correctly diagnosed,
  twice leaving the outer repo's `core.sparseCheckout` config stuck `true`
  with a cone-mode pattern excluding all subdirectories -- `docs/`,
  `notes/`, and most of `../_scratch/` disappeared from the working directory
  (but were NEVER at risk in git history/objects -- `git log` showed all
  commits intact throughout, and `git ls-tree HEAD` always showed the full
  file list). Fully recovered via `git sparse-checkout disable` (had to be
  run twice, since the first recovery attempt itself triggered the second
  incident the same way) and verified thoroughly afterward: tracked file
  count matches exactly between `git ls-tree HEAD` and the actual working
  directory (6895 = 6895), `git diff --stat` empty, directory sizes sane.
  **Lesson for future sessions: NEVER run `git` commands with cwd inside
  any `../_scratch/` subdirectory. If external repo content needs fetching or
  updating, do it in a genuinely separate location (e.g. `/tmp/`) and copy
  the needed files in afterward** -- exactly the pattern used successfully
  for the dt-bindings fetch right after this incident, and the same pattern
  already used (correctly) for every other addition to `../_scratch/` so far.

- 2026-09-15: **`_scratch/` moved back OUT of the repo, to a sibling
  location (`../_scratch/` from the repo root), not tracked in git.**
  Reverses the 2026-09-14 decision to commit it. Reasoning: the incident
  earlier this session (see the "Real, well-understood accident" entry
  above) happened specifically because `_scratch/`'s subdirectories have no
  `.git` of their own while living *inside* a git-tracked working tree --
  any `git` command run there silently walks up and hits the outer repo's
  `.git` instead of failing cleanly. Confirmed `~/Documents/GitHub` itself
  is not a git repository (`git rev-parse --is-inside-work-tree` ->
  "not a git repository, stopping at filesystem boundary"), so as a
  sibling location, the same mistake would now fail loudly and safely
  instead of silently damaging the repo. User's call, given they're the
  only person using this repo and `_scratch/` is genuinely just a
  workspace: prefer the sibling location; bring specific files back into
  the repo "in a more organized manner" later, once actually needed for
  something durable (e.g. once the real research file is settled, not the
  whole 90MB+ reference dump).
  Added `.gitignore` (`_scratch/`) to prevent accidentally re-tracking it.
  Fixed all path references in docs/README/dts (were `_scratch/...`, now
  `../_scratch/...` for files at repo root depth, or the correct relative
  depth for `dts/dm1q/dm1q.dts` specifically). Verified nothing broke:
  recompiled `dm1q.dts` from its new required path and got a byte-identical
  `.dtb` (same SHA256) as before the move.

- 2026-09-15 (continued): **Fixed the first-boot-relevant TODOs in
  dm1q.dts, starting from the user's request to investigate GPU/CPU OPP
  retuning.**
  - **OPP/CPR investigation (see docs/02-open-questions-and-risks.md item 3
    for full detail): resolved favorably, no devicetree changes needed.**
    Mainline's SM8550 CPU OPP tables use EPSS hardware-driven voltage
    scaling (real per-chip fuse calibration at runtime), not static
    devicetree voltages — confirmed by reading the actual opp-table entries
    in sm8550.dtsi (opp-hz only, no opp-microvolt). The "SM8550-AC bin"
    concern doesn't threaten boot reliability; worst case is underclocking.
  - **UART console (uart7) confirmed and enabled.** Cross-checked GPIO26/27
    + function name in dm1q's real source against mainline's uart7 pinctrl
    — exact match. Added the missing `&uart7 { status = "okay"; }` override
    — sm8550.dtsi disables it by default, so without this there would be
    zero boot console output regardless of the aliases/chosen nodes already
    in the file. This was a real, silent first-boot blocker.
  - **microSD (sdhc_2) alias — corrected twice, see below for the final
    answer.** First pass: initially assumed dm1q might lack SD support
    (later S-series phones often do), then wrongly "corrected" to assume
    it DOES have SD support based on a real card-detect GPIO12 found in
    dm1q's downstream source. **Both were wrong. Final correction
    (2026-09-15, from the user, who physically owns the device): the
    Galaxy S23 has no microSD slot at all.** The card-detect GPIO12 is
    real data but doesn't mean what it was assumed to mean — it's
    evidently a leftover/shared definition from Samsung's common
    devicetree base, not populated hardware on this device. Lesson: real
    hardware ground truth from someone who owns the device beats
    devicetree-archaeology inference, however well-evidenced the
    inference seemed. `mmc1` alias removed entirely, `sdhc_2` left
    disabled permanently (not "deferred" — this is settled, not open).
  - **UFS (actual boot/root storage) substantially wired up.** Real
    fixup-table cross-referencing (same method as the QCA6490 regulator
    resolution) confirmed: reset-gpios = GPIO210 (exact match with
    gts9uwifi), vccq-supply = PM8550VS-G L1, vdda-pll-supply = PM8550VS-E
    L3, vdda-phy-supply = PM8550VS-E L1 (downstream property name differs
    — "vdda-qref-supply" — but same physical rail, confirmed by channel
    match). All channel identities confirmed via dm1q's own fixup tables,
    all four exactly matching gts9uwifi's channel assignments (strong
    platform-fixed-channel cross-confirmation, same pattern as WLAN).
    **vcc-supply (main UFS power) deliberately left unresolved, not
    guessed**: dm1q's fixup table shows it fed by a PMIC instance letter
    ("humu") that doesn't appear anywhere in Qualcomm's own reference
    kalama-pmic-overlay.dtsi — a Samsung-specific addition, not one of the
    chips already in this file. Blindly copying gts9uwifi's vreg_l17b_2p5
    (PM8550B) would have wired UFS main power to the wrong physical chip.
    UFS host controller node stays `status = "disabled"` until this is
    resolved — better to boot without storage working than to guess wrong
    on the main power rail for the boot device.
  Verified throughout with real `cpp`+`dtc` compilation, not just written
  and assumed correct — caught and fixed one real syntax bug (an orphaned
  comment block from a bad find-replace) during this pass. Final state:
  exit code 0, only the two already-known/flagged placeholder warnings
  (wcn6855-pmu, i2c-touchscreen — both have missing reg/ranges by design,
  since they're intentionally incomplete) plus mainline's own upstream
  warnings (duplicate i2c/spi unit addresses — normal Qualcomm QUP pattern,
  not something to fix here).
  **Still open after this pass**: UFS vcc-supply identity, touch
  controller's I2C bus instance, display/panel (deferred, needs real
  driver work). microSD is settled (no slot exists), not open.

- 2026-09-15 (continued): **UFS vcc-supply resolved via live hardware
  measurement — a new technique for this project.** Gained root on the
  physical device via KernelSU (whitelisted the `shell` identity for adb),
  then read `/sys/class/regulator/` directly. Found `regulator.44`
  (`pm_humu_l17`) has a consumer symlink literally naming the UFS host
  controller's exact address — fully unambiguous. Live values:
  state=enabled, 2.504V (fixed), 1 consumer, fast mode. Also checked real
  kernel mailing list patches for PM8350C's documented regulator range,
  which partially matches "humu"'s BOB capability but not its full channel
  count — concluded "humu" is likely an RPMh domain aggregating multiple
  PMICs (2× PM8010 + PM8350C), not a single chip, and didn't force a wrong
  single-chip identification.
  dm1q.dts now models this as a `regulator-fixed` node at the real
  measured voltage rather than the unresolved real PMIC chain — a
  deliberate, evidenced choice (UFS holds boot media, so firmware must
  already enable this rail before Linux starts; live num_users=1 confirms
  no dynamic sharing to misrepresent). `&ufs_mem_hc` now `status = "okay"`.
  Full writeup in docs/05-dm1q-real-hardware-values.md. **This live-device
  measurement technique is now available for other stuck items** — worth
  reaching for earlier next time static source analysis hits a genuine
  wall, rather than only as a last resort.
  Verified via real compilation as always: exit code 0, no new errors.

- 2026-09-15 (continued): **Full live-hardware verification pass on every
  remaining "INFERRED" regulator value in dm1q.dts.** Checked all 8
  gts9uwifi-inferred voltages (L15B, L3E, L1E, L1G, S4G, S6G, S4E, S2G)
  against the real physical device via adb/KernelSU root. Also
  independently cross-confirmed all 5 WLAN channel identities via
  `/sys/class/devlink/` consumer symlinks (a second, more direct method
  than the downstream fixup-table approach used earlier).
  **Result: every single inferred value either matched exactly or fell
  within the real confirmed range** — strong validation of the
  cross-referencing methodology used throughout this project. Updated
  dm1q.dts to use real min/max ranges (rather than the originally-guessed
  single fixed points) for the genuinely multi-corner ARC-voted rails
  (S2G, S4G, S6G, S4E, L1E, L1G) — more accurate and matches how real
  mainline reference boards represent these. L15B and L3E stay fixed
  single values since the real device confirms they genuinely are fixed
  (min=max). Full comparison table in docs/05-dm1q-real-hardware-values.md.
  Fixed one duplicate-label bug introduced mid-edit (caught before commit
  via the usual cpp+dtc compile check, exit 0 clean).

- 2026-09-15 (continued): **Two corrections from the user, plus the touch
  controller I2C bus resolved.**
  User corrected (ground truth, physically owns the device): the Galaxy
  S23 has no microSD slot at all. This overturns an earlier "confirmed"
  conclusion in this same file that took a real card-detect GPIO12 in
  dm1q's source as sufficient evidence for SD support — it wasn't; that
  GPIO is evidently a leftover/shared definition from Samsung's common
  devicetree base. `mmc1` alias removed from dm1q.dts entirely, `sdhc_2`
  now documented as permanently N/A rather than "deferred." Real hardware
  ground truth from the device owner overrides devicetree-archaeology
  inference, however well-evidenced the inference seemed at the time.
  **Touch controller I2C bus — resolved via the live device's own booted
  devicetree** (`/sys/firmware/devicetree/base/`, not inference): address
  0xa90000 matches mainline's `&i2c4` exactly. Also cross-checked
  reset-gpio/irq-gpio/irq-flags directly from the live tree — all matched
  the earlier fixup-table-based extraction exactly, good corroboration of
  that method too. dm1q.dts updated to use the real `&i2c4` bus instead of
  a placeholder container; this also removed a real compile warning
  (missing reg/ranges), not just resolved a TODO comment.
  Verified via cpp+dtc as always: exit 0, one fewer warning than before.

- 2026-09-15 (continued): **USB fully wired up (HS PHY, SS PHY, real
  eUSB2 repeater), using the same live-evidence methodology as UFS/WLAN.**
  Confirmed QCA6490 is genuinely PCIe-attached (`qcom,wlan-rc-num = <0x00>`
  in dm1q's real source, "rc-num" = PCIe Root Complex number) before
  starting PCIe work next.
  New PMIC channels identified: L5B (PM8550B, 3.104V, eUSB2 repeater
  vdd3) and L3F (PM8550VE, 0.912V, USB SS PHY vdda-pll) -- the latter
  required finally adding `pm8550ve.dtsi` with its real confirmed SID (5),
  resolving a TODO left over from the very first devicetree draft.
  eUSB2 repeater resolved via real kernel dmesg (not just static
  devicetree): of two candidate repeater nodes in the tree (PMIC-SPMI vs.
  NXP-I2C), only the NXP one shows real probe activity on the live
  device. Its full real init register sequence was read directly from
  the device's own booted devicetree and cross-matched dmesg byte-for-byte.
  Obtained Samsung's own official GPL kernel source
  (opensource.samsung.com, SM-S911B, ~3.5GB) for the display driver
  investigation -- confirmed real, substantial panel driver logic exists,
  but the exact raw DCS byte table wasn't located this session (see the
  dedicated section in docs/05 for the full trail and where to look next).
  Also downloaded crDroid's full kernel source (not just -devicetrees) to
  check for panel driver code there -- confirmed it does NOT contain
  Samsung's proprietary panel framework (only generic Qualcomm DPU
  controller code), consistent with that framework being distributed as
  a vendor module rather than GPL kernel source in crDroid's build.
  Verified via cpp+dtc throughout: exit 0, no new errors, only expected
  warnings (own placeholder + mainline's own upstream duplicate-address
  warnings).

- 2026-09-15 (continued): **PCIe0 wired up — the bus QCA6490 actually
  attaches over.** Confirmed genuinely needed (dm1q's real
  qcom,wlan-rc-num=0, and the live device's actual PCI bus topology shows
  exactly one populated domain with the QCA6490 endpoint at the expected
  vendor/device ID). pcie1 exists but is unused on this board.
  **Major discovery: sm8550-samsung-q5q.dts (Z Fold5) already exists in
  real, already-upstream mainline Linux** (named Linaro/community
  contributors, not something needing the same scrutiny as the earlier
  agcarbajo situation). Its real values for PCIe (GPIOs, regulators)
  exactly match what we'd already independently confirmed via live
  measurement on dm1q -- genuinely strong cross-validation from two
  independent methods landing on the same answer.
  **Follow-up identified, not yet done**: worth cross-checking q5q against
  everything already wired in dm1q.dts (WLAN, UFS, USB) as additional free
  confirmation, given it's a real, same-family, already-upstream reference
  we didn't know existed until now. Should happen before or alongside the
  actual boot attempt.
  Verified via cpp+dtc: exit 0, no new errors, only expected warnings.

- 2026-09-16: **Cross-checked dm1q.dts against sm8550-samsung-q5q.dts (Z
  Fold5, real already-upstream mainline), per the follow-up flagged at
  the end of the PCIe work.** WLAN and USB not comparable (q5q doesn't
  have those wired up in this mainline state). UFS comparison genuinely
  improved the file:
  - Added the missing `vdd-hba-supply` (L3G) -- a real gap, not just a
    confirmation.
  - **Properly resolved `vcc-supply`**, replacing the workaround
    fixed-regulator with the real PM8550B L17 subnode. q5q's real value
    exactly matched the live-measured channel from the earlier UFS
    investigation -- this also retroactively confirms "humu" (the
    previously-unidentified PMIC codename) is PM8550B's own internal
    RPMh codename.
  - One genuine discrepancy found and correctly left alone:
    `vdda-phy-supply` is L1E for dm1q (direct evidence from dm1q's own
    fixup table) vs. L1D for q5q -- reasoned through as an expected
    board-to-board SPMI-instance-letter difference (different physical
    PCB layouts, foldable vs. slab phone), not a contradiction requiring
    a fix.
  Removed the now-dead `vreg_ufs_vcc_2p5` workaround regulator definition.
  Verified via cpp+dtc: exit 0, no new errors.
  User caught and corrected a mix-up during this session: an earlier
  reply mistakenly implied the user had told Claude the touch controller
  was Goodix -- it was actually found independently from dm1q's own real
  devicetree (twice: static source + live confirmation). Also flagged a
  real discrepancy worth recording: an iFixit teardown identifies the
  touch controller as STMicroelectronics for the S23 *Ultra*
  specifically -- confirmed via the user's own further research that the
  base S23 (dm1q) does use Goodix, resolving the apparent conflict as a
  variant difference, not an error in either source.

- 2026-09-19: **Checked kernel defconfig against postmarketOS's real
  kconfigcheck.toml spec** (fetched fresh from pmaports, "community"
  category -- the full real target checklist). Wrote
  notes/check_kconfig.py to parse the TOML (handles version/arch ranges)
  and cross-check against our actual .config, since manual comparison
  against 475 option requirements isn't practical by hand.
  **Result: 313 of 475 don't match.** Mostly not concerning for right now
  -- the bulk is accessibility (SPEAKUP screen reader), containers/
  Waydroid netfilter rules, exotic filesystems (exFAT/F2FS/XFS/EROFS),
  and hardening/CFI -- all genuinely needed for a real, polished,
  submittable pmOS device port, but not relevant to the immediate goal
  (prove the devicetree boots to a shell).
  **Applied narrowly**: only UEVENT_HELPER=y and NULL_TTY=m -- cheap,
  harmless, genuinely useful for device-node robustness even in a minimal
  initramfs, verified via scripts/config + olddefconfig. Confirmed
  DEVTMPFS/DEVTMPFS_MOUNT/TMPFS/SERIAL_QCOM_GENI_CONSOLE were already on
  by default, covering what's actually load-bearing for the shell itself.
  **Deliberately deferred**: the other ~311 items. Revisit once basic
  boot is proven and an actual pmaports submission is the goal, not
  before. kconfigcheck.toml and kconfig-generic.toml fetched to
  /tmp during this check (not persisted anywhere in-repo since they're
  a live upstream spec, easy to re-fetch when needed again).

- 2026-09-20: **First real kernel build + boot image assembly — materials
  ready for a real flash/boot attempt, not yet flashed.**

  **Scope clarified up front**: this builds a real upstream mainline
  kernel with dm1q.dts, plus a bare-minimum custom initramfs (busybox +
  a one-line shell /init). This is NOT postmarketOS -- no Alpine
  userspace, no pmaports packaging, no init system. It's the smallest
  possible thing that can prove "does this kernel initialize dm1q's real
  hardware," deliberately separated from the actual pmOS work.

  **Safety planning first**: user's device is their daily driver, so
  walked through real risk before touching anything. Corrected an early
  wrong assumption of mine: Samsung phones do NOT support fastboot at
  all (confirmed via web search) -- they use their own proprietary Odin/
  Download Mode protocol exclusively (heimdall on Linux). No
  temporary/non-persistent boot option exists the way fastboot boot
  offers on other Android devices -- any real test requires an actual
  persistent flash. Real risk assessment: true hard-bricking is rare for
  boot-partition-only testing, since Download Mode lives in the PBL
  (protected boot ROM) entirely separate from anything being flashed,
  and is specifically designed to survive a bad kernel/bootloader.
  Real risks are wrong-partition-targeting and power loss mid-flash, not
  kernel badness itself. User has stock firmware, crDroid, OrangeFox, and
  confirmed Download Mode access as the recovery path. User will do the
  actual flashing themselves via Heimdall GUI.

  **Kernel build**: full shallow clone of torvalds/linux (2.1GB,
  `../_scratch/linux-build/full`), built with clang/LLVM (already
  available, no separate cross-toolchain needed -- matches what real
  Android GKI kernels use). arm64 defconfig already had everything
  needed for SM8550 (CONFIG_INTERCONNECT_QCOM_SM8550=y confirmed, all
  PHY/UFS/USB/PCIe/ATH11K/regulator drivers present). Kernel version
  built: 7.3.0-rc3.

  **Checked against postmarketOS's real kconfigcheck.toml spec**
  (per user's specific request) -- see the 2026-09-19 entry above for
  the full detail. Applied only the two genuinely load-bearing-adjacent
  options (UEVENT_HELPER, NULL_TTY); deferred the other ~311 (real pmOS
  submission work, not relevant to this first boot test).

  **dm1q.dtb built through the real Kbuild system** (not just our
  standalone cpp+dtc check used throughout earlier devicetree work) --
  genuine additional validation that it integrates cleanly with the full
  kernel build, not just standalone dtc. 120176 bytes.

  **Initramfs**: real Alpine busybox-static (v1.37.0-r30, aarch64,
  fetched directly from dl-cdn.alpinelinux.org -- thematically apt given
  the eventual pmOS/Alpine target) plus a minimal /init that mounts
  proc/sys/devtmpfs and execs a shell. 657KB gzip-compressed cpio.

  **Real boot image structure discovered, not assumed**: pulled the
  actual current boot/init_boot/vendor_boot partitions directly off the
  device via adb+dd (root via KernelSU) -- this doubles as a complete,
  exact backup of the working boot state before any flash is attempted.
  unpack_bootimg revealed a true 3-way GKI split (boot=kernel only,
  init_boot=generic ramdisk, vendor_boot=vendor ramdisk+dtb), header
  version 4, matching gts9uwifi's real deviceinfo (header_version=4,
  flash_pagesize=4096) exactly. Extracted real parameters: kernel load
  0x8000, ramdisk load 0x1000000, dtb load 0x1f00000, real vendor
  cmdline, os_version 16.0.0, patch level 2026-07.

  **Built three replacement images** with mkbootimg, verified by
  re-unpacking each and diffing against the originals -- everything
  identical except the intentional swaps (our kernel in boot_new.img,
  our initramfs in init_boot_new.img, our dtb -- 120176 bytes, replacing
  Samsung's 1.8MB multi-board-revision blob -- in vendor_boot_new.img,
  vendor ramdisk otherwise byte-identical). Both raw .img and
  img2simg-converted .simg versions produced, since it wasn't certain
  which format this Heimdall GUI expects (Heimdall/Odin traditionally
  expects raw, sparse is more of an AOSP/fastboot convention) -- left
  the choice to the user rather than guessing.

  All materials in `../_scratch/boot-backup-20260920/`: the three
  original partition dumps (backup/recovery path), the three new
  replacement images (raw + sparse), and the unpacked component
  directories for reference.

  **Status: ready for the user to flash via Heimdall. Not yet flashed,
  not yet tested on real hardware.** Next real milestone: an actual
  boot/flash attempt.
