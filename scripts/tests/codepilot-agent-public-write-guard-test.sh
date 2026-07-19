#!/usr/bin/env zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GUARD_BIN="$ROOT/scripts/agent-guard-bin"
TMP_ROOT="$(mktemp -d)"
export CODEPILOT_AGENT_PUBLIC_AUTONOMY="review"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

cat > "$TMP_ROOT/gh" <<'EOF'
#!/bin/zsh
printf '%s\n' "$@" > "$CODEPILOT_GUARD_CAPTURE"
EOF

cat > "$TMP_ROOT/git" <<'EOF'
#!/bin/zsh
if [[ "$1" == "branch" && "$2" == "--show-current" ]]; then
  printf '%s\n' "${CODEPILOT_FAKE_GIT_BRANCH:-agent/test}"
  exit 0
fi
if [[ "$1" == "remote" && "$2" == "get-url" && "$3" == "origin" ]]; then
  printf '%s\n' "${CODEPILOT_FAKE_GIT_REMOTE_URL:-https://github.com/codepilotios/codepilot.git}"
  exit 0
fi
if [[ "$1" == "show-ref" ]]; then
  exit 1
fi
if [[ "$1" == "rev-parse" ]]; then
  exit 0
fi
if [[ "$1" == "log" && "$2" == --format=* ]]; then
  case "$2" in
    *%an*) printf '%s\t%s\t%s\t%s\n' "${CODEPILOT_FAKE_GIT_AUTHOR_NAME:-CodePilot}" "codepilotios""@users.noreply.github.com" "CodePilot" "codepilotios""@users.noreply.github.com" ;;
    *%B*) printf '%s\n' "${CODEPILOT_FAKE_GIT_MESSAGE:-Public hardening change}" ;;
  esac
  exit 0
fi
if [[ "$1" == "config" && "$2" == "--get" && "$3" == "alias.publish" ]]; then
  [[ "${CODEPILOT_FAKE_GIT_ALIAS:-}" == "publish" ]] || exit 1
  printf '%s\n' 'push'
  exit 0
fi
if [[ "$1" == "config" && "$2" == "--get" ]]; then
  exit 1
fi
printf '%s\n' "$@" > "$CODEPILOT_GUARD_CAPTURE"
EOF

chmod +x "$TMP_ROOT/gh" "$TMP_ROOT/git"
export CODEPILOT_GUARD_CAPTURE="$TMP_ROOT/capture"
export CODEPILOT_AGENT_REAL_GH="$TMP_ROOT/gh"
export CODEPILOT_AGENT_REAL_GIT="$TMP_ROOT/git"
export CODEPILOT_AGENT_PUBLIC_AUTONOMY="draft"
export CODEPILOT_REPO_ROOT="$ROOT"

"$GUARD_BIN/gh" issue list --repo codepilotios/codepilot
grep -qx 'list' "$TMP_ROOT/capture"

if "$GUARD_BIN/gh" issue create --title unsafe; then
  echo "Guard allowed public issue creation" >&2
  exit 1
fi

if "$GUARD_BIN/gh" pr merge 7; then
  echo "Guard allowed PR merge" >&2
  exit 1
fi

if "$GUARD_BIN/gh" pr create --title test --body test; then
  echo "Guard allowed non-draft PR creation" >&2
  exit 1
fi

"$GUARD_BIN/git" status --short
grep -qx 'status' "$TMP_ROOT/capture"

if CODEPILOT_FAKE_GIT_BRANCH="main" "$GUARD_BIN/git" commit -m unsafe; then
  echo "Guard allowed git commit on main" >&2
  exit 1
fi

if CODEPILOT_FAKE_GIT_BRANCH="agent/test" "$GUARD_BIN/git" switch main; then
  echo "Guard allowed switching to main" >&2
  exit 1
fi

cat > "$TMP_ROOT/fastlane" <<'EOF'
#!/bin/zsh
printf '%s\n' "$@" > "$CODEPILOT_GUARD_CAPTURE"
EOF
cat > "$TMP_ROOT/asc" <<'EOF'
#!/bin/zsh
printf '%s\n' "$@" > "$CODEPILOT_GUARD_CAPTURE"
EOF
cat > "$TMP_ROOT/xcrun" <<'EOF'
#!/bin/zsh
printf '%s\n' "$@" > "$CODEPILOT_GUARD_CAPTURE"
EOF
chmod +x "$TMP_ROOT/fastlane" "$TMP_ROOT/asc" "$TMP_ROOT/xcrun"
export CODEPILOT_AGENT_REAL_FASTLANE="$TMP_ROOT/fastlane"
export CODEPILOT_AGENT_REAL_ASC="$TMP_ROOT/asc"
export CODEPILOT_AGENT_REAL_XCRUN="$TMP_ROOT/xcrun"

