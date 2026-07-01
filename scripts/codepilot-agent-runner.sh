#!/usr/bin/env zsh
set -euo pipefail

ROOT="${CODEPILOT_REPO_ROOT:-/Users/homeserver/Developer/CodexAccountSwitcher}"
JOB="${1:-}"
STATE_DIR="${CODEPILOT_AGENT_STATE_DIR:-$HOME/.codex-account-switcher/agents}"
WORKTREE_ROOT="$STATE_DIR/worktrees"
THREAD_ID_FILE="$STATE_DIR/thread-id"
CODEX_BIN="${CODEPILOT_CODEX_BIN:-codex}"

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
  if [[ -f "$LOCK_DIR/pid" ]]; then
    existing_pid="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"
    if [[ -n "$existing_pid" ]] && ! kill -0 "$existing_pid" 2>/dev/null; then
      rm -rf "$LOCK_DIR"
      mkdir "$LOCK_DIR"
    else
      echo "CodePilot agent already running: $JOB"
      exit 0
    fi
  else
    rm -rf "$LOCK_DIR"
    mkdir "$LOCK_DIR"
  fi
fi
printf '%s\n' "$$" > "$LOCK_DIR/pid"
trap 'rm -rf "$LOCK_DIR" 2>/dev/null || true' EXIT

mkdir -p "$LOG_DIR" "$ROOT/ops/agents/escalations" "$WORKTREE_ROOT"

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
log_file="$LOG_DIR/$JOB-$timestamp.log"

exec >>"$log_file" 2>&1

echo "== CodePilot agent: $JOB =="
echo "started_at=$timestamp"
echo "repo=$ROOT"

cd "$ROOT"

WORKTREE="$WORKTREE_ROOT/$JOB"
BRANCH="agent/$JOB"

if [[ ! -d "$WORKTREE/.git" && ! -f "$WORKTREE/.git" ]]; then
  git worktree prune
  git fetch --quiet origin main 2>/dev/null || true
  git worktree add -B "$BRANCH" "$WORKTREE" main
fi

if [[ -d "$WORKTREE/.git" || -f "$WORKTREE/.git" ]]; then
  cd "$WORKTREE"
fi

ESCALATION_FILE="$ROOT/ops/agents/escalations/$JOB.md"
BEFORE_HASH=""
if [[ -f "$ESCALATION_FILE" ]]; then
  BEFORE_HASH="$(shasum -a 256 "$ESCALATION_FILE" | awk '{print $1}')"
fi

if [[ "${CODEPILOT_AGENT_TEST_ESCALATION:-}" == "1" ]]; then
  {
    echo "# Test escalation"
    echo
    echo "This is a test escalation from $JOB."
  } > "$ESCALATION_FILE"
else

"$CODEX_BIN" exec \
  --cd "$PWD" \
  --sandbox danger-full-access \
  - < "$PROMPT"

fi

AFTER_HASH=""
if [[ -f "$ESCALATION_FILE" ]]; then
  AFTER_HASH="$(shasum -a 256 "$ESCALATION_FILE" | awk '{print $1}')"
fi

if [[ -n "$AFTER_HASH" && "$AFTER_HASH" != "$BEFORE_HASH" ]]; then
  THREAD_ID="${CODEPILOT_AGENT_THREAD_ID:-}"
  if [[ -z "$THREAD_ID" && -f "$THREAD_ID_FILE" ]]; then
    THREAD_ID="$(tr -d '[:space:]' < "$THREAD_ID_FILE")"
  fi

  if [[ -n "$THREAD_ID" ]]; then
    {
      echo "A CodePilot continuous agent needs intervention."
      echo
      echo "Agent: $JOB"
      echo "Escalation file: $ESCALATION_FILE"
      echo
      sed -n '1,220p' "$ESCALATION_FILE"
    } | "$CODEX_BIN" exec resume "$THREAD_ID" -
  else
    echo "Escalation written but no thread id is configured: $ESCALATION_FILE" >&2
  fi
fi

echo "finished_at=$(date -u +%Y%m%dT%H%M%SZ)"
