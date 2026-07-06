#!/usr/bin/env zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="${CODEPILOT_REPO_ROOT:-$DEFAULT_ROOT}"
JOB="${1:-}"
STATE_DIR="${CODEPILOT_AGENT_STATE_DIR:-$HOME/.codex-account-switcher/agents}"
WORKTREE_ROOT="$STATE_DIR/worktrees"
THREAD_ID_FILE="$STATE_DIR/thread-id"
CODEX_BIN="${CODEPILOT_CODEX_BIN:-codex}"
CODEX_MODEL="${CODEPILOT_AGENT_MODEL:-}"
GUARD_BIN="$ROOT/scripts/agent-guard-bin"
PUBLIC_AUTONOMY="${CODEPILOT_AGENT_PUBLIC_AUTONOMY:-launch}"

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

git fetch --quiet origin main 2>/dev/null || true
if git diff --quiet && git diff --cached --quiet; then
  if git merge-base --is-ancestor HEAD origin/main 2>/dev/null; then
    git merge --ff-only --quiet origin/main
  else
    echo "Agent worktree has commits not on origin/main; leaving branch as-is."
  fi
else
  echo "Agent worktree has local changes; skipping origin/main refresh."
fi

REAL_GIT="$(command -v git)"
REAL_GH="$(command -v gh 2>/dev/null || true)"
export CODEPILOT_AGENT_REAL_GIT="$REAL_GIT"
export CODEPILOT_AGENT_REAL_GH="$REAL_GH"
export CODEPILOT_AGENT_PUBLIC_AUTONOMY="$PUBLIC_AUTONOMY"
export CODEPILOT_REPO_ROOT="$ROOT"
export PATH="$GUARD_BIN:$PATH"

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

model_args=()
if [[ -n "$CODEX_MODEL" ]]; then
  model_args=(-m "$CODEX_MODEL")
fi

REASONING_EFFORT="${CODEPILOT_AGENT_REASONING_EFFORT:-}"
if [[ -z "$REASONING_EFFORT" ]]; then
  case "$JOB" in
    security-scan|release-readiness)
      REASONING_EFFORT="high"
      ;;
    *)
      REASONING_EFFORT="medium"
      ;;
  esac
fi

PUBLIC_WRITE_POLICY=$(cat <<'EOF'
# Public write policy

Autonomy mode: launch.

Use the public CodePilot identity. Do not mention private names, private email
addresses, personal hosts, local usernames, machine-specific paths, tokens, or
private screenshots in commits, issues, pull requests, docs, metadata, logs, or
escalations.

This unattended run may inspect public systems, create local branches and
commits, push `agent/*` branches, create GitHub issues, and open draft GitHub
pull requests when that directly advances public launch readiness. Run the
privacy audit before any public write.

This unattended run MUST NOT merge pull requests, publish releases, submit App
Store review, upload TestFlight/App Store builds, alter pricing or legal
metadata, create accounts, post publicly on social/community sites, change
credentials, or mutate non-GitHub external systems. This applies to shell
commands, connectors, apps, browsers, HTTP APIs, and any other tool. Do not
bypass the command guards or invoke absolute binary paths to evade them.

Prepare TestFlight/App Store metadata as local files or draft PRs only. Write an
escalation only when maintainer intervention is genuinely required.
EOF
)

{
  printf '%s\n\n' "$PUBLIC_WRITE_POLICY"
  cat "$PROMPT"
} | "$CODEX_BIN" exec \
    --cd "$PWD" \
    "${model_args[@]}" \
    --config "model_reasoning_effort=\"$REASONING_EFFORT\"" \
    --sandbox danger-full-access \
    -

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
