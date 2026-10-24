#!/usr/bin/env bash
# Collect the phone's WLAN/PCIe state + full kernel logs over the phone's USB network and save
# them into the repo, so nothing has to go through the chat while the PC is on the phone's network.
#
# Why: the PC is either on the phone's USB network or on the internet, never both -- and a chat
# session that runs on the PC drops (taking any in-flight output with it) when the network
# switches. So: run this script yourself, in a terminal, while connected to the phone; when it says
# "done", reconnect to the internet and tell Claude, who reads the files from disk.
#
# Usage:  scripts/collect-phone-state.sh <label> [--reboot] [--reload] [--regdump[=idle|load|reload]] [--fresh] [--touch] [--display] [--drm-test] [--backlight] [--plasma-preflight] [--apknet] [--apk-https] [--plasma-install] [--plasma-start[=SECONDS]] [--plasma-profile=default|software|softpipe] [--plasma-keep] [--sigill-core] [--gpu] [--pam-fix[=check|undo]] [--gpu-powerup=sqe-gmu|full] [--boot-setup=check|gpu-fw|undo-gpu-fw|plasma|undo-plasma] [--touch-watch[=SECONDS]] [--touch-sleepwake[=SECONDS]] [--touch-recover] [--touch-trace=arm|dump|disarm] [--sleep-probe] [--load-probe] [--input-check] [--touch-scanmode] [--touch-pm] [--touch-poke=read|senseon|scanmode|reset|hex:<bytes>]
#   <label>      names the output dir: notes/<YYYY-MM-DD>-<label>/   (e.g. v8-wlan-rails); reusing a
#                label on the same day writes to notes/<YYYY-MM-DD>-<label>-2/ (then -3 ...), never over an earlier capture
#   --reboot     first `adb reboot` (phone sitting in recovery -> boots the system)
#   --reload     also run scripts/phone-ath11k-reload.sh (reload ath11k_pci, sample the PCIe link for ~30 s)
#   --regdump    also run scripts/phone-mhi-regdump.sh in the given mode (default load): sample the chip's
#                MHI/BHI registers (and the interrupt counters, the endpoint's MSI state and the PCIe controller's
#                BDF-to-SID table) while ath11k's power-up runs (adds regdump.txt). It reads MMIO through the static
#                helper scripts/bin/mmio-read-aarch64, which this script copies to the phone (build it once with
#                `bash scripts/build-mmio-read.sh`; docs/07 section 14 says why dd on /dev/mem cannot do it).
#   --fresh      the representative experiment, in one go: blacklist ath11k_pci, reboot the phone over ssh,
#                log in again (second password prompt), then on the freshly powered, untouched chip run the
#                probe, the register sampler in idle mode (chip in PBL, nobody talking to it) and then in
#                load mode (a clean ath11k attempt), and collect everything. The blacklist file is removed
#                again right after the reboot, so later boots are normal.
#   --touch      also run scripts/phone-touch-spi-probe.sh (docs/08 step B1: needs the spidev test image; loads
#                gpi / spi_geni_qcom / spidev, talks the FTS2BA61Y protocol over /dev/spidev*, adds touch.txt). It uses
#                the static helper scripts/bin/spi-xfer-aarch64 (build once with `bash scripts/build-spi-xfer.sh`).
#   --display    also run scripts/phone-display-probe.sh (docs/09: read-only; running kernel config, display modules,
#                DRM/fbdev state, platform devices and their drivers, clocks, panel rails and GPIOs, display dmesg
#                lines; adds display.txt). No modprobe, no MMIO.
#   --drm-test   also run scripts/phone-drm-test.sh with the static helper scripts/bin/drm-fill-aarch64 (build once with
#                `bash scripts/build-drm-fill.sh`): lists the msm DRM card's connectors, then SHOWS TEST PATTERNS on the
#                panel (bars 12 s, then red/green/blue/white 5 s each, ~35 s) -- watch the phone; adds drm-test.txt.
#   --backlight  also run scripts/phone-backlight-test.sh (docs/09 section 17): shows solid white (drm-fill, same helper as
#                --drm-test) and sweeps the panel's brightness 100 % -> raw 1 -> 0, then restores it (~1 min) -- watch the
#                phone; adds backlight.txt.
#   --plasma-preflight  also run scripts/phone-plasma-preflight.sh (docs/10: read-only; init system, Wi-Fi / USB-gadget
#                managers, free space, apk triggers, UI packages, DRM/input/backlight, sessions, and an `apk add --simulate`
#                of postmarketos-ui-plasma-mobile; the only write is `apk update`, which needs the phone's Wi-Fi internet;
#                adds plasma-preflight.txt, which prints no SSIDs/MACs/passwords but is still not for committing raw).
#   --apknet     also run scripts/phone-apknet-diag.sh (docs/10 section 5: read-only; why `apk update` fails on the phone:
#                clock, route/DNS/MTU, ICMP, HTTP/HTTPS fetch of the index files with headers, `apk update -vv`; adds apknet.txt).
#   --apk-https  also run scripts/phone-apk-https.sh (docs/10 section 6: CHANGES /etc/apk/repositories http:// -> https:// (original
#                kept as repositories.dm1q-orig) because the ISP middlebox hijacks plain HTTP, runs `apk update`, and SIMULATES the
#                Plasma Mobile install with the pipewire backend pinned; installs nothing; adds apk-https.txt).
#   --plasma-install  also run scripts/phone-plasma-install.sh (docs/10 section 8): INSTALLS Plasma Mobile (apk add, ~2.7 GB, 15-40 min,
#                detached on the phone so a dropped ssh does not kill it; re-run the same command to follow/finish), masks usb-moded,
#                saves the working initramfs-extra, does NOT start the UI and does NOT reboot. The install regenerates
#                /boot/initramfs-extra: DO NOT boot the system afterwards, go to TWRP and run scripts/fix-phone-initramfs-extra.sh
#                first (docs/06 rule 3). Adds plasma-install.txt.
#   --plasma-start[=SECONDS]  also run scripts/phone-plasma-start.sh (docs/10 section 9): starts plasma-mobile.service BY HAND, you use the
#                phone for SECONDS (default 240) while it logs, then it collects journal/process/DRM/kscreen evidence and stops the UI
#                again (console restored). Aborts early on a crash loop; a dropped ssh or Ctrl-C also stops it. Adds plasma-start.txt.
#                WATCH THE PHONE SCREEN and touch it, press the keys, move the brightness slider, open the keyboard.
#   --plasma-profile=software|softpipe  with --plasma-start: run the session with a TEMPORARY env script (removed at the end; default changes nothing):
#                software = QT_QUICK_BACKEND=software (Qt Quick apps on the CPU, KWin still on llvmpipe); softpipe = software +
#                LIBGL_ALWAYS_SOFTWARE=1 + GALLIUM_DRIVER=softpipe (Mesa's non-JIT rasteriser, avoids the llvmpipe SIGILL; slow).
#   --sigill-core  also run scripts/phone-sigill-core.sh (docs/10 section 9.2: read-only; parses the stored SIGILL coredumps of the Plasma
#                clients with python3 and prints the faulting pc, its mapping and the instruction words, to be decoded with llvm-mc on the PC;
#                runs AFTER --plasma-start so its new cores are included; adds sigill-core.txt).
#   --plasma-keep  with --plasma-start: leave the UI running at the end instead of stopping it.
#   --gpu        also run scripts/phone-gpu-probe.sh (docs/11 section 7: read-only; Adreno 740 state: running kernel config, GPU modules,
#                gpu / gmu / gpucc / adreno-smmu devices and drivers, DT gpu + zap-shader nodes, zap carveout, DRM nodes, devfreq, firmware
#                files and staging dirs with sha256, Mesa packages, initramfs-extra fingerprint, GPU clocks/genpd, GPU dmesg lines, a
#                key=value summary; it NEVER opens /dev/dri/* -- the first open powers the GPU up; adds gpu.txt).
#   --pam        also run scripts/phone-pam-probe.sh (docs/11 section 9.10: read-only; PAM files that mention selinux, their apk owners, the PAM modules that exist,
#                pam/systemd/shadow package versions, the tail of /var/log/apk.log, the user@10000 unit and journal; adds pam.txt).
#   --pam-fix[=check|undo]  also run scripts/phone-pam-fix.sh (docs/11 section 9.10): CHANGES /etc/pam.d (no apk): adds override files for systemd-user and
#                systemd-run0 with the pam_selinux.so lines made optional (linux-pam 1.7.1-r4 lost that module), then starts user@10000.service once.
#                =check shows what would change and writes nothing; =undo removes the overrides again (adds pam-fix.txt).
#   --gpu-powerup=sqe-gmu|full  also run scripts/phone-gpu-powerup.sh (docs/11 step S3): CHANGES THE GPU STATE, powers the Adreno 740 up once.
#                Copies the linux-firmware files from $DM1Q_GPU_FW (default ../_scratch/dm1q-gpu-fw, never committed) to /root/dm1q-gpu-fw on the
#                phone (not under /lib/firmware, so no mkinitfs trigger), points firmware_class.path at a staging copy only for the duration of
#                one open of the render node, restores it, and prints the new kernel log lines + a verdict (adds gpu-powerup.txt).
#                sqe-gmu = SQE + GMU only (GMU boots, stops cleanly at the missing zap shader); full = also the zap shader (secure-world
#                authentication: the step that could reset the phone; then just let it reboot, the default firmware path never has the files).
#   --boot-setup=check|gpu-fw|undo-gpu-fw|plasma|undo-plasma  also run scripts/phone-boot-setup.sh (docs/11 section 9.12): makes the GPU fix and the Plasma start
#                permanent WITHOUT apk (plain files + systemd units; initramfs-extra is hashed before and after). gpu-fw installs the phone's own
#                Adreno firmware (from $DM1Q_GPU_FW, which must hold qcom/sm8550/a740_zap.mbn; the phone script pins the known hashes) under
#                /lib/firmware/postmarketos plus a boot-loop breaker that moves it away again if a boot with it does not finish; plasma enables
#                plasma-mobile.service at boot (refuses unless the GPU came up by itself in the current boot and PAM is fixed); undo-* revert;
#                check is read-only (adds boot-setup.txt).
#   --touch-watch[=SECONDS]  also run scripts/phone-touch-watch.sh (docs/08 section 2.13; no persistent change; runs before the display / GPU / PAM / Plasma steps): holds the touchscreen's
#                evdev node open for SECONDS (default 45) and logs once a second the fts2ba61y interrupt count, the gpio25 level, the evdev events, the SPI /
#                regulator / panel / backlight state, then a verdict, the new kernel lines and the last SPI transfers (spi:spi_transfer_stop tracepoint, enabled
#                only for the run and restored). DRAG A FINGER CONTINUOUSLY on the screen for the whole window, even if touch looks dead (adds touch-watch.txt).
#   --touch-sleepwake[=SECONDS]  with --touch-watch (implies it): after the first window, a second window (default 20 s) in which the script says when to press
#                the POWER KEY (screen off), wait 5 s, press it again (screen on) and keep dragging a finger.
#   --touch-recover  with --touch-watch (implies it): if the first window shows no events, tries ONE reversible experiment at a time (unbind / bind of spi0.0 =
#                power cycle of the chip's rails, then modprobe -r / modprobe fts2ba61y), each followed by a 15 s window, and stops at the first that brings events
#                back. The device is always left bound; nothing is made permanent.
#   --touch-trace=arm|dump|disarm  the touch flight recorder (docs/08 section 2.14; scripts/phone-touch-trace.sh): keeps the last SPI transfers of the touch chip in a
#                trace buffer in RAM, so that what the chip said just before it went silent survives the failure. arm (once per boot): starts it, then a 6 s alive
#                check (DRAG A FINGER); if touch is dead right then it is revived with a rebind so that the NEXT failure is recorded. dump (after touch died, BEFORE
#                reviving it): READ-ONLY, saves the raw buffer (touch-trace-raw.txt) and prints the decoded records, the status records and the gap. disarm: stops it.
#   --load-probe  also run scripts/phone-load-probe.sh (docs/08 section 2.16; READ-ONLY, runs first of all, ~10 s): a CPU snapshot for "the phone is laggy / hot": loadavg and
#                pressure, per-CPU busy percentages over 3 s, the interrupts with the highest rate, top (processes and threads), plasma-mobile.service state and
#                restart count, who holds a /dev/dri node, the renderer lines of the journal, GPU hang / throttling lines, cpufreq, the hottest thermal zones. Run it WHILE
#                THE PHONE IS HOT OR LAGGY (adds load-probe.txt).
#   --touch-pm  also run scripts/phone-touch-pm.sh (docs/08 section 2.18; REVERSIBLE, no unbind): holds the serial engine and spi0.0 awake
#                (power/control=on) while watching the touch interrupt count for WAIT seconds, then restores them (adds touch-pm.txt).
#                Drag a finger for the whole watch. Verdict: PM-HOLD-AWAKE (interrupts rose while held) or NO-CHANGE.
#   --touch-poke=STEP  also run scripts/phone-touch-poke.sh (docs/08 section 2.21; sends exactly ONE SPI transfer through the debugfs raw knob of kernel patch 0004,
#                no unbind): STEP is read (87+17), senseon (C010), scanmode (A00001), reset (FA2000002481) or hex:<bytes>. Run it only while touch is dead (it checks:
#                DRAG a finger for the first 3 s, a moving interrupt count aborts with NOT-DEAD and sends nothing), then DRAG again when told. One step per run, in
#                that order. Verdict: REVIVED, CHIP-RESPONDED, NO-CHANGE (adds touch-poke.txt). Combine with --touch-trace=dump to see the poke in the recorder.
#   --touch-scanmode  also run scripts/phone-touch-scanmode.sh (docs/08 section 2.12; NOT read-only; BLOCKED on the current image, the script exits 5 without ALLOW_UNBIND=1, see docs/08 2.18):
#                swaps the touch driver for spidev on spi0.0, sends the vendor scan-mode command A0 00 01 once, watches the
#                interrupt line for WAIT seconds, and gives spi0.0 back to fts2ba61y (adds touch-scanmode.txt).
#   --input-check  also run scripts/phone-input-check.sh (docs/08 section 2.17; READ-ONLY, runs early): the evdev / BTF /
#                taint lines of dmesg, /proc/bus/input/devices, the FTS2BA61Y touch driver binding and input device, and the
#                power / volume key devices, with a verdict line (EVDEV, BTF, TOUCH, KEYS); healthy is EVDEV=loaded BTF=none
#                TOUCH=ok KEYS=ok (adds input-check.txt).
#   --sleep-probe  also run scripts/phone-sleep-probe.sh (docs/08 section 2.15; READ-ONLY, runs early): power / cpuidle / wakeup-source configuration, the kernel-log timeline of
#                suspend and resume, runtime PM of the display / GPU / storage, this boot's journal lines about suspend / power key / idle / powerdevil, the sleep
#                configuration. Run it AFTER a slow wake and BEFORE rebooting (a reboot loses the kernel log; the journal only if it is volatile) (adds sleep-probe.txt).
# Env:  PHONE=172.16.42.1  PHONE_USER=user  WAIT_PING=240 (seconds to wait for the USB network)  DM1Q_GPU_FW=<firmware dir for --gpu-powerup>
#
# What it does on the phone: only reads (plus module loads and the temporary modprobe blacklist), writes
# under /tmp/dm1q-collect (probe.txt from scripts/phone-wlan-probe.sh, dmesg.txt, journal-kernel.txt,
# regulator_summary.txt, gpio.txt[, reload.txt, regdump*.txt]), as root through one sudo call per login.
# Everything shown on the terminal during the collection is also kept in session.log on the PC.
set -u
LABEL=""; REBOOT=0; RELOAD=0; REGDUMP=""; FRESH=0; TOUCH=0; DISPLAY_PROBE=0; DRM_TEST=0; BACKLIGHT=0; PLASMA_PRE=0; APKNET=0; APK_HTTPS=0; PLASMA_INSTALL=0; PLASMA_START=''; PLASMA_KEEP=0; PLASMA_PROFILE=default; SIGILL_CORE=0; GPU_PROBE=0; GPU_POWERUP=''; PAM_PROBE=0; PAM_FIX=''; BOOT_SETUP=''; TOUCH_WATCH=''; TOUCH_SW=''; TOUCH_RECOVER=0; TOUCH_TRACE=''; SLEEP_PROBE=0; LOAD_PROBE=0; INPUT_CHECK=0; TOUCH_SCANMODE=0; TOUCH_PM=0; TOUCH_POKE=''
for a in "$@"; do
	case "$a" in
	--reboot) REBOOT=1 ;;
	--reload) RELOAD=1 ;;
	--regdump) REGDUMP=load ;;
	--regdump=idle|--regdump=load|--regdump=reload) REGDUMP="${a#--regdump=}" ;;
	--fresh) FRESH=1 ;;
	--touch) TOUCH=1 ;;
	--display) DISPLAY_PROBE=1 ;;
	--drm-test) DRM_TEST=1 ;;
	--backlight) BACKLIGHT=1 ;;
	--plasma-preflight) PLASMA_PRE=1 ;;
	--apknet) APKNET=1 ;;
	--apk-https) APK_HTTPS=1 ;;
	--plasma-install) PLASMA_INSTALL=1 ;;
	--plasma-start) PLASMA_START=240 ;;
	--plasma-start=*) PLASMA_START="${a#--plasma-start=}"; case "$PLASMA_START" in ''|*[!0-9]*) echo "--plasma-start=SECONDS needs a number" >&2; exit 2 ;; esac ;;
	--plasma-keep) PLASMA_KEEP=1 ;;
	--plasma-profile=*) PLASMA_PROFILE="${a#--plasma-profile=}"; case "$PLASMA_PROFILE" in default|software|softpipe) ;; *) echo "--plasma-profile must be default, software or softpipe" >&2; exit 2 ;; esac ;;
	--sigill-core) SIGILL_CORE=1 ;;
	--gpu) GPU_PROBE=1 ;;
	--pam) PAM_PROBE=1 ;;
	--pam-fix) PAM_FIX=apply ;;
	--pam-fix=*) PAM_FIX="${a#--pam-fix=}"; case "$PAM_FIX" in check|undo) ;; *) echo "--pam-fix takes no value, =check or =undo" >&2; exit 2 ;; esac ;;
	--gpu-powerup=*) GPU_POWERUP="${a#--gpu-powerup=}"; case "$GPU_POWERUP" in sqe-gmu|full) ;; *) echo "--gpu-powerup must be sqe-gmu or full" >&2; exit 2 ;; esac ;;
	--boot-setup=*) BOOT_SETUP="${a#--boot-setup=}"; case "$BOOT_SETUP" in check|gpu-fw|undo-gpu-fw|plasma|undo-plasma) ;; *) echo "--boot-setup must be check, gpu-fw, undo-gpu-fw, plasma or undo-plasma" >&2; exit 2 ;; esac ;;
	--touch-watch) TOUCH_WATCH=45 ;;
	--touch-watch=*) TOUCH_WATCH="${a#--touch-watch=}"; case "$TOUCH_WATCH" in ''|*[!0-9]*) echo "--touch-watch=SECONDS needs a number (5..600)" >&2; exit 2 ;; esac; { [ "$TOUCH_WATCH" -ge 5 ] && [ "$TOUCH_WATCH" -le 600 ]; } || { echo "--touch-watch=SECONDS must be 5..600" >&2; exit 2; } ;;
	--touch-sleepwake) TOUCH_SW=20 ;;
	--touch-sleepwake=*) TOUCH_SW="${a#--touch-sleepwake=}"; case "$TOUCH_SW" in ''|*[!0-9]*) echo "--touch-sleepwake=SECONDS needs a number (15..600)" >&2; exit 2 ;; esac; { [ "$TOUCH_SW" -ge 15 ] && [ "$TOUCH_SW" -le 600 ]; } || { echo "--touch-sleepwake=SECONDS must be 15..600" >&2; exit 2; } ;;
	--touch-recover) TOUCH_RECOVER=1 ;;
	--touch-trace=*) TOUCH_TRACE="${a#--touch-trace=}"; case "$TOUCH_TRACE" in arm|dump|disarm) ;; *) echo "--touch-trace must be arm, dump or disarm" >&2; exit 2 ;; esac ;;
	--sleep-probe) SLEEP_PROBE=1 ;;
	--input-check) INPUT_CHECK=1 ;;
	--touch-scanmode) TOUCH_SCANMODE=1 ;;
	--touch-pm) TOUCH_PM=1 ;;
	--touch-poke=*) TOUCH_POKE="${a#--touch-poke=}"
		case "$TOUCH_POKE" in
		read|senseon|scanmode|reset) ;;
		hex:*) case "${TOUCH_POKE#hex:}" in ''|*[!0-9A-Fa-f+]*) echo "--touch-poke=hex:<bytes> takes hex digits and an optional +N suffix" >&2; exit 2 ;; esac ;;
		*) echo "--touch-poke must be read, senseon, scanmode, reset or hex:<bytes>" >&2; exit 2 ;;
		esac ;;
	--load-probe) LOAD_PROBE=1 ;;
	-*) echo "unknown option $a" >&2; exit 2 ;;
	*) LABEL="$a" ;;
	esac
