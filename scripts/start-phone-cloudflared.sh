#!/bin/zsh
set -euo pipefail

CONFIG="$HOME/.cloudflared/codepilot-config.yaml"
LEGACY="$HOME/.cloudflared/codex-phone-config.yaml"
if [ ! -f "$CONFIG" ] && [ -f "$LEGACY" ]; then
  CONFIG="$LEGACY"
fi

if command -v cloudflared >/dev/null 2>&1; then
  exec "$(command -v cloudflared)" tunnel --config "$CONFIG" run
fi

exec /opt/homebrew/bin/cloudflared tunnel --config "$CONFIG" run
