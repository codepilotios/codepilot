#!/usr/bin/env zsh
set -euo pipefail

ROOT="$(mktemp -d)"
STATE_DIR="$ROOT/state"
TMP_ROOT="$ROOT/tmp"
CAPTURE="$ROOT/dispatched-job"

cleanup() {
  rm -rf "$ROOT"
}
trap cleanup EXIT

mkdir -p "$ROOT/scripts" "$STATE_DIR" "$TMP_ROOT/codepilot-agent-scheduler.lock"

cat > "$ROOT/scripts/codepilot-agent-runner.sh" <<'EOF'
#!/bin/zsh
printf '%s\n' "$1" > "$CODEPILOT_TEST_CAPTURE"
EOF
chmod +x "$ROOT/scripts/codepilot-agent-runner.sh"

CODEPILOT_REPO_ROOT="$ROOT" \
CODEPILOT_AGENT_STATE_DIR="$STATE_DIR" \
CODEPILOT_TEST_CAPTURE="$CAPTURE" \
TMPDIR="$TMP_ROOT" \
  "$PWD/scripts/codepilot-agent-scheduler.sh"

if [[ "$(cat "$CAPTURE" 2>/dev/null || true)" != "health-watch" ]]; then
  echo "Scheduler did not recover its stale lock and dispatch health-watch" >&2
  exit 1
fi

echo "CodePilot scheduler stale-lock test passed."
