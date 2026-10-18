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

### 6.1 Result (run 2026-10-17 ~17:30 local, `notes/2026-10-17-apknet/`, raw, uncommitted): root cause found

FACT:
- **The ISP's middlebox hijacks plain HTTP.** `wget -S` against `http://dl-cdn.alpinelinux.org/...` and
  `http://mirror.postmarketos.org/...` both got `HTTP/1.1 307 Temporary Redirect`, `Via: 1.0 middlebox`, `Location:
  http://megaplusredirection.tedata.net/VDSL-Redirection_100.html`, which answers `200 OK` with an 8674-byte HTML page. apk
  therefore receives HTML instead of an index: `HTTP: unrecognized server error` for all five repositories.
- **HTTPS is not touched:** `https://dl-cdn.alpinelinux.org/...APKINDEX.tar.gz` returned `200 OK` (532406 bytes, fresh: Last-Modified
  2026-10-17 09:38 UTC); `https://mirror.postmarketos.org/...` returned `301` to `https://mirror.nura.eco/postmarketos/main/...` and then
  `200 OK` (106571 bytes, Last-Modified 2026-10-17 11:03 UTC). busybox wget follows that redirect; apk-tools 3.0.8 following it is
  INFERENCE until `apk update` over https succeeds.
- Everything else is fine: phone clock correct (Sat 2026-10-17 14:30 UTC), default route via 192.168.1.1 on wlan0 (MTU 1500, gateway ping
  16-27 ms, 1.1.1.1 ping 65-70 ms, 1400-byte ping OK), DNS via systemd-resolved (`127.0.0.53`) answers for both mirrors (IPv6 answers shown),
  no proxy variables, apk-tools 3.0.8-r0, `/var/cache/apk` holds the stale indexes (Sep 28 and Oct 11) plus a local `iw-6.17-r0.apk`.
  `/proc/net/wireless` is absent (no signal figures; cfg80211 without wext).
- The earlier world-file observation fits: `iw` and `linux-firmware-ath11k` came from local apks because http repositories never worked
  on this network.

Fix (not applied yet): switch all repository URLs to `https://`. Script `scripts/phone-apk-https.sh` (test
`scripts/test-phone-apk-https.sh`, passes under bash; dash not installed on the PC; shellcheck clean), collector flag `--apk-https`:

    bash scripts/collect-phone-state.sh apk-https --apk-https

