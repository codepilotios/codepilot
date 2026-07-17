#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$HOME/.codex-account-switcher"
CLOUDFLARED_DIR="$HOME/.cloudflared"
CONFIG_PATH="$CLOUDFLARED_DIR/codepilot-config.yaml"
LEGACY_CONFIG_PATH="$CLOUDFLARED_DIR/codex-phone-config.yaml"
METADATA_PATH="$APP_DIR/cloudflare-setup.json"
LABEL="${CODEPILOT_CLOUDFLARED_LAUNCHD_LABEL:-io.codepilot.phone-cloudflared}"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
GATEWAY_URL="${CODEPILOT_GATEWAY_URL:-http://127.0.0.1:18790}"

mkdir -p "$APP_DIR" "$CLOUDFLARED_DIR"

cloudflared_bin() {
  if command -v cloudflared >/dev/null 2>&1; then
    command -v cloudflared
    return 0
  fi
  if [ -x /opt/homebrew/bin/cloudflared ]; then
    echo /opt/homebrew/bin/cloudflared
    return 0
  fi
  if [ -x /usr/local/bin/cloudflared ]; then
    echo /usr/local/bin/cloudflared
    return 0
  fi
  return 1
}

brew_bin() {
  if command -v brew >/dev/null 2>&1; then
    command -v brew
    return 0
  fi
  if [ -x /opt/homebrew/bin/brew ]; then
    echo /opt/homebrew/bin/brew
    return 0
  fi
  if [ -x /usr/local/bin/brew ]; then
    echo /usr/local/bin/brew
    return 0
  fi
  return 1
}

write_metadata() {
  local mode="$1"
  local hostname="$2"
  local tunnel_name="$3"
  local tunnel_id="$4"
  /usr/bin/python3 - "$METADATA_PATH" "$mode" "$hostname" "$tunnel_name" "$tunnel_id" "$CONFIG_PATH" "$LABEL" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

path = Path(sys.argv[1])
payload = {
    "mode": sys.argv[2],
    "hostname": sys.argv[3],
    "tunnelName": sys.argv[4],
    "tunnelId": sys.argv[5],
    "configPath": sys.argv[6],
    "launchAgentLabel": sys.argv[7],
    "lastVerifiedAt": None,
    "updatedAt": datetime.now(timezone.utc).isoformat(),
}
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(payload, indent=2) + "\n")
PY
}

status() {
  local cf=""
  local brew=""
  cf="$(cloudflared_bin 2>/dev/null || true)"
  brew="$(brew_bin 2>/dev/null || true)"
  /usr/bin/python3 - "$cf" "$brew" "$CONFIG_PATH" "$LEGACY_CONFIG_PATH" "$METADATA_PATH" "$PLIST" <<'PY'
import json
import sys
from pathlib import Path

cf, brew, config, legacy, metadata, plist = sys.argv[1:]
print(json.dumps({
    "cloudflaredPath": cf or None,
    "homebrewPath": brew or None,
    "configPath": config if Path(config).exists() else None,
    "legacyConfigPath": legacy if Path(legacy).exists() else None,
    "metadataPath": metadata if Path(metadata).exists() else None,
    "launchAgentPath": plist if Path(plist).exists() else None,
}, indent=2))
PY
}

install_cloudflared() {
  if cloudflared_bin >/dev/null 2>&1; then
    echo "cloudflared already installed at $(cloudflared_bin)"
    return 0
  fi

  local brew
  brew="$(brew_bin)" || {
    echo "Homebrew is missing. Install Homebrew or install cloudflared manually from Cloudflare." >&2
    exit 20
  }
  "$brew" install cloudflared
}

login() {
  local cf
  cf="$(cloudflared_bin)" || {
    echo "cloudflared is missing." >&2
    exit 21
  }
  "$cf" tunnel login
}

parse_tunnel_id() {
  /usr/bin/python3 -c '
import json
import re
import sys

text = sys.stdin.read()
try:
    decoded = json.loads(text)
    if isinstance(decoded, dict) and decoded.get("id"):
        print(decoded["id"])
        raise SystemExit
except Exception:
    pass

match = re.search(r"[0-9a-fA-F-]{20,}", text)
print(match.group(0) if match else "")
'
}

configure_permanent() {
  local hostname=""
  local tunnel_name="codepilot"
  while [ $# -gt 0 ]; do
    case "$1" in
      --hostname)
        hostname="$2"
        shift 2
        ;;
      --tunnel-name)
        tunnel_name="$2"
        shift 2
        ;;
      *)
        echo "Unknown argument: $1" >&2
        exit 2
        ;;
    esac
  done
  [ -n "$hostname" ] || {
    echo "--hostname is required" >&2
    exit 2
  }

  local cf create_output tunnel_id
  cf="$(cloudflared_bin)" || {
    echo "cloudflared is missing." >&2
    exit 21
  }
  create_output="$("$cf" tunnel create "$tunnel_name" 2>&1 || true)"
  tunnel_id="$(printf '%s' "$create_output" | parse_tunnel_id)"
  "$cf" tunnel route dns "$tunnel_name" "$hostname"

  cat > "$CONFIG_PATH" <<EOF
tunnel: $tunnel_name
credentials-file: $CLOUDFLARED_DIR/$tunnel_id.json

ingress:
  - hostname: $hostname
    service: $GATEWAY_URL
  - service: http_status:404
EOF

  write_metadata permanent "$hostname" "$tunnel_name" "$tunnel_id"
  echo "Configured Cloudflare Tunnel for https://$hostname"
}

install_service() {
  mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
  /usr/bin/python3 - "$ROOT" "$PLIST" "$LABEL" <<'PY'
import plistlib
import os
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
    "StandardOutPath": str(Path.home() / "Library" / "Logs" / "codepilot-cloudflared.out.log"),
    "StandardErrorPath": str(Path.home() / "Library" / "Logs" / "codepilot-cloudflared.err.log"),
}
plist_path.write_bytes(plistlib.dumps(plist, sort_keys=False))
os.chmod(plist_path, 0o600)
PY

  launchctl bootout "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || true
  launchctl bootstrap "gui/$(id -u)" "$PLIST"
  launchctl enable "gui/$(id -u)/$LABEL"
  launchctl kickstart -k "gui/$(id -u)/$LABEL"
  echo "Installed $LABEL"
}

verify_url() {
  local url=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --url)
        url="$2"
        shift 2
        ;;
      *)
        echo "Unknown argument: $1" >&2
        exit 2
        ;;
    esac
  done
  [ -n "$url" ] || {
    echo "--url is required" >&2
    exit 2
  }
  curl -fsS "$url/api/health" >/dev/null
  echo "verified $url"
}

start_trycloudflare() {
  local cf
  cf="$(cloudflared_bin)" || {
    echo "cloudflared is missing." >&2
    exit 21
  }
  "$cf" tunnel --url "$GATEWAY_URL"
}

case "${1:-}" in
  status)
    status
    ;;
  install-cloudflared)
    install_cloudflared
    ;;
  login)
    login
    ;;
  configure-permanent)
    shift
    configure_permanent "$@"
    ;;
  install-service)
    install_service
    ;;
  restart-service)
    install_service
    ;;
  verify)
    shift
    verify_url "$@"
    ;;
  start-trycloudflare)
    start_trycloudflare
    ;;
  *)
    echo "Usage: $0 status|install-cloudflared|login|configure-permanent|install-service|restart-service|verify|start-trycloudflare" >&2
    exit 2
    ;;
esac
