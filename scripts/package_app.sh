#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="P31n Insight"
PRODUCT_NAME="P31nInsight"
CONFIGURATION="${CONFIGURATION:-release}"

cd "$ROOT_DIR"
swift build --build-system native -c "$CONFIGURATION"

BIN_DIR="$(swift build --build-system native -c "$CONFIGURATION" --show-bin-path)"
BINARY="$BIN_DIR/$PRODUCT_NAME"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"
cp "$BINARY" "$MACOS/$PRODUCT_NAME"

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>P31nInsight</string>
    <key>CFBundleIdentifier</key>
    <string>com.xhugoliu.p31n-insight</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>P31n Insight</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>Collect physical key telemetry from your P31n keyboard over Bluetooth.</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 xhugoliu</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP_DIR"
echo "$APP_DIR"
