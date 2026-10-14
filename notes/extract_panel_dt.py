#!/usr/bin/env python3
"""Extract the S6E3FAC panel node of Samsung's downstream dm1q DT into readable text.

PC-side only. Usage:
  python3 notes/extract_panel_dt.py <dm1q_eur_openx_w00_r13.dts> [node-name] > out.txt

The downstream DT is a decompiled DTB: string properties carry literal "\\n"
sequences and numeric properties are <0x..> cells. This prints
  - the command-script properties (POWER_ON_PRE_SETTING, ...) with real newlines
  - every other scalar property with its cells converted to decimal where short
  - the display-timings sub-nodes (one block per mode)
Nothing here is written back anywhere; it only reads the .dts.
"""
import re
import sys

path = sys.argv[1]
node = sys.argv[2] if len(sys.argv) > 2 else "DM1_S6E3FAC_AMB606AW01"

lines = open(path, encoding="utf-8", errors="replace").read().split("\n")

# locate "<node> {" that is the panel definition (has qcom,mdss-dsi-panel-name right after)
start = None
for i, l in enumerate(lines):
    if re.match(r"\s*%s \{\s*$" % re.escape(node), l) and "panel-name" in lines[i + 1]:
        start = i
        break
if start is None:
    sys.exit("node %s not found" % node)

# brace-match to the end of the node
depth = 0
end = None
for i in range(start, len(lines)):
    depth += lines[i].count("{") - lines[i].count("}")
    if depth == 0:
        end = i
        break

CMD_PROPS = {
    "POWER_ON_PRE_SETTING", "POWER_ON_POST_SETTING", "POWER_OFF_SETTTING",
    "DSC_SETTING", "TE_ON", "PAGE_ADDRESS_SET", "FIXED_TE_SETTING",
    "FFC_SET_0", "ECC_SETTING", "ERR_FG_SETTING",
}


def cells(v):
    m = re.fullmatch(r"<(.*)>", v.strip())
    if not m:
        return v
    out = []
    for c in m.group(1).split():
        out.append(str(int(c, 16)) if re.fullmatch(r"0x[0-9a-fA-F]+", c) else c)
    return "<" + " ".join(out) + ">"


print("# source: %s lines %d-%d (node %s)" % (path.split("/")[-1], start + 1, end + 1, node))
print()
depth = 0
for i in range(start, end + 1):
    l = lines[i]
    s = l.strip()
    if s.endswith("{"):
        print("  " * depth + s)
        depth += 1
        continue
    if s == "};":
        depth -= 1
        print("  " * depth + s)
        continue
    m = re.match(r'([A-Za-z0-9_,.\-#]+) = (.*);$', s)
    if not m:
        if s:
            print("  " * depth + s)
        continue
    name, val = m.group(1), m.group(2)
    if name in CMD_PROPS and val.startswith('"'):
        print("  " * depth + name + " = <<")
        body = val.strip('"').replace("\\n", "\n").replace("\\t", "\t")
        for b in body.split("\n"):
            print("  " * (depth + 1) + b)
        print("  " * depth + ">>")
    elif name.startswith(("samsung,flash_spi", "samsung,poc", "samsung,ss_", "samsung,manual_aor",
                          "samsung,analog_offset", "samsung,dynamic_mipi_clk_sel", "samsung,dynamic_mipi_clk_timing",
                          "samsung,gm2")) or (name.isupper() or name.replace("_", "").isupper()):
        # bulky tables / command scripts we do not need for bring-up: keep the name only
        print("  " * depth + "%s = (omitted, %d chars)" % (name, len(val)))
    elif val.startswith("<") and len(val) < 200:
        print("  " * depth + "%s = %s   ; raw %s" % (name, cells(val), val))
    else:
        print("  " * depth + "%s = %s" % (name, val[:300]))
