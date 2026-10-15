/* drm-fill.c -- show a test pattern on a DRM connector straight through the KMS ioctls, and list what the card has.
 *
 * Freestanding (no libc, raw syscalls) and static, like scripts/spi-xfer.c and scripts/mmio-read.c, so the bare
 * postmarketOS rootfs needs no libdrm, modetest or python. Built for aarch64 by scripts/build-drm-fill.sh; the
 * x86_64 branch exists only so the parsing and the ioctl numbers/struct sizes can be tested on the PC.
 *
 * Why it exists (docs/09): the first msm boot (r7) brings the panel up, but the kernel log cannot say whether
 * pixels, colours and geometry are right, and fbcon may not draw (the log shows "fb0: sys_imageblit: framebuffer
 * is not in virtual address space"). This tool bypasses fbcon: dumb buffer -> framebuffer -> SETCRTC.
 *
 * usage: drm-fill --selftest                         print struct sizes + ioctl numbers (checked on the PC against the real headers)
 *        drm-fill info CARD                          read-only: connectors (type, state, modes), encoders, CRTCs
 *        drm-fill fill CARD PATTERN SECONDS          modeset the first connected connector with a pattern, keep it
 *                                                    SECONDS seconds, then exit (closing the card restores fbdev)
 *   CARD     /dev/dri/cardN
 *   PATTERN  bars | red | green | blue | white | black | border
 *            bars: white yellow cyan green magenta red blue black, left to right; a gradient strip along the
 *            bottom tenth; a 1-pixel white frame on bars (clipping/geometry check). border: black with the frame.
 * Exit: 0 ok, 1 usage, 2 open failed, 3 ioctl/mmap failed ("ERR <what> errno=N"), 4 no connected connector.
 * "fill" needs to be DRM master: run it as root with nothing else (no compositor) holding the card.
 */
typedef unsigned long u64;
typedef unsigned int u32;
typedef unsigned short u16;
typedef unsigned char u8;

#if defined(__aarch64__)
#define SYS_openat 56
#define SYS_close 57
#define SYS_ioctl 29
#define SYS_write 64
#define SYS_exit_group 94
#define SYS_nanosleep 101
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
#define SYS_close 3
#define SYS_ioctl 16
#define SYS_write 1
#define SYS_exit_group 231
#define SYS_nanosleep 35
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
#define O_RDWR 2L
#define PROT_RW 3L
#define MAP_SHARED 1L
#define MAXC 16 /* connectors / crtcs / encoders listed */
#define MAXM 64 /* modes per connector */

/* include/uapi/drm/drm_mode.h; identical layout on aarch64 and x86_64 */
struct mode_info {
	u32 clock;
	u16 hdisplay, hsync_start, hsync_end, htotal, hskew;
	u16 vdisplay, vsync_start, vsync_end, vtotal, vscan;
	u32 vrefresh, flags, type;
	char name[32];
};
struct card_res {
	u64 fb_id_ptr, crtc_id_ptr, connector_id_ptr, encoder_id_ptr;
	u32 count_fbs, count_crtcs, count_connectors, count_encoders;
	u32 min_width, max_width, min_height, max_height;
};
struct get_connector {
	u64 encoders_ptr, modes_ptr, props_ptr, prop_values_ptr;
	u32 count_modes, count_props, count_encoders;
	u32 encoder_id, connector_id, connector_type, connector_type_id;
	u32 connection, mm_width, mm_height, subpixel, pad;
};
struct get_encoder {
	u32 encoder_id, encoder_type, crtc_id, possible_crtcs, possible_clones;
};
struct crtc {
	u64 set_connectors_ptr;
	u32 count_connectors, crtc_id, fb_id, x, y, gamma_size, mode_valid;
	struct mode_info mode;
};
struct create_dumb {
	u32 height, width, bpp, flags, handle, pitch;
	u64 size;
};
struct map_dumb {
	u32 handle, pad;
	u64 offset;
};
struct fb_cmd2 {
	u32 fb_id, width, height, pixel_format, flags;
	u32 handles[4], pitches[4], offsets[4];
	u64 modifier[4];
};
_Static_assert(sizeof(struct mode_info) == 68, "mode_info");
_Static_assert(sizeof(struct card_res) == 64, "card_res");
_Static_assert(sizeof(struct get_connector) == 80, "get_connector");
_Static_assert(sizeof(struct get_encoder) == 20, "get_encoder");
_Static_assert(sizeof(struct crtc) == 104, "crtc");
_Static_assert(sizeof(struct create_dumb) == 32, "create_dumb");
_Static_assert(sizeof(struct map_dumb) == 16, "map_dumb");
_Static_assert(sizeof(struct fb_cmd2) == 104, "fb_cmd2");

