#!/usr/bin/env bash
# Installs the facekey PAM module and its sudo_local entry, rolling back on any failure.
# Usage: install.sh <path-to-pam_facekey.so>
# Optional FACEKEY_SUDO_ROOT prefixes every system path, to test in a scratch tree.
# Optional FACEKEY_SUDO_CHECK overrides the final verification command (default: sudo -n true as the console user).
set -euo pipefail

if [ $# -ne 1 ] || [ ! -f "$1" ]; then
    echo "facekey: argument must be a path to an existing regular file" >&2
    exit 2
fi
module_src="$1"

# FACEKEY_SUDO_ROOT lets a test run against a scratch tree.
root="${FACEKEY_SUDO_ROOT:-}"
module_dir="${root}/usr/local/lib/pam"
module_dest="${module_dir}/pam_facekey.so"
# The real absolute path, always: it is what goes inside sudo_local.
module_abs="/usr/local/lib/pam/pam_facekey.so"
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

# The module version is the content hash of the installed file.
version=$(shasum -a 256 "$module_src" | cut -d' ' -f1)

# Snapshot of what is there now, so a failure restores exactly this state.
workdir=$(mktemp -d)
local_pre="$workdir/sudo_local.pre"
module_pre="$workdir/pam_facekey.pre"
local_existed=0
module_existed=0
backup_made=0
[ -f "$sudo_local" ] && local_existed=1 && cp "$sudo_local" "$local_pre"
[ -f "$module_dest" ] && module_existed=1 && cp "$module_dest" "$module_pre"

# Gives an installed file its final mode and owner (owner only when running as root).
finalize() {
    chmod "$2" "$1"
    if [ "$(id -u)" -eq 0 ]; then
        chown root:wheel "$1"
    fi
}

# Puts a file in place through a temporary in the same directory, so the swap is atomic.
# mktemp creates it exclusively, and the directories were checked as closed to other users above.
place() {
    local tmp
    tmp=$(mktemp "$(dirname "$2")/.facekey.XXXXXX")
    cp "$1" "$tmp"
    mv "$tmp" "$2"
}

# Rewrites sudo_local in place. SIP lets root edit this one file but not create siblings next to it,
# so there is no temporary-and-rename here; the result is compared byte for byte instead.
write_sudo_local() {
    cat "$1" > "$sudo_local" && cmp -s "$1" "$sudo_local"
}

# Restores the snapshot taken above; never fails, so every step gets a chance to run.
restore() {
    set +e
    if [ "$local_existed" -eq 1 ]; then
        write_sudo_local "$local_pre"
    else
        rm -f "$sudo_local" 2>/dev/null || : > "$sudo_local"
    fi
    if [ "$module_existed" -eq 1 ]; then
        place "$module_pre" "$module_dest" && finalize "$module_dest" 0755
    else
        rm -f "$module_dest"
    fi
    [ "$backup_made" -eq 1 ] && rm -f "$backup"
    return 0
}

# Any exit before the install is confirmed restores the previous state.
confirmed=0
cleanup() {
    local status=$?
    if [ "$confirmed" -ne 1 ]; then
        restore
        echo "facekey: install failed, rolled back" >&2
    fi
    rm -rf "$workdir"
    exit "$status"
}
trap cleanup EXIT

mkdir -p "$module_dir"
chmod 755 "$module_dir"

# The backup is always the original: kept once, never refreshed from an installed block.
if [ "$local_existed" -eq 1 ] && ! grep -q '^# BEGIN facekey' "$sudo_local"; then
    backup_made=1
    place "$sudo_local" "$backup"
    finalize "$backup" 0644
fi

place "$module_src" "$module_dest"
finalize "$module_dest" 0755

# Drops any old block and inserts the new one before the first live pam_tid.so line (or at the end).
if [ "$local_existed" -eq 1 ]; then
    src="$sudo_local"
else
    src="/dev/null"
fi
awk -v version="$version" -v module_path="$module_abs" '
    function block() {
        print "# BEGIN facekey"
        print "# facekey-version: " version
        print "auth       sufficient     " module_path
        print "# END facekey"
    }
    $0 == "# BEGIN facekey" { skip = 1; next }
    skip && $0 == "# END facekey" { skip = 0; next }
    skip { next }
    !inserted && !/^[[:space:]]*#/ && /pam_tid\.so/ { block(); inserted = 1 }
    { print }
    END {
        # An opening marker with no closing one would swallow the rest of the file.
        if (skip) exit 3
        if (!inserted) block()
    }
' "$src" > "$workdir/sudo_local.new"
write_sudo_local "$workdir/sudo_local.new"

# A non-zero exit passes only when sudo still just asks for a password.
# By default sudo runs as the console user: as root it skips authentication and would prove nothing.
console_user=$(stat -f %Su /dev/console 2>/dev/null || true)
if [ -n "$console_user" ] && [ "$console_user" != "root" ]; then
    default_check="su \"$console_user\" -c 'sudo -n true'"
else
    default_check="sudo -n true"
fi
check="${FACEKEY_SUDO_CHECK:-$default_check}"
check_code=0
check_output=$(eval "$check" 2>&1) || check_code=$?
if [ "$check_code" -ne 0 ] && ! grep -q "a password is required" <<< "$check_output"; then
    restore
    confirmed=1
    echo "facekey: sudo check failed, rolled back" >&2
    [ -n "$check_output" ] && printf '%s\n' "$check_output" >&2
    exit 1
fi

confirmed=1
echo "facekey: installed $version"
