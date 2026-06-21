#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LABEL="${CODEPILOT_CLOUDFLARED_LAUNCHD_LABEL:-io.codepilot.phone-cloudflared}"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"

/usr/bin/python3 - "$ROOT" "$PLIST" "$LABEL" <<'PY'
import plistlib
import sys
from pathlib import Path

root = Path(sys.argv[1])
plist_path = Path(sys.argv[2])
label = sys.argv[3]
plist = {
    "Label": label,
    "ProgramArguments": [
        str(root / "scripts" / "start-phone-cloudflared.sh"),
    ],
    "RunAtLoad": True,
    "KeepAlive": True,
    "WorkingDirectory": str(root),
    "StandardOutPath": str(Path.home() / "Library" / "Logs" / "codex-phone-cloudflared.out.log"),
    "StandardErrorPath": str(Path.home() / "Library" / "Logs" / "codex-phone-cloudflared.err.log"),
}
plist_path.write_bytes(plistlib.dumps(plist, sort_keys=False))
PY

launchctl bootout "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl enable "gui/$(id -u)/$LABEL"
launchctl kickstart -k "gui/$(id -u)/$LABEL"

echo "Installed $LABEL"
