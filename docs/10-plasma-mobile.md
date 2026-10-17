# 10 - Plasma Mobile on the dm1q

Started 2026-10-17 (handoff `2026-10-17-handoff-plasma-mobile.md`). Goal: Plasma Mobile on the native panel, first with
software rendering (llvmpipe), then GPU (Adreno 740, see the plan in the handoff; findings go to `docs/11-gpu-bringup.md`).

Labels: **FACT** = seen in a file, a command output or on hardware; **INFERENCE** = reasoned, not verified; **TODO** = not done.

## 1. How this work is run (constraint)

- FACT (Baraa, 2026-10-17): only Baraa can ssh to the phone. While the PC is on the phone's USB network it has no internet,
  and the chat session on the PC drops. So the chat cannot run phone commands itself; anything phone-side is a script
  that Baraa runs (`scripts/collect-phone-state.sh <label> --<flag>`), which saves its output under `notes/<date>-<label>/`
  for the chat to read from disk after he reconnects to the internet.
- FACT: on 2026-10-17 the PC had `eno1 192.168.137.159/24` (internet) and an unconfigured `enp9s0u3` (the phone's USB
  gadget interface, no address). A TCP port-22 sweep of 192.168.137.0/24 found no ssh host, so the phone is not reachable
  from the PC over the home LAN either (phone off, other subnet, or sshd not listening on WLAN). INFERENCE: the "ssh to the
  phone's WLAN IP while the PC stays online" idea (handoff rule 5) is only usable if Baraa gives the phone's WLAN IP and the
  PC and phone share a subnet; not assumed.

## 2. What `postmarketos-ui-plasma-mobile` is today (pmaports `main`, HEAD 8bd6c16, 2026-10-17)

FACT, read from a fresh sparse clone of `gitlab.postmarketos.org/postmarketOS/pmaports` (the local pmbootstrap cache was at
1c99c07, 2026-09-13, five weeks old; the UI package is `pkgver=6 pkgrel=10`, `arch="noarch !armhf !x86"`,
`options="pmb:drm pmb:default-systemd pmb:support-systemd"`).

- `postmarketos-ui-plasma-mobile` depends on: `callaudiod feedbackd plasma-mobile postmarketos-base-ui-plasma
  postmarketos-usb-moded udisks2`. Subpackage `-openrc` (install_if openrc) adds `modemmanager-openrc openrc tinydm
  tinydm-openrc`. `-web` adds `angelfish`; `-extras`, `-extras-web` are optional meta packages. `_pmb_recommends` (pulled by
  pmbootstrap only, not by plain `apk add`): dolphin kclock krecorder kweather plasma-camera plasma-dialer
  plasma-mobile-sounds plasma-phonebook qmlkonsole spacebar ttyescape vvmplayer.
- `postmarketos-base-ui-plasma` depends on: `bluedevil breeze geoclue iio-sensor-proxy kunifiedpush kscreen kwallet-pam
  modemmanager polkit-kde-agent-1 postmarketos-base-ui postmarketos-base-ui-audio postmarketos-base-ui-networkmanager
  powerdevil urfkill xdg-desktop-portal-kde xorg-server`. Openrc subpackage: `bluez-openrc elogind elogind-openrc
  iio-sensor-proxy-openrc openrc networkmanager-openrc urfkill-openrc`. Systemd subpackage: `polkit-systemd`.
- `postmarketos-base-ui` (pkgver 62) depends on: `avahi chrony dbus haveged nftables pipewire pipewire-spa-libcamera
  pipewire-webrtc postmarketos-artwork-icons postmarketos-base postmarketos-bootsplash-virtual shadow tzdata util-linux
  wireless-regdb wireplumber xdg-utils`, plus a Wi-Fi backend (`postmarketos-base-ui-wifi`: wpa_supplicant has provider
  priority 100, iwd 90, so wpa_supplicant wins) and an audio backend (pipewire 90 vs pulseaudio 100, so pulseaudio would
  win unless pipewire is chosen; pmbootstrap normally selects via `_pmb_select`, plain `apk add` picks by priority:
  TODO check with the simulation what is chosen).
- The display manager on openrc is `tinydm` (+ `tinydm-openrc`), session launched through tinydm's session files.
  INFERENCE: on systemd the UI package relies on the systemd user/session units instead (`pmb:default-systemd` means a
  fresh pmbootstrap install of this UI now defaults to systemd).

### Risks this dependency list creates (FACT = the dependency exists; the consequence is INFERENCE)

