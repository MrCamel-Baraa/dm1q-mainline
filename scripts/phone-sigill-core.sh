#!/bin/sh
# Read-only: find out WHICH instruction killed the Plasma clients with SIGILL (docs/10 section 9.1-9.2). Runs on the phone as
# root (sudo sh phone-sigill-core.sh), POSIX sh + python3 (stdlib only; python3 is on the phone because usb-moded-notify is a
# python script).
#
# For the newest few SIGILL coredumps in systemd-coredump (one per executable) it extracts the core (coredumpctl dump), parses
# the ELF core with a small python parser (NT_PRSTATUS of the crashing thread, NT_FILE mappings, PT_LOAD contents) and prints:
# the faulting PC and its mapping (anonymous = JIT code, otherwise the file), LR and SP, x0-x30, and 17 instruction words around
# the PC, plus a ready-to-paste byte line for `llvm-mc --disassemble --triple=aarch64 -mattr=+all` on the PC. It changes nothing
# (temporary cores go under /tmp and are removed again).
#
# Test overrides (scripts/test-phone-sigill-core.sh): COREDUMPCTL, PYTHON, TMPD, MAXCORES.
COREDUMPCTL="${COREDUMPCTL:-coredumpctl}"; PYTHON="${PYTHON:-python3}"
TMPD="${TMPD:-/tmp/dm1q-sigill}"; MAXCORES="${MAXCORES:-4}"

sec() { echo; echo "=== $1"; }
have() { command -v "$1" >/dev/null 2>&1; }

sec "1 tools"
if ! have "$COREDUMPCTL"; then echo "no $COREDUMPCTL: abort"; echo "done"; exit 1; fi
if ! have "$PYTHON"; then echo "no $PYTHON: abort (apk add python3 would fix it)"; echo "done"; exit 1; fi
"$PYTHON" --version 2>&1
mkdir -p "$TMPD"

sec "2 SIGILL coredumps known to systemd-coredump (newest last)"
LIST="$("$COREDUMPCTL" list --no-pager --no-legend 2>&1)"
echo "$LIST" | grep -c SIGILL | sed 's/^/SIGILL entries: /'
echo "$LIST" | grep SIGILL | tail -n 12

cat > "$TMPD/core.py" <<'PYEOF'
import mmap, struct, sys

def u(fmt, buf, off):
    return struct.unpack_from(fmt, buf, off)

