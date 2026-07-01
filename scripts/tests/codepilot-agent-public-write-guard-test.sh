#!/usr/bin/env zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GUARD_BIN="$ROOT/scripts/agent-guard-bin"
TMP_ROOT="$(mktemp -d)"

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
printf '%s\n' "$@" > "$CODEPILOT_GUARD_CAPTURE"
EOF

chmod +x "$TMP_ROOT/gh" "$TMP_ROOT/git"
export CODEPILOT_GUARD_CAPTURE="$TMP_ROOT/capture"
export CODEPILOT_AGENT_REAL_GH="$TMP_ROOT/gh"
export CODEPILOT_AGENT_REAL_GIT="$TMP_ROOT/git"

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

"$GUARD_BIN/git" status --short
grep -qx 'status' "$TMP_ROOT/capture"

if "$GUARD_BIN/git" push origin main; then
  echo "Guard allowed git push" >&2
  exit 1
fi

echo "CodePilot public write guard tests passed."
