# dm1q real hardware values — extracted from crDroid downstream source

Date: 2026-09-14
Source: `../_scratch/crdroid-dm1q-dts/samsung/dm1q_eur_openx_w00_r13.dts`
(real Samsung downstream devicetree, decompiled/flattened DTB — labels are
lost, phandles are numeric, structured as DT overlay fragments rather than
a clean node tree)

## Methodology and its limits

This file is a **dtc-decompiled DTB**, not hand-written source — node labels
were resolved away, leaving only numeric phandles and node names like
`fixed_regulator@2`. Extraction here is regex/line-window based (two small
scripts in `notes/extract_regulators.py` and `notes/extract_pinctrl.py`),
not a real DT-semantics parser. Good enough to plan and write dm1q's own
clean devicetree from; not a substitute for checking specifics again when
actually writing a given node, especially anything phandle-cross-reference
dependent.

## Regulators (28 real `regulator-name` definitions found)

**Panel fixed regulators (GPIO-controlled, not PMIC LDOs):**
- `panel_vddr` — GPIO-controlled fixed regulator
- `panel_vci` — GPIO-controlled fixed regulator
- `panel_vdd3` — GPIO-controlled fixed regulator
- `display_panel_avdd` — 5.500V

**s2mpb02 — a real Samsung LSI sub-PMIC, not previously known to this
project.** Likely dedicated to camera/display rails (18 LDOs + 2 bucks + 1
buck-boost is a classic camera-PMIC channel count):
| Regulator | Voltage |
|---|---|
| s2mpb02-l1 | 0.925V |
| s2mpb02-l2 | 1.000V |
| s2mpb02-l3 | 1.100V |
| s2mpb02-l4 | 0.925V |
| s2mpb02-l5 | 1.050V |
| s2mpb02-l6 – l10 | 1.800V |
| s2mpb02-l11, l13 | 3.200V |
| s2mpb02-l12, l14, l15, l16 | 2.800V |
| s2mpb02-l17, l18 | 2.200V |
| s2mpb02-b1 (buck1) | 0.925V |
| s2mpb02-b2 (buck2) | 1.300V |
| s2mpb02-bb (buck-boost) | 3.400V |

**Other:**
- `VDD_BTP_1P8` — 1.800–1.810V (fingerprint sensor rail — BTP = likely
  "biometric touch processor" or similar Samsung naming)
- `hap-swr-slave-reg`, `dummy_vreg` — present, no voltage set at this node

**Not recovered here via simple text extraction: the general PM8550/
PM8550B/PM8550VE/PM8550VS SPMI regulator channel-to-consumer mapping** for
most consumers. These PMIC LDO/SMPS subnodes exist (confirmed in
docs/02-open-questions-and-risks.md item 2) but don't carry descriptive
`regulator-name` properties in this decompiled file. **Exception, resolved
below: WLAN/BT (QCA6490)** — its mapping *was* fully recovered, not via text
extraction but via reading Samsung's own DTB+DTBO overlay fixup tables
directly (see the dedicated section further down). The same fixup-table
method should work for other consumers too if/when needed — it's a matter
of doing it per-consumer as the devicetree gets written, not a blanket
upfront blocker.

## Key GPIO numbers (direct properties, not pinctrl-state indirection)

| Signal | Property | GPIO (hex → decimal) |
|---|---|---|
| Touch reset | `goodix,reset-gpio` | 0x18 → **GPIO24** |
| Touch IRQ | `goodix,irq-gpio` | 0x19 → **GPIO25** |
| WLAN enable | `wlan-en-gpio` | 0x50 → **GPIO80** |
| WLAN reset | `qcom,wl-reset-gpio` | 0x50 → **GPIO80** (same pin as enable) |
| BT enable | `qcom,bt-en-gpio` | 0x51 → **GPIO81** |
| BT reset | `qcom,bt-reset-gpio` | 0x51 → **GPIO81** (same pin as enable) |
| WLAN/BT sw-ctrl | `qcom,sw-ctrl-gpio` | 0x52 → **GPIO82** |
| WLAN/BT XO clock req | `qcom,xo-clk-gpio` | 0xcc → **GPIO204** |
| Panel reset | `qcom,platform-reset-gpio` | 0x7d → **GPIO125** |
| Panel TE (path A) | `qcom,platform-te-gpio` | 0x56 → **GPIO86** |
| Panel TE (path B) | `qcom,platform-te-gpio` | 0x57 → **GPIO87** (second
  panel/DSI path — matches the dual-sourced panel situation) |

