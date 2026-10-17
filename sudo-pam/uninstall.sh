#!/usr/bin/env bash
# Uninstalls the facekey PAM module and its sudo_local entry, leaving nothing behind.
# No arguments; the app runs it as root. Honours FACEKEY_SUDO_ROOT to test in a scratch tree.
set -euo pipefail

# FACEKEY_SUDO_ROOT lets a test run against a scratch tree.
root="${FACEKEY_SUDO_ROOT:-}"
module_dir="${root}/usr/local/lib/pam"
module_dest="${module_dir}/pam_facekey.so"
pam_dir="${root}/etc/pam.d"
sudo_local="${pam_dir}/sudo_local"
# Kept beside the module: /etc/pam.d is SIP-protected and root cannot create other files there.
backup="${module_dir}/sudo_local.facekey-backup"

# As root on the real system, every directory above the install paths must be root-owned and
# closed to group and others, or an unprivileged user could swap what root is about to load.
require_root_owned() {
    local dir="$1"
    # The directory may not exist yet: check the nearest one that does.
    while [ ! -d "$dir" ]; do
        dir=$(dirname "$dir")
    done
    dir=$(cd -P "$dir" && pwd -P)
    while [ "$dir" != "/" ]; do
        local mode perm
        mode=$(stat -f '%Su %Sp' "$dir")
        perm="${mode#* }"
        if [ "${mode%% *}" != "root" ] || [ "${perm:5:1}" = "w" ] || [ "${perm:8:1}" = "w" ]; then
            echo "facekey: $dir must be owned by root and not writable by group or others" >&2
            exit 1
        fi
        dir=$(dirname "$dir")
    done
}

if [ "$(id -u)" -eq 0 ] && [ -z "$root" ]; then
    require_root_owned "$module_dir"
    require_root_owned "$pam_dir"
fi

# Drops the marked block, byte-for-byte around it. The result is built in a scratch directory and
# written over sudo_local in place, because SIP does not let root create other files in /etc/pam.d.
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
if [ -f "$sudo_local" ] && grep -q '^# BEGIN facekey$' "$sudo_local" && grep -q '^# END facekey$' "$sudo_local"; then
    tmp="$workdir/sudo_local.new"
    awk '
        $0 == "# BEGIN facekey" { skip = 1; next }
        skip && $0 == "# END facekey" { skip = 0; next }
        skip { next }
        { print }
        END { if (skip) exit 3 }
    ' "$sudo_local" > "$tmp" || exit 1
    # Install adds a final newline to an original that lacked one: when that is the only difference, give the original back.
    if [ -s "$backup" ] && [ -n "$(tail -c 1 "$backup")" ] && { cat "$backup"; echo; } | cmp -s - "$tmp"; then
        cp "$backup" "$tmp"
    fi
    if grep -q '[^[:space:]]' "$tmp"; then
        # Content survives: write it back over the file.
        cat "$tmp" > "$sudo_local"
        cmp -s "$tmp" "$sudo_local" || { echo "facekey: could not rewrite sudo_local" >&2; exit 1; }
    else
        # Only the block existed: install created the file, so delete it (or empty it if deleting is refused).
        rm -f "$sudo_local" 2>/dev/null || : > "$sudo_local"
    fi
fi

# Removes the backup and the module, then any directories that end up empty.
rm -f "$backup"
rm -f "$module_dest"
rmdir "$module_dir" 2>/dev/null || true
rmdir "${root}/usr/local/lib" 2>/dev/null || true

echo "facekey: removed"
