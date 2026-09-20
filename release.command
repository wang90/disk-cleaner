#!/bin/bash
# ============================================================================
#  Package releases: build EACH architecture separately -> zip -> sha256
#
#  Output (in dist/):
#     DiskCleaner-v<ver>-macos-arm64.zip      Apple Silicon (M1/M2/M3/M4…)
#     DiskCleaner-v<ver>-macos-x86_64.zip     Intel
#     SHA256SUMS.txt                          checksums for all of the above
#
#  Each zip contains DiskCleaner.app at its root, ready to drag into /Applications.
#  Attach all of them to a GitHub Release.
#
#  Env:
#     ARCHS="arm64 x86_64"   which architectures to package (default: both)
#     DISKAPP_NO_PAUSE=1     do not wait for a key press
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

ARCHS_TO_BUILD="${ARCHS:-arm64 x86_64}"

printf '==============================================\n'
printf '  Packaging DiskCleaner v%s\n' "$VERSION"
printf '  Architectures: %s\n' "$ARCHS_TO_BUILD"
printf '==============================================\n'

mkdir -p "$DIST" || die "cannot create dist/"
rm -f "$DIST"/DiskCleaner-*-macos-*.zip "$DIST"/DiskCleaner-*-macos-*.zip.sha256 "$DIST/SHA256SUMS.txt"

PACKED=""

for arch in $ARCHS_TO_BUILD; do
  case "$arch" in
    arm64)  label="arm64" ;;
    x86_64) label="x86_64" ;;
    *) die "unsupported architecture: $arch (use arm64 or x86_64)" ;;
  esac

  printf '\n'
  say "Building $label ..."
  ARCHS="$arch" NO_OPEN=1 DISKAPP_NO_PAUSE=1 "$ROOT/build.command" || die "$label build failed"
  [ -d "$APP" ] || die "DiskCleaner.app was not produced"

  # 双保险：确认产物真的是单一架构，避免把通用包当成单架构发出去
  got="$(lipo -archs "$APP/Contents/MacOS/DiskCleaner" 2>/dev/null)"
  [ "$got" = "$arch" ] || die "$label: expected a $arch binary, got: $got"

  name="DiskCleaner-v${VERSION}-macos-${label}"
  zip="$DIST/${name}.zip"

  say "Zipping $name ..."
  rm -f "$zip" "$zip.sha256"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$zip" || die "ditto failed for $label"
  ( cd "$DIST" && shasum -a 256 "${name}.zip" > "${name}.zip.sha256" ) || die "shasum failed"

  PACKED="$PACKED ${name}|${arch}"
done

say "Writing SHA256SUMS.txt ..."
( cd "$DIST" && shasum -a 256 DiskCleaner-v"${VERSION}"-macos-*.zip > SHA256SUMS.txt ) || die "shasum failed"

printf '\n==============================================\n'
printf '  Release packages ready\n'
printf '==============================================\n'
for entry in $PACKED; do
  name="${entry%%|*}"
  arch="${entry##*|}"
  printf '  %-46s %8s  %s\n' "${name}.zip" \
    "$(du -h "$DIST/${name}.zip" | awk '{print $1}')" "$arch"
done
printf '\nVersion: %s\n' "$VERSION"
printf 'Folder:  %s\n' "$DIST"
printf '\nSHA256SUMS.txt:\n'
sed 's/^/  /' "$DIST/SHA256SUMS.txt"

printf '\nUpload to GitHub:\n'
printf '  gh release create v%s dist/DiskCleaner-v%s-macos-arm64.zip \\\n' "$VERSION" "$VERSION"
printf '      dist/DiskCleaner-v%s-macos-x86_64.zip dist/SHA256SUMS.txt \\\n' "$VERSION"
printf '      --title "DiskCleaner %s" --notes-file docs/releases/v%s.md\n' "$VERSION" "$VERSION"

if [ "${DISKAPP_NO_PAUSE:-0}" != "1" ] && [ -t 0 ] && [ -t 1 ]; then
  read -r -p "Press Enter to close..." _ 2>/dev/null || true
fi
