#!/usr/bin/env bash
# Builds pam_facekey.so for every architecture sudo may run as, plus one universal file.
# FACEKEY_TEAM_ID is the signing team the module trusts; without it the module builds but
# ignores every request. Optional FACEKEY_BUNDLE_ID overrides the app identifier it expects,
# and FACEKEY_PAM_OUT the output directory (default: sudo-pam/out).
set -euo pipefail

cd "$(dirname "$0")"
out="${FACEKEY_PAM_OUT:-out}"
mkdir -p "$out"

arches="arm64e arm64"
defines=()
if [ -n "${FACEKEY_TEAM_ID:-}" ]; then
    defines+=("-DFACEKEY_TEAM_ID=\"${FACEKEY_TEAM_ID}\"")
else
    echo "warning: FACEKEY_TEAM_ID is empty; the module will ignore every request" >&2
fi
if [ -n "${FACEKEY_BUNDLE_ID:-}" ]; then
    defines+=("-DFACEKEY_BUNDLE_ID=\"${FACEKEY_BUNDLE_ID}\"")
fi

for arch in $arches; do
    clang -dynamiclib -arch "$arch" -Wall -Wextra -O2 ${defines[@]+"${defines[@]}"} \
        -o "$out/pam_facekey_${arch}.so" pam_facekey.c -framework Security -framework CoreFoundation -lpam
done

lipo -create "$out/pam_facekey_arm64e.so" "$out/pam_facekey_arm64.so" -output "$out/pam_facekey.so"

for arch in $arches; do
    echo "$out/pam_facekey_${arch}.so: $(lipo -archs "$out/pam_facekey_${arch}.so")"
done
echo "$out/pam_facekey.so: $(lipo -archs "$out/pam_facekey.so")"
