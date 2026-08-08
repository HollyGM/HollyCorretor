#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="HollyCorretor"
APP_VERSION="${HOLLY_VERSION:-0.2.0}"
APP_BUILD="${HOLLY_BUILD_NUMBER:-1}"
APP_DIR="$PROJECT_DIR/dist/${APP_NAME}.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
INFO_TEMPLATE="$PROJECT_DIR/Resources/Info.plist"

command -v swift >/dev/null
command -v codesign >/dev/null
test -f "$INFO_TEMPLATE"

cd "$PROJECT_DIR"
swift build -c release --product "$APP_NAME"
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BIN_DIR/$APP_NAME" "$MACOS_DIR/$APP_NAME"
cp "$INFO_TEMPLATE" "$CONTENTS_DIR/Info.plist"

/usr/bin/plutil -replace CFBundleShortVersionString -string "$APP_VERSION" "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -replace CFBundleVersion -string "$APP_BUILD" "$CONTENTS_DIR/Info.plist"

for bundle in "$BIN_DIR"/*.bundle; do
    if [[ -e "$bundle" ]]; then
        cp -R "$bundle" "$RESOURCES_DIR/"
    fi
done

chmod +x "$MACOS_DIR/$APP_NAME"
/usr/bin/plutil -lint "$CONTENTS_DIR/Info.plist"
/usr/bin/codesign --force --deep --sign - --timestamp=none "$APP_DIR"
/usr/bin/codesign --verify --deep --strict "$APP_DIR"

echo "$APP_DIR"
