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
2. **NetworkManager takes over networking** (`postmarketos-base-ui-networkmanager`). Preflight (section 5): NetworkManager +
   wpa_supplicant already manage wlan0, so this mostly does not apply. Original INFERENCE: it can fight the current
   wlan0 setup (wpa_supplicant/iwd/ifupdown, whichever the rootfs uses now); the Wi-Fi session that `apk add` itself runs
   over must survive the install. Services are only added to runlevels on install (openrc), not started, so the running
   link should survive until reboot; verify with the preflight what manages wlan0 today.
3. **mkinitfs triggers (docs/06 rule 3)**: the packages install into `/usr/lib/udev` (`50-udmabuf.rules`,
   `90-iio-sensor-proxy-proximity-sensor-enable.rules`) and `/usr/share/mkinitfs/files/10-wireless-regdb.files`,
   so the install WILL regenerate `/boot/initramfs-extra`. Run `scripts/fix-phone-initramfs-extra.sh` from TWRP before the
   first reboot after the install. The full trigger list is `cat /lib/apk/db/triggers`.
4. `xorg-server` is a hard dependency of `postmarketos-base-ui-plasma` (needed for XWayland); it brings `xf86-video-fbdev`
   and libinput drivers via `postmarketos-base-ui-x11`. INFERENCE: harmless, but it adds size.
5. ~~Init system unknown~~ resolved by the preflight: systemd (section 5), so `plasma-mobile.service`, not tinydm.

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

## 5. Preflight results (run 2026-10-17 ~17:26 local, `notes/2026-10-17-plasma-preflight/`, raw, uncommitted)

FACT unless marked. Several items in sections 2 and 4 were INFERENCE before this run and are corrected here.

- **Init is systemd** (`/sbin/init -> ../lib/systemd/systemd`), not openrc; logind is systemd-logind (sessions `1` manager and
  `c1` user for the ssh login, no seat). So the systemd path of the UI package applies: no tinydm; the session is the system
  service `plasma-mobile.service` (enabled through the `-systemd` post-install alias to `display-manager.service`), and a
  generator (`system-generators-plasma-mobile-user-override`) sets `User=`/`Group=` from `/etc/default_user`, falling back to
  uid/gid 10000 = our `user` (uid 10000). INFERENCE: `systemctl start plasma-mobile.service` from ssh is therefore the
  natural manual start (a proper logind session on a VT, no seat needed from ssh); the unit itself ships in Alpine's
  `plasma-mobile-systemd` (upstream `INSTALL_SYSTEMD_SERVICE=ON`) and has not been read yet: TODO `systemctl cat plasma-mobile.service`
  right after the install.
- Rootfs: `/dev/loop0p2` 216 GB, 203.5 GB free; 345 packages; world = alpine-baselayout apk-tools busybox device-samsung-dm1q fonts
  lang musl-utils postmarketos-base(-nofde/-systemd) postmarketos-mkinitfs postmarketos-ui-console sudo-rs + `iw` and
  `linux-firmware-ath11k` (those two carry local-file checksums in the world file, i.e. they were installed from local .apk files,
  not from a repository). RAM 6604 MB total, 9.9 GB swap, idle 295 MB used. Kernel `7.3.0-rc3`. Repositories: pmOS `main`
  and `extra-repos/systemd/main`, Alpine edge main/community/testing (all http).
- **apk cannot reach its repositories.** `apk update` failed for all five with `HTTP: unrecognized server error`, and the
  cached indexes are stale (pmOS main from 2026-10-11, systemd extra-repo 2026-10-09, Alpine edge `v20260805-*`). Wi-Fi itself is up
  (`wlan0` 192.168.1.x, NetworkManager + wpa_supplicant running), so the handoff's "apk needs the phone's internet, which Wi-Fi gives"
  was INFERENCE and is NOT confirmed. Cause unknown: diagnose with `--apknet` (section 6). Consequence: the simulation below used
  stale indexes (it picked `postmarketos-base-ui 61-r0` while pmaports `main` today has 62, `plasma-mobile 6.7.5` while Alpine
  has 6.8.0), so its package list is only indicative.
- **Simulation (stale index): 825 operations (818 installs, 7 upgrades, 0 purges), 2761.5 MiB, ending at 1163 packages.**
  Upgrades: hwdata-pci, mesa 26.2.3->26.2.4 (mesa, -gbm, -dri-gallium, -gles, -egl), libmm-glib. No errors or conflicts.
  Installs include plasma-mobile 6.7.5, kwin `99996.7.5` (from the pmOS systemd extra-repo, the `99996` epoch is that repo's
  convention), plasma-workspace, xorg-server + plasma-workspace-x11 + xf86 drivers, NetworkManager add-ons, modemmanager,
  iio-sensor-proxy, powerdevil, geoclue, kaccounts, angelfish (web), udisks2 and `postmarketos-usb-moded` (+ `-default-profile-developer`,
  `usb-moded-notify`, `umtprd`, `usb-signaller`, all with systemd units).
- **Audio backend choice (FACT in the simulation, consequence INFERENCE):** pipewire + wireplumber are already installed, but the
  simulation adds `pulseaudio`, `pulseaudio-alsa`, `pulseaudio-wireplumber`, `pulseaudio-bluez`, `postmarketos-base-ui-audio-backend-pulseaudio`
  because pulseaudio has the higher provider priority (100 vs 90). Audio does not work on this phone yet (ADSP), but pulseaudio next to
  pipewire is unwanted. Decision: pin the pipewire backend explicitly, `apk add postmarketos-base-ui-audio-backend-pipewire
  postmarketos-ui-plasma-mobile` (re-simulate to confirm).
