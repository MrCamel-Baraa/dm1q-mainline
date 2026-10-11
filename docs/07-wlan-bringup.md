# WLAN bring-up (QCA6490 / ath11k)

> **2026-10-10 UPDATE -- READ SECTION 15 FIRST: CONFIRMED ON HARDWARE.** With the DTB's `iommu-map`
> back in the legacy 4-cell form (test image v9, same kernel as v8) the QCA6490 boots in 0.7 s,
> ath11k probes, `wlan0` appears, and after a normal reboot it joins the AP and gets DHCP. The
> controller's BDF-to-SID table read back from the phone is exactly the one section 14 predicted.
> This supersedes the "not yet proven" below. Open: link quality (69-80 % ping loss to the gateway)
> and DNS, the proper fix (kernel r5), and everything that is not WLAN (15.6, 15.7).

> **2026-10-09 UPDATE -- READ SECTION 14 FIRST.** The WLAN stall after the chip enumerates is most
> likely **not a chip problem**: 7.3-rc3 programs the PCIe controller's BDF-to-SID table from a
> mis-parsed (5-cell) `iommu-map`, so our endpoint's MSIs never reach the host -- a known upstream
> regression, already fixed upstream (patch carried as kernel r5; DT-only test image v9). **Not yet
> proven on hardware.** The register experiment of 2026-10-07 produced no data (two bugs in my
> sampler), and the "rails at their DT minimum" (section 13) and "boot ROM never completes BHI"
> (v8) readings are retired. Section 14 has the evidence, the test and what it must show.

> **2026-10-01 UPDATE -- READ THIS FIRST.** The "&pcie0 breaks whenever the
> devicetree changes" regression described from "2026-09-28: real hardware
> result" onward was **not a devicetree problem**. Every rebuilt kernel carries
> a fresh, random module-signing key; the pmOS rootfs' modules are signed with
> the *first* build's key; the pmaports config forces kernel lockdown, so every
> rebuilt kernel refused every module (PCIe PHY included) and `&pcie0` could
> never probe. Proven from the logs, the image files and the kernel source --
> see **"ROOT CAUSE FOUND 2026-10-01"** at the bottom. The sections in between
> are kept as written (the history of how we got there), with `CORRECTION`
> notes where a claim turned out wrong. A second, independent bug in the
> `wifi@0` wiring that the first one was masking is described there too.

## Symptom, from the real pmOS boot on 2026-09-28

From the actual dmesg pulled off the booted device
(notes/2026-09-28-pmos-v1-hang/dmesg-ssh-live.txt):

```
probe of soc@0:wcn6855-pmu with driver pwrseq-qcom_wcn returned 0 after 2258 usecs
...
qcom-pcie 1c00000.pcie: Device not found
qcom-pcie 1c00000.pcie: PCI host bridge to bus 0000:00
probe of 1c00000.pcie with driver qcom-pcie returned 0 after 1131480 usecs
```

The power-sequencer (`pwrseq-qcom_wcn`, bound to our `wcn6855-pmu` node)
probes cleanly. The PCIe controller itself also eventually probes
successfully (`returned 0`, after waiting through several `-517`
deferred-probe retries while its regulators came up). But no device
answers on the bus: `Device not found`. No `ath11k`/`qca6490` string
appears anywhere in the log -- the driver never even got a chance to
bind, because nothing showed up for it to bind to.

## Finding 1: the PDC calibration table in our DTS is from the wrong node

`dts/dm1q/dm1q.dts`'s `wcn6855-pmu` node carries a `qcom,wlan-pdc-init`
table this project's own earlier notes marked CONFIRMED from dm1q's real
downstream source. That's true, but it's the wrong table. Checked
directly against `_scratch/crdroid-dm1q-dts/samsung/dm1q_eur_openx_w00_r13.dts`
(same for r01-r13; not a revision drift): there are TWO
`qcom,pdc_init_table` properties in that file, in two different nodes:

- Line 17092: inside a `qcom,bt-*` block (surrounded by
  `qcom,bt-vdd-io-supply`, `qcom,bt-vdd-aon-supply`, etc) -- this is the
  **Bluetooth** sequencer's own table. Ends `..., dwnval: 515}`. This is
  the one our DTS copied.
- Line 17224: inside the actual `qcom,cnss-qca6490 { compatible =
  "qcom,cnss-qca6490"; ... }` node -- the real WLAN chip's own table.
  Ends `..., dwnval: 800}", "{class: wlan_pdc, ss: bb, res: pdc,
  enable: 0}"` -- one more entry than the BT table, and a different
  final value.

Since mainline's `qcom,wlan-pdc-init` property name is WLAN-specific (not
a combined/generic name), the semantically correct source is the second
table, not the first. This is a real, fixable bug: swap in the WLAN
table from line 17224, not the BT one from line 17092.

**This alone probably isn't the whole story** -- a wrong calibration
value would more likely cause an unstable/underperforming radio than a
complete PCIe enumeration failure. It's being fixed regardless since it's
now verified wrong, but Finding 2 below looks like the bigger blocker.

## Finding 2: our devicetree likely lacks the pci-pwrctrl-pwrseq binding QCA6490 needs

Checked dm1q's own real `qcom,cnss-qca6490` node (same file, lines
17187-17224) for anything resembling a PCIe PERST/reset GPIO. There is
none -- only `wlan-en-gpio`, `qcom,bt-en-gpio`, `qcom,sw-ctrl-gpio`,
`qcom,xo-clk-gpio` (all of which we already carry as
wlan/bt-enable-gpios, sw-ctrl, xo-clk under `wcn6855-pmu`). No separate
reset line for the chip itself.

Cross-checked against a live, currently-open mainline regression report
(found via web search, 26 days old at the time of writing) for a
different chip in the same family (WCN7850) on a different SoC
(X1E80100/Surface Pro 11), with an IDENTICAL symptom signature:
Bluetooth (UART) works, `pwrseq_qcom_wcn` is loaded and bound, PCIe
"Device found, but not active" / link never trains, `ath12k` never
probes. The report explicitly notes: *"it is power-sequenced via
wcn7850-pmu / pwrseq"* and has *"no PERST# GPIO"*.

Then checked real, current mainline devicetree examples (also via web
search) for how boards actually wire a wcn6855-pmu-family chip that sits
on PCIe: several (sc8280xp-microsoft-arcata, the Hamoa IoT EVK M.2 slot)
use a `wifi@0` CHILD NODE under the PCIe port itself:

```
&pcie_port0 {
	wifi@0 {
		compatible = "pci17cb,XXXX";   /* device-specific ID */
		reg = <...>;
		vddaon-supply = <...>;
		vddwlmx-supply = <...>;        /* kernel test robot flagged a
		                                   real board for omitting this
		                                   required property */
		...
	};
};
```

This is the mainline `pci-pwrctrl-pwrseq` mechanism: it's how the kernel
knows to hold PCIe link training until the referenced pwrseq/PMU node has
actually powered the chip, for chips with no independent PERST# line.
**Our current DTS has no such node** -- `wcn6855-pmu` is a bare top-level
node with no relationship wired to `&pcie0`'s own probe, so `qcom-pcie`
has no reason to wait for it and attempts link training on its own
schedule. That fits our exact symptom: the controller itself comes up
fine (after its own deferred-probe waits), but nothing answers, because
nothing told it to wait for the chip to actually be powered first.

**Caveat, to stay honest about confidence level here:** other real
mainline boards using `wcn6855-pmu` (qcs8300-ride, monaco-arduino-monza)
do NOT use a `wifi@0` child node -- just the simple top-level pattern we
already have. Whether dm1q's QCA6490 needs the `wifi@0`/pwrctl pattern or
the simple pattern is NOT yet independently confirmed for this specific
chip -- it's a well-evidenced hypothesis from a real matching bug report
and real examples of the alternative pattern, not something read
directly off dm1q's own source (downstream uses an entirely different,
proprietary `cnss2` driver stack that doesn't map 1:1 onto either
mainline pattern). This needs to be tried and observed, not assumed
correct on the first attempt.

## Not yet done

- Finding the real Qualcomm PCI vendor/device ID for QCA6490
  (`pci17cb,XXXX` -- need the actual number, not a guess).
- Working out exactly which of our 10 existing `vddXXX-supply` regulator
  assignments map onto whichever supply names a `wifi@0` node would need
  (likely a subset/rename of what `wcn6855-pmu` already has, per the
  qcs8300-ride example's naming: vddaon/vddwlcx/vddwlmx/vddrfacmn/
  vddrfa0p8/vddrfa1p2/vddrfa1p8/vddpcie0p9/vddpcie1p8 -- a DIFFERENT and
  more numerous set of names than the 10 our `wcn6855-pmu` node current
  uses (vddio/vddaon/vddpmu/vddpmumx/vddpmucx/vddrfa0p95/vddrfa1p3/
  vddrfa1p9/vddpcie1p3/vddpcie1p9) -- these do NOT obviously 1:1 map, and
  guessing the mapping wrong here would repeat the exact mistake being
  corrected in Finding 1).
- Actually editing the DTS, rebuilding, reflashing, and observing the
  real result. Not done yet -- writing this up first so the plan is
  grounded in evidence before spending another build/flash cycle on it.

## Confirmed 2026-09-28: Finding 2 is real, not just a plausible hypothesis

Checked the `pwrseq` subsystem's own design against its original author's
cover letter (Bartosz Golaszewski, `power: sequencing: implement the
subsystem and add first users`, upstream):

> "The WLAN-specific resources are handled by the 'wlan-enable' unit and
> so are not enabled until the WLAN driver requests the 'wlan' target to
> be powered on."

This confirms `pwrseq` is strictly consumer-driven: a provider (our
`wcn6855-pmu` node) probing successfully only means it REGISTERED
available power targets. It does not assert any enable line by itself.
The `wlan-enable` GPIO is only toggled when a consumer explicitly
requests the "wlan" target via the pwrseq API. Our DTS has no such
consumer anywhere. So on the 2026-09-28 boot, `wlan-enable-gpios` was
almost certainly never asserted at all -- not a race/timing issue as
first floated, but simply nothing ever asking for the chip to be
powered. This resolves the earlier caveat: the `wifi@0`-under-`&pcie0`
pattern is genuinely needed here, not just one of two equally-valid
options.

## Confirmed 2026-09-28: the two missing implementation facts

**PCI compatible string.** The official upstream binding
(`Documentation/devicetree/bindings/net/wireless/qcom,ath11k-pci.yaml`)
lists only two PCI IDs: `pci17cb,1101` (QCA6390) and `pci17cb,1103`
(WCN6855). QCA6490 has no separate entry. Checked directly against the
real `ath11k_pci_id_table[]` in `drivers/net/wireless/ath/ath11k/pci.c`:
only three entries exist -- `QCA6390_DEVICE_ID` (0x1101), `WCN6855_DEVICE_ID`
(0x1103), `QCN9074_DEVICE_ID` (0x1104). QCA6490 is the same base silicon
generation as QCA6390 and enumerates under the same PCI device ID
(0x1101) -- so our `wifi@0` node's `compatible` must be `"pci17cb,1101"`.
This is read off the real driver source, not inferred from a naming
similarity.

> **CORRECTION 2026-10-01:** the table lookup is accurate; the conclusion
> drawn from it is not. "QCA6490 enumerates under 0x1101" was an inference
> from silicon-generation naming, and docs/05 (the live downstream device's
> `/sys/bus/pci/devices/`) had already recorded the QCA6490 enumerating as
> **17cb:1103** -- `WCN6855_DEVICE_ID`. The compatible is `pci17cb,1103`, with
> the 1103 supply list (`vddrfa1p8`, not `vddrfa1p7`). `pci-pwrctrl-pwrseq`
> binds both IDs, so 1101 was wrong rather than causal.

**Required supply properties for that compatible.** Per the same official
binding YAML, `pci17cb,1101` requires: `vddrfacmn-supply`,
`vddaon-supply`, `vddwlcx-supply`, `vddwlmx-supply`, `vddrfa0p8-supply`,
`vddrfa1p2-supply`, `vddrfa1p7-supply`, `vddpcie0p9-supply`,
`vddpcie1p8-supply` -- 9 names, none of which match our existing
`wcn6855-pmu` node's 10 supply names 1:1. This mapping (which of our
real PM8550-family regulators corresponds to which of these 9 names) is
the next real piece of work, and needs the same care as Finding 1 --
matching by expected voltage domain against dm1q's own real downstream
`qcom,vdd-wlan-*-config` values, not by guessing from another board's
numbers.

> **CORRECTION 2026-10-01:** these 9 supplies are not board rails to be
> mapped from downstream voltage configs. In the mainline model they must be
> the *PMU's own output regulators* (`wcn6855-pmu/regulators/ldoN`):
> `pwrseq_qcom_wcn_match()` only matches a consumer whose `vddaon-supply`
> resolves there, and otherwise `pwrseq_get()` defers forever (and with it
> `&pcie0`). The voltage-matching exercise, including its LOW-confidence
> placeholders, therefore had no bearing on function; the real board rails
> are already the PMU node's ten input supplies. See "ROOT CAUSE FOUND
> 2026-10-01", item 6.

## Next steps, in order

1. Work out the wifi@0 supply mapping against dm1q's own real downstream
   voltage configs (not copied from another board).
2. Fix Finding 1 (swap in the WLAN-specific PDC table, not BT's).
3. Add the `wifi@0` node under `&pcie0` with the confirmed compatible and
   mapped supplies.
4. Rebuild the kernel, reflash, and observe the real result -- this is a
   real hardware experiment, not a certainty, since no dm1q-specific
   confirmation exists yet that this combination is complete and correct.

## Implemented 2026-09-28

Both fixes are now in `dts/dm1q/dm1q.dts` (synced to the pmaports copy)
and pass a syntax check (`cpp | dtc`, exit 0 -- one new cosmetic warning,
`wifi@0` sharing unit-address `0` with the base dtsi's own `pcie@0` child,
which real upstream boards using this exact pattern also produce; not an
error, still a valid .dtb).

- Finding 1: `wcn6855-pmu`'s `qcom,wlan-pdc-init` now ends `... s2g.v,
  dwnval: 800}", "{... bb, res: pdc, enable: 0}"` -- the real WLAN table
  from inside `qcom,cnss-qca6490`, not the BT sequencer's table.