done
[ -n "$LABEL" ] || { sed -n '2,/^[^#]/p' "$0" | sed '$d'; exit 2; }
if [ -n "$TOUCH_SW" ] || [ "$TOUCH_RECOVER" = 1 ]; then [ -n "$TOUCH_WATCH" ] || TOUCH_WATCH=45; fi
PHONE="${PHONE:-172.16.42.1}"
PUSER="${PHONE_USER:-user}"
WAIT_PING="${WAIT_PING:-240}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
MMIO_BIN="$REPO/scripts/bin/mmio-read-aarch64"
if [ "$FRESH" = 1 ] || [ -n "$REGDUMP" ]; then
	[ -f "$MMIO_BIN" ] || { echo "no $MMIO_BIN -- run: bash scripts/build-mmio-read.sh   (needs clang + lld)"; exit 1; }
fi
SPI_BIN="$REPO/scripts/bin/spi-xfer-aarch64"
DRM_BIN="$REPO/scripts/bin/drm-fill-aarch64"
if [ "$DRM_TEST" = 1 ] || [ "$BACKLIGHT" = 1 ]; then
	[ -f "$DRM_BIN" ] || { echo "no $DRM_BIN -- run: bash scripts/build-drm-fill.sh   (needs clang + lld)"; exit 1; }