It edits `/etc/apk/repositories` (http:// to https://; the original is kept once as `repositories.dm1q-orig`), runs `apk update`, and
only if that succeeds runs `apk add --simulate postmarketos-base-ui-audio-backend-pipewire postmarketos-ui-plasma-mobile` with a
summary (counts, pulseaudio lines, key package versions). Nothing is installed and no trigger runs, so rule 3 does not apply to
this step. INFERENCE: if apk-tools cannot follow the pmOS `301` to `mirror.nura.eco`, the fallback is to point the two pmOS
lines at `https://mirror.nura.eco/postmarketos/...` directly. The https change is a rootfs-local edit (the file comes from the
image build); a persistent fix for reinstalls belongs in the pmbootstrap config used to build the rootfs, TODO.

### 6.2 Result of the https switch (run 2026-10-17 ~17:33 local, `notes/2026-10-17-apk-https/`)

FACT:
- `/etc/apk/repositories` on the phone is now all `https://` (original in `/etc/apk/repositories.dm1q-orig`).
- **`apk update` works over https**: `OK: 37536 distinct packages available`, all five indexes fresh (pmOS main 2026-10-17 11:03 UTC,
  systemd extra-repo 2026-10-16 09:33 UTC, Alpine edge main/community/testing `v20260805-4298/4288/4300`; the `v20260805` is the
  Alpine edge branch-point label, not a stale date, the git-describe counter moved from 39xx to 42xx). apk-tools 3.0.8 follows the
  pmOS 301 to `mirror.nura.eco` and only prints `WARNING: Permanently redirected to https://mirror.nura.eco:443/...` (resolves the
  INFERENCE of 6.1; no need to edit the pmOS URLs).
- **Bug in my script (found by this run):** `phone-apk-https.sh` treated any `WARNING` as a failed update, so it printed
  `UPDATE-STATUS: FAILED` and skipped the simulation although the update had succeeded. Fixed: success is now a final `OK:` line and
  no `unrecognized|ERROR|UNTRUSTED|N unavailable` marker; the PC test stub now emits the redirect WARNING so it would have caught
  this. The script is idempotent, so rerunning the same command only repeats the update and runs the simulation.

### 6.3 Fresh simulation with the pipewire backend pinned (run 2026-10-17 ~17:34 local, `notes/2026-10-17-apk-https2/`)

FACT (`apk add --simulate postmarketos-base-ui-audio-backend-pipewire postmarketos-ui-plasma-mobile`, fresh indexes): **821 operations =
810 installs + 11 upgrades, 0 purges, no errors or conflicts, 2761.0 MiB, ending at 1155 packages**; 812 packages to download.
- Versions: plasma-mobile 6.8.0, plasma-workspace/kwin `99996.8.0` (pmOS systemd extra-repo), plasma-keyboard and plasma-nano 6.8.0,
  postmarketos-base-ui 62 (+ `-audio-backend-pipewire` 62-r0), postmarketos-base-ui-plasma 3-r2, postmarketos-ui-plasma-mobile 6-r10,
  xorg-server 999921.1.23, postmarketos-usb-moded 11-r0 (+ developer default profile, usb-moded-notify, umtprd, usb-signaller).
- Upgrades (11): pipewire, pipewire-lang, pipewire-udev, pipewire-systemd 1.6.8-r5 -> 1.6.9-r0; hwdata-pci 0.411 -> 0.412; mesa, mesa-gbm,
  mesa-dri-gallium, mesa-gles, mesa-egl 26.2.3-r1 -> 26.2.4-r1; libmm-glib. No kernel, firmware, device-package or postmarketos-base change.
- **Pinning the backend worked:** no pulseaudio daemon is installed (the 4 `pulseaudio` lines are `pulseaudio-utils` and `pulseaudio-qt`,
  each once as a download and once as an install); `pipewire-pulse` and `pipewire-alsa` come in instead.
- 45 simulated installs are `-systemd`/`-udev` subpackages; `-udev` ones (feedbackd, gmobile, libfprint, libmtp, fuse3, libmbim,
  iio-sensor-proxy, modemmanager, alsa-utils, ddcutil) land in `/usr/lib/udev`, which is on the mkinitfs trigger list: the initramfs
  regeneration is certain.

## 8. The install (script ready, not run yet)

Script `scripts/phone-plasma-install.sh` (test `scripts/test-phone-plasma-install.sh`: 38 checks pass under bash, ~15 s; dash not
installed on the PC; `shellcheck -s sh` clean), collector flag `--plasma-install`:

    bash scripts/collect-phone-state.sh plasma-install --plasma-install

What it does on the phone, in order: guards (repositories https-only, >= 6 GB free on `/`, `/boot` has room for mkinitfs to rewrite
`initramfs-extra`) -> snapshot in `/root/dm1q-plasma` (boot listing, sha256 and a COPY of the working `/boot/initramfs-extra` as
`initramfs-extra.pre-plasma` on the rootfs, not in the small nested /boot; package list; enabled units; apk triggers) -> **masks
`usb-moded.service`** (precaution, INFERENCE: it may take over the ncm gadget that carries our ssh; undo with `systemctl unmask`) ->
`apk add postmarketos-base-ui-audio-backend-pipewire postmarketos-ui-plasma-mobile`, **detached** (nohup + setsid, log
`/root/dm1q-plasma/install.log`, so a dropped ssh cannot kill apk half way; running the same command again follows or finishes it and
never starts a second install) -> after-state: whether `initramfs-extra` changed (expected: yes), whether the new file has usr-merge
symlinks, unit states, USB gadget still listed, `systemctl cat plasma-mobile.service`, `/etc/default_user`, package file lists ->
disables `plasma-mobile.service`/`display-manager.service` only if the install left them enabled. It does not start the UI and does
not reboot. Expected duration 15-40 min (about 2.7 GB over the home line).

**Hard rule after it (docs/06 rule 3): do not boot the system.** Reboot to TWRP, run `bash scripts/fix-phone-initramfs-extra.sh`
(dry run) and then `--yes`, and only then reboot into the system. The saved `initramfs-extra.pre-plasma` is the rollback copy.

### 8.1 Result (run 2026-10-17 ~22:2x-22:35 local, `notes/2026-10-17-plasma-install/`, raw, uncommitted)

FACT:
- Guards passed (203 GB free; `/boot` 313 MB free for a 11.8 MB initramfs-extra). `initramfs-extra.pre-plasma` saved (sha256 b952b26f...).
- **apk add finished with rc=0: 1155 packages (was 345), 2761.0 MiB**, exactly as simulated; all triggers ran.
- **The mkinitfs trigger fired as predicted:** `/boot/initramfs-extra` 11 828 461 -> 12 228 225 bytes (sha256 now fbd141f1...), `/boot/initramfs`
  and `/boot/sm8550-samsung-dm1q.dtb` in the nested boot filesystem were rewritten too (same dtb size 121 890 B; the boot chain uses
  the images flashed from TWRP, so those two copies are not what boots). The new initramfs-extra had the usr-merge symlinks
  `bin -> usr/bin`, `lib -> usr/lib`, `sbin -> usr/bin` (the known breakage).
- **TWRP fix applied** (PC side, `~/.cache/dm1q-phone`): two runs at 22:38:54 (dry run) and 22:39:20 (`--yes`), each with a full 512 MiB backup of the
  nested boot partition; the FIXED file has no top-level `bin`/`lib`/`sbin` symlinks (only `usr/sbin -> bin`, same as the Oct 4 fix). Whether the phone then
  booted the system is confirmed by the next collector run (section 9), not by this paragraph.
- Units after the install (packages' presets): enabled `plasma-mobile.service` (alias `display-manager.service`; **the script disabled both again**, the
  alias symlink in /etc/systemd/system was removed), `ModemManager.service`, `bluetooth.service`, `alsa-restore/alsa-state`, `udisks2.service` (graphical.target),
  `usb-signaller.service` (basic.target; INFERENCE: with `usb-moded` masked it may still act on the USB gadget, to be checked in the journal after the next
  boot), user units `usb-moded-notify`, `fbd-alert-slider`, `gnome-keyring-daemon`. `usb-moded.service` is masked by our precaution (the unit file does not exist in
  the package list, only `umtprd` config + `usb-signaller` TOML + a generator `umtprd-config-generator`), so the INFERENCE that usb-moded
  takes over the gadget is moot for this package set; `usb-signaller` is the thing to watch. After the install and before the reboot: `usb0` 172.16.42.1/16 up,
  gadget `g1` UDC `a600000.usb` function `ncm.usb0` unchanged, `wlan0` 192.168.1.11 (the MAC did not change during the install; the random-MAC conf only applies
  from the next NetworkManager connection).
- **Session unit (FACT, `systemctl cat plasma-mobile.service`):** `Conflicts=getty@tty1.service`, `After=getty@tty1.service ... session-c1.scope`,
  `OnFailure=getty@tty1.service`, `ExecStart=/usr/bin/startplasmamobile`, `PAMName=login`, `TTYPath=/dev/tty1` (+ reset/vhangup/disallocate),
  `XDG_SEAT=seat0`, `XDG_VTNR=tty1`, `LANG=C.UTF-8`, `Restart=always`, `RestartSec=5s`, `TimeoutStartSec=30`, `Alias=display-manager.service`; the unit says `User=1000`
  but the generator drop-in `/run/systemd/generator/plasma-mobile.service.d/10-user.conf` sets `User=10000`/`Group=10000` (`/etc/default_user` is absent, so the
  fallback is used) = our `user`. So the session is a real logind session on seat0/tty1 with seat device ACLs, not an ssh session; no group changes needed
  (INFERENCE until the first start shows libinput/DRM access).

## 9. First start by hand (script ready, not run yet)

Script `scripts/phone-plasma-start.sh` (test `scripts/test-phone-plasma-start.sh`: 36 checks pass under bash incl. crash-loop abort and SIGTERM trap;
dash not installed on the PC; `shellcheck -s sh` clean), collector flags `--plasma-start[=SECONDS]` and `--plasma-keep`:

    bash scripts/collect-phone-state.sh plasma-start --plasma-start=240

It starts `plasma-mobile.service` by hand (no autostart), watches it for SECONDS (default 240) printing a status line every 10 s (state, restarts, kwin
process count, load, memory, hottest SoC temperature), aborts the window early after 3 restarts (crash loop), then collects: unit status, the unit's journal
since T0 (first 250 lines), warnings/errors of all units, the process list, kwin_wayland's environment (selected variables), its open DRM/input fds, logind
sessions/seats, `kscreen-doctor -o` as the UI user (outputs, scale, rotation), backlight value, filtered dmesg (msm/dpu/drm/arm-smmu faults/touch) and the
smmu fault count, `top`, and then stops the UI and restores getty on tty1 (also on Ctrl-C, SIGTERM and a dropped ssh) unless `--plasma-keep`. It changes no files. No
environment tuning is applied on purpose: the first run shows what KWin picks by itself on a KMS-only device (renderD128 exists without a GPU; llvmpipe vs a
failure); `KWIN_DRM_DEVICES`, `QT_QUICK_BACKEND=software` and the software-compositor fallbacks are the prepared next steps (handoff step 3).
While it runs, on the phone: touch the screen, short power key, volume keys, swipe down for quick settings, move the brightness slider, open a text field for the
on-screen keyboard.

### 9.1 Result of the first start (run 2026-10-17 ~22:47 local, 240 s window, default profile, `notes/2026-10-17-plasma-start/`, raw, uncommitted)

What Baraa saw (FACT): the screen went completely black and flashed the `samsung-dm1q login:` line over and over; Plasma Mobile never appeared.

FACT from the log:
- The phone booted the system after the TWRP fix (uptime 419 s at the start of the run; usb0 ssh worked; `usb-signaller` active, `usb-moded` masked, gadget fine).
- **The session does start**: `startplasma-wayland`, `kwin_wayland_wrapper --xwayland`, `kwin_wayland --wayland-fd 7 --socket wayland-1 --xwayland`, `kded6`, `plasmashell`,
  `plasma-mobile-initial-start`, `org_kde_powerdevil`, `plasma-keyboard`, `kscreenlocker_greet` all ran; logind session `c5` on seat0/tty1 (kwin env `XDG_VTNR=1`, `XDG_SESSION_TYPE=wayland`).
  Only the unit's `XDG_VTNR=tty1` is rejected by pam_systemd (`Failed to parse environment variable value 'tty1' of 'XDG_VTNR'`, harmless here, startplasma re-sets it).
- **But `plasma-mobile.service` exits (status 0, "Deactivated successfully") about every 33 s and `Restart=always` brings it back 5 s later** (restart counter 1, 2, 3 at t=40, 80, 110 s;
  the script aborted at 3). Each cycle drops the compositor (black screen) and getty@tty1 shows its login line in the gap: this is exactly what Baraa saw, and probably also the
  "login prompt repeats" mystery in the early console of docs/09 (INFERENCE: a getty respawn there; not verified).
- **Qt Quick clients crash with SIGILL (`status=4/ILL`) inside Mesa**: `ksplashqml` and `plasma-keyboard` dumped core; both stack traces have the same shape: frame #0 in anonymous memory
  (`n/a`, i.e. JIT-generated code), frame #1 `libgallium-26.2.4.so + 0x735d4c` (the same offset in both). INFERENCE (strong, not proven): llvmpipe's LLVM JIT emitted an instruction the CPU/kernel
  does not allow for userspace (candidate: an SVE/SVE2-class or other extension that LLVM assumes for the Cortex-X3/A715/A510 cores but the kernel or firmware does not enable). `plasma-ksplash.service` then
  fails ("Failed to start Splash screen shown during boot"), which is the likely reason startplasma ends after ~30 s. Not yet checked: `Features` in `/proc/cpuinfo`, `CONFIG_ARM64_SVE`,
  the faulting instruction word in a core, and what KWin itself uses (it stayed alive; no KWin log was collected in this run: only the system-unit journal and warnings).
- Noise, not causes: `xembedsniproxy` and `gmenudbusmenuproxy` abort (X11 helpers without an X display) and restart in a loop; `ddcutil` (via powerdevil) fails to open `/dev/i2c-0` (EACCES); wireplumber
  complains that UPower/BlueZ were not up yet. The repeated coredumps also keep `systemd-coredump` busy (visible in `top`).
- **Heat and load**: hottest thermal zone 75-90 C during the crash loop (89 at t=40 s, 90 at the end), load 2.3, memory used 0.9-1.7 GB of 6.6 GB; software GL for 3-4 Qt Quick processes plus coredump handling.
  INFERENCE: do not let a crash loop run for long; the script now aborts at 95 C.
- `arm-smmu 15000000.iommu: Unhandled context fault: fsr=0x402, iova=0xb809cd00 ... cb=4` at 0.288 s: **1 fault** in this boot (docs/09 had 0 faults in the v17 run). The address lies in the
  simplefb region `b8000000` and the time is before msm loads (7.9 s). INFERENCE: the boot images flashed now may not be the v17 splash-iommu set, or the fault is timing dependent; TODO compare
  with docs/09 section 15 and the flashed set before concluding anything.
- **Bugs of my script found by this run (fixed):** it used `WAYLAND_DISPLAY=wayland-0` for `kscreen-doctor` but KWin's socket is `wayland-1` (kscreen-doctor failed and core dumped), and it picked
  `kwin_wayland_wrapper` instead of `kwin_wayland` for the fd/environment listing (so the open DRM/input fds list was empty). The script now finds the real socket(s) and uses `pgrep -n -x kwin_wayland`,
  collects the UI user's journal (kwin/plasmashell/ksplash), the coredump summaries, CPU part/features, kernel SVE config and the user manager environment, and aborts when too hot.

Next run (software profile, no GL anywhere):

    bash scripts/collect-phone-state.sh plasma-start-sw --plasma-start=240 --plasma-profile=software

`--plasma-profile=software` writes a TEMPORARY env script `/etc/xdg/plasma-workspace/env/90-dm1q-test.sh` (`export QT_QUICK_BACKEND=software`, `export KWIN_COMPOSE=Q`: all Qt Quick apps
render on the CPU into shm buffers, KWin uses its QPainter compositor on dumb buffers; `KWIN_COMPOSE=Q` is the documented software compositor backend for Wayland), removes it at the end and
reports whether the variables reached the user manager (`systemctl --user show-environment`). INFERENCE: this avoids llvmpipe's JIT entirely, so the SIGILL cannot occur; if it works, the
persistent form is a file in `/etc/xdg/plasma-workspace/env/` shipped by `device-samsung-dm1q` (to be packaged after the test). The llvmpipe SIGILL root cause stays open (it matters if software GL
is ever needed again, e.g. XWayland clients or before the Adreno works); the GPU path (docs/11) removes llvmpipe from the picture for the session itself.

### 9.2 Result of the second start: `software` profile with `KWIN_COMPOSE=Q` (run 2026-10-18 ~05:23 local, `notes/2026-10-18-plasma-start-sw/`, raw, uncommitted)

What Baraa saw (FACT): still a black screen and then the same login line. He also reports (FACT) that touch and the buttons work fine on the console: he installed
`ttyescape` (one of the plasma-mobile recommended packages, an on-screen keyboard for the tty) and has a working on-screen keyboard without a desktop environment.
So touch and keys are confirmed outside Plasma, and the log shows the same inside KWin (below).

FACT from the log:
- **The env-script hook works:** `systemctl --user show-environment` and kwin's own environment both had `KWIN_COMPOSE=Q` and `QT_QUICK_BACKEND=software`, so
  `/etc/xdg/plasma-workspace/env/*.sh` reaches every user service (INFERENCE of 9.1 confirmed). The same hook is the right place for a persistent setting.
- **`KWIN_COMPOSE=Q` is a dead end on this KWin (6.8, DRM platform):** `kwin_core: Compositing forced to QPainter mode by environment variable` -> `Configured compositor not
  supported by Platform. Falling back to defaults` -> `Attempting to load the OpenGL scene` -> `Could not fulfill the requested compositing mode in KWIN_COMPOSE: 1 . Exiting.` -> kwin_wayland
  SIGSEGV; the wrapper restarts it about 10 times in 10 s (`KWIN_RESTART_COUNT=8` when collected), every Wayland client then aborts (SIGABRT: kded6, plasmashell, powerdevil, ...),
  `startplasma-wayland` shuts down and the unit restarts every ~12 s (faster than in 9.1). INFERENCE: the QPainter backend no longer exists for the DRM platform in 6.8 (not checked against
  the KWin source or changelog). The profile no longer sets it.
- **KWin's hardware side is fine:** it opens `/dev/dri/card1` with atomic modesetting (10 planes), creates the output `DSI-1` (no EDID, expected), libinput lists `gpio-keys`, `pmic_pwrkey`, `pmic_resin`
  as keyboards and `STMicroelectronics FTS2BA61Y Touchscreen` as a touch device; kwin_wayland holds 1 card1 fd and 3 renderD128 fds.
- **KWin enumerates its render devices as `/dev/udmabuf: llvmpipe` and `/dev/dri/renderD128: llvmpipe`** and chooses `/dev/udmabuf` as the primary GPU. Mesa first tries the msm
  gallium driver on renderD128 (`MESA: error: get_param:235: get-param failed! -6`, `fd_pipe_new2:34: allocation failed`, i.e. no GPU behind the render node, ENXIO) and then falls back to
  llvmpipe. Harmless noise but it confirms the fallback chain.
- **llvmpipe kills every GL user, KWin included:** the first-run coredump list (9.1) also holds `kwin_wayland` and `plasmashell` with `Signal: 4 (ILL) si_code: ILL_ILLOPC`, same
  shape (frame #0 in anonymous JIT memory, frame #1 `libgallium-26.2.4.so + 0x735d4c` in every process). So `QT_QUICK_BACKEND=software` for the clients cannot be enough: KWin itself needs GL.
- **CPU (FACT, `/proc/cpuinfo`, kernel config):** 8 cores = 3x Cortex-A510 (part 0xd46), 2x A710 (0xd47), 2x A715 (0xd4d), 1x X3 (0xd4e). `Features`: fp asimd aes pmull sha1 sha2 crc32 atomics fphp asimdhp
  asimdrdm jscvt fcma lrcpc dcpop sha3 sm3 sm4 asimddp sha512 asimdfhm dit uscat ilrcpc flagm sb paca pacg dcpodp flagm2 frint i8mm bti: **no `sve`, no `sve2`, no `bf16`**, although
  `CONFIG_ARM64_SVE=y` and `CONFIG_ARM64_SME=y`. dmesg also has `CPU features: SANITY CHECK: Unexpected variation in SYS_ID_AA64MMFR1_EL1` (boot CPU 0x...11212122 vs CPU3-7
  0x...10212122) and `SYS_ID_MMFR4_EL1` on CPU5-7, then `Unsupported CPU feature variation detected`.
  INFERENCE (strong, still unproven): Qualcomm's hypervisor/firmware hides SVE (and BF16) from EL1, LLVM picks a CPU model (X3/A715, which implies SVE2 and BF16) from the `CPU part`
  lines, and llvmpipe's JIT emits an instruction that is illegal for userspace on this phone. The faulting instruction word will settle it (next step).
- Fixed or understood noise: `/tmp/.X11-unix` and `/tmp/.ICE-unix` do not exist (`kwin_xwl: /tmp/.X11-unix does not exist`, `Failed to create Xwayland connection sockets`, `_IceTransmkdir`),
  INFERENCE: the systemd package here does not ship tmpfiles `x11.conf` (the start script now prints whether it exists and creates the two directories, mode 1777, as a stopgap; a tmpfiles.d
  snippet in `device-samsung-dm1q` is the persistent fix, TODO); `Failed to gain real time thread priority (CAP_SYS_NICE)`; `gkr-pam: couldn't unlock the login keyring`; `XDG_VTNR=tty1`.
  This run had 0 arm-smmu faults (the single fault of 9.1 was a one-off or boot dependent: still open).
- Temperatures were lower this time (hottest 71 C at the end, abort after the crash loop at t=40 s).

Next run, three changes in one command (all read-only except the temporary env script and the two empty directories):

    bash scripts/collect-phone-state.sh plasma-start-sp --plasma-start=240 --plasma-profile=softpipe --sigill-core

- `--plasma-profile=softpipe` = `QT_QUICK_BACKEND=software` + `LIBGL_ALWAYS_SOFTWARE=1` + `GALLIUM_DRIVER=softpipe`: Mesa's non-JIT software rasteriser for KWin (and for anything else that needs GL), so the
  llvmpipe JIT is not involved at all. INFERENCE: it should avoid the SIGILL; it will be slow (the panel is 1080x2340), which is acceptable for a first light.
- `--sigill-core` (`scripts/phone-sigill-core.sh`, test `scripts/test-phone-sigill-core.sh`, 28 checks pass under bash incl. a decode with `llvm-mc`): parses the stored SIGILL cores of the clients with python3
  and prints the faulting pc, its mapping, registers and 17 instruction words around it; decode them on the PC with `llvm-mc --disassemble --triple=aarch64 -mattr=+all`.

### 9.3 Result of the third start: `softpipe` profile, and the decoded SIGILL (run 2026-10-18 ~09:16 local, `notes/2026-10-18-plasma-start-sp/`, raw, uncommitted)

What Baraa saw (FACT): same outcome (black screen, then the login line). Decision (Baraa, 2026-10-18): **do the GPU (Adreno 740) enablement first**; handoff in `notes/2026-10-18-handoff-gpu.md`.

FACT:
- **The SIGILL is decoded.** `scripts/phone-sigill-core.sh` parsed the stored cores of `plasma-keyboard`, `kwin_wayland`, `plasmashell` and `ksplashqml`: **all four have the same faulting word `0x04a14003`** at the same offset
  (`pc` = start of an anonymous `r-x` JIT page + 0x38/0x3c, LR = `libgallium-26.2.4.so + 0x735d4c`, EL0). `llvm-mc --disassemble --triple=aarch64` decodes it as **`index z3.s, #0, #1`, an SVE instruction**
  (valid with `+sve`/`+sve2`/`+sme`, `invalid instruction encoding` with plain `+v8.6a,+neon,+i8mm`), sitting in a JIT prologue between scalar loads and NEON `dup v1.4s, w5` / `movi v16.4s`.
  Together with `/proc/cpuinfo` (no `sve`/`sve2`/`bf16` in `Features`, section 9.2): **llvmpipe's LLVM JIT generates SVE code for this phone, which the kernel does not expose to userspace** (the firmware/hypervisor hides it;
  the kernel has `CONFIG_ARM64_SVE=y`). INFERENCE for the "why": LLVM takes its CPU model from the `CPU part` lines (X3/A715/A510 all imply SVE2) instead of from the `Features` line.
- **softpipe with `LIBGL_ALWAYS_SOFTWARE=1` does not work for KWin:** `MESA-EGL: warning: Not allowed to force software rendering when API explicitly selects a hardware device.`, `egl: failed to create dri2 screen`,
  `kwin_scene_opengl: Error during eglInitialize "EGL_NOT_INITIALIZED"`, `Failed to create gbm device for "/dev/dri/renderD128"` and `"/dev/dri/card1"`, `Found no render device!`, `The used windowing system requires
  compositing`, `We are going to quit KWin now as it is broken` -> kwin_wayland dumps core, the unit restarts every ~10 s (3 restarts by t=40 s, hottest 78 C, abort). INFERENCE: KWin selects the device explicitly
  (EGL device / GBM on the DRM node), which Mesa refuses to override with `LIBGL_ALWAYS_SOFTWARE`. Untested variants: `GALLIUM_DRIVER=softpipe` with `MESA_LOADER_DRIVER_OVERRIDE=kms_swrast` and no `LIBGL_ALWAYS_SOFTWARE`.
- `/tmp/.X11-unix` and `/tmp/.ICE-unix` existed at the start of this run (cause unknown, not created by the script this time); `/usr/lib/tmpfiles.d` has `tmp.conf` but no `*x11*` file (FACT).
- **Housekeeping:** `coredumpctl` lists **290 SIGILL cores** (5-7 MB each, compressed, under `/var/lib/systemd/coredump`) from the three runs, i.e. roughly 1.5-2 GB, and the crash loops keep `systemd-coredump` busy. They can be deleted
  (`sudo rm -f /var/lib/systemd/coredump/*`) now that the analysis is done; for further crash experiments a drop-in `/etc/systemd/coredump.conf.d/dm1q.conf` with `[Coredump]` / `Storage=none` avoids new ones. Not done by me.

Ways to make software GL work without the GPU (all INFERENCE, none tried; the GPU path of docs/11 makes them moot for the session itself, but they matter for any CPU-only fallback, XWayland clients and Waydroid-style uses):
(a) give LLVM a CPU model without SVE, e.g. a bind-mounted `/proc/cpuinfo` for the UI services (`BindReadOnlyPaths=`) in which the `CPU part` lines say a non-SVE core; (b) look for a Mesa gallivm override of the JIT
CPU/feature string in Mesa 26.2 (not searched); (c) the softpipe variant above; (d) rebuild Mesa/LLVM with SVE disabled for aarch64 (a pmaports patch, heavy).

## 7. Status

- DONE: docs read; pmaports package definitions read against current `main` (8bd6c16); preflight script, test and collector flag;
  **preflight run and read (section 5)**; apk network diagnosis script, test and `--apknet` flag.
- Route decision: A (`apk add` over Wi-Fi, systemd path, pipewire backend pinned, manual `systemctl start plasma-mobile.service`).
  The blocker is fixed on the phone (ISP middlebox vs plain http, sections 6.1-6.2); apk update works over https.
- DONE: fresh simulation read (6.3); install script, test and `--plasma-install` flag written (section 8).
- DONE: install run, rc=0, 1155 packages; TWRP initramfs fix applied (section 8.1); first-start script, test and flags written (section 9).
- DONE: first start by hand run (section 9.1): the session starts, but restarts every ~33 s because Qt Quick clients (ksplashqml, plasma-keyboard) die with SIGILL in llvmpipe's JIT; the phone boots after the TWRP fix, usb ssh fine.
- DONE: second start with `--plasma-profile=software` (+ `KWIN_COMPOSE=Q`): KWin 6.8 has no QPainter compositor on DRM and exits (section 9.2); touch and keys confirmed (console via ttyescape, libinput inside KWin).
- DONE: third start (`softpipe`) and the SIGILL decode (section 9.3): llvmpipe's JIT emits the SVE instruction `index z3.s, #0, #1`, which this phone's userspace cannot execute; softpipe + `LIBGL_ALWAYS_SOFTWARE` breaks KWin's EGL init. **Decision: GPU first (docs/11, handoff `notes/2026-10-18-handoff-gpu.md`); Plasma Mobile resumes after the Adreno works or after one of the software-GL variants of 9.3 is tried.**
- TODO: tmpfiles.d snippet for `/tmp/.X11-unix`, `/tmp/.ICE-unix`; usb-moded decision; read `plasma-mobile.service`; manual session start; verification (touch, keys, backlight,
  keyboard, Wi-Fi in the UI, idle load/temperature); persistence in the device package; docs/06 and Project memory updates; GPU plan
  (`docs/11-gpu-bringup.md`).
