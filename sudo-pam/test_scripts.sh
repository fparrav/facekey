#!/usr/bin/env bash
# Self-tests for install.sh and uninstall.sh. Never touches the real system:
# every case runs against a fresh mktemp tree via FACEKEY_SUDO_ROOT, with a
# fake PAM module, and the final verification command is overridden.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
install_sh="$here/install.sh"
uninstall_sh="$here/uninstall.sh"

R=""            # current scratch tree
SL=""           # $R/etc/pam.d/sudo_local
BK=""           # sudo_local backup path
MOD=""          # installed module path
INSTALL_RC=0
UNINSTALL_RC=0
FAILS=0
TREES=()

# Removes every scratch tree on exit.
cleanup() {
    local t
    for t in ${TREES[@]+"${TREES[@]}"}; do
        rm -rf "$t"
    done
}
trap cleanup EXIT

check() {
    # check <name> <0|nonzero>: prints PASS/FAIL and counts failures.
    if [ "$2" -eq 0 ]; then
        echo "PASS: $1"
    else
        echo "FAIL: $1"
        FAILS=$((FAILS + 1))
    fi
}

assert() {
    # assert <name> <shell-expression>: PASS when the expression exits 0.
    local rc=0
    eval "$2" || rc=1
    check "$1" "$rc"
}

new_tree() {
    # Fresh scratch tree with the base sudo_local (saved as $R/orig) and fake modules.
    local r
    r=$(mktemp -d) || r=""
    if [ -z "$r" ]; then
        echo "FATAL: cannot create a scratch tree" >&2
        exit 1
    fi
    TREES+=("$r")
    R="$r"
    SL="$R/etc/pam.d/sudo_local"
    BK="$R/usr/local/lib/pam/sudo_local.facekey-backup"
    MOD="$R/usr/local/lib/pam/pam_facekey.so"
    mkdir -p "$R/etc/pam.d" "$R/usr/local/lib/pam" "$R/src"
    printf '# sudo_local\nauth       sufficient     pam_tid.so\n' > "$SL"
    cp "$SL" "$R/orig"
    printf 'fake facekey module A\n' > "$R/src/mod_a.so"
    printf 'fake facekey module B\n' > "$R/src/mod_b.so"
}

run_install() {
    # run_install <module-src> [check-cmd]. The check defaults to 'true' so the test
    # never depends on the real sudo (the script's own default is 'sudo -n true').
    local check="${2:-true}"
    env FACEKEY_SUDO_ROOT="$R" FACEKEY_SUDO_CHECK="$check" bash "$install_sh" "$1" > "$R/install.log" 2>&1
    INSTALL_RC=$?
}

run_uninstall() {
    env FACEKEY_SUDO_ROOT="$R" bash "$uninstall_sh" > "$R/uninstall.log" 2>&1
    UNINSTALL_RC=$?
}

echo "== case 1: install"
new_tree
run_install "$R/src/mod_a.so"
assert "1 install exits 0" '[ "$INSTALL_RC" -eq 0 ]'
assert "1 sudo_local has BEGIN marker" 'grep -q "# BEGIN facekey" "$SL"'
assert "1 sudo_local has END marker" 'grep -q "# END facekey" "$SL"'
lf=$(grep -n -F "auth       sufficient     /usr/local/lib/pam/pam_facekey.so" "$SL" | head -n 1 | cut -d: -f1)
lt=$(grep -n -F "pam_tid.so" "$SL" | head -n 1 | cut -d: -f1)
assert "1 facekey line before pam_tid line" '[ -n "$lf" ] && [ -n "$lt" ] && [ "$lf" -lt "$lt" ]'
assert "1 installed module identical to source" 'cmp -s "$MOD" "$R/src/mod_a.so"'
assert "1 backup exists" '[ -f "$BK" ]'
assert "1 backup identical to orig" 'cmp -s "$BK" "$R/orig"'

