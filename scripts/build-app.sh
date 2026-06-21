#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/CodePilot.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

cd "$ROOT"
swift build -c release

rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES/scripts"
cp "$ROOT/.build/release/CodexAccountSwitcher" "$MACOS/CodePilot"
cp "$ROOT/scripts/"*.sh "$RESOURCES/scripts/"
cp "$ROOT/scripts/"*.py "$RESOURCES/scripts/" 2>/dev/null || true
chmod +x "$RESOURCES/scripts/"*.sh

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>CodePilot</string>
  <key>CFBundleIdentifier</key>
  <string>io.codepilot.mac</string>
  <key>CFBundleName</key>
  <string>CodePilot</string>
  <key>CFBundleDisplayName</key>
  <string>CodePilot</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST

echo "$APP"