fi
if [ "$TOUCH" = 1 ] || [ "$TOUCH_SCANMODE" = 1 ]; then
	[ -f "$SPI_BIN" ] || { echo "no $SPI_BIN -- run: bash scripts/build-spi-xfer.sh   (needs clang + lld)"; exit 1; }
fi
GPU_FW="${DM1Q_GPU_FW:-$REPO/../_scratch/dm1q-gpu-fw}"
if [ -n "$GPU_POWERUP" ] || [ "$BOOT_SETUP" = gpu-fw ]; then
	[ -d "$GPU_FW/qcom" ] || { echo "no $GPU_FW/qcom -- the linux-firmware files of docs/11 section 9.2 are needed for --gpu-powerup"; exit 1; }
	[ -f "$GPU_FW/qcom/a740_sqe.fw" ] && [ -f "$GPU_FW/qcom/gmu_gen70200.bin" ] || { echo "$GPU_FW/qcom needs a740_sqe.fw and gmu_gen70200.bin"; exit 1; }
	# the phone script pins the linux-firmware hashes by default; the hashes of the set actually being pushed override them (integrity of the transfer,
	# and it lets a vendor-signed set through: DM1Q_GPU_FW=<dir with qcom/a740_sqe.fw, qcom/gmu_gen70200.bin, qcom/sm8550/a740_zap.mbn>)
	GPU_PINS="FW_SQE_SHA=$(sha256sum "$GPU_FW/qcom/a740_sqe.fw" | cut -d' ' -f1) FW_GMU_SHA=$(sha256sum "$GPU_FW/qcom/gmu_gen70200.bin" | cut -d' ' -f1)"
	if [ -f "$GPU_FW/qcom/sm8550/a740_zap.mbn" ]; then GPU_PINS="$GPU_PINS FW_ZAP_SHA=$(sha256sum "$GPU_FW/qcom/sm8550/a740_zap.mbn" | cut -d' ' -f1)"; fi
