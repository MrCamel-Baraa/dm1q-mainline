#!/usr/bin/env bash
# PC-side test of scripts/phone-sigill-core.sh (docs/06 rule 3). A python snippet builds SYNTHETIC aarch64 ELF cores (one
# PT_NOTE with NT_PRSTATUS + NT_FILE, one PT_LOAD with known instruction words around the pc); coredumpctl is a stub that
# lists them and "dumps" (copies) them. The phone script runs with dash (closest to busybox ash) and bash. Checks: the pc
# and its anonymous-mapping classification, LR in a file mapping, the instruction words with the '=>' marker, the byte line
# for llvm-mc (decoded here with llvm-mc when present), one parse per executable even with duplicate entries, a vacuumed core,
# missing tools, and that temporary files are removed.
# Usage: bash scripts/test-phone-sigill-core.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
fail=0
ok()  { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; fail=1; }
expect() { if grep -qE -- "$3" "$1"; then ok "$2"; else bad "$2 (no match for: $3)"; fi; }
reject() { if grep -qE -- "$3" "$1"; then bad "$2 (unexpected: $3)"; else ok "$2"; fi; }

command -v python3 >/dev/null || { echo "python3 missing on the PC, cannot test"; exit 1; }
mkdir -p "$W/cores" "$W/bin"
python3 - "$W/cores" <<'PYEOF'
import struct, sys
out = sys.argv[1]

def make_core(path, pc, lr, words_at_pc, signo=4, extra_threads=True):
    # one load segment of 0x1000 bytes holding instruction words, base chosen so that pc sits at +0x3c
    base = pc - 0x3c
    code = bytearray(0x1000)
    for off, w in words_at_pc.items():
        struct.pack_into('<I', code, 0x3c + off, w)
    # NT_PRSTATUS for the crashing thread (and a second, innocent one first to prove the parser picks the SIGILL one)
    def prstatus(sig, pcv, lrv):
        d = bytearray(112 + 34 * 8 + 8)
        struct.pack_into('<iii', d, 0, sig, 1 if sig == 4 else 0, 0)
        struct.pack_into('<H', d, 12, sig)
        regs = [0] * 34
        regs[0] = 0xdead0000beef; regs[30] = lrv; regs[31] = 0xffffc0000000; regs[32] = pcv; regs[33] = 0x60000000
        struct.pack_into('<34Q', d, 112, *regs)
        return bytes(d)
    def note(name, ntype, desc):
        nm = name + b'\0'
        b = struct.pack('<III', len(nm), len(desc), ntype) + nm + b'\0' * ((4 - len(nm) % 4) % 4)
        return b + desc + b'\0' * ((4 - len(desc) % 4) % 4)
    notes = b''
    if extra_threads:
        notes += note(b'CORE', 1, prstatus(0, 0x1000, 0x2000))
    notes += note(b'CORE', 1, prstatus(signo, pc, lr))
    # NT_FILE: the library that contains LR
    files = [(0xffff78800000, 0xffff79800000, 0, b'/usr/lib/libgallium-26.2.4.so')]
    nf = struct.pack('<QQ', len(files), 4096)
    for s, e, o, n in files:
        nf += struct.pack('<QQQ', s, e, o)
    for s, e, o, n in files:
        nf += n + b'\0'
    notes += note(b'CORE', 0x46494c45, nf)
    ehsize, phentsize, phnum = 64, 56, 2
    note_off = ehsize + phentsize * phnum
    load_off = (note_off + len(notes) + 15) & ~15
    eh = bytearray(64)
    eh[0:4] = b'\x7fELF'; eh[4] = 2; eh[5] = 1; eh[6] = 1
    struct.pack_into('<HHI', eh, 16, 4, 183, 1)            # ET_CORE, EM_AARCH64
    struct.pack_into('<Q', eh, 32, ehsize)                 # e_phoff
    struct.pack_into('<HH', eh, 54, phentsize, phnum)      # e_phentsize, e_phnum
    ph_note = struct.pack('<IIQQQQQQ', 4, 0, note_off, 0, 0, len(notes), 0, 4)
    ph_load = struct.pack('<IIQQQQQQ', 1, 7, load_off, base, 0, len(code), len(code), 4096)
    blob = bytes(eh) + ph_note + ph_load + notes
    blob += b'\0' * (load_off - len(blob)) + bytes(code)
    open(path, 'wb').write(blob)

# word at pc = 0xd503201f (nop), neighbours differ so the dump order is checkable
words = {-32: 0x11111111, -4: 0xaaaaaaaa, 0: 0xd503201f, 4: 0xbbbbbbbb, 32: 0x22222222}
make_core(out + '/core.1836', 0xffff5ffb103c, 0xffff78f35d4c, words)
words2 = {0: 0xd503201f, 4: 0x33333333}
make_core(out + '/core.2034', 0xffff9573703c, 0xffffb1535d4c, words2)
make_core(out + '/core.9999', 0xffff9a2de03c, 0xffff78f35d4c, words)   # older duplicate of ksplashqml
PYEOF

