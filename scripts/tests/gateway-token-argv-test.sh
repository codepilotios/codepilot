#!/usr/bin/env zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
INSTALLER="$ROOT/scripts/install-phone-gateway-agent.sh"
TUNNEL_SETUP="$ROOT/scripts/setup-cloudflare-remote-access.sh"

if grep -Eq -- '(-H|--header)[[:space:]]+"Authorization: Bearer \\$token"' "$INSTALLER" "$TUNNEL_SETUP"; then
  echo "Gateway tooling exposes the bearer token through curl arguments" >&2
  exit 1
fi

grep -Fq -- '--config -' "$INSTALLER"
grep -Fq -- 'printf '\''header = "Authorization: Bearer %s"' "$INSTALLER"
grep -Fq -- '--config -' "$TUNNEL_SETUP"
grep -Fq -- 'printf '\''header = "Authorization: Bearer %s"' "$TUNNEL_SETUP"

echo "Gateway token argv test passed."
