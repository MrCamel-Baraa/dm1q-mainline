#!/bin/sh
# Pre-allocate the numbered greeter accounts GDM needs.
#
# GDM >= 47 runs its greeter as a per-display user "gdm-greeter-<N>" and gets it
# from its GdmDynamicUserStore, which either finds the account already present
# ("preallocated") or asks systemd-userdbd to make one on the fly.  Alpine's
# systemd is built WITHOUT userdbd - no binary, no unit, no userdbctl - so the
# second path does not exist and gdm dies with
#
#   User 'gdm-greeter-2' not preallocated and system lacks userdb
#   GdmDisplay: Session never registered, failing
#
# in a tight loop; on this device that filled a 240 MB journal and core-dumped
# gdm, leaving a black screen.  The gdm package only creates the unnumbered
# "gdm-greeter", which is never the name GDM looks up.
#
# The ids come from 61184-65519, the range systemd itself reserves for dynamic
# users, so they cannot collide with anything Alpine allocates.  GDM refuses a
# home directory in /home or at the root, hence /var/lib.
set -eu

COUNT=${GDM_GREETER_COUNT:-10}
ROOT=${ROOT:-}
BASE_ID=${GDM_GREETER_BASE_ID:-61184}

passwd_file="$ROOT/etc/passwd"
group_file="$ROOT/etc/group"
shadow_file="$ROOT/etc/shadow"

# Start after anything already using the dynamic range, so re-running is safe.
first_id=$(awk -F: -v base="$BASE_ID" '
	$3 >= base && $3 < 65520 { if ($3 >= m) m = $3 + 1 }
	END { print (m ? m : base) }' "$passwd_file" "$group_file")

created=0
id=$first_id
for n in $(seq 1 "$COUNT"); do
	user="gdm-greeter-$n"
	home="/var/lib/$user"

	grep -q "^$user:" "$passwd_file" 2>/dev/null && continue

	printf '%s:x:%s:\n' "$user" "$id" >> "$group_file"
	printf '%s:x:%s:%s:GDM Greeter %s:%s:/sbin/nologin\n' \
		"$user" "$id" "$id" "$n" "$home" >> "$passwd_file"
	[ -f "$shadow_file" ] && printf '%s:!:::::::\n' "$user" >> "$shadow_file"

	mkdir -p "$ROOT$home"
	chown "$id:$id" "$ROOT$home" 2>/dev/null || true
	chmod 700 "$ROOT$home"

	id=$((id + 1))
	created=$((created + 1))
done

echo "gdm greeter accounts created: $created (ids ${first_id}-$((id - 1)))"
