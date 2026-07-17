#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."

gateway_python=""
python_candidates=(
  "${CODEPILOT_GATEWAY_PYTHON:-}"
  "$(command -v python3 2>/dev/null || true)"
  "$(command -v python3.13 2>/dev/null || true)"
  "$(command -v python3.12 2>/dev/null || true)"
  "$(command -v python3.11 2>/dev/null || true)"
  /opt/homebrew/bin/python3
  /usr/local/bin/python3
  /usr/bin/python3
)

for candidate in "${python_candidates[@]}"; do
  if [[ -n "$candidate" && -x "$candidate" ]] && "$candidate" -c 'import tomllib' >/dev/null 2>&1; then
    gateway_python="$candidate"
    break
  fi
done

if [[ -z "$gateway_python" ]]; then
  echo "CodePilot gateway requires Python 3.11 or newer (tomllib is unavailable)." >&2
  exit 1
fi

exec "$gateway_python" gateway/codex_phone_gateway.py --host 127.0.0.1 --port 18790