1. **`postmarketos-usb-moded`** is a hard dependency. INFERENCE: it manages the USB gadget and may replace the ncm
   gadget that gives Baraa ssh at 172.16.42.1 (the only phone shell he has). Check `/etc/conf.d`/`usb-moded` config after
   the install and BEFORE the next reboot; keep the Wi-Fi ssh path (or adb in TWRP) as the fallback.
2. **NetworkManager takes over networking** (`postmarketos-base-ui-networkmanager`). INFERENCE: it can fight the current
   wlan0 setup (wpa_supplicant/iwd/ifupdown, whichever the rootfs uses now); the Wi-Fi session that `apk add` itself runs
   over must survive the install. Services are only added to runlevels on install (openrc), not started, so the running
   link should survive until reboot; verify with the preflight what manages wlan0 today.
3. **mkinitfs triggers (docs/06 rule 3)**: the packages install into `/usr/lib/udev` (`50-udmabuf.rules`,
   `90-iio-sensor-proxy-proximity-sensor-enable.rules`) and `/usr/share/mkinitfs/files/10-wireless-regdb.files`,
   so the install WILL regenerate `/boot/initramfs-extra`. Run `scripts/fix-phone-initramfs-extra.sh` from TWRP before the
   first reboot after the install. The full trigger list is `cat /lib/apk/db/triggers`.
4. `xorg-server` is a hard dependency of `postmarketos-base-ui-plasma` (needed for XWayland); it brings `xf86-video-fbdev`
   and libinput drivers via `postmarketos-base-ui-x11`. INFERENCE: harmless, but it adds size.
5. Init system unknown: the UI package has separate openrc and systemd subpackages, so which init the current rootfs runs
   decides which display-manager path applies (preflight section 2).

## 3. Preflight (read-only) - run this first

Script: `scripts/phone-plasma-preflight.sh` (phone-side, POSIX sh) with PC-side test `scripts/test-phone-plasma-preflight.sh`
(FACT: passes under bash; `dash` and busybox `ash` are not installed on the PC, so the dash run was skipped;
`shellcheck -s sh` reports only SC2012 info notes and `bash --posix -n` accepts it).
It is wired into the collector:

    bash scripts/collect-phone-state.sh plasma-preflight --plasma-preflight

Run it with the PC on the phone's USB network (phone must have Wi-Fi internet for the `apk update` step). It saves
`notes/<date>-plasma-preflight/plasma-preflight.txt` plus the usual probe/dmesg files. Everything it does is read-only except
`apk update` (index cache only, no triggers); installation is only simulated (`apk add --simulate`; the test asserts this).
It prints no SSIDs, MACs or passwords (connection files are only counted), but the notes dir stays uncommitted anyway.

What it records: kernel, os-release, init system and runlevels, free space, installed package count, repositories, apk
triggers, network managers/processes, USB gadget config, deviceinfo keys, which UI/session/graphics packages are installed,
DRM/backlight/input/fb state, users and groups, loginctl, `apk policy` of the key packages, the simulated install list (with
counts), load and temperatures.

## 4. Install route (decision pending the preflight)

INFERENCE, recommended: route A, `apk add postmarketos-ui-plasma-mobile` on the running phone over Wi-Fi (heavy but
no re-flash of the rootfs, no reinstall of the module set; docs/06 rule 6: the rootfs is the only copy of the module set),
then the docs/06 rule 3 fix from TWRP before any reboot, then a MANUAL session start from ssh with logging; display
manager autostart only after the session is stable by hand. Route B (rebuild the rootfs with `pmbootstrap install`) is
rejected unless the preflight shows a blocker for A (e.g. not enough space, a conflicting init system, a package conflict
in the simulation).

Decision gates after reading the preflight output:

| Check | Pass | If not |
|---|---|---|
| free space on `/` (simulation says how much) | several GB free (rootfs grew to ~222 GB) | n/a, expected fine |
| simulation has no conflicts/errors | clean install list | read the error; maybe pin the wifi/audio backend |
| usb-moded vs current USB gadget | understood and a fallback ready | decide before the install whether to mask usb-moded |
| what manages wlan0 | known | plan how NM and the current manager coexist |
| init system | known (openrc or systemd) | pick tinydm path or systemd units accordingly |

## 5. Status

- DONE: docs read; pmaports package definitions read against current `main`; preflight script + test + collector flag.
- TODO: Baraa runs the preflight; read it; record results in this doc; choose route; the install; manual session start;
  verification (touch, keys, backlight, keyboard, Wi-Fi in the UI, idle load/temperature); persistence in the device package;
  README / docs/02 / docs/06 / Project memory updates; GPU plan (`docs/11-gpu-bringup.md`).