fi
if [ "$BOOT_SETUP" = gpu-fw ]; then
	[ -f "$GPU_FW/qcom/sm8550/a740_zap.mbn" ] || { echo "gpu-fw needs the phone's own signed zap shader: $GPU_FW/qcom/sm8550/a740_zap.mbn (DM1Q_GPU_FW=<the dm1q-gpu-fw-vendor-run dir of docs/11 9.8>); the generic one is refused by the secure world"; exit 1; }
	# the vendor-signed zap of docs/11 9.8; the phone script pins the same hash and would refuse anything else, this just fails early on the PC
	[ "$(sha256sum "$GPU_FW/qcom/sm8550/a740_zap.mbn" | cut -d' ' -f1)" = 60cf7ab4f3d96e0992a42560ac288c053328bda5e41b4fe5e678be94ecd7ae35 ] || { echo "$GPU_FW/qcom/sm8550/a740_zap.mbn is not the phone's own signed zap (sha256 60cf7ab4...): that is the generic one, refused by the secure world. Use DM1Q_GPU_FW=$REPO/../_scratch/dm1q-gpu-fw-vendor-run"; exit 1; }
fi
DEST="$REPO/notes/$(date +%Y-%m-%d)-$LABEL"
if [ -e "$DEST" ]; then
	n=2; while [ -e "$DEST-$n" ]; do n=$((n + 1)); done
	echo "notes dir $DEST exists (an earlier capture): writing to $DEST-$n instead"
	DEST="$DEST-$n"
