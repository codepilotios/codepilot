#!/usr/bin/env zsh
set -euo pipefail

unset CODEPILOT_AGENT_MODEL CODEPILOT_AGENT_REASONING_EFFORT
export CODEPILOT_AGENT_PUBLIC_AUTONOMY="launch"

ROOT="$(mktemp -d)"
STATE_DIR="$(mktemp -d)"
LOG_DIR="$ROOT/logs"
JOB="health-watch"
CAPTURE="$ROOT/codex-args"
PROMPT_CAPTURE="$ROOT/codex-prompt"
ASC_CAPTURE="$ROOT/asc-path"

cleanup() {
  rm -rf "$ROOT"
  rm -rf "$STATE_DIR"
}
trap cleanup EXIT

mkdir -p \
  "$ROOT/bin" \
  "$ROOT/ops/agents/prompts" \
  "$ROOT/ops/agents/escalations" \
  "$STATE_DIR/worktrees/$JOB"
touch "$STATE_DIR/worktrees/$JOB/.git"
printf 'Check health.\n' > "$ROOT/ops/agents/prompts/$JOB.md"

cat > "$ROOT/codex-stub" <<'EOF'
#!/bin/zsh
printf '%s\n' "$@" > "$CODEPILOT_TEST_CAPTURE"
printf '%s\n' "${CODEPILOT_AGENT_REAL_ASC:-}" > "$CODEPILOT_TEST_ASC_CAPTURE"
cat > "$CODEPILOT_TEST_PROMPT_CAPTURE"
EOF
chmod +x "$ROOT/codex-stub"

cat > "$ROOT/bin/asc" <<'EOF'
#!/bin/zsh
exit 0
EOF
chmod +x "$ROOT/bin/asc"

run_runner() {
  CODEPILOT_REPO_ROOT="$ROOT" \
  CODEPILOT_AGENT_STATE_DIR="$STATE_DIR" \
  CODEPILOT_AGENT_LOG_DIR="$LOG_DIR" \
  CODEPILOT_CODEX_BIN="$ROOT/codex-stub" \
  CODEPILOT_TEST_CAPTURE="$CAPTURE" \
  CODEPILOT_TEST_PROMPT_CAPTURE="$PROMPT_CAPTURE" \
  CODEPILOT_TEST_ASC_CAPTURE="$ASC_CAPTURE" \
  TMPDIR="$ROOT/tmp" \
  PATH="$ROOT/bin:$PATH" \
    "$PWD/scripts/codepilot-agent-runner.sh" "$JOB"
}

mkdir -p "$ROOT/tmp"

run_runner

if [[ "$(<"$ASC_CAPTURE")" != "$ROOT/bin/asc" ]]; then
  echo "Runner did not export the real asc executable before installing guards" >&2
  exit 1
fi

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
