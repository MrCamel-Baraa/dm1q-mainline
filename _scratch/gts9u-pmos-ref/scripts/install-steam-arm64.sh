#!/bin/sh
# Install the ARM64 Steam client on postmarketOS, adapted from the Fedora
# install.sh that circulates for arm64 Steam.
#
# WHY THIS IS NOT A LINE-BY-LINE PORT OF THAT SCRIPT
#
# The Fedora script assumes a glibc host: it dnf-installs a pile of libraries and
# runs the Steam bootstrap directly.  postmarketOS is Alpine, and Alpine is
# **musl**.  Steam and everything it downloads at runtime are glibc binaries; the
# musl loader cannot run them, and gcompat is a shim for small programs, not for
# a self-updating runtime that ships its own linker.  Swapping dnf for apk would
# produce a script that installs cleanly and then fails at the first exec.
#
# So the port keeps the same three phases as the original - dependencies, client
# bootstrap, Proton - but runs the last two inside a rootless glibc container
# (Debian arm64 via distrobox/podman), with the host GPU, audio and display
# passed through.  $HOME is shared, so ~/.local/share/Steam lives on the host and
# survives the container being rebuilt.
#
# On the Galaxy Tab S9 Ultra specifically: the GPU is an Adreno 740, so the
# container needs Mesa's freedreno/Turnip drivers, and GNOME runs Wayland while
# Steam is an X11 application, so Xwayland has to be present.
#
# Usage:
#   scripts/install-steam-arm64.sh            install
#   scripts/install-steam-arm64.sh --recreate rebuild the container from scratch
#   scripts/install-steam-arm64.sh --remove   remove container and Steam data
#
# Environment:
#   STEAM_CONTAINER   container name              (default steam-arm64)
#   STEAM_IMAGE       glibc base image            (default debian:trixie)
#   STEAM_SKIP_PROTON set to 1 to skip Proton
set -eu

CDN="https://client-update.steamstatic.com"
MANIFEST="steam_client_publicbeta_linuxarm64"
BINSZIP="linuxarm64_bins.zip"
# NOTE: this Proton build is an unofficial third-party tarball on archive.org,
# exactly as in the original script.  It is not signed and not from Valve.  It is
# fetched only when the user does not opt out with STEAM_SKIP_PROTON=1.
PROTONURL="https://archive.org/download/arm-64proton-runtime-64.tar/ARM64proton-Runtime64.tar.gz"

CONTAINER=${STEAM_CONTAINER:-steam-arm64}
IMAGE=${STEAM_IMAGE:-debian:trixie}
STEAMDIR="$HOME/.local/share/Steam"

log()  { printf '\033[1;32m-> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!! %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[1;31mxx %s\033[0m\n' "$*" >&2; exit 1; }

# postmarketOS images ship doas; some also have sudo.  Use whichever exists
# rather than reading a password into a variable the way the original did.
if command -v doas >/dev/null 2>&1; then
	SU=doas
elif command -v sudo >/dev/null 2>&1; then
	SU=sudo
else
	die "neither doas nor sudo found"
fi

[ "$(id -u)" -ne 0 ] || die "run this as your normal user, not root"

case "${1:-}" in
--remove)
	log "Removing container and Steam data"
	distrobox rm -f "$CONTAINER" 2>/dev/null || true
	rm -rf "$STEAMDIR" "$HOME/.steam"
	log "Done"
	exit 0
	;;
--recreate)
	log "Removing existing container"
	distrobox rm -f "$CONTAINER" 2>/dev/null || true
	;;
"") ;;
*) die "unknown option: $1" ;;
esac

# ---------------------------------------------------------------- host packages
#
# These are the Alpine equivalents of the Fedora list, minus everything that only
# matters inside the container.  What the host genuinely needs is the container
# runtime, the DRM/Vulkan drivers for the Adreno (the container reuses the host
# kernel and /dev/dri), and Xwayland for an X11 client under GNOME.
log "Installing host packages"
$SU apk add --no-interactive \
	podman distrobox fuse-overlayfs crun conmon \
	mesa-dri-gallium mesa-vulkan-freedreno mesa-gl mesa-egl vulkan-loader \
	xwayland xdg-user-dirs curl tar xz unzip shadow-subids || \
	die "apk add failed"

