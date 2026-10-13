#!/bin/bash
# Developer install: builds, copies the app to ~/Applications and opens it.
# (End users just download the zip from Releases and drag Bismillah.app to Applications.)
set -e
cd "$(dirname "$0")"
DEST="$HOME/Applications/Bismillah.app"

./build.sh
pkill -x Bismillah 2>/dev/null || true
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
cp -R Bismillah.app "$DEST"
open "$DEST"
echo "Installed to $DEST. Choose Launch at Login from its menu bar item to start it with your Mac."
