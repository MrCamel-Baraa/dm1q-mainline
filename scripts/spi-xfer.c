/* spi-xfer.c -- send raw SPI messages through a /dev/spidevB.C node and print what came back.
 *
 * Freestanding (no libc, raw syscalls) and static, like scripts/mmio-read.c, so one small binary runs on a
 * bare postmarketOS rootfs that has no spi-tools, python or compiler. Built by scripts/build-spi-xfer.sh for
 * aarch64 (the phone); the x86_64 branch exists only so the parsing logic can be tested on the PC.
 *
 * Why it exists (docs/08 section 2): the S23's touch controller (STMicroelectronics FTS2BA61Y) sits on
 * the SPI engine at a90000 and no driver for it exists yet. Binding spidev to the DT node lets this tool
 * speak the chip's protocol from userspace to prove the bus, the rails and the chip-select work.
 *
 * usage: spi-xfer DEV HZ ITEM [ITEM ...]
 *        spi-xfer --dry-run ITEM [ITEM ...]     parse only, print the TX frames, touch no device
 *        spi-xfer --selftest                    print struct size + ioctl numbers (checked against the kernel header)
 *   DEV   /dev/spidevB.C
 *   HZ    decimal, speed of every transfer
 *   ITEM  HEX[+N]   one SPI message with ONE transfer: the hex bytes, then N zero bytes (decimal), e.g.
 *                   87+17 = 0x87 followed by 17 zeros; FA2000002481 = six literal bytes
 *         sleep:MS  pause MS milliseconds (decimal) before the next item
 * Output, one line per item, in order:   TX b0 b1 ...   /   RX b0 b1 ...   /   SLEEP ms
 * The device is set to SPI mode 0, 8 bits per word first. Chip select is asserted by the SPI core for the
 * duration of each message (cs_change = 0), which is what chips like this one expect.
 * Exit status: 0 ok, 1 usage, 2 open failed, 3 ioctl failed ("ERR open|ioctl <what> errno=N" is printed).
 */
typedef unsigned long u64;
typedef unsigned int u32;
typedef unsigned short u16;
typedef unsigned char u8;

#if defined(__aarch64__)
#define SYS_openat 56
#define SYS_ioctl 29
#define SYS_write 64
#define SYS_exit_group 94
#define SYS_nanosleep 101
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
#define SYS_ioctl 16
#define SYS_write 1
#define SYS_exit_group 231
#define SYS_nanosleep 35
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
#define O_RDWR 2L
#define MAXF 512 /* bytes per frame */
#define MAXI 64  /* items per call */

/* include/uapi/linux/spi/spidev.h: identical layout on aarch64 and x86_64 */
struct spi_ioc_transfer {
	u64 tx_buf;
	u64 rx_buf;
	u32 len;
	u32 speed_hz;
	u16 delay_usecs;
	u8 bits_per_word;
	u8 cs_change;
	u8 tx_nbits;
	u8 rx_nbits;
	u8 word_delay_usecs;
	u8 pad;
};
_Static_assert(sizeof(struct spi_ioc_transfer) == 32, "spi_ioc_transfer layout");

/* _IOW('k', nr, size): dir=1 (write) << 30 | size << 16 | 'k' << 8 | nr */
#define IOW(nr, size) (0x40000000UL | ((u64)(size) << 16) | (0x6bUL << 8) | (nr))
#define SPI_IOC_WR_MODE IOW(1, 1)
#define SPI_IOC_WR_BITS_PER_WORD IOW(3, 1)
#define SPI_IOC_WR_MAX_SPEED_HZ IOW(4, 4)
#define SPI_IOC_MESSAGE_1 IOW(0, 32)

static u8 txb[MAXF], rxb[MAXF];
static const char *items[MAXI];

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
	if (v < 0)
		v = -v;
	do {
		b[--i] = '0' + (v % 10);
		v /= 10;
	} while (v && i > 0);
	out(&b[i]);
}

static void out_hex8(u32 v)
{
	char b[9];
	int k;
	for (k = 7; k >= 0; k--) {
		b[k] = "0123456789abcdef"[v & 15];
		v >>= 4;
	}
	b[8] = 0;
	out(b);
}

static void out_bytes(const char *tag, const u8 *p, u32 n)
{
	u32 i;
	char b[4];
	out(tag);
	for (i = 0; i < n; i++) {
		b[0] = ' ';
		b[1] = "0123456789abcdef"[p[i] >> 4];
		b[2] = "0123456789abcdef"[p[i] & 15];
		b[3] = 0;
		out(b);
	}
	out("\n");
}

static int usage(void)
{
	out("usage: spi-xfer DEV HZ ITEM [ITEM ...]   ITEM = HEX[+N zero bytes] | sleep:MS   (see scripts/spi-xfer.c)\n"
	    "       spi-xfer --dry-run ITEM [ITEM ...]\n"
	    "       spi-xfer --selftest\n");
	return 1;
}

static int streq(const char *a, const char *b)
{
	while (*a && *a == *b) {
		a++;
		b++;
	}
	return *a == *b;
}

static int prefix(const char *s, const char *p)
{
	while (*p) {
		if (*s++ != *p++)
			return 0;
	}
	return 1;
}

static int parse_dec(const char *s, u64 *res)
{
	u64 v = 0;
	int digits = 0;
	for (; *s; s++) {
		if (*s < '0' || *s > '9')
			return -1;
		if (++digits > 12)
			return -1;
		v = v * 10 + (u64)(*s - '0');
	}
	if (!digits)
		return -1;
	*res = v;
	return 0;
}

