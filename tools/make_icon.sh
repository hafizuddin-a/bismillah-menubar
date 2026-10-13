#!/bin/zsh
# Regenerates Resources/AppIcon.icns from tools/make_icon.swift.
set -euo pipefail
cd "${0:A:h}/.."

TMP="$(mktemp -d)"
swiftc -O tools/make_icon.swift -o "$TMP/make_icon"
"$TMP/make_icon" "$TMP/AppIcon.iconset"
mkdir -p Resources
iconutil -c icns "$TMP/AppIcon.iconset" -o Resources/AppIcon.icns
cp "$TMP/AppIcon.iconset/icon_512x512@2x.png" "$TMP/preview.png"
echo "Wrote Resources/AppIcon.icns (preview: $TMP/preview.png)"