echo "== case 2: reinstall"
new_tree
run_install "$R/src/mod_a.so"
cp "$SL" "$R/snap1"
run_install "$R/src/mod_a.so"
assert "2 reinstall exits 0" '[ "$INSTALL_RC" -eq 0 ]'
assert "2 sudo_local identical between installs" 'cmp -s "$SL" "$R/snap1"'
assert "2 backup still identical to orig" 'cmp -s "$BK" "$R/orig"'

echo "== case 3: reinstall with another module"
new_tree
run_install "$R/src/mod_a.so"
v1=$(grep -F "# facekey-version:" "$SL")
run_install "$R/src/mod_b.so"
v2=$(grep -F "# facekey-version:" "$SL")
assert "3 version line changed" '[ -n "$v2" ] && [ "$v1" != "$v2" ]'
assert "3 block appears exactly once" '[ "$(grep -c "# BEGIN facekey" "$SL")" -eq 1 ]'

echo "== case 4: uninstall"
new_tree
run_install "$R/src/mod_a.so"
run_uninstall
assert "4 uninstall exits 0" '[ "$UNINSTALL_RC" -eq 0 ]'
assert "4 sudo_local restored identical to orig" 'cmp -s "$SL" "$R/orig"'
assert "4 module removed" '[ ! -f "$MOD" ]'
assert "4 backup removed" '[ ! -f "$BK" ]'

echo "== case 5: idempotent uninstall"
new_tree
run_install "$R/src/mod_a.so"
run_uninstall
run_uninstall
assert "5 second uninstall exits 0" '[ "$UNINSTALL_RC" -eq 0 ]'

echo "== case 6: no prior sudo_local"
new_tree
rm -f "$SL"
run_install "$R/src/mod_a.so"
assert "6 install exits 0" '[ "$INSTALL_RC" -eq 0 ]'
assert "6 sudo_local created with block" 'grep -q "# BEGIN facekey" "$SL"'
run_uninstall
assert "6 uninstall removes sudo_local" '[ ! -e "$SL" ]'

echo "== case 7: rollback on failed verification"
new_tree
run_install "$R/src/mod_a.so" "false"
assert "7 install exits non-zero" '[ "$INSTALL_RC" -ne 0 ]'
assert "7 sudo_local identical to orig" 'cmp -s "$SL" "$R/orig"'
assert "7 module removed" '[ ! -f "$MOD" ]'
assert "7 backup removed" '[ ! -f "$BK" ]'

echo "== case 8: rollback preserves a previous install"
new_tree
run_install "$R/src/mod_a.so"
cp "$SL" "$R/snap"
cp "$MOD" "$R/mod_installed"
run_install "$R/src/mod_b.so" "false"
assert "8 install B exits non-zero" '[ "$INSTALL_RC" -ne 0 ]'
assert "8 sudo_local identical to after first install" 'cmp -s "$SL" "$R/snap"'
assert "8 module still A" 'cmp -s "$MOD" "$R/mod_installed"'

echo "== case 9: verification passes with 'a password is required'"
new_tree
run_install "$R/src/mod_a.so" 'echo "sudo: a password is required"; false'
assert "9 install exits 0" '[ "$INSTALL_RC" -eq 0 ]'

echo "== case 10: unclosed block"
new_tree
printf '# sudo_local\nauth       sufficient     pam_tid.so\n# BEGIN facekey\n# facekey-version: 000000\nauth       sufficient     /usr/local/lib/pam/pam_facekey.so\n' > "$SL"
cp "$SL" "$R/pre"
run_install "$R/src/mod_a.so"
assert "10 install exits non-zero" '[ "$INSTALL_RC" -ne 0 ]'
assert "10 sudo_local unchanged" 'cmp -s "$SL" "$R/pre"'
assert "10 module removed" '[ ! -f "$MOD" ]'

if [ "$FAILS" -eq 0 ]; then
    echo "All facekey script self-tests passed."
    exit 0
else
    echo "$FAILS facekey script check(s) FAILED."
    exit 1
fi
