# _scratch — external reference material

This directory holds frozen snapshots of external repositories used as
reference material for the dm1q port. These are **not our code** — they're
other people's work (or, for `crdroid-dm1q-dts` and `pmaports`, official
project sources), kept here for convenience so this repo is self-contained
and doesn't depend on those sources staying available/unchanged upstream.

`.git` directories were deliberately stripped from all of these before
committing — they were git clones during research, but we only need the
file contents, not live-clone/pull ability. Exact source URL and commit
hash for each is recorded below (and in more detail in the docs/ files
referenced) for reproducibility if you ever need to re-fetch or verify
against the original.

## What's here

### `crdroid-dm1q-dts/` (90MB)
Real Samsung downstream devicetree source for dm1q, 10 board revisions.
**This is the most important thing in this folder** — it's the ground
truth for dm1q's actual hardware (WCN chip, PMIC parts, panel, touch,
regulators, pinctrl), used throughout docs/02-open-questions-and-risks.md.
- Source: `https://github.com/crdroidandroid/android_kernel_samsung_sm8550-devicetrees`
- Branch: `16.0`
- Fetched: 2026-09-14 (shallow, depth=1)
- Relevant files: `samsung/dm1q_eur_openx_w00_r*.dts` (r01–r13)

### `gts9u-pmos-ref/` (1.6MB) and `gts9u-ubuntu-ref/` (6.0MB)
Tab S9 Ultra (same SM8550/kalama SoC) mainline Linux/postmarketOS reference
ports by GitHub user `agcarbajo`. Verified legitimate (real, technically
correct code) after an earlier back-and-forth misjudged them — full
verification writeup and history in docs/03-references.md. Used as the
*structural* template for dm1q's own pmaports packages and devicetree — the
*values* are tablet-specific and don't transfer, only the shape of the work.
- Sources: `https://github.com/agcarbajo/postmarketos-galaxy-tab-s9-ultra`,
  `https://github.com/agcarbajo/ubuntu-galaxy-tab-s9-ultra`
- Fetched: 2026-09-13 (shallow, depth=1)
- Key files: `gts9u-pmos-ref/pmaports/device/testing/{device,linux}-samsung-gts9uwifi*`,
  `gts9u-ubuntu-ref/kernel/dts/sm8550-samsung-gts9uwifi.dts`

### `linux-mainline/` (12MB)
Sparse checkout of `arch/arm64/boot/dts/qcom/` only, from real upstream
Linux. Used to check what's genuinely SoC-generic (`sm8550.dtsi` and the
PM8550-family PMIC dtsi files) vs. board-specific in the gts9u reference —
see docs/04-gts9u-vs-mainline-devicetree-diff.md.
- Source: `https://github.com/torvalds/linux`
- Fetched: 2026-09-13, `master` branch tip at fetch time

### `pmaports/` (480KB)
Small sparse checkout of the official postmarketOS package repo. Used to
confirm dm1q has no existing pmaports package (checked against full
14,885-commit history, not just current tip — see
docs/02-open-questions-and-risks.md item 1b) and as a structural example
for shared kernel packages (`device/main/linux-postmarketos-mainline`,
`device/archived/linux-postmarketos-qcom-sm8350`).
- Source: `https://gitlab.postmarketos.org/postmarketOS/pmaports`
- Fetched/verified: 2026-09-13, `main` branch, HEAD `1c99c070f` at the time

### `gts9u-board-specific-labels.txt`
Output of the regex-heuristic devicetree diff described in
docs/04-gts9u-vs-mainline-devicetree-diff.md — the 105 labels found in the
gts9u board file that don't appear in the upstream files it includes.

## Why this is committed, not gitignored

Earlier in this project these were kept as uncommitted siblings outside the
repo specifically to avoid this. Moved in and documented on request — the
tradeoff (repo size vs. self-containment/durability if upstream sources
change or disappear) was a deliberate call, not a default.
