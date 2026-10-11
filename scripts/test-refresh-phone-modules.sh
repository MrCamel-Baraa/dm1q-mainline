#!/usr/bin/env bash
# PC-side tests for scripts/refresh-phone-modules.sh (--dry-run / --tar-out) and scripts/phone-swap-modules.sh
# (run against a fake root with a fake depmod). No phone, no sudo, no network.
#   bash scripts/test-refresh-phone-modules.sh [--real-apk FILE]   (--real-apk: also push the real kernel APK's
#   tarball through the phone script's checks on a fake root; default: the newest APK in pmbootstrap's packages)
# shellcheck disable=SC2015  # the `[ test ] && ok || bad` pattern is intentional (ok never fails)
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
DRV="$REPO/scripts/refresh-phone-modules.sh"
PHN="$REPO/scripts/phone-swap-modules.sh"
REAL=""; [ "${1:-}" = "--real-apk" ] && REAL="${2:-}"
[ -n "$REAL" ] || REAL="$(find "$HOME/.local/var/pmbootstrap/packages/edge/aarch64" -maxdepth 1 -name "linux-samsung-dm1q-mainline-*.apk" 2>/dev/null | sort -V | tail -n 1)"
T="$(mktemp -d /tmp/dm1q-test-modules.XXXXXX)"
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "  ok   $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL $1"; }
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }
nocheck() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then bad "$d"; else ok "$d"; fi; }

# --- fixtures -------------------------------------------------------------------------------------------------
mkmods() { # mkmods <dir> <release> <marker> [omit-module]
	local d="$1/usr/lib/modules/$2" mk="$3" omit="${4:-}"
	mkdir -p "$d/kernel/drivers/clk/qcom" "$d/kernel/drivers/phy/qualcomm" "$d/kernel/drivers/net/wireless/ath/ath11k" "$d/kernel/fs"
	[ "$omit" = gpucc ]   || echo "$mk" > "$d/kernel/drivers/clk/qcom/gpucc-sm8550.ko.zst"
	[ "$omit" = qmp ]     || echo "$mk" > "$d/kernel/drivers/phy/qualcomm/phy-qcom-qmp-pcie.ko.zst"
	[ "$omit" = ath11k ]  || echo "$mk" > "$d/kernel/drivers/net/wireless/ath/ath11k/ath11k_pci.ko.zst"
	echo "$mk" > "$d/kernel/fs/fuse.ko.zst"; echo "$mk" > "$d/kernel/fs/extra.ko.zst"; echo "$mk" > "$d/kernel/fs/extra2.ko.zst"
	echo "$mk" > "$d/modules.dep"
}
mkroot() { mkdir -p "$T/$1/usr/lib" "$T/$1/var/lib"; mkmods "$T/$1" 7.3.0-rc3 OLD; }
FAKEBIN="$T/bin"; mkdir -p "$FAKEBIN"
cat > "$FAKEBIN/depmod" <<'EOF'
#!/bin/sh
echo "depmod $*" >> "$DEPMOD_LOG"
EOF
chmod +x "$FAKEBIN/depmod"
export DEPMOD_LOG="$T/depmod.log"; : > "$DEPMOD_LOG"

mkdir -p "$T/apkroot/boot"; mkmods "$T/apkroot" 7.3.0-rc3 NEW
echo vmlinuz > "$T/apkroot/boot/vmlinuz"
( cd "$T/apkroot" && tar -czf "$T/fake.apk" boot usr )

echo "== static checks"
check "phone script: sh -n"            sh -n "$PHN"
# shellcheck disable=SC2016
check "phone script: dash -n (if any)" sh -c 'command -v dash >/dev/null || exit 0; dash -n "$1"' _ "$PHN"
check "phone script: shellcheck -s sh" shellcheck -s sh "$PHN"
check "driver: bash -n"                bash -n "$DRV"
check "driver: shellcheck"             shellcheck -s bash "$DRV"
check "test script: shellcheck"        shellcheck -s bash "$0"
check "driver --help prints usage"     bash -c "'$DRV' --help | grep -q 'refresh-phone-modules'"

