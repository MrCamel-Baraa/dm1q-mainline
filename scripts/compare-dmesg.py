#!/usr/bin/env python3
"""Compare two kernel logs (dmesg / journalctl -k) and show what changed.

Usage: scripts/compare-dmesg.py <baseline.txt> <new.txt>
  e.g. scripts/compare-dmesg.py notes/2026-09-28-pmos-v1-hang/dmesg-ssh-live.txt ~/dmesg.txt

Prints the identity lines of the new boot (kernel build, cmdline, lockdown, taint), every
warning/error-looking line that exists only in one of the logs (numbers and hex normalised
away, so timestamps/addresses don't create noise), and the deferred-probe-pending list of both.
Written 2026-10-03 for the r4 control-boot comparison (docs/07, section 10).
"""
import re
import sys

if len(sys.argv) != 3:
    sys.exit(__doc__)
BASE, NEW = sys.argv[1], sys.argv[2]
ts = re.compile(r"^\[\s*(\d+\.\d+)\]\s?")


def load(p):
    out = []
    for line in open(p, errors="replace"):
        line = line.rstrip("\n")
        m = ts.match(line)
        out.append((float(m.group(1)), line[m.end():]) if m else (None, line))
    return out


def norm(s):
    s = re.sub(r"0x[0-9a-fA-F]+", "0xN", s)
    s = re.sub(r"\b[0-9a-f]{8,}\b", "H", s)
    return re.sub(r"\d+(\.\d+)?", "N", s)


interesting = re.compile(
    r"warn|error|fail|oops|\bbug\b|taint|cannot|unable|timed out|timeout|not found|refus|denied|"
    r"invalid|unhandled|deferred|dummy|missing|unsupported|ignor|can't|couldn't|no such|-EPROBE|returned [1-9]",
    re.I)
noise = re.compile(r"^(calling|initcall)\b")


def interesting_lines(L):
    return [(t, s) for t, s in L if not noise.match(s) and interesting.search(s)]


def only_in(a, b, label):
    nb = {norm(s) for _, s in b}
    seen, rows = set(), []
    for t, s in a:
        k = norm(s)
        if k in nb or k in seen:
            continue
        seen.add(k)
        rows.append((t, s))
    print("\n=== %s: %d warning/error-ish line(s) ===" % (label, len(rows)))
    for t, s in rows:
        print("[%8.3f] %s" % (t if t is not None else -1, s[:240]))


base, new = load(BASE), load(NEW)
print("lines: baseline=%d new=%d; last timestamp baseline=%.1f new=%.1f" % (
    len(base), len(new), [t for t, _ in base if t][-1], [t for t, _ in new if t][-1]))
print("\n=== identity (new) ===")
for t, s in new:
    if re.search(r"Linux version|Kernel is locked down|Loaded X\.509|verification failed|Machine model|Kernel command line", s):
        print("[%8.3f] %s" % (t, s[:230]))

ib, inew = interesting_lines(base), interesting_lines(new)
only_in(inew, ib, "ONLY in NEW")
only_in(ib, inew, "ONLY in BASELINE (gone in new)")
for name, L in (("NEW", new), ("BASELINE", base)):
    print("\n=== deferred-probe-pending, %s ===" % name)
    for t, s in L:
        if "deferred probe pending" in s:
            print("[%8.3f] %s" % (t, s[:240]))
