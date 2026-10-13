#!/bin/zsh
# Regenerates assets/demo.gif for the README: the app's real popup renderer on a recreation of the
# design prototype's desktop. Uses the same Sources files as the app, so it always shows the current animation.
set -euo pipefail
cd "${0:A:h}/.."
TMP="$(mktemp -d)"
swiftc -O -framework AppKit -framework QuartzCore \
  Sources/BismillahData.swift Sources/SVGPath.swift Sources/BismillahView.swift tools/demo_gif/main.swift \
  -o "$TMP/demo_gif"
"$TMP/demo_gif" assets/demo.gif
rm -rf "$TMP"
ls -la assets/demo.gif