fi
CP="/tmp/dm1q-ssh-$$"
SSH_OPTS=(-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o LogLevel=ERROR
          -o ControlPath="$CP" -o ConnectTimeout=10)
mkdir -p "$DEST"

push_scripts() {
	scp "${SSH_OPTS[@]}" -q "$REPO/scripts/phone-wlan-probe.sh" "$REPO/scripts/phone-ath11k-reload.sh" "$REPO/scripts/phone-mhi-regdump.sh" "$PUSER@$PHONE:/tmp/" || { echo "scp of the scripts failed"; exit 1; }
	if [ -f "$MMIO_BIN" ]; then
		scp "${SSH_OPTS[@]}" -q "$MMIO_BIN" "$PUSER@$PHONE:/tmp/mmio-read" || { echo "scp of the MMIO helper failed"; exit 1; }
	fi
	if [ "$DISPLAY_PROBE" = 1 ]; then
		scp "${SSH_OPTS[@]}" -q "$REPO/scripts/phone-display-probe.sh" "$PUSER@$PHONE:/tmp/" || { echo "scp of the display probe failed"; exit 1; }
	fi
	if [ "$GPU_PROBE" = 1 ]; then
		scp "${SSH_OPTS[@]}" -q "$REPO/scripts/phone-gpu-probe.sh" "$PUSER@$PHONE:/tmp/" || { echo "scp of the GPU probe failed"; exit 1; }
	fi
	if [ -n "$PAM_FIX" ]; then
		scp "${SSH_OPTS[@]}" -q "$REPO/scripts/phone-pam-fix.sh" "$PUSER@$PHONE:/tmp/" || { echo "scp of the PAM fix failed"; exit 1; }
	fi
	if [ -n "$BOOT_SETUP" ]; then
		scp "${SSH_OPTS[@]}" -q "$REPO/scripts/phone-boot-setup.sh" "$PUSER@$PHONE:/tmp/" || { echo "scp of the boot setup script failed"; exit 1; }
		if [ "$BOOT_SETUP" = gpu-fw ]; then
			ssh "${SSH_OPTS[@]}" "$PUSER@$PHONE" 'rm -rf /tmp/dm1q-gpu-fw; mkdir -p /tmp/dm1q-gpu-fw' || { echo "mkdir for the GPU firmware failed"; exit 1; }
			scp "${SSH_OPTS[@]}" -q -r "$GPU_FW/qcom" "$PUSER@$PHONE:/tmp/dm1q-gpu-fw/" || { echo "scp of the GPU firmware failed"; exit 1; }
		fi
	fi
	if [ "$PAM_PROBE" = 1 ]; then
		scp "${SSH_OPTS[@]}" -q "$REPO/scripts/phone-pam-probe.sh" "$PUSER@$PHONE:/tmp/" || { echo "scp of the PAM probe failed"; exit 1; }
	fi
	if [ -n "$GPU_POWERUP" ]; then
		scp "${SSH_OPTS[@]}" -q "$REPO/scripts/phone-gpu-powerup.sh" "$PUSER@$PHONE:/tmp/" || { echo "scp of the GPU power-up script failed"; exit 1; }
		ssh "${SSH_OPTS[@]}" "$PUSER@$PHONE" 'rm -rf /tmp/dm1q-gpu-fw; mkdir -p /tmp/dm1q-gpu-fw' || { echo "mkdir for the GPU firmware failed"; exit 1; }
		scp "${SSH_OPTS[@]}" -q -r "$GPU_FW/qcom" "$PUSER@$PHONE:/tmp/dm1q-gpu-fw/" || { echo "scp of the GPU firmware failed"; exit 1; }
	fi
	if [ "$SIGILL_CORE" = 1 ]; then
		scp "${SSH_OPTS[@]}" -q "$REPO/scripts/phone-sigill-core.sh" "$PUSER@$PHONE:/tmp/" || { echo "scp of the SIGILL core script failed"; exit 1; }
	fi
	if [ -n "$PLASMA_START" ]; then
		scp "${SSH_OPTS[@]}" -q "$REPO/scripts/phone-plasma-start.sh" "$PUSER@$PHONE:/tmp/" || { echo "scp of the Plasma start script failed"; exit 1; }
	fi
	if [ "$PLASMA_INSTALL" = 1 ]; then
		scp "${SSH_OPTS[@]}" -q "$REPO/scripts/phone-plasma-install.sh" "$PUSER@$PHONE:/tmp/" || { echo "scp of the Plasma install script failed"; exit 1; }
	fi
	if [ "$APK_HTTPS" = 1 ]; then
		scp "${SSH_OPTS[@]}" -q "$REPO/scripts/phone-apk-https.sh" "$PUSER@$PHONE:/tmp/" || { echo "scp of the apk https script failed"; exit 1; }
	fi
	if [ "$APKNET" = 1 ]; then
		scp "${SSH_OPTS[@]}" -q "$REPO/scripts/phone-apknet-diag.sh" "$PUSER@$PHONE:/tmp/" || { echo "scp of the apk network diagnosis failed"; exit 1; }
	fi
	if [ "$PLASMA_PRE" = 1 ]; then
		scp "${SSH_OPTS[@]}" -q "$REPO/scripts/phone-plasma-preflight.sh" "$PUSER@$PHONE:/tmp/" || { echo "scp of the Plasma preflight failed"; exit 1; }
	fi
	if [ "$DRM_TEST" = 1 ]; then
		scp "${SSH_OPTS[@]}" -q "$REPO/scripts/phone-drm-test.sh" "$PUSER@$PHONE:/tmp/" || { echo "scp of the DRM test failed"; exit 1; }
		scp "${SSH_OPTS[@]}" -q "$DRM_BIN" "$PUSER@$PHONE:/tmp/drm-fill" || { echo "scp of drm-fill failed"; exit 1; }
	fi
	if [ "$BACKLIGHT" = 1 ]; then
		scp "${SSH_OPTS[@]}" -q "$REPO/scripts/phone-backlight-test.sh" "$PUSER@$PHONE:/tmp/" || { echo "scp of the backlight test failed"; exit 1; }
		scp "${SSH_OPTS[@]}" -q "$DRM_BIN" "$PUSER@$PHONE:/tmp/drm-fill" || { echo "scp of drm-fill failed"; exit 1; }
	fi
	if [ "$TOUCH" = 1 ] || [ "$TOUCH_SCANMODE" = 1 ]; then
		scp "${SSH_OPTS[@]}" -q "$REPO/scripts/phone-touch-spi-probe.sh" "$PUSER@$PHONE:/tmp/" || { echo "scp of the touch probe failed"; exit 1; }
		scp "${SSH_OPTS[@]}" -q "$SPI_BIN" "$PUSER@$PHONE:/tmp/spi-xfer" || { echo "scp of the SPI helper failed"; exit 1; }
	fi
	if [ -n "$TOUCH_WATCH" ]; then
		scp "${SSH_OPTS[@]}" -q "$REPO/scripts/phone-touch-watch.sh" "$PUSER@$PHONE:/tmp/" || { echo "scp of the touch watch script failed"; exit 1; }
	fi
	if [ -n "$TOUCH_TRACE" ]; then
		scp "${SSH_OPTS[@]}" -q "$REPO/scripts/phone-touch-trace.sh" "$PUSER@$PHONE:/tmp/" || { echo "scp of the touch trace script failed"; exit 1; }
	fi
	if [ "$LOAD_PROBE" = 1 ]; then
		scp "${SSH_OPTS[@]}" -q "$REPO/scripts/phone-load-probe.sh" "$PUSER@$PHONE:/tmp/" || { echo "scp of the load probe failed"; exit 1; }
	fi
	if [ "$SLEEP_PROBE" = 1 ]; then
		scp "${SSH_OPTS[@]}" -q "$REPO/scripts/phone-sleep-probe.sh" "$PUSER@$PHONE:/tmp/" || { echo "scp of the sleep probe failed"; exit 1; }
	fi
	if [ "$INPUT_CHECK" = 1 ]; then
		scp "${SSH_OPTS[@]}" -q "$REPO/scripts/phone-input-check.sh" "$PUSER@$PHONE:/tmp/" || { echo "scp of the input check failed"; exit 1; }
	fi
	if [ "$TOUCH_SCANMODE" = 1 ]; then
		scp "${SSH_OPTS[@]}" -q "$REPO/scripts/phone-touch-scanmode.sh" "$PUSER@$PHONE:/tmp/" || { echo "scp of the scan-mode probe failed"; exit 1; }
	fi
	if [ "$TOUCH_PM" = 1 ]; then
		scp "${SSH_OPTS[@]}" -q "$REPO/scripts/phone-touch-pm.sh" "$PUSER@$PHONE:/tmp/" || { echo "scp of the touch PM probe failed"; exit 1; }
	fi
	if [ -n "$TOUCH_POKE" ]; then
		scp "${SSH_OPTS[@]}" -q "$REPO/scripts/phone-touch-poke.sh" "$PUSER@$PHONE:/tmp/" || { echo "scp of the touch poke script failed"; exit 1; }
	fi
}
wait_up() {
	local t=0
	echo "waiting up to ${WAIT_PING}s for the phone at $PHONE (connect the PC to the phone's USB network if it does not switch by itself) ..."
	until ping -c1 -W1 "$PHONE" >/dev/null 2>&1; do
		sleep 2; t=$((t + 3)); [ $((t % 30)) -lt 3 ] && echo "  ... ${t}s"
		if [ "$t" -ge "$WAIT_PING" ]; then
			echo "no answer from $PHONE after ${WAIT_PING}s: the phone did not reach userspace (or the USB network is not up)."
			echo "Reboot it to recovery and ask Claude to pull the stage-1 log from the dtbo partition."
			exit 1
		fi
	done
	echo "phone answers after ~${t}s -- userspace is up"
	t=0; until timeout 3 bash -c "exec 3<>/dev/tcp/$PHONE/22" 2>/dev/null; do
		sleep 2; t=$((t + 3)); [ "$t" -ge 90 ] && { echo "ssh port 22 never opened"; exit 1; }
	done
}
login() {
	echo "== log in (password prompt; the connection is reused afterwards) =="
	ssh "${SSH_OPTS[@]}" -o ControlMaster=yes -o ControlPersist=900 -fN "$PUSER@$PHONE" || { echo "ssh login failed"; exit 1; }
}
trap 'ssh "${SSH_OPTS[@]}" -O exit "$PUSER@$PHONE" 2>/dev/null' EXIT

