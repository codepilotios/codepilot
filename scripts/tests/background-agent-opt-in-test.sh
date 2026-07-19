#!/usr/bin/env zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SOURCE="$ROOT/Sources/CodexAccountSwitcher/main.swift"
INSTALLER="$ROOT/scripts/install-codepilot-local-agents.sh"

if grep -Eq 'threadID[^=]*=.*[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}' "$SOURCE"; then
  echo "background-agent guard failed: app source contains a fallback thread identifier" >&2
  exit 1
fi

grep -Fq 'appDir.appendingPathComponent("agents/thread-id")' "$SOURCE"
grep -Fq '!threadID.isEmpty else' "$SOURCE"
grep -Fq 'umask 077' "$INSTALLER"
grep -Fq 'chmod 600 "$STATE_DIR/thread-id"' "$INSTALLER"
grep -Fq 'chmod 600 "$plist"' "$INSTALLER"

echo "background-agent opt-in guard passed"
