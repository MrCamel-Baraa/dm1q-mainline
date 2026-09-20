#!/usr/bin/env python3
"""Check a kernel .config against postmarketOS's kconfigcheck.toml
requirements for the 'community' category (the full real target checklist).
Handles version-range and arch-range keys. Not a full pmbootstrap
reimplementation -- good enough for a manual pre-flight check."""
import sys, re
import tomllib

KCONFIGCHECK = sys.argv[1]
CONFIG_PATH = sys.argv[2]
KERNEL_VERSION = tuple(int(x) for x in sys.argv[3].split("-")[0].split("."))  # e.g. "7.3.0"
ARCH = sys.argv[4]  # "aarch64" for pmOS naming

with open(KCONFIGCHECK, "rb") as f:
    data = tomllib.load(f)

aliases = data.get("aliases", {})
community_categories = aliases.get("community", [])

# parse actual .config into a dict of CONFIG_X -> "y"/"m"/"n"/"<string>"
config = {}
with open(CONFIG_PATH) as f:
    for line in f:
        line = line.strip()
        m = re.match(r'^CONFIG_(\w+)=(.*)$', line)
        if m:
            key, val = m.group(1), m.group(2)
            val = val.strip('"')
            config[key] = val
            continue
        m = re.match(r'^# CONFIG_(\w+) is not set$', line)
        if m:
            config[m.group(1)] = "n"

def version_in_range(range_str, version):
    # range_str like ">=0.0.0" or "<8.0.0" or ">=6.0.0,<7.0.0"
    parts = range_str.split(",")
    for p in parts:
        p = p.strip()
        m = re.match(r'(>=|<=|>|<|=)(\d+)\.(\d+)\.(\d+)', p)
        if not m:
            continue
        op, a, b, c = m.group(1), int(m.group(2)), int(m.group(3)), int(m.group(4))
        target = (a, b, c)
        if op == ">=" and not version >= target: return False
        if op == "<=" and not version <= target: return False
        if op == ">" and not version > target: return False
        if op == "<" and not version < target: return False
        if op == "=" and not version == target: return False
    return True

def arch_matches(arch_str, arch):
    if arch_str == "all":
        return True
    return arch in arch_str.split()

missing = []
wrong = []
checked = 0

for cat in community_categories:
    if cat not in data:
        continue
    cat_data = data[cat]
    for version_range, arch_dict in cat_data.items():
        if not version_in_range(version_range, KERNEL_VERSION):
            continue
        for arch_str, options in arch_dict.items():
            if not arch_matches(arch_str, ARCH):
                continue
            for opt, expected in options.items():
                checked += 1
                actual = config.get(opt)
                if isinstance(expected, str) and expected in ("y", "m", "n"):
                    if expected == "n":
                        if actual not in (None, "n"):
                            wrong.append((cat, opt, expected, actual))
                    elif expected in ("y", "m"):
                        # y or m both acceptable per the spec's own rule, but
                        # let's be strict-ish: accept y or m for either
                        if actual not in ("y", "m"):
                            missing.append((cat, opt, expected, actual))
                elif isinstance(expected, list):
                    if actual is None or not all(e in actual for e in expected):
                        wrong.append((cat, opt, expected, actual))
                elif isinstance(expected, str):
                    if actual != expected:
                        wrong.append((cat, opt, expected, actual))

print(f"Checked {checked} option requirements for kernel {KERNEL_VERSION}, arch {ARCH}\n")
print(f"=== MISSING/WRONG-STATE ({len(missing)}) ===")
for cat, opt, exp, act in missing:
    print(f"  [{cat}] CONFIG_{opt}: want {exp!r}, have {act!r}")
print(f"\n=== WRONG VALUE ({len(wrong)}) ===")
for cat, opt, exp, act in wrong:
    print(f"  [{cat}] CONFIG_{opt}: want {exp!r}, have {act!r}")