if [ "$REBOOT" = 1 ]; then
	[ "$(adb get-state 2>/dev/null || true)" = recovery ] || echo "note: adb does not see the phone in recovery; trying the reboot anyway"
	echo "adb reboot ..."; adb reboot || true
	sleep 5
fi

wait_up
login
push_scripts

if [ "$FRESH" = 1 ]; then
	echo "== phase 1: blacklist ath11k_pci for the next boot and reboot the phone (sudo asks for the password) =="
	ssh "${SSH_OPTS[@]}" -t "$PUSER@$PHONE" "sudo sh -c \"echo 'blacklist ath11k_pci' > /etc/modprobe.d/zz-dm1q-test.conf; sync; nohup sh -c 'sleep 2; reboot' >/dev/null 2>&1 &\"" 2>&1 | tee "$DEST/session-phase1.log"
	ssh "${SSH_OPTS[@]}" -O exit "$PUSER@$PHONE" 2>/dev/null
	echo "waiting for the phone to go down ..."
	t=0; while ping -c1 -W1 "$PHONE" >/dev/null 2>&1; do sleep 1; t=$((t + 1)); [ "$t" -ge 90 ] && { echo "the phone did not go down"; exit 1; }; done
	echo "down after ~${t}s; waiting for it to come back (a normal boot reaches userspace in ~15 s)"
	wait_up
	login
	push_scripts
fi

BODY='rm -f /etc/modprobe.d/zz-dm1q-test.conf
chmod +x /tmp/mmio-read /tmp/spi-xfer 2>/dev/null
rm -rf /tmp/dm1q-collect; mkdir -p /tmp/dm1q-collect
mount | grep -q /sys/kernel/debug || mount -t debugfs none /sys/kernel/debug'
if [ "$FRESH" = 1 ]; then
	BODY="$BODY
sh /tmp/phone-wlan-probe.sh 2>&1 | tee /tmp/dm1q-collect/probe-idle.txt
sh /tmp/phone-mhi-regdump.sh idle 2>&1 | tee /tmp/dm1q-collect/regdump-idle.txt
sh /tmp/phone-mhi-regdump.sh load 2>&1 | tee /tmp/dm1q-collect/regdump-load.txt"
elif [ -n "$REGDUMP" ]; then
	BODY="$BODY
sh /tmp/phone-mhi-regdump.sh $REGDUMP 2>&1 | tee /tmp/dm1q-collect/regdump.txt"
fi
if [ "$LOAD_PROBE" = 1 ]; then
	BODY="$BODY
