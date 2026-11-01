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

ICON_NAME=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$INFO_PLIST")
[[ "$ICON_NAME" == *.icns ]] || ICON_NAME="$ICON_NAME.icns"
ICON_PATH="$APP_PATH/Contents/Resources/$ICON_NAME"
if [[ ! -f "$ICON_PATH" ]]; then
  printf 'Error: app icon not found: %s\n' "$ICON_PATH" >&2
  exit 1
fi
SET_FILE=$(xcrun --find SetFile)

OUTPUT_DIR="$ROOT_DIR/build/macos/dmg"
mkdir -p "$OUTPUT_DIR"
WORK_DIR=$(mktemp -d "$OUTPUT_DIR/.dmg-XXXXXX")
MOUNT_DIR="$WORK_DIR/mount"
MOUNTED=false
cleanup() {
  if [[ "$MOUNTED" == true ]]; then
    if ! hdiutil detach "$MOUNT_DIR"; then
      printf 'Error: could not unmount %s; keeping temporary files.\n' "$MOUNT_DIR" >&2
      return 1
    fi
  fi
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
# Set the icon on the mounted volume before compressing the final image.
hdiutil create -volname Sakuga -srcfolder "$WORK_DIR/staging" \
  -format UDRW "$WORK_DIR/writable.dmg"
mkdir "$MOUNT_DIR"
hdiutil attach "$WORK_DIR/writable.dmg" -readwrite -nobrowse \
  -mountpoint "$MOUNT_DIR"
MOUNTED=true
cp "$ICON_PATH" "$MOUNT_DIR/.VolumeIcon.icns"
"$SET_FILE" -a C "$MOUNT_DIR"
hdiutil detach "$MOUNT_DIR"
MOUNTED=false
hdiutil convert "$WORK_DIR/writable.dmg" -format UDZO \
  -o "$WORK_DIR/$DMG_NAME"
hdiutil verify "$WORK_DIR/$DMG_NAME"
xcrun swift "$ROOT_DIR/tool/set_macos_icon.swift" \
  "$ICON_PATH" "$WORK_DIR/$DMG_NAME"
# Publish only after creation and verification succeed.
mv -f "$WORK_DIR/$DMG_NAME" "$OUTPUT_DIR/$DMG_NAME"
printf '\nDMG created: %s\n' "$OUTPUT_DIR/$DMG_NAME"
