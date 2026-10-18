#!/bin/zsh
# Usage: make-icon.sh OUT.icns
set -euo pipefail
HERE="${0:A:h}"; TMP="$(mktemp -d)"
swiftc -O "$HERE/make-icon.swift" -o "$TMP/mk" && "$TMP/mk" "$TMP/raw"
S="$TMP/AppIcon.iconset"; mkdir -p "$S"
for n in 16 32 128 256 512; do
  cp "$TMP/raw/icon_$n.png" "$S/icon_${n}x${n}.png"
  cp "$TMP/raw/icon_${n}x2.png" "$S/icon_${n}x${n}@2x.png"
done
iconutil -c icns "$S" -o "$1"