/* _IOWR('d', nr, size): dir=3 << 30 | size << 16 | 'd' << 8 | nr */
#define IOWR(nr, size) (0xC0000000UL | ((u64)(size) << 16) | (0x64UL << 8) | (nr))
#define IOCTL_GETRESOURCES IOWR(0xA0, sizeof(struct card_res))
#define IOCTL_SETCRTC IOWR(0xA2, sizeof(struct crtc))
#define IOCTL_GETENCODER IOWR(0xA6, sizeof(struct get_encoder))
#define IOCTL_GETCONNECTOR IOWR(0xA7, sizeof(struct get_connector))
#define IOCTL_CREATE_DUMB IOWR(0xB2, sizeof(struct create_dumb))
#define IOCTL_MAP_DUMB IOWR(0xB3, sizeof(struct map_dumb))
#define IOCTL_ADDFB2 IOWR(0xB8, sizeof(struct fb_cmd2))
#define FOURCC_XR24 0x34325258U /* 'X' 'R' '2' '4' */
#define CONNECTOR_DSI 16

static u32 ids_crtc[MAXC], ids_conn[MAXC], ids_enc[MAXC], conn_encs[MAXC];
static struct mode_info modes[MAXM];

/* the compiler may emit these for struct copies/zeroing even with -ffreestanding; volatile keeps the loops from
 * being turned back into a call to themselves */
void *memset(void *d, int c, unsigned long n)
{
	volatile u8 *p = d;
	while (n--)
		*p++ = (u8)c;
	return d;
}
void *memcpy(void *d, const void *s, unsigned long n)
{
	volatile u8 *p = d;
	const volatile u8 *q = s;
	while (n--)
		*p++ = *q++;
	return d;
}

static unsigned long slen(const char *s)
{
	unsigned long n = 0;
	while (s[n])
		n++;
	return n;
}
static void out(const char *s) { sc6(SYS_write, 1, (long)s, (long)slen(s), 0, 0, 0); }
static void err(const char *s) { sc6(SYS_write, 2, (long)s, (long)slen(s), 0, 0, 0); }
static void outu(u64 v)
{
	char b[24];
	int i = 23;
	b[i] = 0;
	do {
		b[--i] = '0' + (char)(v % 10);
		v /= 10;
	} while (v);
	out(b + i);
}
static void outx(u64 v)
{
	char b[20];
	int i = 19;
	b[i] = 0;
	do {
		b[--i] = "0123456789abcdef"[v & 15];
		v >>= 4;
	} while (v);
	out("0x");
	out(b + i);
}
static void fail(const char *what, long rc)
{
	err("ERR ");
	err(what);
	err(" errno=");
	{
		char b[24];
		int i = 23;
		unsigned long e = (unsigned long)(-rc);
		b[i] = 0;
		do {
			b[--i] = '0' + (char)(e % 10);
			e /= 10;
		} while (e);
		err(b + i);
	}
	err("\n");
}
static int streq(const char *a, const char *b)
{
	while (*a && *a == *b) {
		a++;
		b++;
	}
	return *a == *b;
}
static void usage(void)
{
	err("usage: drm-fill --selftest\n"
	    "       drm-fill info CARD\n"
	    "       drm-fill fill CARD bars|red|green|blue|white|black|border SECONDS\n");
}
static void sleep_s(long s)
{
	long ts[2] = { s, 0 };
	sc6(SYS_nanosleep, (long)ts, 0, 0, 0, 0, 0);
}