"$GUARD_BIN/asc" appstore list --output json
grep -qx 'appstore' "$TMP_ROOT/capture"

if CODEPILOT_AGENT_PUBLIC_AUTONOMY="launch" "$GUARD_BIN/fastlane" upload_to_testflight; then
  echo "Launch autonomy allowed fastlane upload" >&2
  exit 1
fi

timeout_marker="$TMP_ROOT/asc-timeout"
env -u CODEPILOT_AGENT_REAL_ASC PATH="$GUARD_BIN:$PATH" \
  "$GUARD_BIN/asc" appstore list --output json &
asc_pid="$!"
(
  sleep 2
  if kill -0 "$asc_pid" 2>/dev/null; then
    touch "$timeout_marker"
    kill -TERM "$asc_pid" 2>/dev/null || true
  fi
) &
watchdog_pid="$!"
wait "$asc_pid" || true
kill "$watchdog_pid" 2>/dev/null || true
wait "$watchdog_pid" 2>/dev/null || true
if [[ -f "$timeout_marker" ]]; then
  echo "asc guard recursed when the real executable was not exported" >&2
  exit 1
fi

if CODEPILOT_AGENT_PUBLIC_AUTONOMY="launch" "$GUARD_BIN/asc" appstore submit --app-id 123; then
  echo "Launch autonomy allowed App Store submission" >&2
  exit 1
fi

if CODEPILOT_AGENT_PUBLIC_AUTONOMY="launch" "$GUARD_BIN/xcrun" altool --upload-app; then
  echo "Launch autonomy allowed xcrun upload" >&2
  exit 1
fi

if "$GUARD_BIN/git" push origin main; then
  echo "Guard allowed git push" >&2
  exit 1
fi

if CODEPILOT_AGENT_PUBLIC_AUTONOMY="launch" "$GUARD_BIN/git" -C "$ROOT" push origin main; then
  echo "Launch autonomy allowed git -C to bypass the push guard" >&2
  exit 1
fi

if CODEPILOT_AGENT_PUBLIC_AUTONOMY="launch" "$GUARD_BIN/git" -c alias.publish=push publish origin main; then
  echo "Launch autonomy allowed a command-line alias to bypass the push guard" >&2
  exit 1
fi

if CODEPILOT_FAKE_GIT_ALIAS="publish" CODEPILOT_AGENT_PUBLIC_AUTONOMY="launch" "$GUARD_BIN/git" publish origin main; then
  echo "Launch autonomy allowed a configured alias to bypass the push guard" >&2
  exit 1
fi

if CODEPILOT_AGENT_PUBLIC_AUTONOMY="launch" "$GUARD_BIN/git" send-pack origin main; then
  echo "Launch autonomy allowed direct send-pack remote writes" >&2
  exit 1
fi

CODEPILOT_AGENT_PUBLIC_AUTONOMY="launch" "$GUARD_BIN/gh" issue create --title "Setup issue" --body "Drafted by agent"
grep -qx 'create' "$TMP_ROOT/capture"

if CODEPILOT_AGENT_PUBLIC_AUTONOMY="launch" "$GUARD_BIN/gh" issue create --title "person""@example.net" --body "Drafted by agent"; then
  echo "Launch autonomy allowed private outbound issue content" >&2
  exit 1
fi

print -r -- "Drafted by agent" > "$TMP_ROOT/issue-body.md"
if CODEPILOT_AGENT_PUBLIC_AUTONOMY="launch" "$GUARD_BIN/gh" issue create --title "Setup issue" --body-file "$TMP_ROOT/issue-body.md"; then
  echo "Launch autonomy allowed an untracked issue body file" >&2
  exit 1
fi

if CODEPILOT_AGENT_PUBLIC_AUTONOMY="launch" "$GUARD_BIN/gh" issue create --title "Setup issue" --body-file -; then
  echo "Launch autonomy allowed an unaudited stdin issue body" >&2
  exit 1
fi

if CODEPILOT_AGENT_PUBLIC_AUTONOMY="launch" "$GUARD_BIN/gh" issue create --title "Setup issue" --recover saved-input; then
  echo "Launch autonomy allowed recovered issue content" >&2
  exit 1
fi

if CODEPILOT_AGENT_PUBLIC_AUTONOMY="launch" "$GUARD_BIN/gh" issue create --repo example/other --title unsafe; then
  echo "Launch autonomy allowed issue creation outside the CodePilot repository" >&2
  exit 1
fi

