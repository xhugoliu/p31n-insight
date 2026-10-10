#!/usr/bin/env bash
set -euo pipefail
PROBE_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$PROBE_DIR/../../dist/P31n Telemetry Probe.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$PROBE_DIR/../../.build/probe-module-cache"
xcrun swiftc -swift-version 6 -O \
  -module-cache-path "$PROBE_DIR/../../.build/probe-module-cache" \
  -framework AppKit -framework CoreBluetooth \
  "$PROBE_DIR/Sources/TelemetryProtocol.swift" "$PROBE_DIR/Sources/ProbeApp.swift" \
  -o "$APP_DIR/Contents/MacOS/p31n-telemetry-probe"
python3 - "$APP_DIR/Contents/Info.plist" "$HOME/Library/Application Support/P31n Telemetry Probe/Captures" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as f:
    plistlib.dump({
        'CFBundleIdentifier': 'com.xhugoliu.p31n-telemetry-probe',
        'CFBundleName': 'P31n Telemetry Probe',
        'CFBundleExecutable': 'p31n-telemetry-probe',
        'CFBundlePackageType': 'APPL',
        'CFBundleVersion': '1',
        'CFBundleShortVersionString': '0.1.0',
        'LSMinimumSystemVersion': '14.0',
        'NSBluetoothAlwaysUsageDescription': '连接 P31n 键盘，验证物理按键的蓝牙遥测事件。',
        'NSHighResolutionCapable': True,
        'ProbeLogDirectory': sys.argv[2],
    }, f)
PY
codesign --force --sign - "$APP_DIR"
"$APP_DIR/Contents/MacOS/p31n-telemetry-probe" --self-test
printf '%s\n' "$APP_DIR"
