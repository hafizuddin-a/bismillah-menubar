#!/bin/bash
# Builds a release zip for GitHub Releases: dist/Bismillah-<version>.zip
set -e
cd "$(dirname "$0")"
./build.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Bismillah.app/Contents/Info.plist)
codesign --verify --deep --strict Bismillah.app
mkdir -p dist
ZIP="dist/Bismillah-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --norsrc --noextattr --keepParent Bismillah.app "$ZIP"
echo "Created $ZIP"
shasum -a 256 "$ZIP"
