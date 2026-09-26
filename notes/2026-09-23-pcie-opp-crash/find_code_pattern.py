#!/usr/bin/env python3
"""Find the oops 'Code:' byte pattern in vmlinux .text and map matches to symbols.

Oops Code line (v4 build, ~10.532s):
    Code: 2a1f03e6 9409333d 14000012 f85f0261 (394022a2)
Decoded: mov w6,wzr ; bl <far> ; b .+0x48 ; ldur x1,[x19,#-16] ; [ldrb w2,[x21,#8]] <- faulting insn
The BL displacement is layout dependent (differs between builds) so it is not searched.
"""
import bisect, re, struct, subprocess, sys

V = '/home/elgamal/Documents/GitHub/_scratch/linux-build/out/vmlinux'
SM = '/home/elgamal/Documents/GitHub/_scratch/linux-build/out/System.map'

out = subprocess.check_output(['llvm-readelf', '-S', '-W', V], text=True)
text = None
for line in out.splitlines():
    m = re.search(r'\]\s+(\.text)\s+PROGBITS\s+([0-9a-f]+)\s+([0-9a-f]+)\s+([0-9a-f]+)', line)
    if m:
        text = (int(m.group(2), 16), int(m.group(3), 16), int(m.group(4), 16))
        break
if not text:
    sys.exit('could not find .text in llvm-readelf output')
vma, off, size = text
print(f'.text vma={vma:#x} off={off:#x} size={size:#x}')

with open(V, 'rb') as f:
    f.seek(off)
    blob = f.read(size)

addrs, names = [], []
for line in open(SM):
    p = line.split()
    if len(p) == 3 and p[1] in 'tTwW':
        addrs.append(int(p[0], 16)); names.append(p[2])
order = sorted(range(len(addrs)), key=lambda i: addrs[i])
addrs = [addrs[i] for i in order]; names = [names[i] for i in order]

def sym(a):
    i = bisect.bisect_right(addrs, a) - 1
    return (names[i], a - addrs[i]) if i >= 0 else ('?', 0)

W = lambda w: struct.pack('<I', w)
pat = W(0x14000012) + W(0xf85f0261) + W(0x394022a2)
print('pattern b+ldur+ldrb:', pat.hex())
pos = 0; n = 0
while True:
    i = blob.find(pat, pos)
    if i < 0:
        break
    if i % 4 == 0:
        a = vma + i
        fa = a + 8
        s, o = sym(fa)
        print(f'match @ {a:#x}: faulting ldrb {fa:#x} = {s}+{o:#x}')
        n += 1
    pos = i + 1
print(n, 'match(es)')
