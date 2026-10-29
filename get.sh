#!/bin/bash
# Installs the latest Bismillah release, no Homebrew needed:
#
#   curl -fsSL https://raw.githubusercontent.com/hafizuddin-a/bismillah-menubar/main/get.sh | bash
#
# It downloads the release zip from GitHub, checks it, puts Bismillah.app in /Applications (or ~/Applications if
# that isn't writable) and opens it. Files downloaded with curl aren't quarantined, so macOS doesn't show its
# "can't verify the developer" warning. Running it again reinstalls the latest version.
# BISMILLAH_DIR=<folder> installs somewhere else; BISMILLAH_NO_OPEN=1 doesn't open the app afterwards.
set -euo pipefail

REPO=hafizuddin-a/bismillah-menubar
say() { printf '%s\n' "$*"; }
fail() { printf 'Bismillah install failed: %s\n' "$*" >&2; exit 1; }

[ "$(uname)" = "Darwin" ] || fail "Bismillah is a Mac app."
[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 14 ] || fail "it needs macOS 14 or later."

if [ -n "${BISMILLAH_DIR:-}" ]; then
  DIR="$BISMILLAH_DIR"
elif [ -w /Applications ]; then
  DIR=/Applications
else
  DIR="$HOME/Applications"
fi
mkdir -p "$DIR" || fail "can't create $DIR."
[ -w "$DIR" ] || fail "can't write to $DIR."

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

say "Looking up the latest release..."
curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" -o "$WORK/release.json" || fail "couldn't reach GitHub."
TAG=$(grep -m1 '"tag_name"' "$WORK/release.json" | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')
URL=$(grep '"browser_download_url"' "$WORK/release.json" | grep -E '\.zip"' | head -1 | sed -E 's/.*"(https[^"]+)".*/\1/')
[ -n "$TAG" ] && [ -n "$URL" ] || fail "couldn't find the download in the latest release."

say "Downloading Bismillah $TAG..."
curl -fSL --progress-bar "$URL" -o "$WORK/Bismillah.zip" || fail "the download didn't finish."

# The release notes list the zip's SHA-256; check it when it's there.
WANT=$(grep -oE 'SHA-256 of [^`]*`[0-9a-f]{64}`' "$WORK/release.json" | head -1 | grep -oE '[0-9a-f]{64}' || true)
if [ -n "$WANT" ]; then
  GOT=$(shasum -a 256 "$WORK/Bismillah.zip" | awk '{print $1}')
  [ "$GOT" = "$WANT" ] || fail "the download doesn't match its published checksum. Nothing was installed."
fi

ditto -x -k "$WORK/Bismillah.zip" "$WORK/unzipped" || fail "couldn't unzip the download."
[ -d "$WORK/unzipped/Bismillah.app" ] || fail "Bismillah.app isn't in the download."
codesign --verify --deep "$WORK/unzipped/Bismillah.app" 2>/dev/null || fail "the app's signature doesn't check out. Nothing was installed."

pkill -x Bismillah 2>/dev/null && sleep 1 || true
rm -rf "$DIR/Bismillah.app"
ditto "$WORK/unzipped/Bismillah.app" "$DIR/Bismillah.app"
xattr -dr com.apple.quarantine "$DIR/Bismillah.app" 2>/dev/null || true

say "Installed Bismillah $TAG to $DIR."
if [ -z "${BISMILLAH_NO_OPEN:-}" ]; then
  open "$DIR/Bismillah.app"
  say "Choose Launch at Login from its menu bar item (بسم الله) to start it with your Mac."
fi
