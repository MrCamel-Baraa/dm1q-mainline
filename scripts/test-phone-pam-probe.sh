#!/usr/bin/env bash
# PC-side test of scripts/phone-pam-probe.sh (docs/06 rule 3): a fake root tree with a systemd-user PAM file that needs pam_selinux.so while the
# module is missing, stub apk / systemctl / journalctl; checks the report content, that nothing is written, that a bare tree does not crash.
# Run with dash (skipped when not installed) and bash. Usage: bash scripts/test-phone-pam-probe.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
fail=0
ok()  { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; fail=1; }
expect() { if grep -qE -- "$3" "$1"; then ok "$2"; else bad "$2 (no match for: $3)"; fi; }
reject() { if grep -qE -- "$3" "$1"; then bad "$2 (unexpected: $3)"; else ok "$2"; fi; }

F="$W/full"; mkdir -p "$F/bin" "$F/etc/pam.d" "$F/usr/lib/pam.d" "$F/usr/lib/security" "$F/var/log"
printf 'account include system-auth\nsession required pam_selinux.so close\nsession required pam_loginuid.so\nsession include system-auth\n' > "$F/usr/lib/pam.d/systemd-user"
printf 'auth required pam_unix.so\nsession required pam_unix.so\n' > "$F/usr/lib/pam.d/system-auth"
printf 'auth required pam_unix.so\n' > "$F/etc/pam.d/login"
touch "$F/usr/lib/security/pam_unix.so" "$F/usr/lib/security/pam_loginuid.so"
printf '[21:25] upgrading systemd (255-r1 -> 256-r0)\n[21:25] upgrading linux-pam (1.7.1-r0 -> 1.7.2-r0)\n' > "$F/var/log/apk.log"
cat > "$F/bin/apk" <<'EOF'
#!/bin/sh
case "$1" in
info)
	if [ "$2" = -W ]; then echo "$3 is owned by systemd-pam-256-r0"; exit 0; fi
	printf 'systemd-256-r0 - system and service manager\nlinux-pam-1.7.2-r0 - PAM\nbash-5.3-r0 - unrelated shell\nshadow-4.18-r0 - login tools\n' ;;
esac
EOF
printf '#!/bin/sh\necho "user@10000.service - User Manager for UID 10000"\necho "     Active: failed (Result: exit-code)"\n' > "$F/bin/systemctl"
printf '#!/bin/sh\necho "Oct 19 user@10000.service: Failed at step PAM spawning /usr/lib/systemd/systemd: Operation not permitted"\n' > "$F/bin/journalctl"
chmod +x "$F/bin/apk" "$F/bin/systemctl" "$F/bin/journalctl"

B="$W/bare"; mkdir -p "$B/bin"
printf '#!/bin/sh\nexit 1\n' > "$B/bin/apk"; printf '#!/bin/sh\nexit 1\n' > "$B/bin/systemctl"; printf '#!/bin/sh\nexit 1\n' > "$B/bin/journalctl"
chmod +x "$B/bin/apk" "$B/bin/systemctl" "$B/bin/journalctl"

for sh in dash bash; do
	command -v "$sh" >/dev/null || { echo "skip $sh (not installed)"; continue; }
	echo "== $sh, full"
	before=$(cd "$F" && find . | sort && find . -type f -exec cksum {} + | sort)
	timeout 20 env ROOT="$F" APK="$F/bin/apk" SYSTEMCTL="$F/bin/systemctl" JOURNALCTL="$F/bin/journalctl" "$sh" "$HERE/phone-pam-probe.sh" > "$W/out-full" 2>&1; rc=$?
	[ "$rc" = 0 ] && ok "exits 0" || bad "exit $rc"
	after=$(cd "$F" && find . | sort && find . -type f -exec cksum {} + | sort)
	[ "$before" = "$after" ] && ok "nothing written" || bad "the probe changed the tree"
	O="$W/out-full"
	expect "$O" "selinux line found in systemd-user" "systemd-user"
	expect "$O" "matching line shown with number" "^2:session required pam_selinux\\.so close$"
	sed -n '/^== 1\./,/^== 2\./p' "$O" > "$W/sec1"
	reject "$W/sec1" "section 1: file without selinux not listed as a match" "^-- .*/system-auth$"
	expect "$O" "owner reported" "systemd-user: /usr/lib/pam.d/systemd-user is owned by systemd-pam-256-r0"
	expect "$O" "absent module reported" "pam_selinux\\.so: absent"
	expect "$O" "modules listed" "pam_loginuid\\.so"
	expect "$O" "relevant package kept" "^systemd-256-r0"
	expect "$O" "login package kept" "^shadow-4\\.18"
	reject "$O" "unrelated package dropped" "^bash-"
	expect "$O" "apk log tail" "upgrading systemd \\(255-r1 -> 256-r0\\)"
	expect "$O" "unit state" "Active: failed"
	expect "$O" "journal" "Failed at step PAM spawning"
	expect "$O" "full file dumped" "^session required pam_loginuid\\.so$"
	expect "$O" "ends with done" "^done$"
	echo "== $sh, bare"
	timeout 20 env ROOT="$B" APK="$B/bin/apk" SYSTEMCTL="$B/bin/systemctl" JOURNALCTL="$B/bin/journalctl" "$sh" "$HERE/phone-pam-probe.sh" > "$W/out-bare" 2>&1; rc=$?
	[ "$rc" = 0 ] && ok "bare: exits 0" || bad "bare: exit $rc"
	expect "$W/out-bare" "bare: absent dirs reported" "pam\\.d: absent"
	expect "$W/out-bare" "bare: no apk log message" "no /var/log/apk\\.log"
	expect "$W/out-bare" "bare: ends with done" "^done$"
done

echo "== static checks"
bash --posix -n "$HERE/phone-pam-probe.sh" && ok "bash --posix -n" || bad "bash --posix -n"
if command -v shellcheck >/dev/null; then
	shellcheck -s sh -S warning "$HERE/phone-pam-probe.sh" && ok "shellcheck -s sh -S warning" || bad "shellcheck"
else
	echo "  skip  shellcheck (not installed)"
fi

echo
[ "$fail" = 0 ] && echo "all tests passed" || { echo "SOME TESTS FAILED"; exit 1; }
