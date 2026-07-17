#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/CodePilot.app"
EXECUTABLE="$APP/Contents/MacOS/CodePilot"
LABEL="${CODEPILOT_SWITCHER_LAUNCHD_LABEL:-io.codepilot.switcher}"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

if [[ ! -x "$EXECUTABLE" ]]; then
  "$ROOT/scripts/build-app.sh" >/dev/null
fi

mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"

/usr/bin/python3 - "$ROOT" "$EXECUTABLE" "$PLIST" "$LABEL" <<'PY'
import plistlib
import os
import sys
from pathlib import Path

root = Path(sys.argv[1])
executable = Path(sys.argv[2])
plist_path = Path(sys.argv[3])
label = sys.argv[4]
plist = {
    "Label": label,
    "ProgramArguments": [
        str(executable),
    ],
    "RunAtLoad": True,
    "KeepAlive": {
        "SuccessfulExit": False,
    },
    "WorkingDirectory": str(root),
    "EnvironmentVariables": {
        "PATH": "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
    },
    "StandardOutPath": str(Path.home() / "Library" / "Logs" / "codex-account-switcher.out.log"),
    "StandardErrorPath": str(Path.home() / "Library" / "Logs" / "codex-account-switcher.err.log"),
    "LimitLoadToSessionType": "Aqua",
}
plist_path.write_bytes(plistlib.dumps(plist, sort_keys=False))
os.chmod(plist_path, 0o600)
PY

launchctl bootout "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl enable "gui/$(id -u)/$LABEL"
launchctl kickstart -k "gui/$(id -u)/$LABEL"

echo "Installed $LABEL"
