#!/bin/bash
# Builds a release for GitHub Releases: dist/Bismillah-<version>.zip and its update signature
# dist/Bismillah-<version>.zip.sig. The signature is what lets installed copies update themselves, so it
# needs the private update key (default ~/.config/bismillah/update-signing.key; override with
# BISMILLAH_SIGNING_KEY). Make one with: tools/update_key.swift keygen <file>
set -e
cd "$(dirname "$0")"
KEY="${BISMILLAH_SIGNING_KEY:-$HOME/.config/bismillah/update-signing.key}"
[ -f "$KEY" ] || { echo "No update signing key at $KEY"; exit 1; }
BUILD=.build-tools
mkdir -p "$BUILD"
swiftc -O tools/update_key.swift -o "$BUILD/update_key"
# the key in the app must be the one we are about to sign with
[ "$("$BUILD/update_key" pubkey "$KEY")" = "$(tr -d '[:space:]' < tools/update-public-key.txt)" ] \
  || { echo "tools/update-public-key.txt doesn't match $KEY"; exit 1; }
./build.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Bismillah.app/Contents/Info.plist)
codesign --verify --deep --strict Bismillah.app
mkdir -p dist
ZIP="dist/Bismillah-$VERSION.zip"
rm -f "$ZIP" "$ZIP.sig"
ditto -c -k --norsrc --noextattr --keepParent Bismillah.app "$ZIP"
"$BUILD/update_key" sign "$KEY" "$ZIP" > "$ZIP.sig"
rm -rf "$BUILD"
echo "Created $ZIP and $ZIP.sig"
shasum -a 256 "$ZIP"
