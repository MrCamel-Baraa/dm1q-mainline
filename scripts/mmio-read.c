/* mmio-read.c -- read 32-bit registers through mmap() of /dev/mem or a sysfs PCI resourceN file.
 *
 * Freestanding (no libc, raw syscalls) and static, so one small binary runs on a bare postmarketOS rootfs
 * that has no devmem, python or compiler. Built by scripts/build-mmio-read.sh for aarch64 (the phone);
 * the x86_64 branch exists only so the logic can be tested on the PC.
 *
 * Why it exists (docs/07 section 14): `dd if=/dev/mem` can NEVER read MMIO on arm64. read()/write() on
 * /dev/mem go through valid_phys_addr_range() (arch/arm64/mm/mmap.c), which only accepts ranges inside
 * mapped system RAM, so every register read of the first WLAN experiment failed with EFAULT and came out
 * as "????????". MMIO has to be mmap()ed.
 *
 * usage: mmio-read FILE BASE OFF [OFF ...]
 *   FILE  /dev/mem, or /sys/bus/pci/devices/<bdf>/resourceN
 *   BASE  hex, page-aligned offset into FILE (the physical address for /dev/mem, 0 for resourceN)
 *   OFF   hex byte offsets relative to BASE, 4-byte aligned, below 1 MiB; each is read as ONE 32-bit load
 * Prints the values as 8 hex digits, space separated, 8 per line, in argument order.
 * Exit status: 0 ok, 1 usage, 2 open failed, 3 mmap failed ("ERR open|mmap errno=N" is printed).
 * Strictly read-only (PROT_READ, O_RDONLY).
 *
 * Caution: reading MMIO of a block that is unclocked/unpowered can hang or reset the machine. The callers
 * (scripts/phone-mhi-regdump.sh) only read once the endpoint's memory space is enabled / the controller is active.
 */
typedef unsigned long u64;
typedef unsigned int u32;

#if defined(__aarch64__)
#define SYS_openat 56
#define SYS_write 64
#define SYS_exit_group 94
#define SYS_mmap 222
static inline long sc6(long n, long a, long b, long c, long d, long e, long f)
{
	register long x8 __asm__("x8") = n;
	register long x0 __asm__("x0") = a;
	register long x1 __asm__("x1") = b;
	register long x2 __asm__("x2") = c;
	register long x3 __asm__("x3") = d;
	register long x4 __asm__("x4") = e;
	register long x5 __asm__("x5") = f;
	__asm__ volatile("svc #0" : "+r"(x0) : "r"(x8), "r"(x1), "r"(x2), "r"(x3), "r"(x4), "r"(x5) : "memory", "cc");
	return x0;
}
__asm__(".globl _start\n"
	"_start:\n"
	"	mov x0, sp\n"
	"	bl c_start\n"
	"	brk #0\n");
#elif defined(__x86_64__)
#define SYS_openat 257
#define SYS_write 1
#define SYS_exit_group 231
#define SYS_mmap 9
static inline long sc6(long n, long a, long b, long c, long d, long e, long f)
{
	long ret;
	register long r10 __asm__("r10") = d;
	register long r8 __asm__("r8") = e;
	register long r9 __asm__("r9") = f;
	__asm__ volatile("syscall" : "=a"(ret) : "a"(n), "D"(a), "S"(b), "d"(c), "r"(r10), "r"(r8), "r"(r9) : "rcx", "r11", "memory");
	return ret;
}
__asm__(".globl _start\n"
	"_start:\n"
	"	mov %rsp, %rdi\n"
	"	and $-16, %rsp\n"
	"	call c_start\n"
	"	hlt\n");
#else
#error "unsupported architecture"
#endif

#define AT_FDCWD (-100L)
#define PROT_READ 1L
#define MAP_SHARED 1L
#define MAX_OFFS 1024
#define MAX_OFF_VALUE 0x100000UL /* 1 MiB window cap */

static u64 offs[MAX_OFFS];

static void out(const char *s)
{
	unsigned long n = 0;
	while (s[n])
		n++;
	sc6(SYS_write, 1, (long)s, (long)n, 0, 0, 0);
}

static void out_dec(long v)
{
	char b[24];
	int i = 23;
	b[i] = 0;
	if (v <= 0)
		v = -v;
	do {
		b[--i] = '0' + (v % 10);
		v /= 10;
	} while (v && i > 0);
	out(&b[i]);
}

static int parse_hex(const char *s, u64 *res)
{
	u64 v = 0;
	int digits = 0;
	if (s[0] == '0' && (s[1] == 'x' || s[1] == 'X'))
		s += 2;
	for (; *s; s++) {
		u32 d;
		if (*s >= '0' && *s <= '9')
			d = *s - '0';
		else if (*s >= 'a' && *s <= 'f')
			d = *s - 'a' + 10;
		else if (*s >= 'A' && *s <= 'F')
			d = *s - 'A' + 10;
		else
			return -1;
		if (++digits > 16)
			return -1;
		v = (v << 4) | d;
	}
	if (!digits)
		return -1;
	*res = v;
	return 0;
}

static int usage(void)
{
	out("usage: mmio-read FILE BASE OFF [OFF ...]   (hex; BASE page-aligned; OFF 4-aligned, < 0x100000)\n");
	return 1;
}

static int run(int argc, char **argv)
{
	u64 base, maxoff = 0, len;
	int n = argc - 3, i;
	long fd, p;

	if (argc < 4 || n > MAX_OFFS)
		return usage();
	if (parse_hex(argv[2], &base) || (base & 0xfff))
		return usage();
	for (i = 0; i < n; i++) {
		if (parse_hex(argv[3 + i], &offs[i]) || (offs[i] & 3) || offs[i] >= MAX_OFF_VALUE)
			return usage();
		if (offs[i] > maxoff)
			maxoff = offs[i];
	}
	fd = sc6(SYS_openat, AT_FDCWD, (long)argv[1], 0 /* O_RDONLY */, 0, 0, 0);
	if (fd < 0) {
		out("ERR open errno=");
		out_dec(fd);
		out("\n");
		return 2;
	}
	len = (maxoff + 4 + 0xfff) & ~0xfffUL;
	p = sc6(SYS_mmap, 0, (long)len, PROT_READ, MAP_SHARED, fd, (long)base);
	if ((unsigned long)p > (unsigned long)-4096L) {
		out("ERR mmap errno=");
		out_dec(p);
		out("\n");
		return 3;
	}
	for (i = 0; i < n; i++) {
		u32 v = *(volatile u32 *)(p + (long)offs[i]);
		char b[10];
		int k;
		for (k = 7; k >= 0; k--) {
			b[k] = "0123456789abcdef"[v & 15];
			v >>= 4;
		}
		b[8] = (i % 8 == 7 || i == n - 1) ? '\n' : ' ';
		b[9] = 0;
		out(b);
	}
	return 0;
}

void c_start(long *sp)
{
	int argc = (int)sp[0];
	char **argv = (char **)(sp + 1);
	sc6(SYS_exit_group, run(argc, argv), 0, 0, 0, 0, 0);
	for (;;)
		;
}
