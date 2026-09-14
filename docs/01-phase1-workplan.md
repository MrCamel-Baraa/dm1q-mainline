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
      `_scratch/` on 2026-09-14 — see `_scratch/README.md`). Done
      2026-09-13: `_scratch/gts9u-pmos-ref` and `_scratch/gts9u-ubuntu-ref`.
- [x] Pull a recent mainline kernel tree (or at least `arch/arm64/boot/dts/qcom/`)
      to get the baseline `sm8550*.dtsi` files. Done 2026-09-13: sparse
      partial clone of `torvalds/linux` into `_scratch/linux-mainline`,
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
      `_scratch/crdroid-dm1q-dts` (~96MB). This is the ground truth used
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

**Note (2026-09-14): `_scratch/` was moved from a sibling, uncommitted
location into this repo (with `.git` stripped from each cloned subfolder)
and is now documented in `_scratch/README.md` and the main README. Log
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
  --no-checkout`) of the live repo into `_scratch/pmaports` (sibling to
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
  `_scratch/gts9u-pmos-ref` and `_scratch/gts9u-ubuntu-ref` (siblings
  to this repo, not committed here) for actual use as SM8550 reference
  material going forward. Next real step: use these — particularly
  `gts9u-pmos-ref/pmaports/device/testing/{device,linux}-samsung-gts9uwifi*`
  and `gts9u-ubuntu-ref/kernel/dts/sm8550-samsung-gts9uwifi.dts` — as the
  structural template for building dm1q's own device+kernel pmaports
  packages, adapting board-specific bits (panel, PMIC regulator names,
  sensors, pinctrl) using the crDroid downstream tree for real hardware
  values.

- 2026-09-13 (night, session close): Pulled real mainline
  `arch/arm64/boot/dts/qcom/` (sparse clone, `_scratch/linux-mainline`)
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
  `_scratch/crdroid-dm1q-dts`). This resolved every remaining Step 0 item
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