# --------------------------------------------------------------- rootless setup
#
# Rootless podman needs a subuid/subgid range for the user.  Alpine does not set
# one up by default, so a fresh postmarketOS install fails here with a confusing
# "lchown ... Invalid argument" during the first pull.
user=$(id -un)
if ! grep -q "^$user:" /etc/subuid 2>/dev/null; then
	log "Allocating subuid/subgid range for $user"
	printf '%s:100000:65536\n' "$user" | $SU tee -a /etc/subuid >/dev/null
	printf '%s:100000:65536\n' "$user" | $SU tee -a /etc/subgid >/dev/null
	# podman caches the mapping; drop any half-initialised state.
	podman system migrate 2>/dev/null || true
fi

# cgroups v2 and user delegation are what let a rootless container start at all.
if [ ! -d /sys/fs/cgroup/user.slice ] && [ ! -f /sys/fs/cgroup/cgroup.controllers ]; then
	warn "cgroups v2 not visible; rootless podman may refuse to start"
fi

# ------------------------------------------------------------------- container
# Ask podman directly rather than parsing distrobox's table output.
if ! podman container exists "$CONTAINER" 2>/dev/null; then
	log "Creating glibc container '$CONTAINER' from $IMAGE"
	# --nvidia is deliberately absent: this is an Adreno.  distrobox already
	# binds /dev/dri, /dev/snd, the Wayland and X11 sockets and $HOME.
	distrobox create --yes --name "$CONTAINER" --image "$IMAGE" \
		--additional-packages "ca-certificates curl unzip tar xz-utils zenity" \
		|| die "distrobox create failed"
else
	log "Container '$CONTAINER' already exists"
fi

log "Starting container"
distrobox enter --name "$CONTAINER" -- true || die "cannot enter container"

# ------------------------------------------------- dependencies inside glibc
#
# Debian names for the same set the Fedora script installed, plus the Mesa
# drivers so the container can talk to the host's Adreno through /dev/dri.
log "Installing Steam dependencies inside the container"
distrobox enter --name "$CONTAINER" -- sh -c '
set -eu
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
	ca-certificates curl unzip tar xz-utils zenity file \
	libgl1-mesa-dri mesa-vulkan-drivers libvulkan1 libglx-mesa0 libegl1 \
	libasound2t64 libfontconfig1 libgtk2.0-0t64 libice6 libnsl2 libpng16-16t64 \
	libxext6 libxinerama1 libxtst6 libxss1 libnm0 libnss3 libpulse0 \
	libcurl4t64 libsystemd0 libva2 libvdpau1 libatomic1 libsdl2-2.0-0 \
	dbus-x11 xdg-user-dirs libgirepository-1.0-1 libopenal1 lsof pciutils \
	libvpx9 2>/dev/null || \
sudo apt-get install -y --no-install-recommends \
	ca-certificates curl unzip tar xz-utils zenity file \
	libgl1-mesa-dri mesa-vulkan-drivers libvulkan1 libglx-mesa0 libegl1 \
	libasound2 libfontconfig1 libgtk2.0-0 libice6 libnsl2 libpng16-16 \
	libxext6 libxinerama1 libxtst6 libxss1 libnm0 libnss3 libpulse0 \
	libcurl4 libsystemd0 libva2 libvdpau1 libatomic1 libsdl2-2.0-0 \
	dbus-x11 xdg-user-dirs libgirepository-1.0-1 libopenal1 lsof pciutils
' || die "dependency install failed inside the container"

# The Fedora script symlinked libvpx.so.9 to libvpx.so.6 because the client still
# asks for the old soname.  Same fix, but in the container and with the Debian
# multiarch path instead of /usr/lib64.
log "Providing the legacy libvpx soname the client asks for"
distrobox enter --name "$CONTAINER" -- sh -c '
set -eu
d=/usr/lib/aarch64-linux-gnu
if [ ! -e "$d/libvpx.so.6" ]; then
	for v in 9 8 7; do
		if [ -e "$d/libvpx.so.$v" ]; then
			sudo ln -sf "$d/libvpx.so.$v" "$d/libvpx.so.6"
			break
		fi
	done