- Finding 2: added a `wifi@0` child under `&pcie0`, `compatible =
  "pci17cb,1101"` (confirmed from `ath11k_pci_id_table[]`), with all 9
  required supplies mapped against dm1q's own decoded downstream voltage
  values. Confidence is marked per-property in the DTS itself: HIGH for
  `vddaon`/`vddwlcx`/`vddpcie1p8` (exact voltage matches to decoded
  downstream values), MEDIUM-HIGH for `vddrfa1p2`/`vddrfa1p7` (same
  physical rail as an already-confirmed neighbor, falls inside its real
  adjustable range), MEDIUM for `vddwlmx` (voltage-class neighbor, no
  distinct downstream value), LOW for `vddrfacmn`/`vddrfa0p8`/`vddpcie0p9`
  (no matching downstream value decoded at all -- genuine placeholders
  reusing the nearest already-defined rail, not confirmed).

**Not yet done:** rebuild via `pmbootstrap build linux-samsung-dm1q-mainline`
(needs Baraa's sudo, per the established pattern), reflash, and observe on
real hardware. The three LOW-confidence supplies are the most likely place
for this to still not fully work on the first attempt -- if WLAN comes up
but is unstable/underpowered rather than simply absent, those three are
the first thing to revisit.

## 2026-09-28: real hardware result -- a regression, not just "still absent"

Built and flashed the above (both fixes). Real post-boot `dmesg`/
`journalctl -k` pulled over ssh (notes/2026-09-28-pmos-v1-hang/dmesg.txt,
journal-kernel.txt) show something worse than "still no WLAN":

```
[    0.106560] probe of 1c00000.pcie with driver qcom-pcie returned -517 after 13 usecs
... (nine more -517 deferrals) ...
[   10.726032] qcom-pcie 1c00000.pcie: supply vdda not found, using dummy regulator
[   10.770410] qcom-pcie 1c00000.pcie: supply vddpe-3v3 not found, using dummy regulator
[   10.795676] probe of 1c00000.pcie with driver qcom-pcie returned 517 after 70377 usecs
```

On the FIRST successful pmOS boot (before either WLAN fix), `qcom-pcie`
itself probed cleanly (`returned 0`) and only failed to find a device
afterward (`Device not found`). This time it never got past its own
deferred-probe give-up -- the host bridge itself never finished probing.
Two new "supply ... not found, using dummy regulator" warnings appear for
`vdda`/`vddpe-3v3` on `&pcie0` ITSELF (not `wifi@0`) that were not present
before.

Checked the real upstream PCIe binding (kernel.org
`qcom,pcie.txt`/`qcom,pcie-common.yaml`): `vdda-supply` is documented
**required** on the host bridge node, and real current sm8550 patches
(found via web search, from an active in-flight series) add it to
`&pcie0` directly. Our `&pcie0` never had it -- but that predates today's
changes and didn't block the earlier successful probe (dummy-regulator
fallback is a normal, non-fatal path). So `vdda-supply` being missing
looks pre-existing, not the new cause.

> **CORRECTION 2026-10-01:** (1) These two warnings are *not* new: the
> working v1 boot prints them too (dmesg-ssh-live.txt lines 5116/5127, at
> 7.127874 / 7.151505 s) -- they come from every `qcom-pcie` probe attempt,
> because `&pcie0` has no `vdda-supply`/`vddpe-3v3-supply` and the regulator
> core falls back to a dummy. What differs is only *when* the probe runs
> (10.7 s here, 7.1 s there) and how it ends. (2) The `vdda-supply` "required"
> claim does not hold for this kernel: 7.3-rc3's `qcom,pcie-sm8550.yaml`
> requires only `power-domains`, `resets`, `reset-names`; `vddpe-3v3-supply`
> is optional; and no upstream SM8550 board sets `vdda-supply` on `&pcie0`
> (the `vdda-supply` hits in sm8550-hdk/qrd are the DSI and a camera sensor).
> Lead retired. See the root-cause section below.

The new element is `wifi@0`: it references five regulators via phandle,
and Linux's `fw_devlink` mechanism can create supplier/consumer device
links from those references. Whether that's actually what's now stalling
`&pcie0`'s own probe isn't confirmed -- this needs kernel source (`pcie-
qcom.c`, the `pci-pwrctrl-pwrseq` core) to trace precisely, which wasn't
available locally, and guessing further here would repeat exactly the
mistake Finding 1 already corrected once.

## Bisection test (in progress)

Temporarily commented out the `wifi@0` node in `dts/dm1q/dm1q.dts` (kept
Finding 1's PDC fix active), synced to the pmaports copy, re-verified the
syntax check (`cpp | dtc`, exit 0, `wifi@0` confirmed absent from the
compiled .dtb via `dtc -I dtb -O dts | grep -c wifi@0` = 0, Finding 1's
`dwnval: 800` confirmed still present). This isolates one variable:

- If `&pcie0` goes back to probing cleanly (`returned 0`, `Device not
  found`) -- `wifi@0` itself is confirmed as what broke host-bridge probing,
  and the next step is figuring out why (fw_devlink graph, or something
  wrong in how the node is structured) before re-adding it.
- If `&pcie0` still fails to probe at all -- something else changed
  between the two boots unrelated to `wifi@0`, and Finding 1's PDC change
  or something environmental needs a fresh look instead.

Not yet built/flashed/observed -- next step is Baraa running
`pmbootstrap checksum linux-samsung-dm1q-mainline` (the DTS changed again)
then `pmbootstrap build linux-samsung-dm1q-mainline`.

## Bisection result 2026-09-30: `wifi@0` is NOT the cause

Flashed the bisect kernel (PDC fix active, `wifi@0` removed). Real dmesg:
`qcom-pcie` STILL fails to ever probe successfully (`returned 517`, same
failure shape as the full change). This cleanly rules out `wifi@0` as the
cause.

Re-flashed the exact original, untouched kernel+DTB (saved from the very
first successful boot, before either WLAN edit -- confirmed by decompiling
its actual .dtb: no `wifi@0`, PDC table still at the old `dwnval: 515`).
It probed cleanly again (`returned 0`, then "Device not found" as before).
So across 4 real boots: original DTB succeeded twice, PDC-changed DTB
failed twice (once with `wifi@0`, once without). This looked like real
causation tied to Finding 1's PDC content change specifically.

## Checked something I had not verified: does anything actually read this property?

Before accepting that conclusion, searched for what mainline driver code
actually parses `qcom,wlan-pdc-init` / `qcom,qmp` under `wcn6855-pmu`.
**Found none.** The only real `pdc` driver in mainline is
`drivers/irqchip/qcom-pdc.c` -- the GPIO wakeup interrupt controller, a
completely unrelated subsystem that happens to share the three-letter
abbreviation. No hit anywhere for a driver reading this specific WLAN
calibration property. If true, the property's *content* is inert at the
kernel level right now, and Finding 1's edit (which only changes that
content) cannot mechanistically cause a PCIe regression -- meaning the
2-succeed/2-fail pattern, while real, is more likely explained by
kernel-build-to-build variance in probe/deferred-probe ordering (a known
class of Linux flakiness, especially on a dependency chain that's already
marginal -- recall `&pcie0` silently tolerates a missing `vdda-supply` via
a dummy regulator, exactly the kind of borderline case sensitive to this)
rather than anything in the devicetree.

**Caveat:** this is inferred from the absence of a search hit, not from
reading the actual `pwrseq-qcom-wcn.c`/`pci-pwrctrl-pwrseq` source in full
(not available locally, see the earlier caveat about `_scratch/linux-mainline`
being a sparse checkout with no `drivers/`). Treat as strong evidence, not
proof.

## Kernel build-to-build variance test (in progress)

Decisive, cheap-relative-to-more-guessing test: rebuild the EXACT SAME
bisect source (PDC fix active, `wifi@0` still removed, nothing else
changed) a second time from scratch, and see if a fresh compile succeeds
or fails. Bumped `pkgrel` 1->2 in the kernel APKBUILD purely to force
`abuild` to actually recompile instead of reusing the cached r1 `.apk` --
no source file changed, so existing `sha512sums` stay valid, no
`abuild checksum` re-run needed this time.

- If this fresh build succeeds (pcie0 `returned 0`) despite byte-identical
  devicetree content to the failing bisect build -- CONFIRMED build-to-build
  variance, not a devicetree bug. Both Finding 1 and Finding 2 (`wifi@0`)
  would then be clear to re-enable together, and the real remaining task
  becomes making `&pcie0`'s own probe less marginal (giving it a real
  `vdda-supply` instead of a silently-tolerated dummy, since that kind of
  borderline dependency is exactly what's sensitive to this class of
  variance) rather than further devicetree archaeology on the WLAN side.
- If it fails again identically -- something IS reproducibly tied to this
  exact source content after all, and the "nothing reads this property"
  conclusion above needs to be revisited (or something else entirely is at
  play).

## Kernel build-to-build variance test: RESULT -- ruled out

Fresh `r2` build (identical DTS to the failing bisect, confirmed by
comparing the built .dtb's sha256 to the bisect's extracted .dtb: byte-
identical) still failed the exact same way -- `qcom-pcie` never probed
successfully. This DISPROVES the build-variance theory. The failure is
genuinely, deterministically tied to the DTS content.

> **CORRECTION 2026-10-01:** the test did show the failure is deterministic
> *per rebuilt kernel* -- but a byte-identical .dtb is not an identical
> build. Each build generates its own random module-signing key, so v2, v3
> (bisect), v4 (r2) and v5 (r3) were all different kernels as far as the
> rootfs' modules are concerned, and all failed for the same reason. The test
> controlled the DTB, not the thing that actually varied. "Build-to-build
> variance" was the right class of explanation, just not the probe-ordering
> kind assumed.

## Re-checked the "nothing reads this property" claim against real driver source

Found and read the actual `pwrseq_qcom_wcn_probe()` structure (via
codebrowser): it allocates regulators via `devm_kcalloc(dev,
ctx->pdata->num_vregs, ...)` -- a fixed count from per-chip match data.
No code path reads `qcom,wlan-pdc-init` or `qcom,qmp` under this node.
This independently reconfirms the earlier search result. The property is
genuinely inert as far as any driver source visible to me shows -- yet
changing only its content reproducibly breaks `&pcie0`. Mechanism unknown.

Also found a real, currently-active mainline bring-up project
(bluseliu50/debian-piano, Xiaomi Pad SM8750) independently confirming that
`pcie-qcom`'s host probe genuinely can defer on an unbound `wifi@0`
pwrctrl device until the pci-pwrctrl-pwrseq subsystem loads -- so `wifi@0`
creating a real dependency is not fantasy in general, even though our own
bisection (wifi@0 absent) still failed, ruling it out as THIS particular
regression's cause.

## Full structural diff, decisively isolated

Decompiled both the proven-working DTB (original, pre-any-WLAN-edit) and
the failing one, normalized out dtc's non-deterministic phandle numbering,
and diffed. With phandle noise removed, the ENTIRE structural difference
between a working boot and a failing one is exactly one property --
`qcom,wlan-pdc-init`'s content (48 bytes of DTB growth, one extra string
entry). Nothing else anywhere in the ~7000-line tree differs. This is as
clean an isolation as real-hardware testing gets.

> **CORRECTION 2026-10-01:** the diff was accurate and the isolation real --
> but it compared DTBs, and the DTB was never the variable. The images being
> compared also differed in the kernel build (and its embedded signing key).

## Current state (2026-09-30): reverted PDC, kept wifi@0, testing in isolation

Given the mechanism is unexplained but the empirical result is solid and
reproduced twice independently (including across a fresh, byte-identical
rebuild), took the pragmatic path: reverted `qcom,wlan-pdc-init` back to
its original (`dwnval: 515`, the BT sequencer's table -- functionally
wrong per Finding 1, but PROVEN not to break anything) and restored
`wifi@0` (which has real design-doc justification and was never actually
tested on its own, uncounfounded by the PDC change, until now). Syntax-
checked clean, `wifi@0` confirmed present in the compiled .dtb, PDC
confirmed back to `515`, synced to pmaports. Bumped kernel `pkgrel` 2->3
(real checksum needed this time, DTS genuinely changed).

Not yet built/flashed. If `&pcie0` probes cleanly with THIS combination
(original PDC + wifi@0 alone), that's real evidence wifi@0's mechanism
works as designed once freed from whatever the PDC content was doing, and
the WLAN-correct PDC table can be retried on its own, later, as a separate
experiment. If it still fails, wifi@0 itself needs harder scrutiny (the
fw_devlink/supply-phandle theory from the first attempt, or something in
how it's structured) despite the design doc's endorsement of the pattern.

## 2026-09-30: result -- wifi@0 ALONE also fails. Both changes independently break it.

Built r3 (original PDC content, wifi@0 restored), flashed, real dmesg: same
exact failure shape (`qcom-pcie` deferred -517 repeatedly, final attempt
"returned 517" after the same two new "supply vdda/vddpe-3v3 not found"
warnings). So now, across all tests:

| PDC content | wifi@0 | result |
|---|---|---|
| original (515) | absent | **works** (x2, incl. a from-scratch rebuild) |
| WLAN-correct (800) | present | fails |
| WLAN-correct (800) | absent | fails (x2, incl. a from-scratch rebuild, ruling out build variance) |
| original (515) | present | fails |

> **CORRECTION 2026-10-01 -- this table confounds DTS content with kernel-build
> identity.** Re-read with the kernel build as an extra column (keys measured
> with `scripts/check-kernel-module-key.py`, raw output in
> `notes/2026-10-01-module-key-root-cause/evidence.txt`):
>
> | PDC | wifi@0 | image set | kernel signing key matches rootfs modules? | result |
> |---|---|---|---|---|
> | original (515) | absent | pmos-v1 (the saved first-boot images) | **yes** | works |
> | WLAN-correct (800) | present | pmos-v2-wlan | no | fails |
> | WLAN-correct (800) | absent | pmos-v3-bisect, pmos-v4-rebuild-test | no (two different keys) | fails |
> | original (515) | present | pmos-v5-pdc-reverted (r3) | no | fails |
>
> Only the very first kernel build can load the rootfs' modules, so only it
> ever worked. The first row's "(x2, incl. a from-scratch rebuild)" is not
> supported by the image trail I could find in the repo and `_scratch/`: both
> "works" results correspond to the saved v1 images (first boot, then the
> restore re-flash); no freshly rebuilt kernel was ever booted against the v1
> rootfs with the original DTS. Prediction that follows (and is cheap to
> test): a fresh rebuild of the ORIGINAL devicetree, with the old config,
> fails exactly like the others.

Both edits, independently, on their own, with the other reverted, break
`&pcie0`'s probe the same way. They are structurally unrelated (one is a
child node under `&pcie0` itself; the other is a string property under a
completely different sibling node, `wcn6855-pmu`, with no phandle
relationship to `&pcie0`). This stopped being a "which of my two edits is
wrong" question -- something more fundamental is going on that affects
`&pcie0` probing whenever EITHER new element is added to the devicetree,
regardless of which one.