All `0xffffffff` first cells are the resolved (placeholder) phandle to the
TLMM GPIO controller in this decompiled file — the second hex value in each
`<0xffffffff 0xNN ...>` tuple is the actual GPIO pin number.

## Pinctrl states (663 pin-group entries found)

Full table in `notes/dm1q-pinctrl-table.txt` (663 lines) — too large to
usefully inline here. Format: `node_name  pins  function  pull  drive_mA`.
Representative examples:
- `key_vol_up_default` → gpio6, function=normal, pull=pull-up
- `sd_card_det_default` → gpio12, function=normal, pull=pull-up
- `display_panel_avdd_default` → gpio11, function=normal, pull=disable,
  drive=3mA
- `eusb2_reset_ctrl_default` → gpio4, function=normal, pull=disable,
  drive=2mA

## WLAN/BT (QCA6490) regulator supply mapping — resolved 2026-09-14

**The architectural wall we hit, and why it doesn't matter:** Qualcomm's
downstream Android driver models PMIC regulators through an RPMh ARC voting
layer (`../_scratch/crdroid-dm1q-dts/qcom/kalama-regulators.dtsi`, internal
codenames like `pm_v6e_l1`) — a completely different abstraction from
mainline's `qcom,rpmh-regulator` binding (`vreg_l1b`-style direct-named
nodes). There's no clean automatic translation between the two, and that's
fine — dm1q's mainline devicetree needs the mainline convention regardless
of what Samsung's Android driver does internally.

**The actual resolution — direct evidence, not inference.** Found the real
overlay fixup tables in dm1q's own devicetree source (search for
`qcom,cnss-qca6490:.*-supply` — these are Samsung's own DTB+DTBO merge
symbol tables, listing exactly which board-level regulator phandle each
named supply property resolves to). **This is direct, unambiguous evidence
from dm1q's own source, not cross-referenced inference from gts9u.**

| Supply property | Board regulator (from dm1q's own fixup table) | Confidence |
|---|---|---|
| `vdd-wlan-io-supply` | **L15B** | Direct evidence from dm1q source |
| `vdd-wlan-dig-supply` | **S4E** | Direct evidence from dm1q source |
| `vdd-wlan-rfa1-supply` | **S6G** | Direct evidence from dm1q source |
| `vdd-wlan-rfa2-supply` | **S4G** | Direct evidence from dm1q source |
| `vdd-wlan-aon-supply` | **S2G** | Direct evidence from dm1q source |

**Correction to an assumption made earlier in this same investigation:**
initially assumed QCA6490 would use the same 7 supply property names as
gts9u's WCN7850 (`vdd`, `vddio`, `vddio1p2`, `vddaon`, `vdddig`,
`vddrfa1p2`, `vddrfa1p8`) since both are ath11k/ath12k-family. **That
assumption was wrong and is corrected here**: dm1q's own fixup table shows
QCA6490's actual downstream driver only has 5 named supplies
(`vdd-wlan-io`, `vdd-wlan-dig`, `vdd-wlan-rfa1`, `vdd-wlan-rfa2`,
`vdd-wlan-aon`) — no separate main `vdd` or `vddio1p2` rail exists in this
driver's binding at all. This is a genuinely different (simpler) binding
than WCN7850's, consistent with QCA6490 being older/simpler silicon.
**When writing dm1q's mainline devicetree, check mainline's actual QCA6490
binding (not the WCN7850/ath12k one used as a starting assumption) for the
correct property names — likely closer to this 5-rail downstream scheme
than to gts9u's 7-rail one.**