static void selftest(void)
{
	out("sizeof mode_info "); outu(sizeof(struct mode_info)); out("\n");
	out("sizeof card_res "); outu(sizeof(struct card_res)); out("\n");
	out("sizeof get_connector "); outu(sizeof(struct get_connector)); out("\n");
	out("sizeof get_encoder "); outu(sizeof(struct get_encoder)); out("\n");
	out("sizeof crtc "); outu(sizeof(struct crtc)); out("\n");
	out("sizeof create_dumb "); outu(sizeof(struct create_dumb)); out("\n");
	out("sizeof map_dumb "); outu(sizeof(struct map_dumb)); out("\n");
	out("sizeof fb_cmd2 "); outu(sizeof(struct fb_cmd2)); out("\n");
	out("GETRESOURCES "); outx(IOCTL_GETRESOURCES); out("\n");
	out("SETCRTC "); outx(IOCTL_SETCRTC); out("\n");
	out("GETENCODER "); outx(IOCTL_GETENCODER); out("\n");
	out("GETCONNECTOR "); outx(IOCTL_GETCONNECTOR); out("\n");
	out("CREATE_DUMB "); outx(IOCTL_CREATE_DUMB); out("\n");
	out("MAP_DUMB "); outx(IOCTL_MAP_DUMB); out("\n");
	out("ADDFB2 "); outx(IOCTL_ADDFB2); out("\n");
}

/* fills ids_*; returns 0 or the negative errno */
static long get_resources(long fd, struct card_res *r)
{
	long rc;
	r->fb_id_ptr = 0;
	r->count_fbs = 0;
	r->crtc_id_ptr = (u64)ids_crtc;
	r->connector_id_ptr = (u64)ids_conn;
	r->encoder_id_ptr = (u64)ids_enc;
	r->count_crtcs = r->count_connectors = r->count_encoders = MAXC;
	rc = sc6(SYS_ioctl, fd, (long)IOCTL_GETRESOURCES, (long)r, 0, 0, 0);
	if (rc < 0)
		return rc;
	if (r->count_crtcs > MAXC)
		r->count_crtcs = MAXC;
	if (r->count_connectors > MAXC)
		r->count_connectors = MAXC;
	if (r->count_encoders > MAXC)
		r->count_encoders = MAXC;
	return 0;
}

static long get_connector(long fd, u32 id, struct get_connector *c)
{
	long rc;
	u32 i;
	for (i = 0; i < sizeof(*c); i++)
		((u8 *)c)[i] = 0;
	c->connector_id = id;
	c->modes_ptr = (u64)modes;
	c->count_modes = MAXM;
	c->encoders_ptr = (u64)conn_encs;
	c->count_encoders = MAXC;
	rc = sc6(SYS_ioctl, fd, (long)IOCTL_GETCONNECTOR, (long)c, 0, 0, 0);
	if (rc < 0)
		return rc;
	if (c->count_modes > MAXM)
		c->count_modes = MAXM;
	if (c->count_encoders > MAXC)
		c->count_encoders = MAXC;
	return 0;
}

static const char *conn_type_name(u32 t)
{
	switch (t) {
	case 11: return "HDMI-A";
	case 14: return "eDP";
	case 15: return "VIRTUAL";
	case 16: return "DSI";
	case 17: return "DPI";
	case 18: return "WRITEBACK";
	case 10: return "DisplayPort";
	default: return "other";
	}
}