CODEPILOT_AGENT_PUBLIC_AUTONOMY="launch" "$GUARD_BIN/gh" pr create --draft --title "Docs update" --body "Prepared by agent"
grep -qx 'create' "$TMP_ROOT/capture"

if CODEPILOT_AGENT_PUBLIC_AUTONOMY="launch" "$GUARD_BIN/gh" pr create --draft --fill; then
  echo "Launch autonomy allowed unaudited commit text to fill a pull request" >&2
  exit 1
fi

if CODEPILOT_AGENT_PUBLIC_AUTONOMY="launch" "$GUARD_BIN/gh" pr create --draft --title "Docs update" --recover saved-input; then
  echo "Launch autonomy allowed recovered pull request content" >&2
  exit 1
fi

CODEPILOT_AGENT_PUBLIC_AUTONOMY="launch" "$GUARD_BIN/git" push origin HEAD:refs/heads/agent/presence-maintenance
grep -qx 'push' "$TMP_ROOT/capture"

if CODEPILOT_FAKE_GIT_AUTHOR_NAME="Private Author" CODEPILOT_AGENT_PUBLIC_AUTONOMY="launch" "$GUARD_BIN/git" push origin HEAD:refs/heads/agent/presence-maintenance; then
  echo "Launch autonomy allowed a push with non-public commit identity" >&2
  exit 1
fi

if CODEPILOT_FAKE_GIT_MESSAGE="Contact person""@example.net" CODEPILOT_AGENT_PUBLIC_AUTONOMY="launch" "$GUARD_BIN/git" push origin HEAD:refs/heads/agent/presence-maintenance; then
  echo "Launch autonomy allowed a push with private commit text" >&2
  exit 1
fi

if CODEPILOT_FAKE_GIT_REMOTE_URL="https://github.com/example/other.git" CODEPILOT_AGENT_PUBLIC_AUTONOMY="launch" "$GUARD_BIN/git" push origin HEAD:refs/heads/agent/presence-maintenance; then
  echo "Launch autonomy allowed a push through an unexpected origin URL" >&2
  exit 1
fi

if CODEPILOT_AGENT_PUBLIC_AUTONOMY="launch" "$GUARD_BIN/git" push origin HEAD:refs/heads/agent/presence-maintenance HEAD:refs/heads/main; then
  echo "Launch autonomy allowed a protected refspec beside an agent refspec" >&2
  exit 1
fi

if CODEPILOT_AGENT_PUBLIC_AUTONOMY="launch" "$GUARD_BIN/git" push --all origin HEAD:refs/heads/agent/presence-maintenance; then
  echo "Launch autonomy allowed a broad push mode" >&2
  exit 1
fi

if CODEPILOT_AGENT_PUBLIC_AUTONOMY="launch" "$GUARD_BIN/git" push --follow-tags origin HEAD:refs/heads/agent/presence-maintenance; then
  echo "Launch autonomy allowed an implicit tag push" >&2
  exit 1
fi

if CODEPILOT_AGENT_PUBLIC_AUTONOMY="launch" "$GUARD_BIN/git" push upstream HEAD:refs/heads/agent/presence-maintenance; then
  echo "Launch autonomy allowed a push outside the CodePilot origin" >&2
  exit 1
fi

if CODEPILOT_AGENT_PUBLIC_AUTONOMY="launch" "$GUARD_BIN/git" push origin HEAD:agent/presence-maintenance; then
  echo "Launch autonomy allowed an ambiguous short destination ref" >&2
  exit 1
fi

if CODEPILOT_AGENT_PUBLIC_AUTONOMY="launch" "$GUARD_BIN/git" push origin agent/presence-maintenance; then
  echo "Launch autonomy allowed a tag-like short refspec" >&2
  exit 1
fi

if CODEPILOT_AGENT_PUBLIC_AUTONOMY="launch" "$GUARD_BIN/git" push origin; then
  echo "Launch autonomy allowed a push without an explicit agent refspec" >&2
  exit 1
fi

if CODEPILOT_AGENT_PUBLIC_AUTONOMY="launch" "$GUARD_BIN/git" push origin main; then
  echo "Launch autonomy allowed pushing main" >&2
  exit 1
fi

if CODEPILOT_AGENT_PUBLIC_AUTONOMY="launch" "$GUARD_BIN/gh" pr merge 7; then
  echo "Launch autonomy allowed PR merge" >&2
  exit 1
fi

if CODEPILOT_AGENT_PUBLIC_AUTONOMY="launch" "$GUARD_BIN/gh" release create v1.0.0; then
  echo "Launch autonomy allowed release creation" >&2
  exit 1
fi

echo "CodePilot public write guard tests passed."