The RPMh resource IDs (S2G/S4E/S4G/S6G) cross-confirm exactly against the
PDC table evidence found earlier in this same investigation and against
gts9u's independently-confirmed mainline mapping for the same resource IDs
— two independent pieces of evidence agreeing is a good sign the underlying
platform-level resource assignment (not board-specific) is being read
correctly. L15B (the `vdd-wlan-io` LDO) is a new confirmation not
previously cross-checked against gts9u.

**Methodology credit:** the general technique — cross-referencing a
downstream PDC voting table against a mainline regulator mapping — is the
same one the gts9u author used; their own inline comment (`/* Stock Kiwi v2
votes PM8550VS-G L3 through its WCN PDC map. */` — "Kiwi" is Qualcomm's
internal codename for WCN7850) confirms they did the same kind of
downstream-source cross-reference, not a guess. For dm1q specifically, the
final resolution above came from an even more direct source (dm1q's own
overlay fixup table), which is why it's high-confidence rather than
inferred-by-analogy.

## Regenerating this data

```
python3 notes/extract_regulators.py ../_scratch/crdroid-dm1q-dts/samsung/dm1q_eur_openx_w00_r13.dts
python3 notes/extract_pinctrl.py ../_scratch/crdroid-dm1q-dts/samsung/dm1q_eur_openx_w00_r13.dts
```
Both scripts take a `.dts` path as their only argument — point them at a
different board revision (`dm1q_eur_openx_w00_r01` through `r13`) to compare
across revisions if needed.

## UFS regulator mapping — resolved 2026-09-15

Same fixup-table cross-referencing method as the QCA6490 WLAN/BT mapping
above, applied to `&ufs_mem_hc`/`&ufs_mem_phy`. All channel identities
below are from dm1q's own real DTB+DTBO overlay fixup tables, not
inference:

| Supply | Real channel | Cross-check |
|---|---|---|
| `reset-gpios` | GPIO210 (`0xd2`) | Exact match with gts9uwifi's reset-gpio |
| `vccq-supply` | PM8550VS-G L1 (`pm_v6g_l1`) | Exact channel match with gts9uwifi's `vreg_l1g_1p2` |
| `vdda-pll-supply` | PM8550VS-E L3 (`pm_v6e_l3`) | Exact channel match with gts9uwifi's `vreg_l3e_1p2` |
| `vdda-phy-supply` | PM8550VS-E L1 (`pm_v6e_l1`, downstream name `vdda-qref-supply`) | Exact channel match with gts9uwifi's `vreg_l1e_0p88` |
| `vdd-hba-supply`/ref-clk | PM8550VS-G L3 (`pm_v6g_l3`) | Exact channel match with gts9uwifi's `vdd-hba-supply = vreg_l3g_1p2` |

**`vcc-supply` (main UFS power) — a genuinely harder case, resolved by live
hardware measurement rather than static source analysis.** dm1q's fixup
table showed this fed by `pm_humu_l17` — a PMIC instance ("humu") absent
from Qualcomm's own reference `kalama-pmic-overlay.dtsi` entirely.
Investigation trail:
1. Checked real kernel mailing list patches for PM8350C's documented
   regulator range: `smps1-smps10, ldo1-ldo13, bob`. This matches the BOB
   (buck-boost) capability seen alongside `humu` in dm1q's source, but
   the L17 numbering exceeds PM8350C's documented L1-L13 range — a real
   inconsistency, not resolved by this alone.
2. Connected to the actual physical device over `adb` (root via KernelSU)
   and read `/sys/class/regulator/` directly. Found `regulator.44`
   (`pm_humu_l17`) has a symlink literally named `1d84000.ufshc-vcc` with
   consumer `platform:1d84000.ufshc` — `1d84000` is the exact UFS host
   controller address from mainline's own `ufshc@1d84000` node.
   **Fully unambiguous, live confirmation**, not inferred: `state=enabled`,
   `microvolts=2504000` (2.504V, fixed — min equals max), `num_users=1`,
   `opmode=fast`.
