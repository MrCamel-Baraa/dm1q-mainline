#!/bin/sh
# Phone-side, READ-ONLY probe of the PAM / systemd user-manager breakage found on 2026-10-19 (docs/11 section 9.10): since the `apk upgrade`
# of 2026-10-19 00:25 plasma-mobile.service dies because user@10000.service fails "at step PAM spawning" with
# "PAM unable to dlopen(/usr/lib/security/pam_selinux.so)". POSIX sh, run as root (collect-phone-state.sh --pam does that). Writes nothing.
# Prints: 1. every PAM config file that mentions selinux (with the matching lines) and the pam.d directory listings (names, sizes, dates)
#   2. which apk package owns those files and pam_selinux.so  3. the PAM modules that exist in /usr/lib/security and /lib/security
#   4. installed pam / systemd / selinux / shadow / login related packages with versions  5. the tail of /var/log/apk.log (what the upgrade changed)
#   6. the user@10000 unit state and its journal  7. the full systemd-user and system-auth PAM files
# Env (PC-side test): ROOT APK SYSTEMCTL JOURNALCTL
ROOT="${ROOT:-}"
APK="${APK:-apk}"
SYSTEMCTL="${SYSTEMCTL:-systemctl}"
JOURNALCTL="${JOURNALCTL:-journalctl}"
say() { echo; echo "== $*"; }

say "1. PAM config files mentioning selinux"
n=0
for d in "$ROOT/etc/pam.d" "$ROOT/usr/lib/pam.d"; do
	[ -d "$d" ] || { echo "$d: absent"; continue; }
	for f in "$d"/*; do
		[ -f "$f" ] || continue
		if grep -qi selinux "$f" 2>/dev/null; then
			n=1
			echo "-- $f"
			grep -n -i selinux "$f"
		fi
	done
done
[ "$n" = 1 ] || echo "(none)"
for d in "$ROOT/etc/pam.d" "$ROOT/usr/lib/pam.d"; do
	echo "listing $d:"
	ls -l "$d" 2>&1 | sed 's/^/  /'
done

say "2. owners (apk info -W)"
for f in /etc/pam.d/systemd-user /usr/lib/pam.d/systemd-user /etc/pam.d/system-auth /usr/lib/pam.d/system-auth /etc/pam.d/system-login /usr/lib/pam.d/system-login /usr/lib/security/pam_selinux.so; do
	[ -e "$ROOT$f" ] || { echo "$f: absent"; continue; }
	echo "$f: $("$APK" info -W "$f" 2>&1 | tr '\n' ' ')"
done

say "3. PAM modules present"
for d in "$ROOT/usr/lib/security" "$ROOT/lib/security"; do
	if [ -d "$d" ]; then echo "$d:"; ls "$d" | sed 's/^/  /'; else echo "$d: absent"; fi
done

say "4. packages (local apk database)"
"$APK" info -vv 2>/dev/null | grep -iE '^(linux-pam|pam|systemd|libselinux|selinux|shadow|login|elogind|polkit|libcap|postmarketos-base|postmarketos-ui|plasma-mobile|kwin|sddm|greetd)' | sort

say "5. apk log (tail)"
if [ -f "$ROOT/var/log/apk.log" ]; then tail -n 300 "$ROOT/var/log/apk.log"; else echo "(no /var/log/apk.log)"; fi

say "6. user@10000 unit"
"$SYSTEMCTL" status user@10000.service --no-pager 2>&1 | head -n 25
"$JOURNALCTL" -b -u user@10000.service --no-pager 2>&1 | tail -n 40

say "7. systemd-user and system-auth PAM files in full"
for f in "$ROOT/etc/pam.d/systemd-user" "$ROOT/usr/lib/pam.d/systemd-user" "$ROOT/etc/pam.d/system-auth" "$ROOT/usr/lib/pam.d/system-auth"; do
	if [ -f "$f" ]; then echo "-- $f"; cat "$f"; else echo "-- $f: absent"; fi
done

echo
echo "done"
