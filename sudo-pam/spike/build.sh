#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
mkdir -p out

arches="arm64e arm64"
for arch in $arches; do
    clang -dynamiclib -arch "$arch" -o "out/pam_spike_${arch}.so" pam_spike.c -lpam
done

for arch in $arches; do
    echo "out/pam_spike_${arch}.so: $(lipo -archs "out/pam_spike_${arch}.so")"
done