sh /tmp/phone-load-probe.sh 2>&1 | tee /tmp/dm1q-collect/load-probe.txt"
fi
if [ "$SLEEP_PROBE" = 1 ]; then
	BODY="$BODY
sh /tmp/phone-sleep-probe.sh 2>&1 | tee /tmp/dm1q-collect/sleep-probe.txt"
fi
if [ "$INPUT_CHECK" = 1 ]; then
	BODY="$BODY
sh /tmp/phone-input-check.sh 2>&1 | tee /tmp/dm1q-collect/input-check.txt"
fi
if [ "$TOUCH_SCANMODE" = 1 ]; then
	BODY="$BODY
sh /tmp/phone-touch-scanmode.sh 2>&1 | tee /tmp/dm1q-collect/touch-scanmode.txt"
fi
if [ "$TOUCH_PM" = 1 ]; then
	BODY="$BODY
sh /tmp/phone-touch-pm.sh 2>&1 | tee /tmp/dm1q-collect/touch-pm.txt"
fi
if [ -n "$TOUCH_POKE" ]; then
	BODY="$BODY
STEP=$TOUCH_POKE sh /tmp/phone-touch-poke.sh 2>&1 | tee /tmp/dm1q-collect/touch-poke.txt"
fi
if [ -n "$TOUCH_TRACE" ]; then
	BODY="$BODY
OUT=/tmp/dm1q-collect/touch-trace-raw.txt BUF_KB=${DM1Q_TRACE_BUF_KB:-12288} sh /tmp/phone-touch-trace.sh $TOUCH_TRACE 2>&1 | tee /tmp/dm1q-collect/touch-trace.txt"
fi
if [ -n "$TOUCH_WATCH" ]; then
	BODY="$BODY
DUR=$TOUCH_WATCH PHASE_B=${TOUCH_SW:-0} RECOVER=$TOUCH_RECOVER sh /tmp/phone-touch-watch.sh 2>&1 | tee /tmp/dm1q-collect/touch-watch.txt"
fi
if [ "$TOUCH" = 1 ]; then
	BODY="$BODY
sh /tmp/phone-touch-spi-probe.sh 2>&1 | tee /tmp/dm1q-collect/touch.txt"
fi
if [ "$DISPLAY_PROBE" = 1 ]; then
	BODY="$BODY
sh /tmp/phone-display-probe.sh 2>&1 | tee /tmp/dm1q-collect/display.txt"
fi
if [ "$GPU_PROBE" = 1 ]; then
	BODY="$BODY
sh /tmp/phone-gpu-probe.sh 2>&1 | tee /tmp/dm1q-collect/gpu.txt"
fi
if [ -n "$PAM_FIX" ]; then
	BODY="$BODY
sh /tmp/phone-pam-fix.sh $PAM_FIX 2>&1 | tee /tmp/dm1q-collect/pam-fix.txt"
fi
if [ -n "$BOOT_SETUP" ]; then
	if [ "$BOOT_SETUP" = gpu-fw ]; then
		BODY="$BODY
rm -rf /root/dm1q-gpu-fw && mkdir -p /root/dm1q-gpu-fw && cp -r /tmp/dm1q-gpu-fw/qcom /root/dm1q-gpu-fw/"
	fi
	BODY="$BODY
sh /tmp/phone-boot-setup.sh $BOOT_SETUP 2>&1 | tee /tmp/dm1q-collect/boot-setup.txt"
fi
if [ "$PAM_PROBE" = 1 ]; then
	BODY="$BODY
sh /tmp/phone-pam-probe.sh 2>&1 | tee /tmp/dm1q-collect/pam.txt"
fi
if [ -n "$GPU_POWERUP" ]; then
	BODY="$BODY
rm -rf /root/dm1q-gpu-fw && mkdir -p /root/dm1q-gpu-fw && cp -r /tmp/dm1q-gpu-fw/qcom /root/dm1q-gpu-fw/
$GPU_PINS sh /tmp/phone-gpu-powerup.sh $GPU_POWERUP 2>&1 | tee /tmp/dm1q-collect/gpu-powerup.txt"
fi
if [ -n "$PLASMA_START" ]; then
	BODY="$BODY
DUR=$PLASMA_START KEEP=$PLASMA_KEEP PROFILE=$PLASMA_PROFILE sh /tmp/phone-plasma-start.sh 2>&1 | tee /tmp/dm1q-collect/plasma-start.txt"
fi
if [ "$SIGILL_CORE" = 1 ]; then
	BODY="$BODY
sh /tmp/phone-sigill-core.sh 2>&1 | tee /tmp/dm1q-collect/sigill-core.txt"
fi
if [ "$PLASMA_INSTALL" = 1 ]; then
	BODY="$BODY
sh /tmp/phone-plasma-install.sh 2>&1 | tee /tmp/dm1q-collect/plasma-install.txt"
fi
if [ "$APK_HTTPS" = 1 ]; then
	BODY="$BODY
sh /tmp/phone-apk-https.sh 2>&1 | tee /tmp/dm1q-collect/apk-https.txt"
fi
if [ "$APKNET" = 1 ]; then
	BODY="$BODY
sh /tmp/phone-apknet-diag.sh 2>&1 | tee /tmp/dm1q-collect/apknet.txt"
fi
if [ "$PLASMA_PRE" = 1 ]; then
	BODY="$BODY
sh /tmp/phone-plasma-preflight.sh 2>&1 | tee /tmp/dm1q-collect/plasma-preflight.txt"
fi
if [ "$DRM_TEST" = 1 ]; then
	BODY="$BODY
sh /tmp/phone-drm-test.sh /tmp/drm-fill 2>&1 | tee /tmp/dm1q-collect/drm-test.txt"
fi
if [ "$BACKLIGHT" = 1 ]; then
	BODY="$BODY
sh /tmp/phone-backlight-test.sh /tmp/drm-fill 2>&1 | tee /tmp/dm1q-collect/backlight.txt"
fi
BODY="$BODY
sh /tmp/phone-wlan-probe.sh 2>&1 | tee /tmp/dm1q-collect/probe.txt
dmesg > /tmp/dm1q-collect/dmesg.txt 2>&1
journalctl -k -b --no-pager > /tmp/dm1q-collect/journal-kernel.txt 2>&1
cat /sys/kernel/debug/regulator/regulator_summary > /tmp/dm1q-collect/regulator_summary.txt 2>&1
cat /sys/kernel/debug/gpio > /tmp/dm1q-collect/gpio.txt 2>&1"
if [ "$RELOAD" = 1 ]; then
	BODY="$BODY