fi'

# ------------------------------------------------------------- steam bootstrap
[ -d "$HOME/.steam" ] && rm -rf "$HOME/.steam"
[ -d "$STEAMDIR" ]    && rm -rf "$STEAMDIR"

tempdir=$(mktemp -d)
cleanup() { rm -rf "$tempdir"; }
trap cleanup EXIT INT TERM

log "Downloading client base"
curl -# -fL -o "$tempdir/manifest" "$CDN/$MANIFEST" || die "manifest download failed"
bins=$(sed -n 's/^[[:space:]]*"file"[[:space:]]*"\(.*bins_linuxarm64_linuxarm64.*\)"[[:space:]]*$/\1/p' \
	"$tempdir/manifest" | head -1)
[ -n "$bins" ] || die "could not find the arm64 bins entry in the manifest"
curl -# -fL -o "$tempdir/$BINSZIP" "$CDN/$bins" || die "client download failed"

log "Extracting client base"
mkdir -p "$STEAMDIR"
unzip -q "$tempdir/$BINSZIP" 'steamrtarm64/*' -d "$STEAMDIR"
mkdir -p "$STEAMDIR/package" "$STEAMDIR/compatibilitytools.d"

log "Enabling publicbeta channel"
echo publicbeta > "$STEAMDIR/package/beta"

log "Preparing environment"
mkdir -p "$HOME/.steam"
ln -sfn "$STEAMDIR"              "$HOME/.steam/steam"
ln -sfn "$STEAMDIR/linuxarm64"   "$HOME/.steam/sdkarm64"
ln -sfn "$STEAMDIR/linux64"      "$HOME/.steam/sdk64"
ln -sfn "$STEAMDIR/linux32"      "$HOME/.steam/sdk32"
chmod +x "$STEAMDIR/steamrtarm64/steam"

# The bootstrap downloads the rest of the client, so it must run under glibc.
log "Bootstrapping client (this downloads several hundred MB)"
distrobox enter --name "$CONTAINER" -- sh -c \
	'"$HOME/.local/share/Steam/steamrtarm64/steam" 2> "$HOME/.steam_bootstrap.log" || true'

# ----------------------------------------------------------------------- proton
if [ "${STEAM_SKIP_PROTON:-0}" != "1" ]; then
	log "Downloading Proton ARM64 (unofficial third-party build)"
	if curl -# -fL -o "$tempdir/proton.tar.gz" "$PROTONURL"; then
		log "Installing Proton ARM64"
		tar xzf "$tempdir/proton.tar.gz" -C "$STEAMDIR/compatibilitytools.d/"
	else
		warn "Proton download failed; Steam will still run, without Windows titles"
	fi
else
	log "Skipping Proton (STEAM_SKIP_PROTON=1)"
fi

# --------------------------------------------------------------------- launcher
log "Creating a launcher"
mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications"
cat > "$HOME/.local/bin/steam-arm64" <<EOF
#!/bin/sh
# Steam runs inside the glibc container; \$HOME is shared with the host.
exec distrobox enter --name "$CONTAINER" -- \\
	"\$HOME/.local/share/Steam/steamrtarm64/steam" "\$@"
EOF
chmod +x "$HOME/.local/bin/steam-arm64"

cat > "$HOME/.local/share/applications/steam-arm64.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Steam (ARM64)
Comment=Steam running in a glibc container
Exec=$HOME/.local/bin/steam-arm64 %U
Icon=steam
Terminal=false
Categories=Game;
StartupNotify=true
EOF

log "Done"
printf '\n'
printf '  Launch with:  %s\n' "$HOME/.local/bin/steam-arm64"
printf '  or from the applications menu as "Steam (ARM64)".\n\n'
printf '  If ~/.local/bin is not on your PATH, log out and back in first.\n'
