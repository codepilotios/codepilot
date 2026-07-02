#!/usr/bin/env zsh
set -euo pipefail

ROOT="${CODEPILOT_REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
STATE_DIR="${CODEPILOT_AGENT_STATE_DIR:-$HOME/.codex-account-switcher/agents}"
RUNNER="$ROOT/scripts/codepilot-agent-runner.sh"
LOCK_DIR="${TMPDIR:-/tmp}/codepilot-agent-scheduler.lock"

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  existing_pid=""
  if [[ -f "$LOCK_DIR/pid" ]]; then
    existing_pid="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"
  fi
  if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
    exit 0
  fi
  rm -rf "$LOCK_DIR"
  mkdir "$LOCK_DIR"
fi
printf '%s\n' "$$" > "$LOCK_DIR/pid"
trap 'rm -rf "$LOCK_DIR" 2>/dev/null || true' EXIT

mkdir -p "$STATE_DIR/last-run"

now="$(date +%s)"

jobs=(
  "health-watch:3600"
  "issue-triage:7200"
  "setup-audit:86400"
  "release-readiness:86400"
  "presence-maintenance:604800"
  "community-drafts:604800"
  "security-scan:604800"
)

for entry in "${jobs[@]}"; do
  job="${entry%%:*}"
  interval="${entry##*:}"
  stamp_file="$STATE_DIR/last-run/$job"
  last=0
  if [[ -f "$stamp_file" ]]; then
    last="$(cat "$stamp_file" 2>/dev/null || echo 0)"
  fi
  if (( now - last >= interval )); then
    printf '%s\n' "$now" > "$stamp_file"
    exec "$RUNNER" "$job"
  fi
done

echo "No CodePilot agent jobs due."