3. Given the channel count (17 LDOs + 2 BOB outputs under "humu") exceeds
   any single chip in dm1q's confirmed PMIC set, "humu" is likely an RPMh
   voting domain that aggregates multiple physical PMICs (dm1q has 2×
   PM8010, 7 LDOs each = 14, plus PM8350C's LDOs/BOB — both already in
   dm1q's confirmed PMIC list), not a single chip. The exact SPMI-level
   binding for this aggregate domain was not resolved.

**Practical resolution in dm1q.dts**: modeled as a simple `regulator-fixed`
node at the confirmed real voltage (2.504V), rather than the real "humu"
PMIC chain. This is a deliberate, evidenced simplification: UFS holds the
boot media itself, so this rail must already be enabled by firmware
(PBL/XBL) before Linux starts — the bootloader couldn't otherwise read the
kernel off UFS. The live `num_users=1` confirms nothing else shares this
rail, so a static always-on representation doesn't misrepresent any
dynamic sharing behavior either.

**Methodology note for future items like this**: when static source
archaeology hits a genuine wall (chip identity ambiguous, downstream/
mainline binding mismatch), live measurement against the actual physical
device (`adb shell su -c 'cat /sys/class/regulator/regulator.N/*'`, once
root is available) can resolve exactly the kind of factual question that's
otherwise stuck at "plausible guess." Worth trying this route earlier for
similarly-stuck items rather than only as a last resort.

## Full live-hardware verification pass — 2026-09-15

Following the UFS vcc-supply resolution above, went back through every
regulator voltage in dm1q.dts marked "INFERRED from gts9uwifi" and checked
each against the real physical device (`adb shell su -c 'cat
/sys/class/regulator/regulator.N/*'`, root via KernelSU). Also
cross-confirmed all 5 WLAN regulator channel identities independently via
`/sys/class/devlink/` consumer symlinks (e.g.
`rpmh-regulator-smpg2--platform:b0000000.qcom,cnss-qca6490`), not just the
downstream fixup-table method used earlier — an even more direct
confirmation, since it shows the live kernel's actual consumer graph.

| Channel | Consumer | Inferred (gts9uwifi) | Live confirmed | Result |
|---|---|---|---|---|
| L15B | WLAN vddio | 1.8V fixed | 1.8V fixed (regulator.34) | Exact match |
| L3E | UFS vdda-pll | 1.2V fixed | 1.2V fixed (regulator.63) | Exact match |
| L1E | UFS vdda-phy | 0.88V | 0.88–0.912V (regulator.57) | Matches min |
| L1G | UFS vccq | 1.2V | 1.144–1.256V (regulator.82) | Matches midpoint |
| S4G | WLAN rfa2 | 1.352V | 1.2–1.352V (regulator.78) | Matches max |
| S6G | WLAN rfa1 | 1.904V | 1.8–2.0V (regulator.81) | Within range |
| S4E | WLAN dig | 0.952V | 0.904–0.984V (regulator.53) | Within range |
| S2G | WLAN aon | 0.98V | 0.5–1.036V (regulator.75) | Within range, live instantaneous reading notably lower (idle corner) |

**Outcome: nothing was actually wrong.** Every gts9uwifi-inferred value
either matched exactly or fell within the real device's confirmed range.
But several of these are genuinely multi-corner ARC-voted rails, not fixed
single points — `dm1q.dts` updated to use the real min/max ranges instead
of the originally-guessed single fixed values, which is both more accurate
and better practice (lets the consumer driver request whatever corner it
actually needs at runtime, same pattern mainline's own reference boards
use — e.g. `sm8450-hdk.dts`'s `vreg_s11b_0p95` has a real
966000–1104000 range, not a literal fixed 0.95V, despite the name).

This is strong validation of the whole cross-referencing methodology used
throughout this project (gts9uwifi's channel-identity mapping + real RPMh
platform-constant reasoning) — every single inferred value checked out.