**Phone restored to the known-working state** (original `boot`/
`vendor_boot`/`dtbo` from `_scratch/pmos-v1/`, hashes `bc1de9de../
89e6dc8e../a5aab00d..`, re-verified by readback) before ending this
investigation thread -- do not leave the device on a known-broken
configuration between sessions.

**Handed off to a dedicated fresh investigation thread** -- see the chat
history / project notes for the full handoff prompt. The live `dts/dm1q/dm1q.dts`
file on disk right now still has r3's content (wifi@0 present, PDC
reverted to 515) for reference/continuation -- it does NOT match what's
currently flashed on the phone (which is the pre-wifi@0, pre-PDC-change
original). Check which state you're building from before the next test.

## ROOT CAUSE FOUND 2026-10-01: kernel module-signing key mismatch, not the devicetree

**Short version.** Every kernel build generates its own random module-signing
key and embeds the public half in the kernel. The pmOS rootfs on the phone --
and the `/lib/modules` inside it -- was built once, from the *first* kernel
build, so its modules are signed with *that* build's key. pmaports'
`config-mainline.aarch64` also forces kernel lockdown (integrity), and under
lockdown the kernel refuses any module whose signature it cannot verify. So
only the first build's boot images ever worked: every rebuilt kernel refused
*every* module, including the PCIe PHY driver (`phy_qcom_qmp_pcie` is a module
in this config), and `&pcie0` could never get its PHY. `wifi@0` and the PDC
table were bystanders -- each devicetree edit needed a rebuilt kernel, and
every rebuilt kernel failed. None of this needed the phone: it follows from
the saved logs, the saved image files and the 7.3-rc3 source.

### 1. What the failing boot says, in plain text

Failing = `notes/2026-10-01-module-key-root-cause/dmesg-r3-failing.txt` (kernel
`#4-samsung-dm1q-mainline`, built 2026-09-30 18:13 UTC = r3 = pmos-v5).
Working = `notes/2026-09-28-pmos-v1-hang/dmesg-ssh-live.txt` (`#2-...`, built
2026-09-28 00:57 UTC = the first build = pmos-v1). Raw excerpts and every
number below: `notes/2026-10-01-module-key-root-cause/evidence.txt`.

```
both boots  [    0.000000] Kernel is locked down from Kernel configuration; see man kernel_lockdown.7
working     [    0.245297] Loaded X.509 cert 'Build time autogenerated kernel key: 4826972c074f6611a00cf75373701a09d8912614'
failing     [    0.253307] Loaded X.509 cert 'Build time autogenerated kernel key: 1c905cbdd8a2f8470e83672fafb385958698a26f'
failing     [    5.620194] Lockdown: modprobe: unsigned module loading is restricted; see man kernel_lockdown.7
            (10 such lines, the last at 6.790699 from (udev-worker); the working boot has none)
```

Modules loaded by userspace: **36** in the working boot (`phy_qcom_qmp_pcie`,
`pwrseq_qcom_wcn`, `llcc_qcom`, `icc_osm_l3`, `icc_bwmon`, the display/camera/
video/GPU clock controllers, `qcom_pon`, ...), **0** in the failing boot (the
only two `init_module`-pattern initcall lines in it are the kernel-internal
`jump_label_init_module`). Other victims in the same log: `qcom-cpufreq-hw ...
Failed to find icc paths` (it needs the `icc_osm_l3` module).

### 2. The keys, all five image sets

Measured with `scripts/check-kernel-module-key.py` (reads the signing
certificate embedded in each `boot.img`'s kernel and the signer of
`phy-qcom-qmp-pcie.ko.zst` / `pwrseq-qcom-wcn.ko.zst` inside the rootfs image
`_scratch/pmos-v1/pmos-userdata.img`, partition 2; the pmbootstrap rootfs
chroot has the same modules):

| image set | embedded signing-cert serial | rootfs modules signed by | result on the phone |
|---|---|---|---|
| pmos-v1 (kernel #2, 2026-09-28) | 78D8215A...BE8E | 78D8215A...BE8E | **works** |
| pmos-v2-wlan | 2EE86D1C...B97D | 78D8215A...BE8E | fails |
| pmos-v3-bisect | 71857EA9...7DB6 | 78D8215A...BE8E | fails |
| pmos-v4-rebuild-test (r2) | 4B7CB35C...D2D2 | 78D8215A...BE8E | fails |
| pmos-v5-pdc-reverted (r3, kernel #4) | 2275E516...5DBC | 78D8215A...BE8E | fails |

(Full serials in `evidence.txt` section 7. The `SKID` of the v1 and v5 certs
equals the hex in the `Loaded X.509 cert` lines above, tying the image files to
the two logs.) Caution: pmbootstrap's `packages/` keeps only the *latest*
r1/r2/r3 APKs, and `r1.apk` there was overwritten by a later `pkgrel=1` build
(it is the bisect build, key 71857EA9...); the module set that matches pmos-v1
now exists only in `pmos-userdata.img` and the pmbootstrap rootfs chroot. Do not
delete either.

### 3. Why it looked like a PCIe / devicetree bug

- `returned -517` vs `returned 517`. `really_probe()` (drivers/base/dd.c
  668-670, 714-721) returns **-517 before the driver is called** while a
  fw_devlink supplier is not ready, and returns **+517 when the driver's own
  `probe()` ran and itself returned -EPROBE_DEFER**. The ten `-517` lines are
  "still waiting for suppliers"; the final `517` is a real probe attempt that
  deferred itself. (The earlier docs read the sign as noise.)
- The attempt happens at 10.7 s because that is when the 10 s deferred-probe
  timeout fires (`deferred_probe_timeout_work_func()`, dd.c ~305): the log shows
  `arm-smmu 3da0000.iommu: deferred probe timeout, ignoring dependency` at
  10.726849, and `qcom-pcie`'s first real `probe()` runs 10.7253 -> 10.7748 (two
  dummy-regulator warnings, then `returned 517 after 45807 usecs`).
- What defers inside: dm1q's DT uses the legacy host-level PHY binding (the
  root port `pcie@0` has no `phys`), so `qcom_pcie_parse_ports()` returns
  -ENODEV and probe falls back to `qcom_pcie_parse_legacy_binding()` ->
  `devm_phy_optional_get(dev, "pciephy")` (pcie-qcom.c:2108). The QMP PCIe PHY
  provider is the `phy_qcom_qmp_pcie` module, which never loaded, so it returns
  -EPROBE_DEFER.
- Working boot, same code path: udev loads `phy_qcom_qmp_pcie` at ~7.07 s,
  `probe of 1c06000.phy ... returned 0` at 7.080932, `qcom-pcie` probes at
  7.12 s, waits ~1 s for a link, logs `Device not found`, and `returned 0
  after 1131480 usecs` at 8.253338.

### 4. Claims from the earlier sections that are retired

- "`vdda` / `vddpe-3v3` dummy-regulator warnings are new" -- no: the working
  boot prints both (lines 5116/5127). Every `qcom-pcie` probe attempt does.
- "`&pcie0` is missing a *required* `vdda-supply`, which may make probing
  marginal" -- not required by 7.3-rc3's `qcom,pcie-sm8550.yaml`
  (`power-domains`, `resets`, `reset-names` only); no upstream SM8550 board
  sets it on `&pcie0`.
- DTB size / property count / device-link effects of `wifi@0`'s phandles --
  nothing in either log needs them, and the DTB was never the variable. (No
  claim is made here about fw_devlink internals; they simply are not needed to
  explain any observation.)
- The PDC table: inert, as the earlier sections already suspected -- it never
  caused anything.

### 5. The fix, and what it was checked against

`pmaports/.../config-dm1q.fragment` now ends with
`CONFIG_LOCK_DOWN_KERNEL_FORCE_NONE=y` / `# CONFIG_LOCK_DOWN_KERNEL_FORCE_INTEGRITY
is not set`. Checked by replaying the APKBUILD's `merge_config.sh` +
`olddefconfig` against the real 7.3-rc3 tree (host gcc instead of clang; only
the lockdown/module-sig symbols matter): the old fragment yields
`FORCE_INTEGRITY=y` (reproducing the "locked down from Kernel configuration"
line), the new one `FORCE_NONE=y`, `MODULE_SIG=y`, `MODULE_SIG_FORCE` unset.
`MODULE_SIG` itself cannot be switched off while `SECURITY_LOCKDOWN_LSM=y`
(it `select`s it).

Why that is enough: in 7.3-rc3 `module_sig_check()` (kernel/module/signing.c)
maps "unsigned / unsupported crypto / key not in the keyring" to
`security_locked_down(LOCKDOWN_MODULE_SIGNATURE)` unless `sig_enforce` is on
(it is not: `MODULE_SIG_FORCE` is unset). With lockdown off that returns 0, so
a module signed by an unknown key loads, tainted (`module verification failed:
signature and/or required key missing - tainting kernel`). The `lockdown=`
command-line parameter can only *raise* the level, so the config is the only
place to fix it.

Alternatives considered:
- *Pin the signing key* (fixed key in the APKBUILD's `prepare()`): keeps
  lockdown and signatures, but puts a private key in the repo/package and has
  the same ABI exposure afterwards.
- *Refresh the rootfs' modules after every kernel build*: the only fully
  ABI-safe route and still the right thing to do after a material **config**
  change (this kernel has `# CONFIG_MODVERSIONS is not set`, so the signature
  was the only thing that ever guarded against loading modules built from a
  different config). Costs a step per cycle, and a mismatched kernel cannot do
  it for itself except over the USB-gadget network.
- *FORCE_NONE* (chosen): one line, no workflow change, and integrity lockdown
  also blocks `/dev/mem`, PCI config/BAR access through sysfs and debugfs
  writes -- all useful during bring-up. A development-port policy; revisit
  before any real release.

### 6. The second bug the first one was hiding: the `wifi@0` wiring itself

Reading the 7.3-rc3 sources (not available locally when Finding 2 was written)
shows the version of `wifi@0` in the r3 DTS could not have worked even with
modules loading, and it would have failed *in the same-looking way*
(`qcom-pcie ... returned 517`, forever):

1. `qcom_pcie_host_init()` calls `pci_pwrctrl_create_devices()` and
   `pci_pwrctrl_power_on_devices()` (pcie-qcom.c 1402/1408). A node with a
   `pci*` compatible and any `*-supply` gets a platform device bound by
   `pci-pwrctrl-pwrseq`; if that driver is not bound yet, the host probe
   returns -EPROBE_DEFER (pwrctrl/core.c:276).
2. `pci-pwrctrl-pwrseq` needs `vddaon-supply` (pci-pwrctrl-pwrseq.c:43) and calls
   `devm_pwrseq_get()` (:91). The provider only accepts a consumer whose
   `vddaon-supply` phandle resolves to **`<pmu>/regulators/<ldoN>`**
   (`pwrseq_qcom_wcn_match_regulator()`, pwrseq-qcom-wcn.c:404-434:
   `reg_node->parent->parent == ctx->of_node`); otherwise `PWRSEQ_NO_MATCH`,
   and `pwrseq_get()` returns -EPROBE_DEFER (pwrseq/core.c:689-691) -- forever.
3. The r3 DTS pointed `wifi@0`'s supplies at PM8550 board rails
   (`rsc@17a00000/regulators-N/smpsX`), had no `regulators { }` node under
   `wcn6855-pmu` at all (the binding, `qcom,qca6390-pmu.yaml`, marks it
   required), used compatible `pci17cb,1101` with the QCA6390 supply names, and
   placed the node under the host bridge instead of the root port.

`scripts/check-wlan-dtb.py` encodes the invariant and checks a compiled DTB:
r3's DTB (extracted from the r3 APK) -> **FAIL**; the new DTB -> **PASS** (output
in `evidence.txt` section 8). The earlier "9-supply mapping against the
downstream voltage configs" was not wasted: those rails are the PMU's *inputs*,
which is exactly what the `wcn6855-pmu` node's ten `vdd*-supply` properties
already describe. The ath11k binding models the chip's *internal* LDO outputs as
the consumer supplies, so `wifi@0` must reference those.

New shape (pattern copied from `sm8450-hdk.dts`, the same-chip reference, and
checked against `qcom,ath11k-pci.yaml`): `wcn6855-pmu { ...; regulators { ldo0
... ldo9 } }`, and `&pcie0_port0 { wifi@0 { compatible = "pci17cb,1103"; reg =
<0x10000 0 0 0 0>; <9 supplies -> PMU ldos>; }; }`.

PCI ID note: Finding 2 chose `pci17cb,1101` by reasoning that QCA6490 "is the
same silicon generation as QCA6390". docs/05 had already recorded the *live
device* enumerating the QCA6490 as 17cb:**1103**, which is `WCN6855_DEVICE_ID`
in ath11k, and the same-chip reference uses 1103. `pci-pwrctrl-pwrseq` accepts
1101/1103/1107 with the same target, so 1101 was wrong rather than causal; it is
1103 now (with the 1103 supply list: `vddrfa1p8`, not `vddrfa1p7`).

### 7. What changed in the repo on 2026-10-01

- `pmaports/device/testing/linux-samsung-dm1q-mainline/config-dm1q.fragment`:
  lockdown forced off (section 5).