- **Networking is already NetworkManager + wpa_supplicant** (processes `NetworkManager --no-daemon`, `wpa_supplicant -u`; 2 NM
  connection files, 1 wpa_supplicant entry, `/etc/NetworkManager/conf.d` empty, no iwd). So risk 2 of section 2 (NM taking over)
  mostly does not apply. Remaining INFERENCE: `postmarketos-base-ui-networkmanager` adds `50-random-mac.conf`, which may change the
  Wi-Fi MAC on the next connection and with it the DHCP lease/IP of the phone (192.168.1.11 now).
- **USB gadget:** `g1`, UDC `a600000.usb`, function `ncm.usb0`, `usb0` is 172.16.42.1/16. `deviceinfo_usb_network_function` is
  commented out, so the gadget is not created by the deviceinfo mechanism; INFERENCE: stage 1 (our patched init_boot) creates it.
  `postmarketos-usb-moded` 11 with the *developer* default profile is in the install list. Whether it keeps, recreates or
  breaks `g1`/ssh at 172.16.42.1 is unknown: risk 1 stays open and must be handled before the first reboot (check
  `systemctl is-enabled usb-moded` after the install; if it is enabled, decide whether to mask it).
- **apk triggers (FACT, `/lib/apk/db/triggers`):** the mkinitfs trigger covers `/lib/firmware/*`, `/usr/lib/systemd/boot`,
  `/usr/lib/udev`, `/usr/libexec/pmos-tests-initramfs`, `/usr/share/deviceinfo`, `/usr/share/kernel/*`, `/usr/share/mkinitfs-triggers`,
  `/usr/share/mkinitfs/*`, `/usr/share/plymouth`. The simulation contains many `-udev` packages (feedbackd-udev, gmobile-udev,
  modemmanager-udev, alsa-utils-udev, iio-sensor-proxy-udev, ddcutil-udev, libfprint-udev, libmtp-udev, libmbim-udev, fuse3-udev) and
  `plymouth-kcm`: **the install will regenerate `/boot/initramfs-extra`; docs/06 rule 3 applies.** Other triggers (systemd units,
  tmpfiles, sysusers, dbus, fonts, glib schemas) are normal.
- **Graphics (FACT):** `mesa-dri-gallium`, `-gbm`, `-egl`, `-gles` already installed (26.2.3-r1); `mesa-vulkan-freedreno` not.
  `/dev/dri/card1` (video, 0660) and **`/dev/dri/renderD128` (render, 0666)** both exist although there is no GPU: INFERENCE: the
  msm driver registers a render node even without an Adreno, which KWin may pick for rendering; llvmpipe/swrast then runs on top of it
  or KWin falls back; to be observed, `KWIN_DRM_DEVICES` and software fallbacks are the prepared answers (handoff step 3).
  Connector `card1-DSI-1` connected, mode 1080x2340, backlight `ae94000.dsi.0` 2047/2047 raw.
- **Input (FACT):** `input0 gpio-keys`, `input1 pmic_pwrkey`, `input2 pmic_resin`, `input3 STMicroelectronics FTS2BA61Y Touchscreen`;
  `/dev/input/event0-3` are `root:input 0660`. `user` is in wheel, audio, video, netdev, plugdev but **not** in `input` or `render`
  (both groups empty). INFERENCE: with logind seat ACLs (uaccess) a session on seat0 gets the input and DRM devices without group
  membership, which is what `plasma-mobile.service` should provide; if it does not, add `user` to `input` and `render`.
- Misc: `sudo` is sudo-rs (present, no doas). Idle load 0.32, SoC temperatures 38-43 C. The preflight did not record the phone's
  own clock (the apk failure might be time related; the `--apknet` script records it).

## 6. Next phone-side step: why does `apk update` fail?

Script `scripts/phone-apknet-diag.sh` (test `scripts/test-phone-apknet-diag.sh`, passes under bash; dash not installed on the PC,
shellcheck `-s sh` clean at warning level), flag `--apknet` of the collector:

    bash scripts/collect-phone-state.sh apknet --apknet

It is read-only and records the phone's clock, route, resolv.conf, MTU, signal, apk version, ICMP to the gateway and 1.1.1.1
(also with a 1400-byte payload), DNS for both mirror hosts, the HTTP and HTTPS response headers for the `aarch64` index files
of Alpine main and pmOS main, and `apk update -vv`. Candidate causes, none verified: a wrong phone clock; HTTP-to-HTTPS redirects
that apk-tools does not follow on plain-http mirrors (then switch the repositories to https); a path-MTU problem on the Wi-Fi
link; DNS or captive-portal behaviour on the home network; a mirror-side problem. If the phone cannot be fixed quickly the
fallback is a local package repository: INFERENCE (not designed yet), build or mirror the 825 packages on the PC and serve them to
the phone over the USB network, but that needs the PC offline from the internet while installing, so it is the last resort.

## 7. Status

- DONE: docs read; pmaports package definitions read against current `main` (8bd6c16); preflight script, test and collector flag;
  **preflight run and read (section 5)**; apk network diagnosis script, test and `--apknet` flag.
- Route decision: still A (`apk add` over Wi-Fi, systemd path, pipewire backend pinned, manual `systemctl start plasma-mobile.service`),
  **blocked until `apk update` works** on the phone.
- TODO: run `--apknet` and fix apk; re-run the simulation on a fresh index; the install; the TWRP initramfs fix before the
  first reboot; usb-moded decision; read `plasma-mobile.service`; manual session start; verification (touch, keys, backlight,
  keyboard, Wi-Fi in the UI, idle load/temperature); persistence in the device package; docs/06 and Project memory updates; GPU plan
  (`docs/11-gpu-bringup.md`).