static int hexval(char c)
{
	if (c >= '0' && c <= '9')
		return c - '0';
	if (c >= 'a' && c <= 'f')
		return c - 'a' + 10;
	if (c >= 'A' && c <= 'F')
		return c - 'A' + 10;
	return -1;
}

/* HEX[+N] -> txb[0..*len). Returns 0 or -1. */
static int parse_frame(const char *s, u32 *len)
{
	u32 n = 0;
	int hi = -1, v;
	for (; *s && *s != '+'; s++) {
		v = hexval(*s);
		if (v < 0)
			return -1;
		if (hi < 0) {
			hi = v;
		} else {
			if (n >= MAXF)
				return -1;
			txb[n++] = (u8)((hi << 4) | v);
			hi = -1;
		}
	}
	if (hi >= 0)
		return -1; /* odd number of hex digits */
	if (*s == '+') {
		u64 z;
		if (parse_dec(s + 1, &z) || n + z > MAXF)
			return -1;
		while (z--)
			txb[n++] = 0;
	}
	if (!n)
		return -1;
	*len = n;
	return 0;
}

static void msleep(u64 ms)
{
	u64 ts[2];
	ts[0] = ms / 1000;
	ts[1] = (ms % 1000) * 1000000UL;
	sc6(SYS_nanosleep, (long)ts, 0, 0, 0, 0, 0);
}

static int selftest(void)
{
	out("sizeof_xfer=");
	out_dec((long)sizeof(struct spi_ioc_transfer));
	out(" msg1=");
	out_hex8((u32)SPI_IOC_MESSAGE_1);
	out(" mode=");
	out_hex8((u32)SPI_IOC_WR_MODE);
	out(" bits=");
	out_hex8((u32)SPI_IOC_WR_BITS_PER_WORD);
	out(" speed=");
	out_hex8((u32)SPI_IOC_WR_MAX_SPEED_HZ);
	out("\n");
	return 0;
}

static int run(int argc, char **argv)
{
	int dry = 0, first, n, i, nitems = 0;
	u64 hz = 0;
	long fd = -1, r;

	if (argc >= 2 && streq(argv[1], "--selftest"))
		return selftest();
	if (argc >= 2 && streq(argv[1], "--dry-run")) {
		dry = 1;
		first = 2;
	} else {
		if (argc < 4 || parse_dec(argv[2], &hz) || !hz || hz > 100000000UL)
			return usage();
		first = 3;
	}
	n = argc - first;
	if (n < 1 || n > MAXI)
		return usage();
	for (i = 0; i < n; i++) {
		u32 len;
		u64 ms;
		const char *a = argv[first + i];
		if (prefix(a, "sleep:")) {
			if (parse_dec(a + 6, &ms))
				return usage();
		} else if (parse_frame(a, &len)) {
			return usage();
		}
		items[nitems++] = a;
	}

	if (!dry) {
		u8 mode = 0, bits = 8;
		u32 speed = (u32)hz;
		fd = sc6(SYS_openat, AT_FDCWD, (long)argv[1], O_RDWR, 0, 0, 0);
		if (fd < 0) {
			out("ERR open errno=");
			out_dec(-fd);
			out("\n");
			return 2;
		}
		r = sc6(SYS_ioctl, fd, (long)SPI_IOC_WR_MODE, (long)&mode, 0, 0, 0);
		if (r < 0) {
			out("ERR ioctl mode errno=");
			out_dec(-r);
			out("\n");
			return 3;
		}
		r = sc6(SYS_ioctl, fd, (long)SPI_IOC_WR_BITS_PER_WORD, (long)&bits, 0, 0, 0);
		if (r < 0) {
			out("ERR ioctl bits errno=");
			out_dec(-r);
			out("\n");
			return 3;
		}
		r = sc6(SYS_ioctl, fd, (long)SPI_IOC_WR_MAX_SPEED_HZ, (long)&speed, 0, 0, 0);
		if (r < 0) {
			out("ERR ioctl speed errno=");
			out_dec(-r);
			out("\n");
			return 3;
		}
	}

	for (i = 0; i < nitems; i++) {
		const char *a = items[i];
		u32 len;
		u64 ms;
		if (prefix(a, "sleep:")) {
			parse_dec(a + 6, &ms);
			out("SLEEP ");
			out_dec((long)ms);
			out("\n");
			if (!dry)
				msleep(ms);
			continue;
		}
		parse_frame(a, &len);
		out_bytes("TX", txb, len);
		if (!dry) {
			struct spi_ioc_transfer t;
			u32 k;
			char *p = (char *)&t;
			for (k = 0; k < sizeof(t); k++)
				p[k] = 0;
			for (k = 0; k < len; k++)
				rxb[k] = 0;
			t.tx_buf = (u64)txb;
			t.rx_buf = (u64)rxb;
			t.len = len;
			t.speed_hz = (u32)hz;
			t.bits_per_word = 8;
			r = sc6(SYS_ioctl, fd, (long)SPI_IOC_MESSAGE_1, (long)&t, 0, 0, 0);
			if (r < 0) {
				out("ERR ioctl message errno=");
				out_dec(-r);
				out("\n");
				return 3;
			}
			out_bytes("RX", rxb, len);
		}
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