- `dts/dm1q/dm1q.dts` + `.../sm8550-samsung-dm1q.dts` (kept identical): `wifi@0`
  moved under `&pcie0_port0` and rewired (section 6); `regulators { }` added
  to `wcn6855-pmu`; the WLAN-specific `qcom,wlan-pdc-init` table (Finding 1)
  restored, with its history in the comment. Compiles with the kernel tree's own
  `dtc`; dtc also enforced "properties must precede subnodes", which the first
  edit got wrong.
- `.../APKBUILD`: `pkgrel` 3 -> 4 (kernel will report `#5-samsung-dm1q-mainline`),
  the two changed `sha512sums` recomputed.
- New: `scripts/check-kernel-module-key.py` (does this kernel trust the rootfs'
  modules?), `scripts/check-wlan-dtb.py` (pwrseq wiring invariant),
  `notes/2026-10-01-module-key-root-cause/` (the failing r3 `dmesg`/`journalctl -k`
  -- the files section "2026-09-28: real hardware result" cites were never
  saved under that name -- plus `evidence.txt`).
- Not touched: the phone (still on the restored pmos-v1 set), `kernel/config/
  dm1q.fragment` (the old arm64-defconfig-based bring-up kernel; lockdown is not
  enabled there).

### 8. Test plan for the next boots (A ran 2026-10-02 -- see section 10; B pending -- see section 11)

Build (needs the user's sudo): `pmbootstrap checksum linux-samsung-dm1q-mainline
&& pmbootstrap build linux-samsung-dm1q-mainline` -> `...-7.3_rc3-r4.apk`.
Then assemble two image sets from the same r4 kernel with
`scripts/make-boot-images.sh` (same `--initramfs` as pmos-v1..v5), flash only
`boot` + `vendor_boot` with the proven push / hash-compare / `dd conv=fsync` /
readback procedure:

- **A -- control: r4 kernel + the ORIGINAL v1 DTB** (extract with `unpack_bootimg`
  from `_scratch/pmos-v1/vendor_boot.img`). Isolates the module fix. Expected:
  no `Lockdown:` lines; a one-time `module verification failed ... tainting
  kernel`; ~36 modules load including `phy_qcom_qmp_pcie` at ~7 s;
  `qcom-pcie ... returned 0 after ~1.1 s`; `Device not found` (no `wifi@0`, so
  the chip is still unpowered) -- i.e. v1's behaviour from a rebuilt kernel. If
  this does NOT happen, the root-cause theory is wrong; stop and look at
  `/sys/kernel/debug/devices_deferred` before changing anything else.
- **B -- WLAN: r4 kernel + r4 DTB** (`scripts/check-wlan-dtb.py` must say PASS
  first). Look for, in order: `pwrseq_qcom_wcn` probe 0; `pci-pwrctrl-pwrseq`
  module loading and binding to the `wifi@0` platform device; GPIO80
  (`wlan-enable`) asserted; `qcom-pcie` link up instead of `Device not found`;
  `pci 0000:01:00.0: [17cb:1103]`; then `ath11k_pci` probing. Failure signatures:
  `qcom-pcie` deferring with the pwrctrl device unbound -> wiring/match problem
  (should not happen, checker passes); pwrctrl bound but `Device not found` ->
  chip powered but not enumerating (PERST#/CLKREQ#/ref-clock/`xo-clk` timing,
  rail voltages); `ath11k_pci` probing but failing on firmware/board data -> a
  new, separate problem class (below), not PCIe.

### 9. Still open after this

- ath11k firmware + board data for the S23's QCA6490. The pmos-v1 rootfs image
  has NO ath11k firmware at all (`/usr/lib/firmware` holds only
  `regulatory.db`; the ath11k/cfg80211/qrtr/mhi *modules* are all present), so
  once the link comes up `ath11k_pci` is expected to stop at a firmware load
  error until `linux-firmware-ath11k` (and, for BT later, the qca firmware
  package) is installed -- `apk add` on the device, or via
  `device-samsung-dm1q`'s `depends`. Beyond that: whether linux-firmware's
  `ath11k/WCN6855/hw2.x` set (with a matching `board-2.bin` entry or a
  `qcom,calibration-variant`) fits Samsung's board. Check the live rootfs
  before assuming; the image may differ from the phone.
- Bluetooth shares the same PMU; nothing consumes its half yet.
- Optional hardening: build the PCIe PHY / pwrseq / pwrctrl drivers in
  (`=y`) so `&pcie0` stops depending on userspace module loading at ~7 s.
- Refresh the rootfs' modules from the r4 APK once the config is stable (the
  `kernel/` + rootfs mismatch is tolerated now, not eliminated).

### 10. Test A result (r4 kernel + the ORIGINAL DTB), run 2026-10-02 -- the module fix is confirmed on hardware

Logs: `notes/2026-10-02-r4-control-boot/{dmesg,journal-kernel}-r4-control.txt`;
`scripts/compare-dmesg.py` against the working v1 log:
`notes/2026-10-02-r4-control-boot/compare-vs-v1.txt`. The booted kernel is
`#5-samsung-dm1q-mainline` (built 2026-10-02 07:12 UTC); its signing cert (SKID
`876c0259...b824`) is the one embedded in the `pmos-v6-r4-control` and
`pmos-v7-r4-wlan` boot.img kernels, so the images and the log line up. Nothing
in the log has a `wifi@0`/pwrctrl line and `pci_pwrctrl_pwrseq` was never
loaded, so this was the control (v6, original DTB), as intended.

- No `Kernel is locked down` line, 0 `Lockdown:` refusals (r3: 10).
- Modules loaded: **36**, the same count as the working v1 boot (r3: 0), including
  `phy_qcom_qmp_pcie` (7.602 s) and `pwrseq_qcom_wcn` (7.687 s). The first one logs
  the predicted `fuse: module verification failed: signature and/or required key
  missing - tainting kernel` (6.149 s); taint flags are `G S W E` (E = unsigned
  module), harmless.
- PCIe, same code path as v1: `probe of 1c06000.phy ... returned 0` 7.638,
  `qcom-pcie` probe 7.65 s (the two dummy-regulator warnings again), `probe of
  soc@0:wcn6855-pmu with driver pwrseq-qcom_wcn returned 0` 7.709, `Device not
  found` 8.767 (no `wifi@0`, so nothing powers the chip), `pci 0000:00:00.0:
  [17cb:0113] ... PCIe Root Port`, `qcom-pcie ... returned 0 after 1121685
  usecs` 8.772 (v1: 1131480).
- Against v1 only five warning/error-ish lines differ: the kernel command line
  (the bootloader passes different charger/boot-mode parameters: `lpcharge=0`
  here, `1` in v1, plus a few extra), the taint/verification lines above, and a
  benign `systemd-journald ... Failed to read journal file ... for rotation`. The
  deferred-probe-pending list (audio codec / lpass pinctrl) is identical to v1;
  `qcom-cpufreq-hw`, which r3 left stuck on `Failed to find icc paths`, is fine.

So: with a rebuilt kernel (new key, `FORCE_NONE`) the old rootfs modules load and
the system behaves exactly like v1. The "PDC / wifi@0 breaks &pcie0" theory is
closed. This does NOT yet say anything about WLAN itself -- test B has not run.

### 11. Readiness review for test B (r4 kernel + r4 DTB = `_scratch/pmos-v7-r4-wlan`), 2026-10-03

Checked statically, nothing flashed:
- v7's `boot.img` carries the same kernel/key as the booted r4 kernel; v7's
  `vendor_boot` DTB (sha256 `a91a6b37...`) is byte-identical to the DTB in the r4
  APK and passes `scripts/check-wlan-dtb.py` (`/soc@0/pcie@1c00000/pcie@0/wifi@0`,
  all nine supplies -> PMU `regulators/ldoN`); v6's DTB is the original (no
  consumer).
- 7.3-rc3's WCN6855 "wlan" target (pwrseq-qcom-wcn.c): enable the PMU input
  regulators -> optional clock -> `xo-clk-assert` (our `xo-clk-gpios`, GPIO 204,
  is consumed by the wcn6855 variant, so it is not a dead property) -> `wlan-enable`
  GPIO 80 -> post-enable `xo-clk-deassert` + power-up delay. `qcom_pcie_host_init()`
  runs this between PERST# assert and deassert, so the chip is powered before link
  training.
- Firmware: the pmos-v1 rootfs image has none (`/usr/lib/firmware` = only
  `regulatory.db`); the kernel can load zstd-compressed firmware
  (`FW_LOADER_COMPRESS_ZSTD=y`, `_XZ=y`). Alpine edge's `linux-firmware-ath11k-20260810-r0`
  (23.6 MB, no dependencies) provides `ath11k/WCN6855/hw2.0/{amss,m3,board-2,regdb}.bin.zst`
  with `hw2.1` as symlinks to it; `linux-firmware-qca-20260810-r0` is the Bluetooth
  half. `networkmanager-wifi`, `wpa_supplicant` 2.11, `libnl3` and `wireless-regdb`
  are already in the rootfs, and `regulatory.db` is present. Downloaded to
  `_scratch/phone-pkgs/` (with `SHA256SUMS`, plus `iw-6.17-r0` for diagnostics);
  the pmOS repos in `/etc/apk/repositories` are the same Alpine edge ones.
- Board data is the real unknown. `board-2.bin` has 157 entries (120 unique for
  `device=1103`, list in `notes/2026-10-02-r4-control-boot/ath11k-board-names-wcn6855.txt`)
  and **none for Samsung** (`subsystem-vendor=144d`); it does have generic
  Qualcomm-reference entries (`17cb:0108`, chip-id 2/18, board-id 255). ath11k
  builds the lookup name from the chip's own PCI subsystem IDs and its QMI chip /
  board id, so whether the S23's QCA6490 matches one of them is only knowable once
  it enumerates (ath11k prints the name it searched for). If not, the S23's own
  board data (downstream `bdwlan` from the vendor partition) has to be packaged
  into a `board-2.bin` -- a separate step after PCIe works.
- Least-verified input to B: the PMU's ten *input* rail mappings, which the DTS
  comments record as inferred (downstream voltage configs plus the HDK pattern),
  not confirmed on this board. If the chip enumerates but misbehaves, look there first.

What to run on the phone (the PC is either on the phone's USB network or on the
internet, not both, so nothing needs the phone to reach the internet):

> **CORRECTION 2026-10-03 -- step 1 below broke the boot; do not run it as written.**
> Installing anything into `/lib/firmware` fires `postmarketos-mkinitfs`'s apk trigger,
> which regenerates `/boot/initramfs-extra` with the usr-merge symlinks and stops stage 2
> from ever switching root (section 12). The firmware itself installs fine. If you ever
> need an apk change on the phone, follow it with `scripts/fix-phone-initramfs-extra.sh`
> from recovery (or re-apply the fix on-device) BEFORE the next boot.

1. PC on the USB network (phone booted, 172.16.42.1): `scp _scratch/phone-pkgs/*.apk
   user@172.16.42.1:/tmp/`, then `ssh -t user@172.16.42.1 'sudo apk add
   /tmp/linux-firmware-ath11k-20260810-r0.apk /tmp/iw-6.17-r0.apk'` (add
   `--allow-untrusted` only if apk rejects the signature).
2. Reboot to recovery; flash only `boot` and `vendor_boot` with
   `scripts/flash-recovery.sh` from `_scratch/pmos-v7-r4-wlan/`. (Rollback: the same
   two partitions from `_scratch/pmos-v6-r4-control/`.)
3. After boot, on the USB network: `scp scripts/phone-wlan-probe.sh
   user@172.16.42.1:/tmp/`, `ssh -t user@172.16.42.1 'sudo sh /tmp/phone-wlan-probe.sh'
   | tr -d '\r' > notes/<dir>/phone-probe-v7.txt`, plus dmesg and `journalctl -k`
   as before; compare with `scripts/compare-dmesg.py`.

### 12. Test B, attempt 1 (2026-10-03): v7 never reached userspace -- NOT a WLAN failure; the phone's own /boot/initramfs-extra had been regenerated

After flashing v7 (`boot` + `vendor_boot`) the phone did not get to userspace. Log pulled
from recovery with `adb exec-out "dd if=/dev/block/by-name/dtbo bs=1M skip=1 count=4"`
(the stage-1 `dtbo-logger.sh` flushes dmesg + `/pmOS_init.log` there; 3.8 MB because of
the loop below): `notes/2026-10-03-v7-wlan-boot/dtbo-log-v7.{raw,txt}`.

What the log says:
- The r4 kernel (`#5`, the v7 DTB) booted normally into pmOS stage 1: USB gadget up,
  `Mount subpartitions of /dev/sda41`, `Mount boot partition (/dev/loop0p1)`. The two
  working boots (v1, r4 control) continue with `Extract /boot/initramfs-extra` ->
  `49636 blocks` -> stage 2 -> `Switching root`.
- This boot instead printed `cpio: can't remove old file lib: Is a directory` and no
  block count, then stage 2 ran without its tools: `ERROR: udev not found!`,
  `parted: not found`, `e2fsck: not found`, and then tens of thousands of lines of
  `[pmOS-rd]: couldn't open /dev/input/` until the logger's 4 MiB cap. Same signature as
  2026-09-28 (docs/06): an initramfs-extra with top-level usr-merge symlinks extracted
  onto a stage-1 ramdisk whose `/lib` is a real directory.
- Side effect, not a result: with no userspace there were no modules, so `qcom-pcie` ended
  in `returned 517` after the 10 s deferred-probe timeout (the r3 pattern). `wifi@0` was
  never reached (`qcom_pcie_host_init()` did not run), so this says nothing about WLAN.