sh /tmp/phone-ath11k-reload.sh 2>&1 | tee /tmp/dm1q-collect/reload.txt
dmesg > /tmp/dm1q-collect/dmesg-after-reload.txt 2>&1"
fi
BODY="$BODY
chmod -R a+rX /tmp/dm1q-collect
ls -la /tmp/dm1q-collect"

RMSG=""
[ "$RELOAD" = 1 ] && RMSG="; the reload step takes ~30 s"
[ -n "$REGDUMP" ] && RMSG="$RMSG; the regdump step takes ~40 s"
[ "$TOUCH" = 1 ] && RMSG="$RMSG; the touch probe takes ~10 s"
[ -n "$TOUCH_WATCH" ] && RMSG="$RMSG; THE TOUCH WATCH RUNS FIRST: DRAG A FINGER CONTINUOUSLY ON THE PHONE SCREEN for the whole ${TOUCH_WATCH} s window, even if touch looks dead${TOUCH_SW:+; then, when it says so, press the POWER KEY (screen off), wait 5 s, press it again (screen on) and keep dragging for ${TOUCH_SW} s}${TOUCH_RECOVER:+; if no events came, up to two recovery experiments of ~25 s each follow (keep dragging)}"
[ "$LOAD_PROBE" = 1 ] && RMSG="$RMSG; the load probe is read-only and takes ~10 s (it is only useful while the phone is hot or laggy)"
[ "$SLEEP_PROBE" = 1 ] && RMSG="$RMSG; the sleep probe is read-only and takes a few seconds (run it before rebooting the phone, after a slow wake)"
[ "$TOUCH_TRACE" = arm ] && RMSG="$RMSG; THE TOUCH RECORDER ARM asks you to DRAG A FINGER on the phone screen for 6 s (twice if touch is dead: it then revives it with a rebind)"
[ "$TOUCH_TRACE" = dump ] && RMSG="$RMSG; the touch recorder dump is read-only and takes a few seconds"
[ -n "$PLASMA_START" ] && RMSG="$RMSG; THE PLASMA MOBILE FIRST START runs ${PLASMA_START}s: WATCH THE PHONE SCREEN and use it (touch, keys, brightness slider, keyboard); the UI is stopped again at the end unless --plasma-keep"
[ "$PLASMA_INSTALL" = 1 ] && RMSG="$RMSG; THE PLASMA MOBILE INSTALL takes 15-40 min and changes the system: stay on the USB network, do NOT reboot the phone into the system afterwards (TWRP + fix-phone-initramfs-extra.sh first)"
[ "$APK_HTTPS" = 1 ] && RMSG="$RMSG; the apk https step downloads ~7 MB of indexes and runs a simulation (~1-2 min); it edits /etc/apk/repositories"
[ "$APKNET" = 1 ] && RMSG="$RMSG; the apk network diagnosis takes ~2 min (it fetches index files and runs apk update -vv)"
[ "$PLASMA_PRE" = 1 ] && RMSG="$RMSG; the Plasma preflight takes ~1 min (apk update + simulation need the phone's Wi-Fi internet)"
[ "$GPU_PROBE" = 1 ] && RMSG="$RMSG; the GPU probe is read-only and takes a few seconds"
[ -n "$BOOT_SETUP" ] && RMSG="$RMSG; THE BOOT SETUP (mode $BOOT_SETUP) writes plain files and systemd units on the phone (no apk, nothing is started or stopped), a few seconds"
[ "$BOOT_SETUP" = gpu-fw ] && RMSG="$RMSG; after the NEXT reboot wait 2 minutes before rebooting again (the boot-loop breaker treats a boot shorter than that as a failed one)"
[ -n "$GPU_POWERUP" ] && RMSG="$RMSG; THE GPU POWER-UP TEST (mode $GPU_POWERUP) powers the GPU up once, ~15 s; if the phone resets, let it reboot (it comes back normally)"
[ "$DRM_TEST" = 1 ] && RMSG="$RMSG; the DRM pattern test takes ~35 s: WATCH THE PHONE SCREEN"
[ "$BACKLIGHT" = 1 ] && RMSG="$RMSG; the backlight sweep takes ~1 min: WATCH THE PHONE SCREEN (white, getting dimmer)"
[ "$FRESH" = 1 ] && RMSG="; the idle + load steps take ~1.5 min"
echo "== collecting on the phone (sudo asks for the password once$RMSG) =="
# everything shown is also kept in session.log, so a hang on the phone does not lose the partial output
ssh "${SSH_OPTS[@]}" -t "$PUSER@$PHONE" "sudo sh -c \"$BODY\"" 2>&1 | tee "$DEST/session.log"

echo "== pulling the files =="
scp "${SSH_OPTS[@]}" -q "$PUSER@$PHONE:/tmp/dm1q-collect/*" "$DEST/" || { echo "scp of the results failed (see $DEST/session.log for what was printed)"; exit 1; }
ssh "${SSH_OPTS[@]}" "$PUSER@$PHONE" 'rm -rf /tmp/dm1q-collect /tmp/phone-wlan-probe.sh /tmp/phone-ath11k-reload.sh /tmp/phone-mhi-regdump.sh /tmp/mmio-read /tmp/phone-touch-spi-probe.sh /tmp/spi-xfer /tmp/phone-display-probe.sh /tmp/phone-drm-test.sh /tmp/phone-backlight-test.sh /tmp/drm-fill /tmp/phone-plasma-preflight.sh /tmp/phone-apknet-diag.sh /tmp/phone-apk-https.sh /tmp/phone-plasma-install.sh /tmp/phone-plasma-start.sh /tmp/phone-sigill-core.sh /tmp/phone-gpu-probe.sh /tmp/phone-gpu-powerup.sh /tmp/phone-pam-probe.sh /tmp/phone-pam-fix.sh /tmp/phone-boot-setup.sh /tmp/phone-touch-watch.sh /tmp/phone-touch-trace.sh /tmp/phone-sleep-probe.sh /tmp/phone-input-check.sh /tmp/phone-touch-scanmode.sh /tmp/phone-touch-pm.sh /tmp/phone-touch-poke.sh /tmp/phone-load-probe.sh /tmp/dm1q-gpu-fw' 2>/dev/null || true
for f in "$DEST"/*; do tr -d '\r' < "$f" > "$f.tmp" && mv "$f.tmp" "$f"; done
ls -la "$DEST"
echo
echo "done. Saved in $DEST"
echo "You can reconnect the PC to the internet now and tell Claude."
