#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT/ios/CodexPhone/fastlane/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE" >&2
  exit 1
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

echo "Paste the full FASTLANE_SESSION value below."
echo "Finish with Ctrl-D on a new line."
cat > "$tmp"

if [[ ! -s "$tmp" ]]; then
  echo "No session was provided." >&2
  exit 1
fi

python3 - "$ENV_FILE" "$tmp" <<'PY'
from pathlib import Path
import os
import sys

env_path = Path(sys.argv[1])
session_path = Path(sys.argv[2])
session = session_path.read_text(encoding="utf-8").strip()
if not session:
    raise SystemExit("No session was provided.")

escaped = session.replace("\\", "\\\\").replace("'", "'\"'\"'")
line = f"FASTLANE_SESSION='{escaped}'"

lines = env_path.read_text(encoding="utf-8").splitlines()
updated = False
out = []
for raw in lines:
    if raw.startswith("FASTLANE_SESSION="):
        out.append(line)
        updated = True
    else:
        out.append(raw)
if not updated:
    out.append(line)

env_path.write_text("\n".join(out) + "\n", encoding="utf-8")
env_path.chmod(0o600)
PY

echo "Saved FASTLANE_SESSION to $ENV_FILE"