# coredumpctl stub: list (oldest first, like the real one) and dump PID --output=FILE
cat > "$W/bin/coredumpctl" <<EOF
#!/bin/sh
case "\$1" in
list)
	echo "Sat 2026-10-17 19:47:40 GMT 9999 10000 10000 SIGILL present  /usr/bin/ksplashqml 1.0M"
	echo "Sat 2026-10-17 19:47:50 GMT 1836 10000 10000 SIGILL present  /usr/bin/ksplashqml 1.1M"
	echo "Sat 2026-10-17 19:47:51 GMT 2034 10000 10000 SIGILL present  /usr/sbin/plasma-keyboard 1.2M"
	echo "Sat 2026-10-17 19:47:52 GMT 7777 10000 10000 SIGILL present  /usr/bin/kwin_wayland 2.2M"
	echo "Sat 2026-10-17 19:47:52 GMT 5555 10000 10000 SIGILL missing  /usr/bin/plasmashell -"
	echo "Sat 2026-10-17 19:47:53 GMT 4576 10000 10000 SIGABRT present  /usr/bin/xembedsniproxy 795.5K"
	;;
dump)
	pid="\$2"; out="\${3#--output=}"
	[ -e "$W/cores/core.\$pid" ] || exit 1
	cp "$W/cores/core.\$pid" "\$out" ;;
esac
EOF
chmod +x "$W/bin/coredumpctl"

for sh in dash bash; do
	command -v "$sh" >/dev/null || { echo "skip $sh (not installed)"; continue; }
	echo "== $sh, scenario normal"
	T="$W/tmp-$sh"
	COREDUMPCTL="$W/bin/coredumpctl" TMPD="$T" "$sh" "$HERE/phone-sigill-core.sh" > "$W/out-$sh" 2>&1 || bad "$sh exits non-zero"
	O="$W/out-$sh"
	expect "$O" "python version printed" "^Python 3"
	expect "$O" "SIGILL entries counted" "SIGILL entries: 5"
	expect "$O" "newest ksplashqml (pid 1836) parsed" "^--- /usr/bin/ksplashqml \\(pid 1836\\)"
	reject "$O" "older duplicate ksplashqml (pid 9999) skipped" "pid 9999"
	expect "$O" "plasma-keyboard parsed" "^--- /usr/sbin/plasma-keyboard \\(pid 2034\\)"
	expect "$O" "missing core skipped" "plasmashell \\(pid 5555\\): skipped, the core file is already gone"
	expect "$O" "present but not extractable reported" "could not extract the core of pid 7777"
	reject "$O" "SIGABRT entry ignored" "xembedsniproxy"
	expect "$O" "pc printed" "pc     = 0x0000ffff5ffb103c  anonymous \\(no file\\), segment flags rwx"
	expect "$O" "lr resolved to the library" "lr\\(x30\\)= 0x0000ffff78f35d4c  /usr/lib/libgallium-26\\.2\\.4\\.so"
	expect "$O" "crashing thread picked, not the first one" "si_signo=4 si_code=1"
	expect "$O" "register dump" "x0 =0000dead0000beef"
	expect "$O" "marker on the faulting word" "=> 0x0000ffff5ffb103c: d503201f"
	expect "$O" "word before" "   0x0000ffff5ffb1038: aaaaaaaa"
	expect "$O" "word after" "   0x0000ffff5ffb1040: bbbbbbbb"
	expect "$O" "first context word (pc-32)" "0x0000ffff5ffb101c: 11111111"
	expect "$O" "last context word (pc+32)" "0x0000ffff5ffb105c: 22222222"
	expect "$O" "fault word line" "^  FAULTWORD d503201f"
	expect "$O" "bytes line has the instruction little-endian" "LLVMMC .* 0x1f 0x20 0x03 0xd5 0xbb 0xbb 0xbb 0xbb"
	n="$(grep -E '^  LLVMMC ' "$O" | head -1 | tr ' ' '\n' | grep -c '^0x')"
	[ "$n" = 68 ] && ok "byte line has 68 bytes" || bad "byte line has $n bytes"
	if command -v llvm-mc >/dev/null; then
		line="$(grep -E '^  LLVMMC ' "$O" | head -1 | sed 's/^  LLVMMC //')"
		dec="$(echo "$line" | llvm-mc --disassemble --triple=aarch64 -mattr=+all 2>&1)"
		echo "$dec" | grep -qE '^\s+nop' && ok "llvm-mc decodes the pc word as nop" || bad "llvm-mc did not decode a nop: $dec"
	else
		echo "  skip  llvm-mc not installed"
	fi
	expect "$O" "clean up message" "removed the temporary files"
	[ ! -e "$T" ] && ok "temporary directory removed" || bad "temporary directory left behind"
	expect "$O" "ends with done" "^done$"

	echo "== $sh, scenario no python"
	COREDUMPCTL="$W/bin/coredumpctl" PYTHON="$W/bin/no-python" TMPD="$W/tmp2-$sh" "$sh" "$HERE/phone-sigill-core.sh" > "$W/out2-$sh" 2>&1
	expect "$W/out2-$sh" "abort message" "no .*no-python: abort"

	echo "== $sh, scenario no coredumpctl"
	COREDUMPCTL="$W/bin/none" TMPD="$W/tmp3-$sh" "$sh" "$HERE/phone-sigill-core.sh" > "$W/out3-$sh" 2>&1
	expect "$W/out3-$sh" "abort message" "no .*none: abort"

	echo "== $sh, MAXCORES=1"
	COREDUMPCTL="$W/bin/coredumpctl" MAXCORES=1 TMPD="$W/tmp4-$sh" "$sh" "$HERE/phone-sigill-core.sh" > "$W/out4-$sh" 2>&1
	expect "$W/out4-$sh" "first counted (newest extractable attempt)" "could not extract the core of pid 7777"
	reject "$W/out4-$sh" "second not tried" "pid 2034\\)$"
done

echo
[ "$fail" = 0 ] && echo "all tests passed" || { echo "SOME TESTS FAILED"; exit 1; }
