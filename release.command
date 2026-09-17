#!/bin/bash
# ============================================================================
#  Package a release:  build -> zip -> sha256
#
#  Output (in dist/):
#     DiskCleaner-v<version>-macos-universal.zip
#     DiskCleaner-v<version>-macos-universal.zip.sha256
#
#  The zip contains DiskCleaner.app at its root, ready to drag into /Applications.
#  Use this to attach artifacts to a GitHub Release.
# ============================================================================
set -uo pipefail

cd "$(dirname "$0")" || exit 1
ROOT="$PWD"
DIST="$ROOT/dist"
APP="$ROOT/DiskCleaner.app"

say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mError:\033[0m %s\n' "$*" >&2; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist" 2>/dev/null)"
[ -n "$VERSION" ] || die "cannot read version from Resources/Info.plist"
NAME="DiskCleaner-v${VERSION}-macos-universal"
ZIP="$DIST/${NAME}.zip"

printf '==============================================\n'
printf '  Packaging DiskCleaner v%s\n' "$VERSION"
printf '==============================================\n'

# ---------------------------------------------------------------- 1. build
NO_OPEN=1 DISKAPP_NO_PAUSE=1 "$ROOT/build.command" || die "build failed"
[ -d "$APP" ] || die "DiskCleaner.app was not produced"

# ---------------------------------------------------------------- 2. zip
mkdir -p "$DIST"
rm -f "$ZIP" "$ZIP.sha256"

say "Zipping (ditto, keeps bundle metadata) ..."
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP" || die "ditto failed"

# ---------------------------------------------------------------- 3. checksum
say "Checksum ..."
( cd "$DIST" && shasum -a 256 "${NAME}.zip" > "${NAME}.zip.sha256" ) || die "shasum failed"

ARCHS="$(lipo -archs "$APP/Contents/MacOS/DiskCleaner" 2>/dev/null || echo unknown)"

printf '\n==============================================\n'
printf '  Release package ready\n'
printf '==============================================\n'
printf 'File:    %s\n' "$ZIP"
printf 'Size:    %s\n' "$(du -h "$ZIP" | awk '{print $1}')"
printf 'Archs:   %s\n' "$ARCHS"
printf 'Version: %s\n' "$VERSION"
printf '\nSHA-256:\n'
cat "$ZIP.sha256"
printf '\nUpload it to GitHub:\n'
printf '  gh release create v%s "%s" --title "DiskCleaner v%s" --notes-file CHANGELOG.md\n' \
  "$VERSION" "$ZIP" "$VERSION"

if [ "${DISKAPP_NO_PAUSE:-0}" != "1" ] && [ -t 0 ] && [ -t 1 ]; then
  read -r -p "Press Enter to close..." _ 2>/dev/null || true
fi
