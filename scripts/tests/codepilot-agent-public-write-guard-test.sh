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
printf '%s\n' "$@" > "$CODEPILOT_GUARD_CAPTURE"
EOF

chmod +x "$TMP_ROOT/gh" "$TMP_ROOT/git"
export CODEPILOT_GUARD_CAPTURE="$TMP_ROOT/capture"
export CODEPILOT_AGENT_REAL_GH="$TMP_ROOT/gh"
export CODEPILOT_AGENT_REAL_GIT="$TMP_ROOT/git"
export CODEPILOT_AGENT_PUBLIC_AUTONOMY="draft"

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

CODEPILOT_AGENT_PUBLIC_AUTONOMY="launch" "$GUARD_BIN/gh" issue create --title "Setup issue" --body "Drafted by agent"
grep -qx 'create' "$TMP_ROOT/capture"

if CODEPILOT_AGENT_PUBLIC_AUTONOMY="launch" "$GUARD_BIN/gh" issue create --repo example/other --title unsafe; then
  echo "Launch autonomy allowed issue creation outside the CodePilot repository" >&2
  exit 1
fi

CODEPILOT_AGENT_PUBLIC_AUTONOMY="launch" "$GUARD_BIN/gh" pr create --draft --title "Docs update" --body "Prepared by agent"
grep -qx 'create' "$TMP_ROOT/capture"

CODEPILOT_AGENT_PUBLIC_AUTONOMY="launch" "$GUARD_BIN/git" push origin HEAD:agent/presence-maintenance
grep -qx 'push' "$TMP_ROOT/capture"

if CODEPILOT_AGENT_PUBLIC_AUTONOMY="launch" "$GUARD_BIN/git" push origin HEAD:agent/presence-maintenance HEAD:main; then
  echo "Launch autonomy allowed a protected refspec beside an agent refspec" >&2
  exit 1
fi

if CODEPILOT_AGENT_PUBLIC_AUTONOMY="launch" "$GUARD_BIN/git" push --all origin HEAD:agent/presence-maintenance; then
  echo "Launch autonomy allowed a broad push mode" >&2
  exit 1
fi

if CODEPILOT_AGENT_PUBLIC_AUTONOMY="launch" "$GUARD_BIN/git" push --follow-tags origin HEAD:agent/presence-maintenance; then
  echo "Launch autonomy allowed an implicit tag push" >&2
  exit 1
fi

if CODEPILOT_AGENT_PUBLIC_AUTONOMY="launch" "$GUARD_BIN/git" push upstream HEAD:agent/presence-maintenance; then
  echo "Launch autonomy allowed a push outside the CodePilot origin" >&2
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