static int cmd_info(long fd)
{
	struct card_res r = { 0 };
	long rc = get_resources(fd, &r);
	u32 i, k;
	if (rc < 0) {
		fail("ioctl GETRESOURCES", rc);
		return 3;
	}
	out("crtcs "); outu(r.count_crtcs); out(":");
	for (i = 0; i < r.count_crtcs; i++) { out(" "); outu(ids_crtc[i]); }
	out("\nencoders "); outu(r.count_encoders); out(":");
	for (i = 0; i < r.count_encoders; i++) {
		struct get_encoder e = { 0 };
		e.encoder_id = ids_enc[i];
		rc = sc6(SYS_ioctl, fd, (long)IOCTL_GETENCODER, (long)&e, 0, 0, 0);
		out(" "); outu(ids_enc[i]);
		if (rc >= 0) { out("(crtc "); outu(e.crtc_id); out(" possible "); outx(e.possible_crtcs); out(")"); }
	}
	out("\nfb size range "); outu(r.min_width); out("x"); outu(r.min_height); out(" .. ");
	outu(r.max_width); out("x"); outu(r.max_height); out("\n");
	for (i = 0; i < r.count_connectors; i++) {
		struct get_connector c;
		rc = get_connector(fd, ids_conn[i], &c);
		if (rc < 0) { fail("ioctl GETCONNECTOR", rc); return 3; }
		out("connector "); outu(c.connector_id);
		out(" type="); out(conn_type_name(c.connector_type)); out("-"); outu(c.connector_type_id);
		out(" connection="); outu(c.connection);
		out(c.connection == 1 ? "(connected)" : c.connection == 2 ? "(disconnected)" : "(unknown)");
		out(" size_mm="); outu(c.mm_width); out("x"); outu(c.mm_height);
		out(" encoder="); outu(c.encoder_id);
		out(" modes="); outu(c.count_modes); out("\n");
		for (k = 0; k < c.count_modes; k++) {
			out("  mode "); outu(modes[k].hdisplay); out("x"); outu(modes[k].vdisplay);
			out("@"); outu(modes[k].vrefresh); out(" clock="); outu(modes[k].clock);
			out(" htotal="); outu(modes[k].htotal); out(" vtotal="); outu(modes[k].vtotal);
			out(" type="); outx(modes[k].type); out("\n");
		}
	}
	return 0;
}

static u32 px_bars(u32 x, u32 y, u32 w, u32 h)
{
	static const u32 col[8] = { 0xffffff, 0xffff00, 0x00ffff, 0x00ff00, 0xff00ff, 0xff0000, 0x0000ff, 0x000000 };
	if (x == 0 || y == 0 || x == w - 1 || y == h - 1)
		return 0xffffff;
	if (y >= h - h / 10) { /* gradient strip: black to white across the width */
		u32 g = (u32)(((u64)x * 255) / (w - 1));
		return (g << 16) | (g << 8) | g;
	}
	return col[(x * 8) / w];
}

