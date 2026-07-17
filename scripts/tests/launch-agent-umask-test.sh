#!/usr/bin/env zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

grep -Fq '"Umask": 0o077' "$ROOT/Sources/CodexAccountSwitcher/main.swift"
grep -Fq '"Umask": 0o077' "$ROOT/scripts/install-phone-gateway-agent.sh"
grep -Fq '"Umask": 0o077' "$ROOT/scripts/install-switcher-agent.sh"
grep -Fq '"Umask": 0o077' "$ROOT/scripts/setup-cloudflare-remote-access.sh"

python3 - "$ROOT/scripts/install-codepilot-local-agents.sh" <<'PY'
import re
import sys
from pathlib import Path

source = Path(sys.argv[1]).read_text(encoding="utf-8")
if re.search(r"<key>Umask</key>\s*<integer>63</integer>", source) is None:
    raise SystemExit("scheduler LaunchAgent must use an owner-only umask")
PY

echo "LaunchAgent umask test passed."
