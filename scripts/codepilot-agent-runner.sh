#!/usr/bin/env zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="${CODEPILOT_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
JOB="${1:-}"

if [[ -z "$JOB" ]]; then
  echo "Usage: $0 <job-name>" >&2
  exit 64
fi

PROMPT="$ROOT/ops/agents/prompts/$JOB.md"
LOG_DIR="${CODEPILOT_AGENT_LOG_DIR:-$HOME/Library/Logs/CodePilotAgents}"
LOCK_DIR="${TMPDIR:-/tmp}/codepilot-agent-$JOB.lock"

if [[ ! -f "$PROMPT" ]]; then
  echo "Unknown CodePilot agent job: $JOB" >&2
  exit 66
fi

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "CodePilot agent already running: $JOB"
  exit 0
fi
trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT

mkdir -p "$LOG_DIR" "$ROOT/ops/agents/escalations"

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
log_file="$LOG_DIR/$JOB-$timestamp.log"

exec >>"$log_file" 2>&1

echo "== CodePilot agent: $JOB =="
echo "started_at=$timestamp"
echo "repo=$ROOT"

cd "$ROOT"

codex exec \
  --cd "$ROOT" \
  --sandbox danger-full-access \
  --ask-for-approval never \
  - < "$PROMPT"

echo "finished_at=$(date -u +%Y%m%dT%H%M%SZ)"
