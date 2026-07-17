#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/CodePilot.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
FRAMEWORKS="$CONTENTS/Frameworks"

cd "$ROOT"
swift build -c release

rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES/scripts" "$RESOURCES/gateway" "$FRAMEWORKS"
cp "$ROOT/.build/release/CodexAccountSwitcher" "$MACOS/CodePilot"
if [[ -d "$ROOT/.build/arm64-apple-macosx/release/LiveKitWebRTC.framework" ]]; then
  cp -R "$ROOT/.build/arm64-apple-macosx/release/LiveKitWebRTC.framework" "$FRAMEWORKS/"
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS/CodePilot" 2>/dev/null || true
fi
cp "$ROOT/scripts/"*.sh "$RESOURCES/scripts/"
cp "$ROOT/scripts/"*.py "$RESOURCES/scripts/" 2>/dev/null || true
cp "$ROOT/gateway/codex_phone_gateway.py" "$RESOURCES/gateway/"
cp "$ROOT/gateway/remote_desktop_gateway.py" "$RESOURCES/gateway/"
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

SIGNING_IDENTITY="${CODEPILOT_SIGNING_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development:/{print $2; exit}')"
fi
if [[ -n "$SIGNING_IDENTITY" ]]; then
  if [[ -d "$FRAMEWORKS/LiveKitWebRTC.framework" ]]; then
    codesign --force --timestamp=none --sign "$SIGNING_IDENTITY" "$FRAMEWORKS/LiveKitWebRTC.framework"
  fi
  codesign --force --timestamp=none --options runtime --identifier io.codepilot.mac --sign "$SIGNING_IDENTITY" "$APP"
else
  echo "warning: no Apple Development signing identity found; macOS permissions may reset after rebuilds" >&2
fi

echo "$APP"
