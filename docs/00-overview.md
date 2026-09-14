# Overview / current state of the art

Last updated: 2026-09-13

## Device

- Samsung Galaxy S23, codename **dm1q** (S23+ = dm2q, S23 Ultra = dm3q)
- SoC: Qualcomm SM8550-AC "Snapdragon 8 Gen 2 for Galaxy" (kalama family)
- GPU: Adreno 740
- Display: AMOLED, 6.1", 2340x1080, 120Hz variable refresh
- Current OS on hand: crDroid (bootloader unlocked, fully modifiable)

## Kernel package strategy (added 2026-09-13)

postmarketOS's near-mainline "shared kernel" packages (e.g.
`linux-postmarketos-qcom-sm8350`) are thin APKBUILD wrappers that pull a
tarball from a dedicated community fork org, e.g.
`gitlab.com/sm8350-mainline/linux`. Checked for an SM8550 equivalent:
**no `sm8550-mainline` org exists** (unlike sm8350-mainline, sm8250-mainline,
sm6125-mainline, sdm845-mainline, msm8939-mainline, which all exist). So
there's no ready-made community fork to point a new
`linux-postmarketos-qcom-sm8550` package at the way sm8350's does.

However: SM8550 SoC-level mainline kernel support looks fairly mature already
via general web search (not yet verified against actual mainline source) —
Linaro/Qualcomm upstreaming work on SM8550 (display/DPU/DSI, interconnect,
clocks) appears to date to ~early 2023, and Linaro's own devboard
documentation states their SM8550-HDK reference board boots mainline
(v6.8+) directly. If true, this means SoC-*platform* support (not
device-specific) is largely already upstream, and what's actually missing is
Galaxy-S23-specific device bring-up (devicetree, panel, touch, PMIC
regulator mapping, pinctrl) — consistent with this project's existing scope
split, just with better evidence behind it now. **Not yet verified: actually
checking mainline `arch/arm64/boot/dts/qcom/sm8550*.dtsi` directly for what's
really upstream vs. still Linaro-only patches.** Do that before assuming any
specific subsystem "just works."

Practical implication for Phase 1 Step 1 (kernel package): since there's no
`sm8550-mainline` fork to wrap, `linux-postmarketos-qcom-sm8550` will likely
need to be created pointing at plain upstream mainline (or a recent
linux-next/Linaro tree) directly, following the sm8350 package as a
structural template (see its APKBUILD) rather than a content template.

## postmarketOS status

- **Correction (2026-09-13, later pass): dm1q not found in current pmaports.**
  A sparse partial clone of the live `gitlab.postmarketos.org/postmarketOS/pmaports`
  repo (`main` branch, HEAD `1c99c07`, dated 2026-09-13) was searched directly
  with `git ls-tree -r` across the *entire* tree — `device/main`,
  `device/testing`, `device/community`, `device/archived`,
  `device/downstream` — for `dm1q`, `dm2q`, `dm3q`, `kalama`, and `sm8550`.
  **Zero matches for any of them.** No SM8550/kalama-family Samsung device
  exists in pmaports today. This directly contradicts the note below (kept,
  struck through) claiming dm1q was "confirmed by hand" as selectable in
  `pmbootstrap init`. That claim was never checked against actual pmaports
  source before now and should be treated as unconfirmed — possible
  explanations include a fuzzy/typo match in pmbootstrap's device search, a
  different/local pmaports checkout, or simple misremembering. **A fresh,
  carefully-observed `pmbootstrap init` run is needed to settle this** — see
  docs/02-open-questions-and-risks.md item 1.
- **Practical implication regardless of how that discrepancy resolves: there
  is no existing dm1q device package to build from or diff against.** This is
  a from-scratch port. This doesn't change the overall plan — the Tab S9
  Ultra was always being used only as an SM8550-family reference, not a
  literal starting point — but Phase 1 Step 0's "confirm dm1q pmaports
  package" item now resolves to "package does not exist," not to specific
  maintainer/kernel-type details.
- ~~dm1q appears as a selectable device in `pmbootstrap init` (confirmed by
  hand, not by web search).~~ — superseded by the correction above.
- **Infrastructure correction (2026-09-13):** postmarketOS migrated `pmaports`
  and its other repos from `gitlab.com` to a self-hosted instance at
  `gitlab.postmarketos.org` on 2024-10-06. The old `gitlab.com/postmarketOS/*`
  projects are now archived/read-only with a "moved" banner. This is why
  earlier searches for dm1q on gitlab.com turned up nothing — wrong host, not
  just weak indexing. The self-hosted instance also isn't well-crawled by web
  search, so it still needs to be checked directly/manually, not via search.
  **Use `gitlab.postmarketos.org/postmarketOS/pmaports` going forward, not the
  gitlab.com link.**
- **Done (2026-09-13):** searched pmaports directly instead of via
  `pmbootstrap init`'s own clone, using a sparse partial clone
  (`git clone --filter=blob:none --depth=1 --no-checkout`) to minimize data
  transfer — result was the "not found" correction above. Still outstanding:
  actually run interactive `pmbootstrap init`, type `dm1q` into its device
  search, and record exactly what it shows (a real match, a fuzzy/typo
  near-match, or nothing) to resolve the contradiction with the earlier
  "confirmed by hand" note.
