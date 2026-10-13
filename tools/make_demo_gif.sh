#!/bin/zsh
# Regenerates the README's two animations, assets/demo-wake.gif and assets/demo-dhikr.gif, with the app's real
# renderers on a recreation of the design prototype's desktop. Uses the same Sources files as the app, so they
# always show the current animation.
set -euo pipefail
cd "${0:A:h}/.."
TMP="$(mktemp -d)"
swiftc -O -framework AppKit -framework QuartzCore \
  Sources/BismillahData.swift Sources/SVGPath.swift Sources/BismillahView.swift Sources/NotchPopup.swift tools/demo_gif/main.swift \
  -o "$TMP/demo_gif"
"$TMP/demo_gif" assets/demo-wake.gif assets/demo-dhikr.gif
rm -rf "$TMP"
ls -la assets/demo-wake.gif assets/demo-dhikr.gif