echo "== driver --dry-run on a fake APK"
out="$(MIN_MODULES=4 "$DRV" --apk "$T/fake.apk" --dry-run --tar-out "$T/fake.tar" 2>&1)"; rc=$?
[ "$rc" = 0 ] && ok "dry run exits 0" || { bad "dry run exits 0 (rc=$rc)"; echo "$out"; }
case "$out" in *"release 7.3.0-rc3, 6 modules"*) ok "reports release and module count" ;; *) bad "reports release and module count"; echo "$out" ;; esac
case "$out" in *"the phone was not touched"*) ok "says the phone was not touched" ;; *) bad "says the phone was not touched" ;; esac
check "tarball paths all start with usr/lib/modules/7.3.0-rc3/" bash -c "! tar -tf '$T/fake.tar' | grep -v '^usr/lib/modules/7.3.0-rc3/'"
check "tarball is owned by root (numeric 0)" bash -c "tar -tvf '$T/fake.tar' --numeric-owner | awk '{print \$2}' | sort -u | grep -qx '0/0'"
nocheck "too few modules -> refused"      env MIN_MODULES=100 "$DRV" --apk "$T/fake.apk" --dry-run
nocheck "missing APK -> refused"          "$DRV" --apk "$T/nope.apk" --dry-run
nocheck "unknown option -> refused"       "$DRV" --bogus
mkdir -p "$T/apk2/usr/lib/modules/7.3.0-rc3" "$T/apk2/usr/lib/modules/7.4.0"; ( cd "$T/apk2" && tar -czf "$T/two.apk" usr )
nocheck "two release dirs in the APK -> refused" env MIN_MODULES=0 "$DRV" --apk "$T/two.apk" --dry-run

echo "== phone script on a fake root"
mkroot r1
out="$(ROOT="$T/r1" MIN_MODULES=4 PATH="$FAKEBIN:$PATH" sh "$PHN" "$T/fake.tar" 2>&1)"; rc=$?
[ "$rc" = 0 ] && ok "swap exits 0" || { bad "swap exits 0 (rc=$rc)"; echo "$out"; }
check "new tree in place (gpucc says NEW)"   grep -qx NEW "$T/r1/usr/lib/modules/7.3.0-rc3/kernel/drivers/clk/qcom/gpucc-sm8550.ko.zst"
check "modules.dep is the new one"           grep -qx NEW "$T/r1/usr/lib/modules/7.3.0-rc3/modules.dep"
check "old tree kept as a backup (says OLD)" bash -c "grep -rqx OLD '$T'/r1/var/lib/dm1q-modules-backup/7.3.0-rc3.*/modules.dep"
check "no staging dir left behind"           bash -c "! ls '$T'/r1/var/lib/ | grep -q 'modules-new'"
check "depmod ran with -b <root> <release>"  grep -qx "depmod -b $T/r1 7.3.0-rc3" "$DEPMOD_LOG"
case "$out" in *"installed 6 modules for kernel release 7.3.0-rc3"*) ok "prints what it installed" ;; *) bad "prints what it installed"; echo "$out" ;; esac
ROOT="$T/r1" MIN_MODULES=4 PATH="$FAKEBIN:$PATH" sh "$PHN" "$T/fake.tar" >/dev/null 2>&1
[ "$(find "$T/r1/var/lib/dm1q-modules-backup" -mindepth 1 -maxdepth 1 | wc -l)" = 2 ] && ok "second swap keeps a second backup" || bad "second swap keeps a second backup"
check "second swap: the first backup is still the OLD tree" bash -c "grep -rlx OLD '$T'/r1/var/lib/dm1q-modules-backup/*/modules.dep | grep -q ."

echo "== phone script refuses bad input and changes nothing"
# helper: tree is unchanged if every module file still says OLD
untouched() { ! grep -rLx OLD "$T/$1/usr/lib/modules/7.3.0-rc3" 2>/dev/null | grep -q .; }
mkroot r2
nocheck "too few modules -> refused"            env ROOT="$T/r2" MIN_MODULES=100 PATH="$FAKEBIN:$PATH" sh "$PHN" "$T/fake.tar"
check   "  ... and the old tree is untouched"   untouched r2
for omit in gpucc qmp ath11k; do
	mkdir -p "$T/om-$omit/boot"; mkmods "$T/om-$omit" 7.3.0-rc3 NEW "$omit"; ( cd "$T/om-$omit" && tar -cf "$T/om-$omit.tar" usr )
	nocheck "tarball without the $omit module -> refused" env ROOT="$T/r2" MIN_MODULES=4 PATH="$FAKEBIN:$PATH" sh "$PHN" "$T/om-$omit.tar"
