#!/bin/zsh
set -euo pipefail

exec /opt/homebrew/bin/cloudflared tunnel --config "$HOME/.cloudflared/codex-phone-config.yaml" run
