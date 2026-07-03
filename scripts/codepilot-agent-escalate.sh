#!/usr/bin/env zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="${CODEPILOT_REPO_ROOT:-$DEFAULT_ROOT}"
STATE_DIR="${CODEPILOT_AGENT_STATE_DIR:-$HOME/.codex-account-switcher/agents}"
THREAD_ID_FILE="$STATE_DIR/thread-id"
CODEX_BIN="${CODEPILOT_CODEX_BIN:-codex}"
JOB="${1:-manual}"
MESSAGE="${2:-}"

mkdir -p "$STATE_DIR"

THREAD_ID="${CODEPILOT_AGENT_THREAD_ID:-}"
if [[ -z "$THREAD_ID" && -f "$THREAD_ID_FILE" ]]; then
  THREAD_ID="$(tr -d '[:space:]' < "$THREAD_ID_FILE")"
fi

if [[ -z "$THREAD_ID" ]]; then
  echo "No CodePilot agent thread id configured." >&2
  exit 66
fi

if [[ -z "$MESSAGE" ]]; then
  MESSAGE="$(cat)"
fi

{
  echo "A CodePilot continuous agent needs intervention."
  echo
  echo "Agent: $JOB"
  echo
  echo "$MESSAGE"
} | "$CODEX_BIN" exec resume "$THREAD_ID" -
