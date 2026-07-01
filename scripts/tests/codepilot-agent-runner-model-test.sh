#!/usr/bin/env zsh
set -euo pipefail

ROOT="$(mktemp -d)"
STATE_DIR="$ROOT/state"
LOG_DIR="$ROOT/logs"
JOB="health-watch"
CAPTURE="$ROOT/codex-args"

cleanup() {
  rm -rf "$ROOT"
}
trap cleanup EXIT

mkdir -p \
  "$ROOT/ops/agents/prompts" \
  "$ROOT/ops/agents/escalations" \
  "$STATE_DIR/worktrees/$JOB"
touch "$STATE_DIR/worktrees/$JOB/.git"
printf 'Check health.\n' > "$ROOT/ops/agents/prompts/$JOB.md"

cat > "$ROOT/codex-stub" <<'EOF'
#!/bin/zsh
printf '%s\n' "$@" > "$CODEPILOT_TEST_CAPTURE"
cat >/dev/null
EOF
chmod +x "$ROOT/codex-stub"

run_runner() {
  CODEPILOT_REPO_ROOT="$ROOT" \
  CODEPILOT_AGENT_STATE_DIR="$STATE_DIR" \
  CODEPILOT_AGENT_LOG_DIR="$LOG_DIR" \
  CODEPILOT_CODEX_BIN="$ROOT/codex-stub" \
  CODEPILOT_TEST_CAPTURE="$CAPTURE" \
    "$PWD/scripts/codepilot-agent-runner.sh" "$JOB"
}

run_runner

if grep -qx -- '-m' "$CAPTURE"; then
  echo "Default runner unexpectedly forced a model" >&2
  exit 1
fi

CODEPILOT_AGENT_MODEL="test-model" run_runner

if ! grep -A1 -x -- '-m' "$CAPTURE" | grep -qx 'test-model'; then
  echo "Explicit model override was not forwarded" >&2
  exit 1
fi

echo "CodePilot agent runner model selection tests passed."
