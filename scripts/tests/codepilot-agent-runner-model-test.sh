#!/usr/bin/env zsh
set -euo pipefail

ROOT="$(mktemp -d)"
STATE_DIR="$ROOT/state"
LOG_DIR="$ROOT/logs"
JOB="health-watch"
CAPTURE="$ROOT/codex-args"
PROMPT_CAPTURE="$ROOT/codex-prompt"

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
cat > "$CODEPILOT_TEST_PROMPT_CAPTURE"
EOF
chmod +x "$ROOT/codex-stub"

run_runner() {
  CODEPILOT_REPO_ROOT="$ROOT" \
  CODEPILOT_AGENT_STATE_DIR="$STATE_DIR" \
  CODEPILOT_AGENT_LOG_DIR="$LOG_DIR" \
  CODEPILOT_CODEX_BIN="$ROOT/codex-stub" \
  CODEPILOT_TEST_CAPTURE="$CAPTURE" \
  CODEPILOT_TEST_PROMPT_CAPTURE="$PROMPT_CAPTURE" \
  TMPDIR="$ROOT/tmp" \
    "$PWD/scripts/codepilot-agent-runner.sh" "$JOB"
}

mkdir -p "$ROOT/tmp"

run_runner

if grep -qx -- '-m' "$CAPTURE"; then
  echo "Default runner unexpectedly forced a model" >&2
  exit 1
fi

if ! grep -A1 -x -- '--config' "$CAPTURE" | grep -qx 'model_reasoning_effort="medium"'; then
  echo "Routine agent did not use medium reasoning" >&2
  exit 1
fi

if ! grep -q 'Public write policy' "$PROMPT_CAPTURE"; then
  echo "Runner did not inject the public write policy" >&2
  exit 1
fi

if ! grep -q 'Autonomy mode: launch' "$PROMPT_CAPTURE"; then
  echo "Runner did not inject launch autonomy mode" >&2
  exit 1
fi

if ! grep -q 'Use the public CodePilot identity' "$PROMPT_CAPTURE"; then
  echo "Runner did not inject anonymous identity guidance" >&2
  exit 1
fi

CODEPILOT_AGENT_MODEL="test-model" run_runner

if ! grep -A1 -x -- '-m' "$CAPTURE" | grep -qx 'test-model'; then
  echo "Explicit model override was not forwarded" >&2
  exit 1
fi

JOB="security-scan"
mkdir -p "$STATE_DIR/worktrees/$JOB"
touch "$STATE_DIR/worktrees/$JOB/.git"
printf 'Scan security.\n' > "$ROOT/ops/agents/prompts/$JOB.md"
run_runner

if ! grep -A1 -x -- '--config' "$CAPTURE" | grep -qx 'model_reasoning_effort="high"'; then
  echo "Security agent did not use high reasoning" >&2
  exit 1
fi

CODEPILOT_AGENT_REASONING_EFFORT="low" run_runner

if ! grep -A1 -x -- '--config' "$CAPTURE" | grep -qx 'model_reasoning_effort="low"'; then
  echo "Explicit reasoning override was not forwarded" >&2
  exit 1
fi

echo "CodePilot agent runner model selection tests passed."
