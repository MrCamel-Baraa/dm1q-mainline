#!/usr/bin/env python3
"""Simpler, more robust pass: for each regulator-name line, walk backward
to find the nearest node-header line above it (handles inline braces too),
and scan forward a fixed window for min/max microvolt. Good enough for a
reference table, not a real DT parser."""
import re, sys

path = sys.argv[1] if len(sys.argv) > 1 else "dm1q_eur_openx_w00_r13.dts"
with open(path) as f:
    lines = f.readlines()

def hex_to_int(s):
    try:
        return int(s, 16)
    except ValueError:
        return None

node_header_re = re.compile(r'^\s*([\w,.@\-+]+)\s*\{')
name_re = re.compile(r'regulator-name\s*=\s*"([^"]+)"')
min_re = re.compile(r'regulator-min-microvolt\s*=\s*<0x([0-9a-fA-F]+)>')
max_re = re.compile(r'regulator-max-microvolt\s*=\s*<0x([0-9a-fA-F]+)>')

results = []
for i, line in enumerate(lines):
    m = name_re.search(line)
    if not m:
        continue
    name = m.group(1)
    node = "?"
    for j in range(i, max(-1, i-60), -1):
        hm = node_header_re.match(lines[j])
        if hm and 'regulator-name' not in lines[j]:
            node = hm.group(1)
            break
    minv = maxv = None
    for j in range(i, min(len(lines), i+15)):
        if minv is None:
            mm = min_re.search(lines[j])
            if mm: minv = hex_to_int(mm.group(1))
        if maxv is None:
            xm = max_re.search(lines[j])
            if xm: maxv = hex_to_int(xm.group(1))
        if lines[j].strip() == '};' and j > i:
            break
    results.append((name, node, minv, maxv, i+1))

print(f"Found {len(results)} regulator-name entries\n")
for name, node, minv, maxv, lineno in results:
    volt_str = ""
    if minv is not None:
        volt_str = f"{minv/1e6:.3f}V" if minv == maxv else f"{minv/1e6:.3f}-{(maxv or 0)/1e6:.3f}V"
    print(f"{name:32s} node={node:28s} {volt_str:14s} (line {lineno})")
