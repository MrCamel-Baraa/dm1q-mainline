#!/usr/bin/env python3
"""Static check of the WLAN power-sequencing wiring in a compiled dm1q DTB.

Why this exists (docs/07-wlan-bringup.md, "ROOT CAUSE FOUND 2026-10-01", item 2):
in kernel 7.3-rc3 a PCI device node that carries *-supply properties and a
"pci17cb,xxxx" compatible gets a pci-pwrctrl-pwrseq platform device. That driver
calls devm_pwrseq_get(dev, "wlan"), and pwrseq_qcom_wcn_match() only accepts the
node when its vddaon-supply phandle resolves to

        <wcn*-pmu node> / regulators / <ldoN>

i.e. the *PMU's own output regulator*. Anything else (a PM8550 board rail, say)
means PWRSEQ_NO_MATCH -> pwrseq_get() returns -EPROBE_DEFER -> the pwrctrl device
never binds -> qcom-pcie's probe defers forever, with a dmesg that looks exactly
like a PCIe controller bug. This script catches that at DTB-build time.

Usage: scripts/check-wlan-dtb.py <file.dtb>      (needs `dtc` on PATH)
Exit status: 0 = wiring OK, 1 = wiring broken, 2 = no WLAN consumer node at all.
"""
import re
import subprocess
import sys


def parse(dtb):
    """Decompile the DTB with dtc and build {path: {prop: raw_value_text}} plus
    a phandle -> path map. Deliberately tiny: it only has to understand what dtc
    prints, not arbitrary DTS."""
    txt = subprocess.run(["dtc", "-I", "dtb", "-O", "dts", "-o", "-", dtb],
                         capture_output=True, text=True, check=True).stdout
    nodes, phandles = {}, {}
    stack, in_prop = [], False
    for raw in txt.splitlines():
        line = raw.strip()
        if not line or line.startswith("/dts-v1/") or line.startswith("//"):
            continue
        if in_prop:                       # continuation of a multi-line property
            nodes[stack_path(stack)][cur_prop] += " " + line
            in_prop = not line.endswith(";")
            continue
        if line == "};":
            stack.pop()
            continue
        m = re.match(r"^(\S+)\s*\{$", line)
        if m:
            stack.append(m.group(1))
            nodes.setdefault(stack_path(stack), {})
            continue
        m = re.match(r"^([^=;\s]+)\s*(?:=\s*(.*?))?(;?)$", line)
        if m:
            cur_prop, val, term = m.group(1), m.group(2) or "", m.group(3)
            path = stack_path(stack)
            nodes[path][cur_prop] = val
            in_prop = (term != ";")
            if cur_prop == "phandle":
                phandles[int(re.search(r"0x[0-9a-fA-F]+", val).group(0), 16)] = path
    return nodes, phandles


def stack_path(stack):
    return "/" + "/".join(s for s in stack if s != "/")


def first_phandle(val):
    m = re.search(r"<\s*(0x[0-9a-fA-F]+)", val)
    return int(m.group(1), 16) if m else None


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    nodes, ph = parse(sys.argv[1])

    pmus = [p for p, props in nodes.items()
            if re.search(r'"qcom,(?:qca6390|wcn\d+)-pmu"', props.get("compatible", ""))]
    consumers = [p for p, props in nodes.items()
                 if re.search(r'"pci17cb,110[137]"', props.get("compatible", ""))]

    print("PMU nodes     :", ", ".join(pmus) or "(none)")
    print("WLAN consumers:", ", ".join(consumers) or "(none)")
    if not consumers:
        print("INFO: no pci17cb,xxxx consumer node -> nothing will ever request the "
              "'wlan' pwrseq target (expected for the original v1 DTB: chip stays "
              "unpowered, 'Device not found').")
        return 2

    ok = True
    for pmu in pmus:
        regs = [p for p in nodes if p.startswith(pmu + "/regulators/")]
        print("%s: regulators{} children = %d%s" % (
            pmu, len(regs), "" if regs else "   <-- binding REQUIRES a regulators node"))
        ok &= bool(regs)

    for c in consumers:
        props = nodes[c]
        parent = c.rsplit("/", 1)[0]
        print("\n%s" % c)
        print("  compatible =", props["compatible"])
        print("  parent     = %s (device_type=%s)" % (
            parent, nodes[parent].get("device_type", "-")))
        if 'device_type = "pci"' not in "device_type = " + nodes[parent].get("device_type", ""):
            print("  WARN: parent is not a PCI root port node (expected pcie@0 / pcie0_port0)")
        supplies = sorted(k for k in props if k.endswith("-supply"))
        for k in supplies:
            target = ph.get(first_phandle(props[k]), "<unresolved phandle %s>" % props[k])
            tag = "PMU output" if any(target.startswith(p + "/regulators/") for p in pmus) else "NOT a PMU output"
            print("  %-18s -> %s   [%s]" % (k, target, tag))
        aon = props.get("vddaon-supply")
        if aon is None:
            print("  FAIL: no vddaon-supply -> pci-pwrctrl-pwrseq refuses the node (-ENODEV)")
            ok = False
            continue
        target = ph.get(first_phandle(aon), "")
        good = any(target.startswith(p + "/regulators/") and target.count("/") == p.count("/") + 2
                   for p in pmus)
        if good:
            print("  OK  : vddaon-supply = PMU/regulators/<ldo> -> pwrseq_qcom_wcn_match() "
                  "returns MATCH_OK")
        else:
            print("  FAIL: vddaon-supply does not resolve to <pmu>/regulators/<ldo> -> "
                  "PWRSEQ_NO_MATCH -> -EPROBE_DEFER forever -> &pcie0 defers forever")
            ok = False
    print("\nRESULT:", "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
