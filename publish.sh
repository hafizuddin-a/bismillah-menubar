#!/bin/bash
# Publishes the version in build.sh in one go:
#   1. builds and signs the release zip (release.sh)
#   2. pushes main and creates the GitHub release with the zip and its signature
#   3. updates the Homebrew cask in hafizuddin-a/homebrew-tap (creating the tap the first time)
#
#   ./publish.sh <release-notes.md>
#
# "{{SHA256}}" in the notes file is replaced with the zip's checksum. Commit your changes first.
set -e
cd "$(dirname "$0")"
NOTES="$1"
[ -f "$NOTES" ] || { echo "usage: ./publish.sh <release-notes.md>"; exit 1; }
REPO=hafizuddin-a/bismillah-menubar
TAP=hafizuddin-a/homebrew-tap
[ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "Commit your changes first."; exit 1; }

./release.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Bismillah.app/Contents/Info.plist)
ZIP="dist/Bismillah-$VERSION.zip"
SHA=$(shasum -a 256 "$ZIP" | awk '{print $1}')
WORK=$(mktemp -d)

echo "Publishing Bismillah $VERSION to GitHub..."
git push origin main
sed "s/{{SHA256}}/$SHA/g" "$NOTES" > "$WORK/notes.md"
gh release create "v$VERSION" "$ZIP" "$ZIP.sig" --repo "$REPO" --title "Bismillah $VERSION" --notes-file "$WORK/notes.md" --target main

echo "Updating the Homebrew tap..."
if ! gh repo view "$TAP" >/dev/null 2>&1; then
  gh repo create "$TAP" --public --description "Homebrew tap for my Mac apps"
  git init -q -b main "$WORK/tap"
  git -C "$WORK/tap" remote add origin "https://github.com/$TAP.git"
  cp tools/tap-README.md "$WORK/tap/README.md"
else
  gh repo clone "$TAP" "$WORK/tap" -- -q
fi
mkdir -p "$WORK/tap/Casks"
sed -e "s/@VERSION@/$VERSION/" -e "s/@SHA256@/$SHA/" tools/bismillah.rb.template > "$WORK/tap/Casks/bismillah.rb"
git -C "$WORK/tap" add -A
git -C "$WORK/tap" commit -q -m "bismillah $VERSION"
git -C "$WORK/tap" push -q origin main
rm -rf "$WORK"
echo "Done: https://github.com/$REPO/releases/tag/v$VERSION"
echo "Install with: brew install --cask hafizuddin-a/tap/bismillah"