Cause, verified read-only from recovery (nested boot partition pulled and compared with the
v1 image; rootfs mounted `ro,noload`):
- The phone's `/boot/initramfs-extra` is 12,228,076 bytes (v1, fixed: 11,828,467), mtime
  1970-01-06 (the phone's clock), new inode -- rewritten on the phone. Its cpio has exactly
  three entries the fixed one lacks: `bin -> usr/bin`, `lib -> usr/lib`, `sbin -> usr/bin`.
- The phone's `/var/log/apk.log` shows `Executing postmarketos-mkinitfs-2.11.1-r0.trigger`
  -> `Generating initramfs` -> `Installing: /boot/initramfs`, `/boot/initramfs-extra`,
  `/boot/sm8550-samsung-dm1q.dtb`. That package's apk trigger watches `/lib/firmware/*`,
  `/usr/lib/udev`, `/usr/share/kernel/*`, `/usr/share/deviceinfo`, `/usr/share/mkinitfs/*`,
  `/usr/share/plymouth`, `/usr/lib/systemd/boot` (the only entry in the rootfs'
  `/lib/apk/db/triggers` that lists `/lib/firmware/*`).
  Installing `linux-firmware-ath11k` writes into `/lib/firmware`, so it fired.
- **That `sudo apk add linux-firmware-ath11k ...` was my instruction (docs/07 section 11,
  step 1), and the breakage is on me: I checked the package, its size and its dependencies,
  but not which apk triggers it would fire.**
- Nothing else changed: the phone's package set differs from the v1 image by exactly
  `iw-6.17-r0` and `linux-firmware-ath11k-20260810-r0`
  (`notes/2026-10-03-v7-wlan-boot/package-diff-v1-vs-phone.txt`); the firmware is in place
  (`/usr/lib/firmware/ath11k/WCN6855/hw2.1/`: `amss`, `m3`, `board-2`, `regdb`, plus an
  `nfa765` dir). The `/boot/initramfs` (stage-1 copy) is byte-identical to before and unused.
  `v7`'s boot.img / vendor_boot.img are not at fault and are still the right set.

Repair: `scripts/fix-phone-initramfs-extra.sh` re-applies `scripts/fix-initramfs-extra.sh` to
the file inside the phone's nested boot partition from recovery (dry run by default: read-only
backup of the whole partition, build + check the fixed file; with `--yes` it does `e2fsck -fn`,
a loop mount limited to that partition's byte range, copy-to-temp-name, sha256 check, atomic
rename, and an independent read-only re-verify; `--file <saved original>` rolls back). The dry
run on 2026-10-03 produced a 286-entry fixed file (11,828,439 bytes), identical in entry names to
the v1-fixed one, and a backup whose sha256 matches the earlier pull. Local `e2fsck -fn` on that
backup reports only the cosmetic `Free blocks count wrong` an unclean shutdown leaves behind.

Prevention: any apk operation on the phone that touches the trigger paths above regenerates
`/boot/initramfs-extra` and breaks the next boot until the fix is re-applied -- see the rule in
docs/06 (2026-10-03). A durable alternative would be teaching stage 1 to extract
initramfs-extra into a scratch dir, drop the top-level symlinks, and merge it (a
`make-boot-images.sh` change plus an `init_boot` flash); not done.

### 13. Test B, attempt 2 (2026-10-04): userspace reached, the WLAN chip enumerates -- then never boots; the PMU rails sit at their DT *minimum*

Setup: the initramfs-extra repair from section 12 was applied from recovery
(`scripts/fix-phone-initramfs-extra.sh --yes`; verified three ways: sha256 of the file read back
on the phone == the fixed file, a re-pulled partition passes `e2fsck -fn` with rc 0, and only
2900 blocks / 11.3 MiB differ from the pre-fix backup, all of them that file's data and
metadata). The phone then booted the v7 images (r4 kernel + the rewired `wifi@0`) into pmOS and
the user ran `scripts/phone-wlan-probe.sh` (first version). Saved verbatim:
`notes/2026-10-03-v7-wlan-boot/phone-probe-v7.txt`.

What now works on hardware (every line from the probe):
1. Userspace is reached; lockdown `[none]`; taint 8708 = unsigned module (E, 8192) + WARN (512)
   + CPU-out-of-spec (S, 4), all expected.
2. `soc@0:wcn6855-pmu` binds `pwrseq-qcom_wcn` (7.014 s, probe 0).
3. `pci_pwrctrl_pwrseq` loads (7.153 s) and `probe of 1c00000.pcie:pcie@0:wifi@0 with driver
   pci-pwrctrl-pwrseq returned 0` (7.159 s). The section 6 rework (supplies = the PMU's own
   outputs, node under `pcie0_port0`) is confirmed: before the pwrctrl device bound, `qcom-pcie`
   deferred five times (`returned 517`, 6.99-7.13 s), exactly as designed, then proceeded.
4. `qcom-pcie: PCIe Gen.3 x1 link up` (7.547 s); `pci 0000:01:00.0: [17cb:1103] type 00 class
   0x028000 PCIe Endpoint`; BAR0 2 MiB; `probe ... returned 0 after 418489 usecs`. **"Device not
   found" is gone**: pwrseq powers the chip and the link trains. sysfs: `17cb:1103`, subsystem
   `17cb:0108` -- the generic Qualcomm-reference board-data key (section 11), good for later.
5. `ath11k_pci`: `wcn6855 hw2.1` (read over BAR0 at 7.640 s), 32 MSI vectors.

What fails: `mhi mhi0: Requested to power ON` / `Power on setup success` (7.804 s), nothing for
21.9 s, then `mhi mhi0: Device link is not accessible`, `MHI did not enter READY state` (29.664 s),
`ath11k_pci ... failed to power up mhi: -110` ... `probe with driver ath11k_pci failed with error
-110`. In 7.3-rc3 "Device link is not accessible" is `MHI_PM_IN_FATAL_STATE(pm_state)` checked at
the READY transition (drivers/bus/mhi/host/pm.c:181): the MHI core had already given up on the
device. The bus itself was healthy at enumeration and when ath11k read SOC_HW_VERSION; what never
happens is the chip's own boot.

Strongest lead (found in the same probe, section "regulators"): **every rail feeding the PMU sits at
the minimum of its DT constraint, because nothing ever requests a voltage.** `pwrseq-qcom-wcn.c`
only calls `devm_regulator_bulk_get()` and `regulator_bulk_enable()` (no `regulator_set_voltage`
anywhere), and the regulator core initialises an RPMh rail whose voltage is unknown to its
*minimum* -- the control boot's dmesg shows it at 0.116 s: `vreg_s2g_0p98: Setting
500000-1036000uV`, `vreg_s4e_0p952: Setting 904000-984000uV`, `vreg_s4g_1p352: Setting
1200000-1352000uV`, `vreg_s6g_1p904: Setting 1800000-2000000uV`. Upstream boards get away with it
because their DT minimums happen to equal what their chip needs (sm8550-qrd, WCN7850: S2G min
800 mV, S4G 1.2 V, S6G 1.8 V -- and WCN7850's rails are 1.2 / 1.8 V, where the WCN6855's are
1.3 / 1.9 V); dm1q's constraints were copied as the *wide hardware ranges* from the downstream
DT, where the CNSS driver requests each rail's voltage itself:

| PMU input rail (consumers) | applied now (regulator_summary) | DT min / max | downstream CNSS request |
|---|---|---|---|
| `vreg_s2g_0p98` (vddaon, vddpmucx, vddrfa0p95) | **500 mV** | 500 / 1036 | **1.012 V** (`vdd-wlan-aon-config` 0xf7120) |
| `vreg_s4e_0p952` (vddpmumx) | 904 mV | 904 / 984 | 0.966 V (`vdd-wlan-dig-config` 0xebd70) |
| `vreg_s4g_1p352` (vddpmu, vddrfa1p3, vddpcie1p3) | 1200 mV | 1200 / 1352 | 1.35 V (`vdd-wlan-rfa2-config` 0x149970) |
| `vreg_s6g_1p904` (vddrfa1p9, vddpcie1p9) | 1800 mV | 1800 / 2000 | 1.9 V (`vdd-wlan-rfa1-config` 0x1cfde0) |
| `vreg_l15b_1p8` (vddio) | 1800 mV | 1800 / 1800 | 1.8 V (`vdd-wlan-io-config` 0x1b7740) |

(Each PMU consumer line reads `0mV 0mV`, i.e. no voltage request.) The always-on island at 0.5 V
instead of 1.012 V, with the others 5-8 % low, fits "PCIe config space answers, boot ROM never
reaches READY" -- but it is a suspect, not a proof: this is only the AP's vote as the kernel sees
it, and RPMh takes the maximum over all masters, so other subsystems may be holding some rails
higher. Nothing else in the data contradicts it.

Fix prepared (not yet flashed): `dts/dm1q/dm1q.dts` (+ pmaports copy, APKBUILD sha512 updated)
raises the minimum of those four rails to the downstream values (S2G 1012000, S4E 966000, S4G
1350000, S6G 1900000; maxima untouched; the only other users are PM8550 L1-L3 as S4E's children).
The compiled DTB shows the new constraints; `check-wlan-dtb.py` still PASSes. Image set
`_scratch/pmos-v8-r4-rails/` (`boot` + `vendor_boot`): same r4 kernel (the gzip'd Image bytes are
identical to v7's), same vendor cmdline (v7's, without `loop.max_part=7`), same vendor ramdisk and
bootconfig, only the DTB differs (sha256 `aa25ed33...`; v7 was `a91a6b37...`).

Probe gaps found while reading it, fixed in the scripts: the GPIO grep matched nothing (consumer
labels differ from the patterns -- the probe now dumps every labelled line plus the chip header);
there were no live PCIe config reads (added: root port + endpoint, link speed/width, the root
port's PCIe-capability bytes); SMMU/AER/pcieport lines were not grepped (added). New:
`scripts/phone-ath11k-reload.sh` (reload `ath11k_pci` with MHI/ath11k debug on and sample the link
every 2 s -- tells "link dropped" from "chip alive, boot ROM stuck"), wired into
`scripts/collect-phone-state.sh --reload`.

Next: flash v8 from recovery, boot, run `scripts/collect-phone-state.sh v8-wlan-rails` (add
`--reload` if ath11k still fails). If `ath11k` gets past MHI, the next things to see are the
firmware / board-data lookups (section 11) and a `wlan0`.

**CORRECTION (2026-10-09, see section 14):** the reading above -- PCIe config space answers but the
boot ROM never reaches READY, with the rails at their DT minimum as the likely cause -- is not
supported. `Device link is not accessible` is one outcome of a 20 s timeout race (14.3), which the
chip's state does not decide; the logs are, if anything, consistent with the boot ROM having accepted
the image while the host never received the chip's interrupts (14.3-14.5). The rail change is still
right (it matches the downstream CNSS requests) but is not shown to matter.

### 14. v8 and the `--fresh` experiment (2026-10-05 .. 2026-10-09): the instrument was broken twice -- and the logs, read against the 7.3-rc3 source and upstream, point at the HOST (the PCIe BDF-to-SID table), not at the chip

Where this stands:

1. The register experiment of 2026-10-07 produced **no register data**: two bugs in my own sampler (14.2). The question it was built for -- what does the chip's boot ROM report while ath11k waits -- is still open.
2. Its logs nevertheless say two things the earlier sections missed (14.3): the four different failure messages collected so far (v7, v8, v8 reload, v8 fresh) are one 20 s timeout seen through a race, not four observations of the chip; and during the fresh attempt none of the endpoint's 11 MSI vectors ever counted an interrupt while the root port's own vector did.
3. 7.3-rc3's `qcom_pcie_config_sid_1_9_0()` mis-parses the 5-cell `iommu-map` of `sm8550.dtsi` and leaves our endpoint (01:00.0) out of the controller's BDF-to-SID table. That is a **known upstream regression, already fixed** (14.4), and it matches our symptom (14.5) -- but it is **not yet proven on this hardware**.
4. Prepared, not flashed: **v9** (the same r4 kernel, DT-only workaround: the legacy 4-cell `iommu-map`) and **r5** (the kernel with the upstream patch carried in pmaports). The test and what it must show: 14.8.
5. Retired or downgraded by this: "the boot ROM never completes the BHI transfer" (my reading of v8 on 2026-10-05) and the rails as the explanation of the stall (14.6). The rail change stays: it matches downstream.

#### 14.1 What v8 showed (2026-10-05, `notes/2026-10-05-v8-wlan-rails/`)

The raised rail minimums took effect (S2G 1012, S4E 968, S4G 1352, S6G 1904 mV in `regulator_summary`); link, enumeration and the `wcn6855 hw2.1` read are as in v7. The boot-time attempt now ended differently: `mhi mhi0: Power on setup success` 8.902 s, `MHI did not load image over BHI, ret: -5` 29.667 s, `failed to power up mhi: -110` 0.1 ms later. A second attempt without re-powering (module reload) ended like v7. At the time I read the new message as "the host now reaches the BHI image download, the boot ROM never completes it". That was an inference from the error text; 14.3 shows it was not established.

#### 14.2 The `--fresh` experiment (2026-10-07, `notes/2026-10-07-v8-fresh/`): why it produced no register data

`bash scripts/collect-phone-state.sh v8-fresh --fresh`: blacklist `ath11k_pci`, reboot, then on the untouched chip the probe, the register sampler `idle` (10 s) and `load` (a clean ath11k attempt, 36 s), then the usual dumps. Both halves came back empty, for two different reasons, both mine:

- **idle**: every sample says `cmd=0000 (memory space off: BAR0 not decoded, not reading)`. The refusal is right (reading an undecoded BAR is how you get an external abort), but nothing ever enabled the endpoint's memory space: with no driver bound the PCI core leaves a freshly enumerated endpoint's command register at 0. A flaw in the sampler.
- **load**: memory space and bus master are on from +1 s (`cmd=0604` is the register's two raw bytes, low byte first, = 0x0406: memory space, bus master, INTx-disable; `0200` = 0x0002, memory space only, after the failure), yet every MHI/BHI register prints `????????`. The sampler read registers with `dd if=/dev/mem`, and **on arm64 `read()` on `/dev/mem` only works for ranges inside mapped system RAM**: `read_mem()` returns -EFAULT unless `valid_phys_addr_range()` accepts the range (`drivers/char/mem.c:94`; `arch/arm64/mm/mmap.c:43`: `memblock_is_region_memory() && memblock_is_map_memory()`). MMIO has to be `mmap()`ed. The header comment of that script ("STRICT_DEVMEM only blocks RAM") was wrong and I never read one known register before trusting the instrument. Checked and ruled out: `CONFIG_IO_STRICT_DEVMEM` is not set (a driver-claimed BAR is not blocked), and the reads kept failing at +21..+35 s when ath11k had already released BAR0 with memory space still on.

Fixed (all on the PC, unflashed, tested):
- `scripts/mmio-read.c` -> `scripts/bin/mmio-read-aarch64` (2224 bytes, static, no libc, raw syscalls, `mmap` + 32-bit volatile loads, read-only; `scripts/build-mmio-read.sh`, clang + lld). `scripts/test-mmio-read.sh`: the same source built for the PC and tested against files (byte order, offsets, every error path), plus checks that the aarch64 binary is a static ELF using the aarch64 syscall numbers (it cannot be run here: no qemu-user).
- `scripts/phone-mhi-regdump.sh` v2: self-tests the helper on a temp file and **refuses to run if it cannot read**; in idle mode enables the memory space through sysfs `enable` (and restores it); prints a line whenever any register or interrupt counter changes (as fast as the shell can for the first 6 s, at least once a second afterwards); decodes EXECENV (`enum mhi_ee_type`: 0 PBL, 1 SBL, 2 AMSS, 3 RDDM, 4 WFW, 5 PTHRU, 6 EDL, 7 FP), BHI_STATUS (bits 31:30: 0 reset, 2 success, 3 error), MHISTATE, the BHIE block; dumps the endpoint's MSI and PCIe capabilities, per-vector interrupt counts, and **the PARF BDF-to-SID table** (`BDF2SID-TABLE-BEGIN/END`, decode with `scripts/predict-qcom-bdf-sid-table.py --decode <file>`); reads PARF only while the controller's runtime status is active. The old, wrong header comment is gone (EXECENV 1=PBL/2=SBL/3=AMSS and STATUS 0/2/3 were wrong; all values above re-checked in `include/linux/mhi.h` and `drivers/bus/mhi/common.h`).
- `scripts/test-phone-mhi-regdump.sh`: runs the real script on the PC against a fake sysfs/proc/physical-memory file with the real helper; a fake `modprobe` flips the fake chip from PBL to SBL/SUCCESS half-way through. 34 checks incl. the guards (missing helper, a helper that lies, a suspended controller) and `shellcheck -s sh`. Not covered: busybox ash itself and the real chip.
- `scripts/collect-phone-state.sh` copies the helper to the phone (`/tmp/mmio-read`) and cleans it up; `scripts/phone-wlan-probe.sh` prints the live `iommu-map` / `msi-map` words of the PCIe node and greps the iommu-map warnings.

#### 14.3 What the experiment's logs do show

**(a) The four failure messages are one timeout, seen through a race.** Power-on to failure:

| attempt | power-on | failure | after | what dmesg printed |
|---|---|---|---|---|
| v7, boot | 7.804 s | 29.664 s | 21.86 s | `Device link is not accessible`, `MHI did not enter READY state` |
| v8, boot | 8.902 s | 29.667 s | 20.77 s | `MHI did not load image over BHI, ret: -5` |
| v8, module reload | 215.213 s | 236.512 s | 21.30 s | `Device link is not accessible`, `MHI did not enter READY state` |
| v8, fresh (`--fresh`) | 56.689 s | 76.769 s | 20.08 s | `Wait for device to enter SBL or Mission mode` (an *info* line, the last line of `mhi_fw_load_handler()`, `boot.c:600`), then `failed to power up mhi: -110` |

ath11k sets the MHI timeout to 20 s (`MHI_TIMEOUT_DEFAULT_MS`, `ath11k/mhi.c:20,438`). Two waits run for that long on the same `state_event`: `mhi_sync_power_up()` waits for mission mode (`pm.c:1307`), and the state-transition worker, in `mhi_fw_load_bhi()`, waits for BHI_STATUS to become nonzero (`boot.c:284`). Both are normally woken by MHI interrupts (`mhi_intvec_threaded_handler()` ends in `wake_up_all(&state_event)`); `wait_event_timeout()` re-checks its condition once more when the timeout expires. When the first wait times out, `mhi_sync_power_up()` calls `mhi_power_down(mhi_cntrl, false)` (`pm.c:1314`); a non-graceful power-down moves pm_state to `MHI_PM_LD_ERR_FATAL_DETECT` (`pm.c:1247`) and wakes everybody. Which message you get depends on who is first: the BHI waiter sees the error state -> `ret: -5` (`-EIO`, `boot.c:548`); or the BHI wait's last-chance check had already passed and the worker goes on to `mhi_ready_state_transition()`, which prints `Device link is not accessible` (`pm.c:181`) if the power-down got in first, or completes and prints the info line if not. The old sections read the READY and BHI messages as evidence of the chip's state. **They are not independent observations.**

**(b) Inference, from the source and the log, not a register read:** the last two outcomes are only reachable if the BHI wait returned 0. With no PM error that needs `BHI_STATUS` != 0 and != ERROR at the last check (ath11k's `read_reg` always returns 0, `ath11k/mhi.c:298-304`), i.e. **SUCCESS: the boot ROM accepted the SBL image** (so its DMA read of the image worked). In the fresh run the READY transition succeeded as well (RESET cleared, READY set: SBL was up). So in the fresh attempt -- and probably in v7 and the v8 reload, which took the same path -- the chip got further than we had assumed. What never happened is the host noticing: every later step (BHI done, EE change to SBL, state change to M0, mission mode) is announced by an interrupt.

**(c) The interrupt counters** (`regdump-load.txt`, `/proc/interrupts`): before the modprobe the root port's vector (`ITS-PCI-MSI-0000:00:00.0 0 Edge PCIe PME, aerdrv, PCIe bwctrl`, irq 172) counts 0. At +4 s and +14 s it counts **2**, and all eleven endpoint vectors (irq 174-183 and 188: `bhi`, `mhi` x2, `ce0-3,5,7,8`, `DP_EXT_IRQ`) count **0**; after the failure the endpoint's lines are freed and 172 still reads 2. A chip that is alive but whose MSIs do not reach the host looks exactly like (a): a 20 s stall with no error from the chip.

#### 14.4 The cause candidate: `qcom_pcie_config_sid_1_9_0()` vs the 5-cell `iommu-map`

Source chain (7.3-rc3, all read): `qcom,pcie-sm8550` -> `cfg_1_9_0` -> `ops_1_9_0.config_sid = qcom_pcie_config_sid_1_9_0` (`pcie-qcom.c:2492,1598,1572`), called from `qcom_pcie_host_init()` right after PERST# deassert (`:1427`). It fills the controller's BDF-to-SID table (256 x u32 at PARF+0x2000, slot = CRC-8 of the 16-bit BDF) from the DT `iommu-map`. That table decides which SMMU stream ID -- and, for MSIs, which GIC-ITS DeviceID -- the controller puts on every inbound transaction of each endpoint. The function reads `iommu-map` as an array of **fixed four-u32 structs** `{bdf, phandle, smmu_sid, smmu_sid_len}` (`:1144-1216`).

`sm8550.dtsi` (and sm8450, sm8650, sm8750) now carries **five-cell** entries, because `apps_smmu` has `#iommu-cells = <2>` (SID and mask): `iommu-map = <0x0 &apps_smmu 0x1400 0x0 0x1>, <0x100 &apps_smmu 0x1401 0x0 0x1>`. In the compiled v8 DTB: `0x0 0x3b 0x1400 0x0 0x1  0x100 0x3b 0x1401 0x0 0x1`. A four-word stride over that array reads unit 1 as `{bdf=0x1, phandle=0x100, sid=0x3b, len=0x1401}`. Result, from `scripts/predict-qcom-bdf-sid-table.py` (a bit-for-bit model of the driver's loop; output in `notes/2026-10-08-pcie-bdf-sid-regression/evidence.txt`): **the only slot programmed is garbage (`0xffed3b00` in slot 0x07) and RID 0x0100 -- our QCA6490 at 01:00.0 -- has no entry** (its hash, slot 0x15, stays empty). The root port (RID 0, unit 0) is fine.

