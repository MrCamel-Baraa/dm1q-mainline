#!/usr/bin/env python3
"""Extract pinctrl state definitions (node name, GPIO pin numbers, function,
pull, drive-strength) from a decompiled Samsung downstream .dts.
Regex/line-window based, not a real DT parser."""
import re, sys

path = sys.argv[1] if len(sys.argv) > 1 else "dm1q_eur_openx_w00_r13.dts"
with open(path) as f:
    lines = f.readlines()

node_header_re = re.compile(r'^\s*([\w,.@\-+]+)\s*\{')
pins_re = re.compile(r'pins\s*=\s*"([^"]+)"')
func_re = re.compile(r'function\s*=\s*"([^"]+)"')
pull_re = re.compile(r'bias-(disable|pull-up|pull-down)')
drive_re = re.compile(r'drive-strength\s*=\s*<0x([0-9a-fA-F]+)>')

results = []
for i, line in enumerate(lines):
    m = pins_re.search(line)
    if not m:
        continue
    pins = m.group(1)
    node = "?"
    for j in range(i, max(-1, i-10), -1):
        hm = node_header_re.match(lines[j])
        if hm and 'pins' not in lines[j] and 'function' not in lines[j]:
            node = hm.group(1)
            break
    func = pull = drive = None
    for j in range(i, min(len(lines), i+8)):
        if func is None:
            fm = func_re.search(lines[j])
            if fm: func = fm.group(1)
        if pull is None:
            pm = pull_re.search(lines[j])
            if pm: pull = pm.group(1)
        if drive is None:
            dm = drive_re.search(lines[j])
            if dm: drive = int(dm.group(1), 16)
        if lines[j].strip() == '};' and j > i:
            break
    results.append((node, pins, func, pull, drive, i+1))

print(f"Found {len(results)} pin-group entries\n")
print(f"{'node':30s} {'pins':15s} {'function':12s} {'pull':12s} {'drive_mA':8s} line")
for node, pins, func, pull, drive, lineno in results:
    print(f"{node:30s} {pins:15s} {str(func):12s} {str(pull):12s} {str(drive):8s} {lineno}")
