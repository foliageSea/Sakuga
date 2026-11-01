#!/usr/bin/env bash
# Build a release app and package it using macOS system tools.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  printf 'Usage: %s [flutter build macos options]\n' "$0"
  printf 'Builds a release DMG in build/macos/dmg using FVM (or Flutter on PATH).\n'
  exit 0
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf 'Error: DMG builds require macOS and Xcode.\n' >&2
  exit 1
fi

# These options would skip the release build or change its expected location.
for arg in "$@"; do
  case "$arg" in
    --debug|--profile|--config-only|--flavor|--flavor=*)
      printf 'Error: unsupported DMG build option: %s\n' "$arg" >&2
      exit 1
      ;;
  esac
done

cd "$ROOT_DIR"
if command -v fvm >/dev/null 2>&1; then
  FLUTTER=(fvm flutter)
elif command -v flutter >/dev/null 2>&1; then
  FLUTTER=(flutter)
else
  printf 'Error: install FVM or add Flutter to PATH.\n' >&2
  exit 1
fi

"${FLUTTER[@]}" build macos --release "$@"

APP_PATH="$ROOT_DIR/build/macos/Build/Products/Release/Sakuga.app"
INFO_PLIST="$APP_PATH/Contents/Info.plist"
if [[ ! -f "$INFO_PLIST" ]]; then
  printf 'Error: release app not found: %s\n' "$APP_PATH" >&2
  exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")
EXECUTABLE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO_PLIST")
ARCHS=$(lipo -archs "$APP_PATH/Contents/MacOS/$EXECUTABLE")
case "$ARCHS" in
  arm64|x86_64) ARCH="$ARCHS" ;;
  *arm64*x86_64*|*x86_64*arm64*) ARCH=universal ;;
  *) printf 'Error: unsupported app architectures: %s\n' "$ARCHS" >&2; exit 1 ;;
esac
# Keep metadata safe for use as a filename, including custom build versions.
if [[ ! "$VERSION" =~ ^[A-Za-z0-9._-]+$ || ! "$BUILD_NUMBER" =~ ^[A-Za-z0-9._-]+$ ]]; then
  printf 'Error: version and build number must contain only letters, digits, dots, underscores or hyphens.\n' >&2
  exit 1
fi

OUTPUT_DIR="$ROOT_DIR/build/macos/dmg"
mkdir -p "$OUTPUT_DIR"
WORK_DIR=$(mktemp -d "$OUTPUT_DIR/.dmg-XXXXXX")
cleanup() {
  # Only remove the exact temporary directory created above.
  if [[ "$WORK_DIR" == "$OUTPUT_DIR"/.dmg-* && -d "$WORK_DIR" ]]; then
    rm -rf -- "$WORK_DIR"
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir "$WORK_DIR/staging"
ditto "$APP_PATH" "$WORK_DIR/staging/Sakuga.app"
ln -s /Applications "$WORK_DIR/staging/Applications"
DMG_NAME="Sakuga-${VERSION}+${BUILD_NUMBER}-macos-${ARCH}.dmg"
hdiutil create -volname Sakuga -srcfolder "$WORK_DIR/staging"   -format UDZO -ov "$WORK_DIR/$DMG_NAME"
hdiutil verify "$WORK_DIR/$DMG_NAME"
# Publish only after creation and verification succeed.
mv -f "$WORK_DIR/$DMG_NAME" "$OUTPUT_DIR/$DMG_NAME"
printf '\nDMG created: %s\n' "$OUTPUT_DIR/$DMG_NAME"