done
check   "  ... and the old tree is still untouched" untouched r2
mkdir -p "$T/stray/usr/lib/other"; echo x > "$T/stray/usr/lib/other/file"; mkmods "$T/stray" 7.3.0-rc3 NEW
( cd "$T/stray" && tar -cf "$T/stray.tar" usr )
nocheck "tarball with paths outside usr/lib/modules/<rel> -> refused" env ROOT="$T/r2" MIN_MODULES=4 PATH="$FAKEBIN:$PATH" sh "$PHN" "$T/stray.tar"
mkdir -p "$T/nodep/usr/lib/modules/7.3.0-rc3/kernel"; echo x > "$T/nodep/usr/lib/modules/7.3.0-rc3/kernel/a.ko.zst"; ( cd "$T/nodep" && tar -cf "$T/nodep.tar" usr )
nocheck "tarball without modules.dep -> refused"  env ROOT="$T/r2" MIN_MODULES=1 PATH="$FAKEBIN:$PATH" sh "$PHN" "$T/nodep.tar"
nocheck "no such tarball -> refused"              env ROOT="$T/r2" sh "$PHN" "$T/nope.tar"
nocheck "no argument -> usage, rc 2"              env ROOT="$T/r2" sh "$PHN"
nocheck "unknown option -> rc 2"                  env ROOT="$T/r2" sh "$PHN" --bogus
mkdir -p "$T/bare"; nocheck "root without usr/lib/modules -> refused" env ROOT="$T/bare" MIN_MODULES=4 sh "$PHN" "$T/fake.tar"
if [ "$(id -u)" != 0 ]; then
	nocheck "not root and no fake ROOT -> refused" env -u ROOT sh "$PHN" "$T/fake.tar"
else
	echo "  skip not-root test (running as root)"
fi
check   "all refusals left the old tree in place" untouched r2

echo "== --reboot"
mkroot r3
ROOT="$T/r3" MIN_MODULES=4 REBOOT_CMD="touch $T/rebooted" PATH="$FAKEBIN:$PATH" sh "$PHN" "$T/fake.tar" --reboot >/dev/null 2>&1
for _ in 1 2 3 4 5 6 7 8; do [ -e "$T/rebooted" ] && break; sleep 1; done
[ -e "$T/rebooted" ] && ok "--reboot runs the reboot command ~2 s later" || bad "--reboot runs the reboot command ~2 s later"
mkroot r4
ROOT="$T/r4" MIN_MODULES=4 REBOOT_CMD="touch $T/rebooted4" PATH="$FAKEBIN:$PATH" sh "$PHN" "$T/fake.tar" >/dev/null 2>&1; sleep 3
[ ! -e "$T/rebooted4" ] && ok "no --reboot -> no reboot" || bad "no --reboot -> no reboot"

echo "== the real kernel APK through both scripts"
if [ -n "$REAL" ] && [ -f "$REAL" ]; then
	echo "  APK: $(basename "$REAL")"
	out="$("$DRV" --apk "$REAL" --dry-run --tar-out "$T/real.tar" 2>&1)"; rc=$?
	[ "$rc" = 0 ] && ok "driver --dry-run on the real APK" || { bad "driver --dry-run on the real APK"; echo "$out"; }
	echo "$out" | grep -E "^release" | sed 's/^/    /'
	mkroot rr
	out="$(ROOT="$T/rr" PATH="$FAKEBIN:$PATH" sh "$PHN" "$T/real.tar" 2>&1)"; rc=$?
	[ "$rc" = 0 ] && ok "phone script accepts the real tarball (default MIN_MODULES=1500)" || { bad "phone script accepts the real tarball"; echo "$out"; }
	echo "$out" | grep -E "^installed" | sed 's/^/    /'
	check "real tree: gpucc / qmp-pcie / ath11k_pci / modules.dep present" bash -c "cd '$T/rr/usr/lib/modules/7.3.0-rc3' && ls kernel/drivers/clk/qcom/gpucc-sm8550.ko.zst kernel/drivers/phy/qualcomm/phy-qcom-qmp-pcie.ko.zst kernel/drivers/net/wireless/ath/ath11k/ath11k_pci.ko.zst modules.dep"
	check "real tree: modules are valid zstd (sampled)" bash -c "cd '$T/rr/usr/lib/modules/7.3.0-rc3' && find kernel -name '*.ko.zst' | head -n 40 | xargs zstd -tq"
else
	echo "  skip: no kernel APK found"
fi

echo
echo "$pass passed, $fail failed"
[ "$fail" = 0 ] && echo "ALL PASS" || exit 1