def main(path, label):
    f = open(path, 'rb')
    m = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
    if m[:4] != b'\x7fELF' or m[4] != 2 or m[5] != 1:
        print("%s: not an ELF64 little-endian core" % label)
        return 1
    e_phoff, = u('<Q', m, 32)
    e_phentsize, e_phnum = u('<HH', m, 54)
    loads, notes = [], []
    for i in range(e_phnum):
        o = e_phoff + i * e_phentsize
        p_type, p_flags, p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, p_align = u('<IIQQQQQQ', m, o)
        if p_type == 1:
            loads.append((p_vaddr, p_memsz, p_offset, p_filesz, p_flags))
        elif p_type == 4:
            notes.append((p_offset, p_filesz))
    threads, files = [], []
    for off, size in notes:
        pos, end = off, off + size
        while pos + 12 <= end:
            namesz, descsz, ntype = u('<III', m, pos)
            name = bytes(m[pos + 12:pos + 12 + namesz]).rstrip(b'\0')
            dpos = pos + 12 + ((namesz + 3) & ~3)
            desc = bytes(m[dpos:dpos + descsz])
            if name == b'CORE' and ntype == 1 and descsz >= 112 + 34 * 8:
                signo, code, errno = u('<iii', desc, 0)
                cursig, = u('<H', desc, 12)
                regs = u('<34Q', desc, 112)
                threads.append((signo, cursig, code, regs))
            elif name == b'CORE' and ntype == 0x46494c45:
                count, pagesz = u('<QQ', desc, 0)
                ents = [u('<QQQ', desc, 16 + 24 * k) for k in range(count)]
                names = desc[16 + 24 * count:].split(b'\0')
                files = [(s, e, n.decode('utf-8', 'replace')) for (s, e, _), n in zip(ents, names)]
            pos = dpos + ((descsz + 3) & ~3)
    print("%s: %d thread(s) in the core, %d mapped files, %d PT_LOAD segments" % (label, len(threads), len(files), len(loads)))
    crash = [t for t in threads if t[0] == 4 or t[1] == 4]
    if not crash:
        print("  no thread with SIGILL in this core (signals seen: %s)" % sorted(set(t[0] for t in threads)))
        return 0
    signo, cursig, code, regs = crash[0]
    pc, sp, lr, pstate = regs[32], regs[31], regs[30], regs[33]

    def mapping(addr):
        for s, e, n in files:
            if s <= addr < e:
                return n
        for vaddr, memsz, off, filesz, flags in loads:
            if vaddr <= addr < vaddr + memsz:
                return "anonymous (no file), segment flags %s%s%s" % ('r' if flags & 4 else '-', 'w' if flags & 2 else '-', 'x' if flags & 1 else '-')
        return "unmapped in the core"

    def readmem(addr, n):
        for vaddr, memsz, off, filesz, flags in loads:
            if vaddr <= addr and addr + n <= vaddr + filesz:
                return bytes(m[off + addr - vaddr:off + addr - vaddr + n])
        return None

    print("  crashing thread: si_signo=%d si_code=%d (ILL_ILLOPC=1)" % (signo, code))
    print("  pc     = 0x%016x  %s" % (pc, mapping(pc)))
    print("  lr(x30)= 0x%016x  %s" % (lr, mapping(lr)))
    print("  sp     = 0x%016x  pstate = 0x%016x (EL%d, NZCV=%x)" % (sp, pstate, (pstate >> 2) & 3, (pstate >> 28) & 15))
    for i in range(0, 31, 4):
        print("  " + "  ".join("x%-2d=%016x" % (j, regs[j]) for j in range(i, min(i + 4, 31))))
    base = pc - 32
    blob = readmem(base, 68)
    if blob is None:
        print("  could not read the code around the pc from the core (segment not dumped)")
        return 0
    print("  instruction words (little-endian, '=>' marks the faulting one):")
    for k in range(17):
        a = base + 4 * k
        w, = struct.unpack_from('<I', blob, 4 * k)
        print("   %s 0x%016x: %08x" % ("=>" if a == pc else "  ", a, w))
    print("  bytes for llvm-mc on the PC (all 17 words, in order):")
    print("  LLVMMC " + " ".join("0x%02x" % b for b in blob))
    print("  FAULTWORD %08x" % struct.unpack_from('<I', blob, 32)[0])
    return 0

if __name__ == '__main__':
    sys.exit(main(sys.argv[1], sys.argv[2]))
PYEOF

sec "3 parsing the newest SIGILL core of each executable"
SEEN=""
N=0
# columns of coredumpctl list: date(3 words+tz) PID UID GID SIG COREFILE EXE SIZE. Take PID and EXE by position from the right.
echo "$LIST" | grep SIGILL | awk '{ a[NR] = $0 } END { for (i = NR; i >= 1; i--) print a[i] }' | while read -r line; do   # newest first (no tac on busybox)
	[ "$N" -ge "$MAXCORES" ] && break
	PID="$(echo "$line" | awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^SIG[A-Z]+$/) { print $(i - 3); exit } }')"
	EXE="$(echo "$line" | awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^SIG[A-Z]+$/) { print $(i + 2); exit } }')"
	[ -n "$PID" ] && [ -n "$EXE" ] || continue
	CF="$(echo "$line" | awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^SIG[A-Z]+$/) { print $(i + 1); exit } }')"
	if [ "$CF" = missing ]; then echo "--- $EXE (pid $PID): skipped, the core file is already gone (vacuumed)"; continue; fi
	case " $SEEN " in *" $EXE "*) continue ;; esac
	SEEN="$SEEN $EXE"
	N=$((N + 1))
	echo "--- $EXE (pid $PID)"
	CORE="$TMPD/core.$PID"
	if "$COREDUMPCTL" dump "$PID" --output="$CORE" >/dev/null 2>&1 && [ -s "$CORE" ]; then
		"$PYTHON" "$TMPD/core.py" "$CORE" "$EXE" 2>&1
	else
		echo "  could not extract the core of pid $PID (already vacuumed?)"
	fi
	rm -f "$CORE"
done

sec "4 clean up"
rm -f "$TMPD/core.py"; rmdir "$TMPD" 2>/dev/null
echo "removed the temporary files"
echo
echo "done"