- postmarketOS wiki has a "Samsung Galaxy S23" page in Category:Android, but the
  page could not be fetched directly (blocked by the wiki's Anubis anti-bot wall,
  and Wayback Machine / search snippets didn't surface its content either).
  **Action: open wiki.postmarketos.org/wiki/Samsung_Galaxy_S23 in a browser and
  paste the maintainer/status/feature-matrix content into this file.**

## Kupfer status

- Kupfer currently supports only ~10 devices, all Snapdragon 845-era or older
  (msm8916, msm8953, sdm670, sdm845 families). Nothing near SM8550.
- Kupfer's own docs state it reuses postmarketOS's deviceinfo files and
  explicitly recommend doing the postmarketOS port first. It does not do
  independent hardware bring-up.
- Conclusion: pmOS bring-up is a hard prerequisite, not just "the easier path."

## Closest prior art: same SoC family (SM8550/kalama)

**Samsung Galaxy Tab S9 Ultra Wi-Fi (SM-X910, codename gts9uwifi)** — independent,
actively maintained mainline-first pmOS-style port by github.com/agcarbajo.
Repo: postmarketos-galaxy-tab-s9-ultra (see docs/03-references.md for link).

As of last check (~30 days old at time of writing), on a 7.2-rc3 mainline kernel:

| Component | Status |
|---|---|
| Display | Working |
| GPU (Adreno 740, freedreno/Turnip) | Working |
| Wi-Fi (ath12k, WCN7850) | Working |
| Bluetooth | Working |
| Audio (quad speaker, CS35L45 amps) | Working |
| Buttons, battery, charging | Working |
| microSD | Working (early enumeration) |
| Camera | Not attempted / not mentioned |
| Modem | N/A — this is a Wi-Fi-only tablet, no modem hardware |

This is the single best available reference for SM8550-specific bring-up
(clocks, GCC/RPMH, interconnects, PMIC/regulator patterns, UFS init sequence),
even though the board-specific bits (panel, touch, pinctrl) will differ for dm1q.

**Resolved (2026-09-13): the WCN chip is confirmed to differ from the Tab S9
Ultra, and by more than we originally guessed.** Qualcomm shipped *two
different* Wi-Fi/BT chips across the S23 line depending on model:

- **S23 and S23+ (dm1q, dm2q)** — Qualcomm FastConnect 6900, i.e. WCN6855-class
  silicon. Wi-Fi 6E only, `ath11k` driver in Linux.
- **S23 Ultra (dm3q)** — Qualcomm FastConnect 7800, i.e. WCN7850/WCN7851-class
  silicon — the *same chip family* as the Tab S9 Ultra reference device —
  though Samsung's firmware limits it to Wi-Fi 6E rather than exposing the
  chip's native Wi-Fi 7 (802.11be) capability. `ath12k` driver in Linux.

Sources: iFixit's Galaxy S23 Ultra chip-ID teardown identifies the WCN7851
part directly; multiple independent Samsung Community / XDA Forums threads
(citing Qualcomm's own device finder page) confirm the base S23/S23+ got
FastConnect 6900 while only the Ultra got 7800.

**Implication for dm1q specifically: assume `ath11k`/WCN6855, not `ath12k`.**
The Tab S9 Ultra's PCIe/WiFi node structure does *not* directly apply to dm1q
— it would be the right reference for dm3q (S23 Ultra) instead. Still confirm
against the actual crDroid kernel tree before committing code (grep for
`wcn6855` / `qcom,wcn6855` compatible strings), since this is sourced from
teardowns/community reporting on retail units, not from dm1q's kernel source
directly.

## Camera reality check

Mainline Linux camera support (qcom-camss + libcamera) is sensor- and
ISP-generation-specific. Reference: a 2026 effort brought up the OmniVision
OV13B10 sensor on a Fairphone 6 (SM7635 "milos", TFE665 ISP block) by comparing
it against the already-supported TFE530 block. No equivalent work exists yet
for the S23's Spectra 780 ISP or its sensors (Samsung S5KGN3, Sony IMX564,
Samsung S5K3K1, etc.) as far as could be found. Waydroid does not solve this —
it only passes through camera devices the host kernel already exposes via
V4L2 or libcamera; it can't create driver support that doesn't exist.

**Working assumption for planning: camera is out of scope for v1.** Revisit only
if someone independently does Spectra-generation camss bring-up.

## Modem reality check

Inconsistent across pmOS Samsung ports and highly device-specific — not
predictable from the Tab S9 Ultra (no modem hardware to test). One SDM845
Samsung port (Galaxy S9) got cellular calls/SMS/data working, but in that same
build Wi-Fi/Bluetooth/camera were all broken — feature completeness on these
ports is usually a tradeoff, not a checklist that fills in order. Treat modem
as a stretch goal, separate effort from the rest of bring-up.
