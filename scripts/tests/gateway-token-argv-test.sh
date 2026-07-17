#!/usr/bin/env zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
INSTALLER="$ROOT/scripts/install-phone-gateway-agent.sh"

if grep -Eq -- '(-H|--header)[[:space:]]+"Authorization: Bearer \\$token"' "$INSTALLER"; then
  echo "Gateway installer exposes the bearer token through curl arguments" >&2
  exit 1
fi

grep -Fq -- '--config -' "$INSTALLER"
grep -Fq -- 'printf '\''header = "Authorization: Bearer %s"' "$INSTALLER"

echo "Gateway token argv test passed."
