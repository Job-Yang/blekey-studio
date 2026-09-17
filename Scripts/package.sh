#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKSPACE="$ROOT/BleKeyStudio.xcworkspace"
DERIVED_DATA="$ROOT/DerivedData/BleKeyStudioRelease"
DIST="$ROOT/dist"
VERSION="0.3.4"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-263.app/Contents/Developer}"
export DEVELOPER_DIR

mkdir -p "$DIST"

xcodebuildmcp macos build \
  --workspace-path "$WORKSPACE" \
  --scheme BleKeyStudio \
  --configuration Release \
  --derived-data-path "$DERIVED_DATA" \
  --arch arm64 \
  --prefer-xcodebuild true \
  --output text

APP_PATH="$DERIVED_DATA/Build/Products/Release/BleKey Studio.app"
DMG_PATH="$DIST/BleKey-Studio-$VERSION.dmg"
STAGE="$(mktemp -d "$DERIVED_DATA/BleKeyStudioPackage.XXXXXX")"

if [[ ! -d "$APP_PATH" ]]; then
  print -u2 "Release app not found: $APP_PATH"
  exit 1
fi

codesign \
  --force \
  --deep \
  --sign - \
  --entitlements "$ROOT/Config/BleKeyStudio.entitlements" \
  "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
/usr/bin/ditto "$APP_PATH" "$STAGE/BleKey Studio.app"
ln -sfn /Applications "$STAGE/Applications"
hdiutil create \
  -volname "BleKey Studio" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

print "$DMG_PATH"
