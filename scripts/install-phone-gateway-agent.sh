#!/bin/zsh
set -euo pipefail

FORCE_RESTART="${CODEX_PHONE_GATEWAY_FORCE_RESTART:-0}"
if [[ "${1:-}" == "--force" ]]; then
  FORCE_RESTART="1"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
if [[ "$(basename "$ROOT")" == "Resources" && "$(basename "$(dirname "$ROOT")")" == "Contents" ]]; then
  APP_BUNDLE="$(dirname "$(dirname "$ROOT")")"
  REPO_ROOT="$(cd "$APP_BUNDLE/../../.." && pwd)"
  if [[ -f "$REPO_ROOT/gateway/codex_phone_gateway.py" ]]; then
    ROOT="$REPO_ROOT"
  fi
fi
LABEL="${CODEPILOT_GATEWAY_LAUNCHD_LABEL:-io.codepilot.phone-gateway}"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"

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

/usr/bin/python3 - "$ROOT" "$PLIST" "$LABEL" "$gateway_python" <<'PY'
import plistlib
import os
import sys
from pathlib import Path

root = Path(sys.argv[1])
plist_path = Path(sys.argv[2])
label = sys.argv[3]
python_path = Path(sys.argv[4])
env_path = Path.home() / ".codex-account-switcher" / "phone-gateway.env"
allowed_env_keys = {
    "CODEX_PHONE_APNS_CERT_PATH",
    "CODEX_PHONE_APNS_CERT_KEY_PATH",
    "CODEX_PHONE_APNS_TEAM_ID",
    "CODEX_PHONE_APNS_KEY_ID",
    "CODEX_PHONE_APNS_KEY_PATH",
    "CODEX_PHONE_APNS_TOPIC",
    "CODEPILOT_FILE_DOWNLOAD_ROOTS",
    "SUPABASE_ACCESS_TOKEN",
}
environment = {}
if env_path.is_file():
    os.chmod(env_path, 0o600)
    for raw_line in env_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        if key not in allowed_env_keys:
            continue
        environment[key] = value.strip().strip('"').strip("'")

plist = {
    "Label": label,
    "ProgramArguments": [
        str(python_path),
        str(root / "gateway" / "codex_phone_gateway.py"),
        "--host",
        "127.0.0.1",
        "--port",
        "18790",
    ],
    "RunAtLoad": True,
    "KeepAlive": True,
    "WorkingDirectory": str(root),
    "StandardOutPath": str(Path.home() / "Library" / "Logs" / "codex-phone-gateway.out.log"),
    "StandardErrorPath": str(Path.home() / "Library" / "Logs" / "codex-phone-gateway.err.log"),
}
if environment:
    plist["EnvironmentVariables"] = environment
plist_path.write_bytes(plistlib.dumps(plist, sort_keys=False))
os.chmod(plist_path, 0o600)
PY

gateway_jobs_state() {
  local token_file="$HOME/.codex-account-switcher/phone-gateway-token"
  [[ -f "$token_file" ]] || {
    echo "unknown"
    return 0
  }

  local token
  token="$(tr -d '\r\n' < "$token_file")"
  [[ -n "$token" ]] || {
    echo "unknown"
    return 0
  }

  local response
  response="$(/usr/bin/curl -fsS --max-time 2 \
    -H "Authorization: Bearer $token" \
    "http://127.0.0.1:18790/api/jobs/active" 2>/dev/null || true)"
  [[ -n "$response" ]] || {
    echo "unknown"
    return 0
  }

  /usr/bin/python3 -c '
import json
import sys

try:
    payload = json.loads(sys.stdin.read())
except json.JSONDecodeError:
    print("unknown")
    sys.exit(0)

jobs = payload.get("jobs")
if jobs is None and payload.get("job") is not None:
    jobs = [payload["job"]]
if not isinstance(jobs, list):
    print("unknown")
    sys.exit(0)

running = [
    job for job in jobs
    if isinstance(job, dict) and job.get("status") == "running"
]
print("active" if running else "idle")
' <<< "$response"
}

gateway_service_is_running() {
  launchctl print "gui/$(id -u)/$LABEL" 2>/dev/null | grep -q "state = running"
}

gateway_listener_pids() {
  /usr/sbin/lsof -nP -tiTCP:18790 -sTCP:LISTEN 2>/dev/null | sort -u || true
}

clear_stale_gateway_listener_if_safe() {
  local jobs_state="$1"
  local pids
  pids="$(gateway_listener_pids)"
  [[ -n "$pids" ]] || return 0

  if [[ "$FORCE_RESTART" != "1" ]]; then
    if [[ "$jobs_state" == "active" ]]; then
      echo "Restart deferred: codex-phone-gateway has a running Codex turn."
      exit 0
    fi
    if [[ "$jobs_state" == "unknown" ]]; then
      echo "Restart deferred: port 18790 is in use, but the script could not verify that the gateway is idle."
      echo "Run $0 after active phone turns finish, or run CODEX_PHONE_GATEWAY_FORCE_RESTART=1 $0 to force it."
      exit 0
    fi
  fi

  echo "Stopping stale codex-phone-gateway listener(s) on port 18790: ${(f)pids}"
  local pid
  for pid in ${(f)pids}; do
    [[ -n "$pid" ]] || continue
    /bin/kill "$pid" 2>/dev/null || true
  done
  sleep 1

  pids="$(gateway_listener_pids)"
  [[ -z "$pids" ]] || {
    echo "Port 18790 is still in use after stopping stale gateway listener(s): ${(f)pids}" >&2
    exit 1
  }
}

JOBS_STATE="$(gateway_jobs_state)"

if [[ "$FORCE_RESTART" != "1" ]]; then
  if [[ "$JOBS_STATE" == "active" ]]; then
    echo "Updated $PLIST"
    echo "Restart deferred: codex-phone-gateway has a running Codex turn."
    echo "Run $0 after the turn finishes, or run CODEX_PHONE_GATEWAY_FORCE_RESTART=1 $0 to force it."
    exit 0
  fi
  if [[ "$JOBS_STATE" == "unknown" ]] && gateway_service_is_running; then
    echo "Updated $PLIST"
    echo "Restart deferred: codex-phone-gateway is running, but the script could not verify that it is idle."
    echo "Run $0 after active phone turns finish, or run CODEX_PHONE_GATEWAY_FORCE_RESTART=1 $0 to force it."
    exit 0
  fi
fi

launchctl bootout "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || true
clear_stale_gateway_listener_if_safe "$JOBS_STATE"
launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl enable "gui/$(id -u)/$LABEL"
launchctl kickstart "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true

echo "Installed $LABEL"