static int cmd_fill(long fd, const char *pattern, long secs)
{
	struct card_res r = { 0 };
	struct get_connector c = { 0 };
	struct get_encoder e = { 0 };
	struct create_dumb cd = { 0 };
	struct map_dumb md = { 0 };
	struct fb_cmd2 fb = { 0 };
	struct crtc cr = { 0 };
	u32 i, k, crtc_id = 0, conn_id = 0, solid = 0, kind;
	long rc;
	u32 *p;

	if (streq(pattern, "bars")) kind = 0;
	else if (streq(pattern, "border")) kind = 1;
	else if (streq(pattern, "red")) { kind = 2; solid = 0xff0000; }
	else if (streq(pattern, "green")) { kind = 2; solid = 0x00ff00; }
	else if (streq(pattern, "blue")) { kind = 2; solid = 0x0000ff; }
	else if (streq(pattern, "white")) { kind = 2; solid = 0xffffff; }
	else if (streq(pattern, "black")) { kind = 2; solid = 0; }
	else { usage(); return 1; }

	rc = get_resources(fd, &r);
	if (rc < 0) { fail("ioctl GETRESOURCES", rc); return 3; }
	for (i = 0; i < r.count_connectors && !conn_id; i++) {
		rc = get_connector(fd, ids_conn[i], &c);
		if (rc < 0) { fail("ioctl GETCONNECTOR", rc); return 3; }
		if (c.connection == 1 && c.count_modes > 0)
			conn_id = c.connector_id;
	}
	if (!conn_id) { err("no connected connector with a mode\n"); return 4; }

	/* encoder -> crtc */
	e.encoder_id = c.encoder_id ? c.encoder_id : conn_encs[0];
	rc = sc6(SYS_ioctl, fd, (long)IOCTL_GETENCODER, (long)&e, 0, 0, 0);
	if (rc < 0) { fail("ioctl GETENCODER", rc); return 3; }
	crtc_id = e.crtc_id;
	for (k = 0; !crtc_id && k < r.count_crtcs; k++)
		if (e.possible_crtcs & (1u << k))
			crtc_id = ids_crtc[k];
	if (!crtc_id) { err("no usable crtc\n"); return 4; }

	cd.width = modes[0].hdisplay;
	cd.height = modes[0].vdisplay;
	cd.bpp = 32;
	rc = sc6(SYS_ioctl, fd, (long)IOCTL_CREATE_DUMB, (long)&cd, 0, 0, 0);
	if (rc < 0) { fail("ioctl CREATE_DUMB", rc); return 3; }
	md.handle = cd.handle;
	rc = sc6(SYS_ioctl, fd, (long)IOCTL_MAP_DUMB, (long)&md, 0, 0, 0);
	if (rc < 0) { fail("ioctl MAP_DUMB", rc); return 3; }
	rc = sc6(SYS_mmap, 0, (long)cd.size, PROT_RW, MAP_SHARED, fd, (long)md.offset);
	if (rc < 0 && rc > -4096) { fail("mmap", rc); return 3; }
	p = (u32 *)rc;
	for (i = 0; i < cd.height; i++) {
		u32 *row = p + (u64)i * (cd.pitch / 4);
		for (k = 0; k < cd.width; k++) {
			u32 v;
			if (kind == 0)
				v = px_bars(k, i, cd.width, cd.height);
			else if (kind == 1)
				v = (k == 0 || i == 0 || k == cd.width - 1 || i == cd.height - 1) ? 0xffffff : 0;
			else
				v = solid;
			row[k] = v;
		}
	}

	fb.width = cd.width;
	fb.height = cd.height;
	fb.pixel_format = FOURCC_XR24;
	fb.handles[0] = cd.handle;
	fb.pitches[0] = cd.pitch;
	rc = sc6(SYS_ioctl, fd, (long)IOCTL_ADDFB2, (long)&fb, 0, 0, 0);
	if (rc < 0) { fail("ioctl ADDFB2", rc); return 3; }

	cr.crtc_id = crtc_id;
	cr.fb_id = fb.fb_id;
	cr.set_connectors_ptr = (u64)&conn_id;
	cr.count_connectors = 1;
	cr.mode_valid = 1;
	cr.mode = modes[0];
	rc = sc6(SYS_ioctl, fd, (long)IOCTL_SETCRTC, (long)&cr, 0, 0, 0);
	if (rc < 0) { fail("ioctl SETCRTC", rc); return 3; }

	out("showing "); out(pattern); out(" "); outu(cd.width); out("x"); outu(cd.height);
	out(" pitch="); outu(cd.pitch); out(" on connector "); outu(conn_id); out(" crtc "); outu(crtc_id);
	out(" for "); outu((u64)secs); out(" s\n");
	sleep_s(secs);
	out("done\n");
	return 0;
}

static long parse_secs(const char *s)
{
	long v = 0;
	if (!*s)
		return -1;
	for (; *s; s++) {
		if (*s < '0' || *s > '9')
			return -1;
		v = v * 10 + (*s - '0');
		if (v > 3600)
			return -1;
	}
	return v;
}

int c_start_main(int argc, char **argv)
{
	long fd, secs, rc;
	if (argc == 2 && streq(argv[1], "--selftest")) {
		selftest();
		return 0;
	}
	if (argc == 3 && streq(argv[1], "info")) {
		fd = sc6(SYS_openat, AT_FDCWD, (long)argv[2], O_RDWR, 0, 0, 0);
		if (fd < 0) { fail("open", fd); return 2; }
		rc = cmd_info(fd);
		return (int)rc;
	}
	if (argc == 5 && streq(argv[1], "fill")) {
		secs = parse_secs(argv[4]);
		if (secs < 0) { usage(); return 1; }
		fd = sc6(SYS_openat, AT_FDCWD, (long)argv[2], O_RDWR, 0, 0, 0);
		if (fd < 0) { fail("open", fd); return 2; }
		rc = cmd_fill(fd, argv[3], secs);
		return (int)rc;
	}
	usage();
	return 1;
}

void c_start(long *sp)
{
	int argc = (int)sp[0];
	char **argv = (char **)(sp + 1);
	int rc = c_start_main(argc, argv);
	sc6(SYS_exit_group, rc, 0, 0, 0, 0, 0);
	for (;;)
		;
}