Upstream (read 2026-10-08): the OF core change `ccb2fd725d41` ("of: Respect #{iommu,msi}-cells in maps", 7.2-rc1) made the DT's old 4-cell entries wrong, a 22-patch DT series (2026-07-30) converted them to 5 cells, and the PCI driver was left parsing 4 words. Fix: **"PCI: qcom: Honor IOMMU provider's #iommu-cells in qcom_pcie_config_sid_1_9_0()"**, Manivannan Sadhasivam, posted 2026-09-07, applied 2026-09-17 to his PCI qcom tree (commit `626acf6efc69c666ffee50bf18e7b95e68670c6a`); Tested-by Loic Poulain (he reported ATH11k WiFi on the Arduino Monza broken without it, fixed with it) and Neil Armstrong (SM8650-HDK). Its commit message describes the same failure: the endpoint's RID is never programmed, its DMA hashes to an unprogrammed slot and is tagged with SID 0 (an SMMU context fault on QCS8300). It is **not in 7.3-rc3**; our `pcie-qcom.c` is the pristine file (git blob `b58a607b713f`, the patch's pre-image).

#### 14.5 What fits, and what is still inference

Verified: the source and call chain; the DTB bytes; the model's table (hand-checked: CRC-8 of `00 01` is 0x07, of `01 00` is 0x15); the upstream text; that the carried patch compiles (14.7).

Fits the observations: (1) the endpoint's MSIs never arrive; (2) the root port, whose entry is right, does get its interrupts; (3) a 20 s stall with no error report from the chip (14.3 a/b); (4) the boot ROM's DMA read of the image seems to have worked -- as expected if an unmatched endpoint is tagged with the base SID 0x1400, which it shares an IOMMU group (5; `iommu_group/devices` in the probe lists both) and domain with the root port, so *DMA translates* but the ITS sees DeviceID 0x1400 instead of the 0x1401 the kernel set up for the endpoint (`msi-map`), so *MSIs are dropped*.

Inference only, not measured: the hardware's behaviour for an unprogrammed BDF (upstream says SID 0); that the 2 interrupts on the root port's vector are the endpoint's EventID-0 MSIs arriving under the root port's DeviceID (they could equally be PME/bandwidth events); the chip's state. All three are settled by the v9 run (14.8).

#### 14.6 What this changes in the earlier sections

- Section 13 ("fits PCIe config space answers, boot ROM never reaches READY") and the rails-at-minimum suspicion are **not supported as the cause of the stall**: by 14.3 the chip probably accepted the image even in v7, with the rails at their DT minimum. The rail change stays (it matches the downstream CNSS requests and the RF side will need it), but its effect is unproven.
- The 2026-10-05 reading "PBL never completes the BHI transfer" is retired.
- Of the handoff's four hypotheses for the stall, 6.1 (host-side DMA/SMMU) and 6.4 (MSI delivery) were in the right family; the cause candidate is the BDF-to-SID tagging that feeds both. 6.2 (AOSS/PDC table over QMP) and 6.3 (power-up sequence) are not needed so far and stay unchecked.

#### 14.7 Prepared (nothing flashed, nothing committed)

