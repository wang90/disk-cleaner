#!/bin/bash
# ============================================================================
#  Build DiskCleaner.app
#
#  Double-click this file, or run:  ./build.command
#
#  Requires only the macOS Command Line Tools (swiftc / sips / iconutil /
#  codesign / lipo).  Produces a Universal binary (arm64 + x86_64) when both
#  slices can be compiled, otherwise falls back to the native architecture.
#
#  Env:
#    ARCHS="arm64 x86_64"   which slices to build
#    NO_OPEN=1              do not open the app after building
#    DISKAPP_NO_PAUSE=1     do not wait for a key press
# ============================================================================
set -uo pipefail

cd "$(dirname "$0")" || exit 1
ROOT="$PWD"
BUILD="$ROOT/.build"
APP="$ROOT/DiskCleaner.app"
SCRIPT_SRC="$ROOT/scripts/diskautoclean.sh"
DEPLOY="14.0"

say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mError:\033[0m %s\n' "$*" >&2; exit 1; }

printf '==============================================\n'
printf '  Building DiskCleaner.app\n'
printf '==============================================\n'

[ -f "$SCRIPT_SRC" ] || die "scripts/diskautoclean.sh not found"
command -v swiftc >/dev/null 2>&1 || die "swiftc not found. Run: xcode-select --install"

rm -rf "$BUILD"
mkdir -p "$BUILD/modulecache" "$BUILD/AppIcon.iconset" || die "cannot create .build"

# ---------------------------------------------------------------- 1. compile
ARCHS_TO_BUILD="${ARCHS:-arm64 x86_64}"
BUILT=""
say "Compiling Swift (macOS $DEPLOY, archs: $ARCHS_TO_BUILD) ..."
for a in $ARCHS_TO_BUILD; do
  printf '    - %s ... ' "$a"
  if swiftc -parse-as-library -swift-version 5 \
        -target "${a}-apple-macosx${DEPLOY}" -O \
        -module-cache-path "$BUILD/modulecache" \
        -framework SwiftUI -framework AppKit \
        -o "$BUILD/DiskCleaner-$a" \
        Sources/*.swift >"$BUILD/cc-$a.log" 2>&1; then
    printf 'ok\n'
    BUILT="$BUILT $a"
  else
    printf 'failed (skipped)\n'
    sed -n '1,6p' "$BUILD/cc-$a.log" | sed 's/^/        /'
  fi
done
[ -n "$BUILT" ] || die "all architectures failed to compile"

say "Creating binary ..."
# shellcheck disable=SC2086
if [ "$(echo $BUILT | wc -w | tr -d ' ')" -gt 1 ]; then
  # shellcheck disable=SC2086
  lipo -create -output "$BUILD/DiskCleaner" $(for a in $BUILT; do echo "$BUILD/DiskCleaner-$a"; done) \
    || die "lipo failed"
  say "Universal binary: $(lipo -archs "$BUILD/DiskCleaner")"
else
  first_arch="$(echo "$BUILT" | awk '{print $1}')"
  cp "$BUILD/DiskCleaner-$first_arch" "$BUILD/DiskCleaner" || die "copy failed"
  say "Single-arch binary: $first_arch"
fi

# ---------------------------------------------------------------- 2. icon
say "Generating app icon ..."
ICON_OK=0
if command -v python3 >/dev/null 2>&1; then
  if python3 tools/make_icon.py "$BUILD/icon_1024.png" >/dev/null 2>&1; then
    gen() { sips -z "$1" "$1" "$BUILD/icon_1024.png" --out "$BUILD/AppIcon.iconset/$2" >/dev/null 2>&1; }
    gen 16   icon_16x16.png
    gen 32   icon_16x16@2x.png
    gen 32   icon_32x32.png
    gen 64   icon_32x32@2x.png
    gen 128  icon_128x128.png
    gen 256  icon_128x128@2x.png
    gen 256  icon_256x256.png
    gen 512  icon_256x256@2x.png
    gen 512  icon_512x512.png
    gen 1024 icon_512x512@2x.png
    iconutil -c icns "$BUILD/AppIcon.iconset" -o "$BUILD/AppIcon.icns" >/dev/null 2>&1 && ICON_OK=1
  fi
fi
[ "$ICON_OK" -eq 1 ] && say "Icon ready" || printf '    (no icon, using default)\n'

# ---------------------------------------------------------------- 3. bundle
say "Assembling .app ..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" || die "cannot create app bundle"

cp "$BUILD/DiskCleaner" "$APP/Contents/MacOS/DiskCleaner" || die "copy binary failed"
chmod +x "$APP/Contents/MacOS/DiskCleaner"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$SCRIPT_SRC" "$APP/Contents/Resources/diskautoclean.sh"
chmod +x "$APP/Contents/Resources/diskautoclean.sh"
[ "$ICON_OK" -eq 1 ] && cp "$BUILD/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# ---------------------------------------------------------------- 4. sign
say "Code signing (ad-hoc) ..."
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 \
  && say "Signed" \
  || printf '    (signing skipped)\n'

# ---------------------------------------------------------------- 5. verify
[ -x "$APP/Contents/MacOS/DiskCleaner" ] || die "bundle is incomplete"
plutil -lint "$APP/Contents/Info.plist" >/dev/null || die "Info.plist is invalid"

SIZE="$(du -sh "$APP" | awk '{print $1}')"
printf '\n==============================================\n'
printf '  Build succeeded\n'
printf '==============================================\n'
printf 'App:     %s\n' "$APP"
printf 'Archs:   %s\n' "$(lipo -archs "$APP/Contents/MacOS/DiskCleaner" 2>/dev/null || echo unknown)"
printf 'Version: %s\n' "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null)"
printf 'Size:    %s\n' "$SIZE"
printf '\nRun it:  open "%s"\n' "$APP"
printf 'Release: ./release.command   (zips it into dist/ with checksums)\n'

if [ "${NO_OPEN:-0}" != "1" ]; then
  read -r -t 5 -p "Press Enter to open the app now (auto-opens in 5s) ... " _ 2>/dev/null || true
  open "$APP" 2>/dev/null || true
fi

if [ "${DISKAPP_NO_PAUSE:-0}" != "1" ] && [ -t 0 ] && [ -t 1 ]; then
  read -r -p "Press Enter to close..." _ 2>/dev/null || true
fi