- `pmaports/device/testing/linux-samsung-dm1q-mainline/pci-qcom-honor-iommu-cells-in-config-sid.patch`, `APKBUILD` **pkgrel 5** (kernel string `#6-samsung-dm1q-mainline`), sha512 added. Built from the pristine file and proven equal to upstream three ways (`notes/2026-10-08-pcie-bdf-sid-regression/build-patch.sh`): pre-image blob `b58a607b713f`, post-image blob `42cbeef083ca` (= upstream's index line), and `patch -p1` of the finished file reproduces it. `compile-check.sh`: `pcie-qcom.o` builds with clang `W=1` against the real dm1q config, 0 warnings, tree restored. DTS and config fragment unchanged from r4 (`PCIE_QCOM=y`, so the fix is in the kernel image, no module refresh needed).
- `scripts/make-dtb-image-set.sh` (new): image set from a DTS without a kernel build, verified against a reference set; `--apk ... --new-kernel` for r5; reports whether the kernel contains the PCIe fix.
- `_scratch/pmos-v9-r4-iommu-legacy/` (`boot.img`, `vendor_boot.img`, `dtbo.img`, the DTB and `dm1q-v9-iommu-legacy.dts`): same r4 kernel (gzip Image byte-identical to v8's), same vendor ramdisk, bootconfig and cmdline as v8; the **only** difference is `iommu-map = <0x0 &apps_smmu 0x1400 0x1>, <0x100 &apps_smmu 0x1401 0x1>` in `&pcie0` (legacy 4-cell form: the unpatched driver parses it correctly, and `of_check_bad_map()` makes the OF core accept it with a one-time warning). DTB sha256 `57c5b348e90b5a3d...`, boot.img `c6b38dfbee0fb7f7...`, vendor_boot.img `b26be4c515d42d61...`. (Image hashes differ from build to build -- the AVB footer salt -- so the DTB hash is the identity of the content.) The repo DTS is untouched: the override is a test, not a fix.
- `scripts/predict-qcom-bdf-sid-table.py`, `notes/2026-10-08-pcie-bdf-sid-regression/` (`evidence.txt` and the scripts that produce it).

#### 14.8 Test plan

**A. v9 (no build, no sudo).** From recovery, with the chat connected:
```
bash scripts/flash-recovery.sh boot ../_scratch/pmos-v9-r4-iommu-legacy/boot.img
bash scripts/flash-recovery.sh vendor_boot ../_scratch/pmos-v9-r4-iommu-legacy/vendor_boot.img
```
boot the system, then with the PC on the phone's network: `bash scripts/collect-phone-state.sh v9-iommu-legacy --fresh` (build the helper first if `scripts/bin/mmio-read-aarch64` is missing: `bash scripts/build-mmio-read.sh`). What to look for, in this order:
1. dmesg: `/soc@0/pcie@1c00000: iommu-map has 1-cell entries targeting 2-cell #iommu-cells, treating as 1-cell output` (the DT took effect; also visible in the probe's live `iommu-map` words: 8 cells instead of 10).
2. `regdump-idle.txt`: the table decodes to **slot 0x15 = 0x01000100 and no 0xffed3b00** (`python3 scripts/predict-qcom-bdf-sid-table.py --decode notes/<date>-v9-iommu-legacy/regdump-idle.txt`).
3. `regdump-load.txt`: the endpoint's interrupt counts rise (`irq[ep=...]`), BHI STATUS goes to SUCCESS and EXECENV PBL -> SBL -> AMSS promptly (milliseconds when the interrupts work, not 20 s), and the root port's vector stays at 0 (if it still reaches 2, those two were PME/bandwidth events, not misrouted MSIs).
4. dmesg after `Wait for device to enter SBL or Mission mode`: ath11k gets past MHI -- firmware version line, board-data lookup (section 11), a `wlan0`.

If the table is right but the interrupts still do not arrive, or the chip state in the samples is not what 14.3 inferred, this hypothesis is wrong or incomplete: read the register samples first (they are the measurement the 2026-10-07 run was meant to be), then hypotheses 6.2/6.3. Whatever v9 shows, the table dump from the phone is the first direct measurement of what the controller was given.

**B. r5 (the proper fix).** `pmbootstrap checksum linux-samsung-dm1q-mainline && pmbootstrap build linux-samsung-dm1q-mainline` (needs your sudo; the sums are already right), then `bash scripts/make-dtb-image-set.sh --dts dts/dm1q/dm1q.dts --out ../_scratch/pmos-v10-r5-pcifix --apk ~/.local/var/pmbootstrap/packages/edge/aarch64/linux-samsung-dm1q-mainline-7.3_rc3-r5.apk --new-kernel` (the last lines must say `PCIe BDF-to-SID fix in this kernel: YES`), flash `boot` + `vendor_boot`, repeat the collection. The DTS stays canonical (5-cell). Drop the patch once the kernel snapshot has the upstream commit.

### 15. v9 result (2026-10-10): the DT-only workaround brings the chip up -- the section 14 diagnosis is confirmed on hardware; first association; what is left

#### 15.1 What ran

v9 (`_scratch/pmos-v9-r4-iommu-legacy/`: `boot.img` + `vendor_boot.img`, the r4 kernel, only the DTB's `iommu-map` changed, 14.7) was flashed, then `bash scripts/collect-phone-state.sh v9-iommu-legacy --fresh` -> `notes/2026-10-10-v9-iommu-legacy/`. The log header confirms the kernel (`#5-samsung-dm1q-mainline`, built 2026-10-02) and so that v8 -> v9 changed nothing but the DTB.

#### 15.2 The predictions of 14.8, against the data

| prediction | result | where |
|---|---|---|
| the DT took effect | `OF: /soc@0/pcie@1c00000: iommu-map has 1-cell entries targeting 2-cell #iommu-cells, treating as 1-cell output` at 8.051 s | `dmesg.txt` |
| the BDF-to-SID table has the endpoint's entry and no garbage | read from the controller (PARF+0x2000, `runtime_status=active`, `BDF_TO_SID_BYPASS=0`), in the idle and the load run: **exactly one slot, `0x15 = 0x01000100`** (BDF 0x0100, SID offset 1); no `0xffed3b00`. Equal to the model's output for a correctly parsed map -- which also checks the model's CRC-8 slot (0x15) against the real hardware table | `regdump-idle.txt`, `regdump-load.txt`, `scripts/predict-qcom-bdf-sid-table.py --decode` |
| the chip boots in milliseconds, its interrupts arrive | 15.3 | `regdump-load.txt` |
| the root port's vector stays at 0 (if it still reached 2, those were PME/bandwidth events) | `rp=0` in every sample; in v8-fresh it was 2 at this stage. v9 shows exactly two endpoint interrupts by the time SBL starts (BHI completion and the EE change, both BHI vector 0) -> they were the endpoint's EventID-0 MSIs arriving under the root port's DeviceID | `regdump-load.txt` vs `notes/2026-10-07-v8-fresh/regdump-load.txt` |
| ath11k gets past MHI | `probe of 0000:01:00.0 with driver ath11k_pci returned 0 after 874834 usecs`; `chip_id 0x2 chip_family 0xb board_id 0xff soc_id 0x400c0210`; `fw_version 0x11088c35 fw_build_timestamp 2024-04-17 08:34 fw_build_id WLAN.HSP.1.1-03125-QCAHSPSWPL_V1_V2_SILICONZ_LITE-3.6510.41`; no ath11k error line (so board-data lookup and regdb passed); `wlan0` + `p2p-dev-wlan0` on `phy0`, rfkill unblocked, NetworkManager `disconnected` | `dmesg.txt`, `probe.txt` |

#### 15.3 The chip's timeline (`regdump-load.txt`; t = uptime, offsets from `mhi mhi0: Requested to power ON` at 53.541 s; the 20 s runs of v7/v8 in brackets)

| t | offset | what the registers / counters show |
|---|---|---|
| 53.31 | | before: EXECENV PBL, BHI_STATUS 0, MHIVER `0xdeadbeef` (the boot ROM's placeholder), BHI version 1.2, INTVEC `0xffffffff`; the same in all ten idle samples (`regdump-idle.txt`) -- **the chip sits in PBL, sane, indefinitely** (first direct reading of the idle chip) |
| 53.54 | +0.00 | BHI_INTVEC = 0 (host power-up) |
| 53.56 | +0.02 | image handed over: IOVA `0xffa00000`, 512 KiB, doorbell seq `0x076b7677` (a translated DMA address: the SMMU path works) |
| 53.60 | +0.06 | **BHI_STATUS = SUCCESS** (`0x876b7677`) -- 60 ms after power-on |
| 53.62 | +0.08 | EXECENV **SBL**, MHIVER `0x01000000`, MHISTATUS READY; endpoint interrupts 2 |
| 53.64 | +0.10 | MHI state M0; endpoint interrupts 4 |
| 53.65 | +0.11 | dmesg `Wait for device to enter SBL or Mission mode` [v8-fresh: +20.08 s] |
| 54.24 | +0.70 | EXECENV **AMSS** (the firmware runs), interrupts 13 |
| 54.25 | +0.71 | `ath11k_pci` probe returns 0 (874.8 ms in total) [v8: -110 after 20 s] |
| 54.66 | +1.12 | M2 (chip idle), interrupts 147; 415 at 55.13; 522 at 56.29; 976 at 63.47 (firmware housekeeping traffic) |

#### 15.4 What is established, and what is not

Established on hardware: with the same kernel, the same vendor ramdisk, bootconfig and cmdline (verified, 14.7), changing only the DTB's `iommu-map` turns "three attempts, all stalling for 20 s" into "chip up in 0.7 s, wlan0". So the blocker was the controller's BDF-to-SID tagging, not the chip, the rails, the firmware or the sequence. 14.3(b) holds in kind: with the interrupts delivered the boot ROM accepts the image within 60 ms. Hypotheses 6.2 (AOSS/PDC) and 6.3 (power-up sequence) were not needed; the PMU rail change of v8 stays (it matches downstream) but nothing shows it was needed.

Not measured: the table in the failing configuration. The 5-cell DT was never read back from the controller; the claim that it programs `0xffed3b00` in slot 0x07 and nothing at 0x15 rests on the model and the upstream text (the table of v9 matches the model's fixed output, which is the best indirect check available). A control would be one `--regdump=idle` collection on the v8 image set; cheap if the phone is ever in that state, not worth a flash cycle of its own.

#### 15.5 First functional use (user's report, 2026-10-10, from the phone's shell after a normal reboot)

No manual `modprobe` any more: after a normal reboot ath11k loads by itself (so the test blacklist file is gone) and NetworkManager joined the saved network. `wlan0`: HWaddr `xx:xx:xx:xx:xx:01` (it was `xx:xx:xx:xx:xx:02` in the collection: NetworkManager's randomised MAC; the phy's own P2P-device address `xx:xx:xx:xx:xx:03` looks like a Qualcomm default, the real MAC is not provided by the generic board file and lives in Samsung's data partitions -- later), `192.168.1.11/24` by DHCP, RX 582 / TX 1713 packets, no errors, no drops.

Pings are **not fine**: to the gateway 192.168.1.1, 13 sent / 4 received (69 % loss), RTT 19-59 ms; to 1.1.1.1, 10 sent / 2 received (80 % loss), 79-96 ms; `ping google.com` -> `bad address`. Observations: (1) 70-80 % loss on the first hop is a Wi-Fi link problem, not an internet problem; a 19-59 ms RTT to a local gateway is also far too high. (2) The replies from the gateway and from 1.1.1.1 both carry TTL 42; one device answering both is the likelier reading (a router or hotspot answering pings itself), so the 1.1.1.1 result says little about the wider internet. (3) DNS failing is probably a symptom (queries lost) or a resolver setting; either way it blocks `apk` and everything else that needs a name. It does matter.

Hypotheses, none checked: power save / DTIM handling; weak RF (the generic `board_id 0xff` board data has no Samsung calibration or antenna configuration, so TX power or antenna selection may be wrong); band/channel; resolver configuration. `scripts/phone-wlan-probe.sh` now also records capabilities, regulatory domain, a scan, `iw ... link`, `station dump` (signal, bitrates, retries, failures), power-save state, `ip -s link`, resolver and a 20-packet gateway ping. Quick experiments to run on the phone: `iw dev wlan0 set power_save off` then re-ping; 2.4 vs 5 GHz if the AP offers both; distance to the AP.

#### 15.6 What else the v9 dmesg shows (housekeeping list, not WLAN)

- **No input devices at all** (`couldn't open /dev/input/` in stage 1; no `goodix`, no `input:` lines): no touch, no power/volume keys. `geni_i2c a90000.i2c: error -ENXIO: Invalid proto 1`: the Goodix Berlin touch controller is on exactly this bus (`i2c@a90000`, docs/05, 2026-09-15), and protocol 1 is `GENI_SE_SPI` (`include/linux/soc/qcom/geni-se.h`): the serial engine comes up with SPI firmware, so `i2c-qcom-geni` refuses to bind. The kernel has a loader for SE firmware (`geni_load_se_firmware()`, `drivers/soc/qcom/qcom-geni-se.c:1553`); which blob it wants and where that lives on the vendor partitions is open.
- **ADSP/CDSP remoteprocs never start** (only the `smp2p` probes appear): no battery/charger data (pmic_glink needs the ADSP), no USB-C role handling, no audio, no sensors. Needs their firmware from the vendor partitions.
- **Display is only the bootloader's framebuffer** (`simpledrm` on `b8000000.framebuffer`, fbcon 67x73): no DPU/DSI/panel driver, no GPU. Section 14/15 do not change that.
- Known and harmless: `cpu cpu7: Voltage update failed freq=3360000` + `failed to update OPP` (cpufreq regulators; worth a look later), SPMI USID-7 `pmic-spmi 0-07 probe failed -5`, `uh-heap`/`uh-guest` reserved-mem (Samsung's hypervisor regions), `ramoops: uncorrectable error in header` x10, `fuse: module verification failed` (the module-key mismatch, section 10), the early `mtu3` trace-event and `dispcc` WARNs.

#### 15.7 Next (in the order I would do it)

1. **WLAN link quality and DNS** (15.5): data first (`bash scripts/collect-phone-state.sh wlan-link`, no reboot needed, or paste the commands' output), then the power-save / band experiments.
2. **r5, the proper fix** (14.8 B): the kernel carries the upstream patch and the DTS stays canonical; same collection must show the same table (`slot 0x15 = 0x01000100`) and no `1-cell entries` warning. Retires the v9 workaround. Needs the user's sudo for the build.
3. **Commit.** Nothing of this (docs 06/07, `scripts/`, `pmaports/`, `notes/`) is committed.
4. **Reach the phone without the USB network**: the PC is on 192.168.137.x, the phone's Wi-Fi is 192.168.1.x and not routable from the PC; joining the phone to the PC's own network plus an ssh key would end the "internet or phone, never both" limit.
5. **Input, then display**: power/volume keys (PMIC pwrkey/resin + gpio-keys, small DT work) and touch (the `a90000` question above), then the native display stack (DPU + DSI + the S6E3FAC panel driver; docs/02 item 3b). A mobile desktop (Phosh / Plasma Mobile) only makes sense after that: on `simpledrm` it would run software-rendered on the bootloader's static framebuffer, with no input and nothing that tests the display, and installing it by `apk` hits the apk-trigger/initramfs trap (docs/06, rule of 2026-10-03).

#### 15.8 Link diagnosis, first look (2026-10-10 ~14:00; raw paste in `notes/2026-10-10-wlan-link-first-look.txt`)

Facts (v9, r4 kernel): joined `<home-ssid>` on 2.4 GHz channel 8 (2447 MHz), DTIM 3. Signal **-46 dBm** (average -49) -- strong -- but per chain **[-80, -46]**: chain 0 is 34 dB below chain 1. rx bitrate 26 Mbit/s (HT MCS 3), tx bitrate 48 Mbit/s (legacy). **tx packets 2225, tx failed 1558 (70 %)**, which matches the ping loss (65-80 %). `tx retries: 0` carries no information (ath11k keeps retry counts only in its debugfs peer stats, `dp_tx.c:442`), and `tx failed` is every frame whose completion is not "acked" (`dp_tx.c:354`, `net/mac80211/status.c:1214`), so air failures and firmware drops both count. Power save was on: switching it off (root needed; without sudo `iw` says `Operation not permitted`) cut the RTT (avg 158 -> 54 ms, min 36 -> 11) but the loss only went 65 % -> 55 % (20 pings each, a small sample). Regulatory: global `00`; the firmware's self-managed phy says `CN` (2.4 GHz 2402-2472 at 20 dBm, 5 GHz 5170-5330 and 5735-5835, no 6 GHz), so channel 8 is allowed and regulatory is not what blocks. DNS: the resolver is the systemd-resolved stub (`127.0.0.53`); the upstream servers were not captured (`resolvectl status` needed). The USB network (`usb0`, 172.16.42.1) is up alongside.

Reading -- hypotheses, none tested: the loss is on the **transmit** side. Receive is fine (-46 dBm, `rx drop misc 0`, no RX errors); transmit is not. The AP also talks to us at MCS 3 although it is 46 dB above the noise at our end, which is what an AP's rate adaptation does when our ACKs (generated by the chip's PHY, not read from host memory) are not heard well. Suspects, in the order I would test them:

1. **RF / antenna configuration**: the generic board data (`board_id 0xff`, the 17cb:0108 reference-design entry of `board-2.bin`, section 11) is not Samsung's calibration and antenna table, and the 34 dB chain imbalance points at the antenna path.
2. **Interference**: CTS protection is on (802.11b clients around) and 2.4 GHz channel 8 is crowded.
3. **Host DMA coherency on the TX path**: `sm8550.dtsi` marks `pcie0` `dma-coherent` (line 2339); under Samsung's hypervisor that is unproven. The chip *reads* TX frames from host memory (stale cache lines would corrupt them), RX writes are not affected the same way. Test: a DT-only image without the property.

Experiments that need no flash: (a) phone next to the router versus far away; (b) 5 GHz, if the AP offers it (`sudo iw dev wlan0 scan | grep -E 'SSID|freq|signal'`); (c) chain masks: `sudo iw phy phy0 set antenna 0x2 0x2` (chain 1 only), `0x1 0x1`, back to `0x3 0x3`, comparing the `tx packets` / `tx failed` deltas of `iw dev wlan0 station dump`; (d) `iw dev wlan0 info` for the TX power. If those do not settle it: `CONFIG_ATH11K_DEBUGFS` (not set in our config; needs a rebuild and the new ath11k module on the rootfs) for firmware and TX statistics, then the coherency test. If (1) holds, the fix path is Samsung's own board data for the QCA6490 from the stock firmware, packed into `board-2.bin` (ath11k-bdencoder); not started.

#### 15.9 Second look (2026-10-10 ~16:15; raw paste in `notes/2026-10-10-wlan-link-second-look.txt`): the link is clean now -- cause of the earlier loss still open

The antenna-mask experiment of 15.8 (c) is **void**: `iw phy phy0 set antenna ...` fails with `Not supported (-95)` for every mask, including the current one, so the configuration never changed (`Available/Configured Antennas: TX 0x3 RX 0x3`; the antenna path cannot be tested this way). TX power is reported as 16 dBm on channel 8 (20 MHz).

What the four runs do show: **80 of 80 pings answered, `tx failed` 0** at every step, with a fresh association (tx packets 104 -> 185 over the whole test; the counters of 15.8 had been 2225/1558 after a 2 h association). So the 65-80 % loss of 2026-10-10 morning does not reproduce right now. Between the two looks three things changed and none is isolated: power save has been off since the first look (assumed, not re-read); the user is next to the router (distance at the first look unknown); the association is new. Caution on the old counter: 2225 TX frames in 7422 s is about one per 3 s, i.e. mostly background and keep-alive/null frames, not the pings, so `tx failed` 70 % may partly count null-function frames of the power-save machinery rather than lost user traffic; that is a reading, not a measurement. DNS is unchecked (the `resolvectl` lines printed nothing).

Next, still no flash: (1) a power-save A/B at this position (on/off/on/off, 40 pings each, `tx packets`/`tx failed` deltas) to see whether power save alone brings the loss back; (2) if it does not, a background logger (power-save state, `tx failed`, rx bitrate, a 10-ping loss every ~25 s) left running for an hour or two to catch when and how the loss returns (association age, load, time of day); (3) DNS now that the link is clean. If power save is the cause, the fix is a NetworkManager setting (`802-11-wireless.powersave 2` = disable on the connection), not a kernel change; the board-data and DMA-coherency suspects of 15.8 stay parked until the loss is reproduced.

#### 15.10 Logger and power-save A/B (2026-10-10 evening, 2026-10-11 morning; raw in `notes/2026-10-10-wlan-logger-and-pstest.txt`): the loss does not reproduce, and power save is not the cause

- **Logger** (`scripts/phone-wlan-log.sh`; the pasted tail is 25 minutes, 17:58-18:22 on the phone's UTC clock; power save off): 60 bursts of 10 pings, **7 pings lost (1.2 %)**, each in a burst of its own (one lost ping per burst); `tx failed` 10 -> 18 over 707 TX packets (1.1 %), the increments line up with the lost pings; no outage longer than one ping. The AP's rate towards us moves between 26 and 65 Mbit/s (HT20, one stream, MCS 3-7).
- **Power-save A/B** (`scripts/phone-wlan-pstest.sh`; power save was found **on** at the start, so it had gone back to the default since the logger run): on / off / on / off, 40 pings each: **160 of 160 answered, `tx failed` 0 throughout**. RTT average 20.8 / 7.9 / 20.3 / 7.6 ms (min 14.7 vs 2.8 ms): power save costs about 13 ms of latency and nothing else.
- **Reading:** next to the router the link is clean with or without power save. The morning's 65-80 % loss (a 2 h old association, power save on, distance unknown, chains `[-80, -46]`) has not come back, and power save -- the leading suspect in 15.9 -- is excluded as its cause. What is left for that episode: distance or phone orientation (uplink margin), channel interference at that time, a long-lived association going bad. Parked, not solved. If it returns: start the logger first, note where the phone is, then take `iw dev wlan0 station dump`.
- **DNS** is still unchecked: the `ping -c 3 google.com; resolvectl status` lines that followed in the paste printed nothing (typed after `sudo`, they may have been swallowed by its password prompt).
- Practical state: WLAN is usable. No NetworkManager change is needed; disabling power save (`nmcli connection modify "<home-ssid>" 802-11-wireless.powersave 2`) would only buy ~13 ms of latency and costs battery.

#### 15.11 Kernel r5 built (2026-10-11): the proper fix, image set ready, not yet flashed

`pmbootstrap build linux-samsung-dm1q-mainline` (run by the user; needs sudo) produced `linux-samsung-dm1q-mainline-7.3_rc3-r5.apk` (sha256 `28716ee90cd78d5a...`, 2026-10-11 07:09). The build log shows both patches applied (`add-samsung-sec-log-console.patch: OK`, `pci-qcom-honor-iommu-cells-in-config-sid.patch: OK`). Image set `_scratch/pmos-v10-r5-pcifix/` made with `scripts/make-dtb-image-set.sh --dts dts/dm1q/dm1q.dts --apk <r5 apk> --new-kernel`: boot.img `1d9f84430266662c...`, vendor_boot.img `d25d280a0635f691...`, dtbo.img `549467793ac65227...`. Verified: the kernel inside `boot.img` contains the fix (`PCIe BDF-to-SID fix in this kernel: YES`); the DTB is the **canonical** one (5-cell `iommu-map`, no workaround; its decompiled text is identical to v8's); vendor ramdisk, bootconfig and cmdline are identical to v8's; `check-wlan-dtb.py` PASS; AVB footers OK. Only the kernel differs from v8, and v8 + this kernel is what the upstream fix is about.

What the first boot must show (the check that retires the v9 workaround): no `iommu-map has 1-cell entries` warning in dmesg (the canonical DT needs none); `wlan0` present after a normal boot; and, in a `--fresh` collection, the BDF-to-SID table still reading `slot 0x15 = 0x01000100` (now produced by the patched driver from the 5-cell map) with the chip up in under a second. Flash from recovery: `bash scripts/flash-recovery.sh boot ../_scratch/pmos-v10-r5-pcifix/boot.img` and the same for `vendor_boot`. **Correction (found on the first boot, section 15.12): this set cannot be flashed on its own -- the rootfs' module tree must first be refreshed from the r5 APK (`scripts/refresh-phone-modules.sh`), because the r5 kernel's code differs from r4's.** The text that stood here ("modules unchanged, as with r4") was wrong.

#### 15.12 r5 first boot (2026-10-11): wlan0 never appeared -- the kernel refused every module of the rootfs' old tree (BTF mismatch); an omission on my side

- **What happened.** `_scratch/pmos-v10-r5-pcifix/` was flashed and booted: the phone reaches userspace (ssh over the USB network works, logs pulled 07:35 into `notes/2026-10-11-v10-r5-btf-modules/`) but there is no `wlan0`. Evidence: `notes/2026-10-11-v10-r5-btf-modules/evidence.txt`.
- **Cause.** The kernel validates every module's BTF against vmlinux (`CONFIG_DEBUG_INFO_BTF_MODULES=y`); without `CONFIG_MODULE_ALLOW_BTF_MISMATCH` (not set, checked in the real build's `.config`) a failed validation **aborts the module load** (`kernel/bpf/btf.c`, `btf_module_notify()`). The r5 boot logs 23 lines `failed to validate module [x] BTF: -22` (v9: 0): `phy_qcom_qmp_pcie`, `gpucc_sm8550`, `dispcc/videocc/camcc_sm8550`, `icc_osm_l3`, `icc_bwmon`, `rtc_pm8xxx`, `rmtfs_mem`, `socinfo`, ... -- 48 drivers that probed in v9 do not probe in r5, among them `qcom-qmp-pcie-phy`, `qcom-pcie`, `pci-pwrctrl-pwrseq`, `ath11k_pci`. `qcom-pcie` waits for its PHY, which never loads; `3da0000.iommu` (the GPU's SMMU, waiting for `gpucc`) hits its deferred-probe timeout at 18.15 s. No PHY -> no PCIe -> no `wlan0`. Nothing is wrong with the PCIe fix itself: the table/probe path is never reached.
- **Why r5 and not r4.** The module tree in the rootfs is the one the earlier boots used (docs/02 item 12); r4's kernel accepted it, r5's does not. The only code difference between r4 and r5 is the PCI patch; a source change shifts vmlinux's BTF type ids and strings, which is what the module BTF refers to (`Invalid name_offset:3136550` in the log). That chain is inferred from the log lines and the source, not measured (no vmlinux BTF diff was done). The config fragment and DTS are unchanged between r4 and r5, so the 2026-10-01 rule ("after a kernel *config* change refresh the modules") did not fire -- but the real trigger is any change to the kernel's code, not only its config.
- **My omission.** docs/06's 2026-10-01 rule (2) says to run `scripts/check-kernel-module-key.py` after every image set and refresh the modules after kernel changes. I handed over the r5 set without running it and without mentioning the modules, and I extended the wrong sentence in 15.11 ("unchanged, as with r4"). Corrected above and in docs/06.
- **Fix, no kernel rebuild.** `scripts/refresh-phone-modules.sh` unpacks `usr/lib/modules/<release>` from the kernel APK, sends it over the USB network and runs `scripts/phone-swap-modules.sh` on the phone (as root): the old tree is *moved* to `/var/lib/dm1q-modules-backup/<release>.<date>.<pid>` (undo = one `mv`), the new one is put in place, `depmod` runs, optionally the phone reboots. No apk is involved, so `/boot/initramfs-extra` is untouched (docs/06, 2026-10-03 rule). `scripts/test-refresh-phone-modules.sh`: 45 checks, ALL PASS (static checks, fake APK and fake root with a fake depmod, every refusal path leaves the old tree untouched, and the real r5 APK's tarball -- 2007 modules, release 7.3.0-rc3, 54 MB -- passes the phone script's checks). Note the swap makes the old kernels (r4/v9) refuse the modules in turn, until the backup is moved back.
- **Expected after the swap + reboot:** the v9 outcome with the canonical DTS: no `iommu-map has 1-cell entries` warning, `wlan0` up, and (with `collect-phone-state.sh ... --fresh`) the BDF-to-SID table still `slot 0x15 = 0x01000100`.
- **Open design choice (not decided):** `CONFIG_MODULE_ALLOW_BTF_MISMATCH=y` in the config fragment would make module loads tolerant to BTF drift (what is lost: BTF debug info for modules in BPF tooling) at the price of a kernel rebuild (r6) and of one more guard fewer, in a kernel that already has no MODVERSIONS. Until decided: every kernel APK that changes kernel code is followed by `refresh-phone-modules.sh`.

#### 15.13 r5 on hardware (2026-10-11 ~14:40; `notes/2026-10-11-v10-r5/`): the upstream PCIe fix works with the canonical DTS -- the v9 workaround is retired

Sequence: `pmos-v10-r5-pcifix` flashed (kernel `#6-samsung-dm1q-mainline`, canonical DTB), module tree refreshed from the r5 APK with `scripts/refresh-phone-modules.sh --reboot` (15.12), then `scripts/collect-phone-state.sh v10-r5 --fresh`.

| check | result |
|---|---|
| modules refused for BTF | 0 (r5 before the refresh: 23) |
| `iommu-map has 1-cell entries` warning | none (v9 had it; the canonical DT needs no workaround) |
| live `iommu-map` (probe.txt) | 5-cell form, `00000000 0000003b 00001400 00000000 00000001  00000100 0000003b 00001401 00000000 00000001` |
| BDF-to-SID table, idle and load | `slot 0x15 = 0x01000100` only, **identical to v9's table** (hash of all 256 words equal) -- now produced by the patched driver from the 5-cell map |
| chip boot | MHI power-on 54.97 s -> `chip_id` / `fw_version` lines 55.74 s (0.77 s; v9: 0.73 s); fw `WLAN.HSP.1.1-03125-...-3.6510.41` |
| interrupts | `irq[ep=1871 rp=0]` at the end of the load sample: the root port's counter stays 0 |
| `wlan0` | authenticated and associated 61.6 s (ath11k_pci was loaded late on purpose by the `--fresh` run); `192.168.1.11/24`, gateway and DHCP DNS `192.168.1.1`, resolver stub 127.0.0.53 |

Link snapshot taken ~3 s after association (probe.txt, power save on by default): signal -52 dBm, chains `[-82, -52]` (the 30 dB imbalance again), tx 52 Mbit/s, rx bitrate still 1.0 Mbit/s, `tx failed` 0; 20/20 gateway pings answered but slowly (RTT min 4.3 / avg 422 / max 1635 ms). The later logger and power-save A/B (15.10) were clean (power save on: avg 20 ms), so this looks like a link that has not adapted yet in its first seconds, not a standing problem -- untested guess. **DNS and internet verified by the user, 2026-10-11 ~17:55 local:** `ping google.com` resolved (142.250.74.174) and 3/3 answered, 62.3 / 66.1 / 70.8 ms min/avg/max, ttl 42. The probe itself only prints the resolver configuration; the earlier broken DNS (15.9) was the lossy link, not the resolver.

Verdict: the carried upstream patch (`pci-qcom-honor-iommu-cells-in-config-sid.patch`, docs/02 item 14) is confirmed on hardware; kernel r5 + canonical DTS is the baseline from here on. The v9 image set stays in `_scratch/` as history only (and, with the module swap of 15.12 in place, no longer boots on the rootfs without moving the old module tree back).
