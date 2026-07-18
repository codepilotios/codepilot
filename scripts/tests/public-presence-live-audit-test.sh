#!/usr/bin/env zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_ROOT="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

cat > "$TMP_ROOT/gh" <<'EOF'
#!/bin/zsh
if [[ "$1 $2" == "repo view" ]]; then
  if [[ "$5" == "description" ]]; then
    printf '%s\n' 'Public beta Mac and iPhone companion for Codex CLI workflows.'
  else
    printf '%s\n' 'https://codepilotios.github.io/codepilot/'
  fi
elif [[ "$2" == "repos/codepilotios/codepilot/pages" ]]; then
  printf '%s\n' 'built' 'https://codepilotios.github.io/codepilot/' 'main' '/docs'
elif [[ "$2" == "repos/codepilotios/codepilot/private-vulnerability-reporting" ]]; then
  printf '%s\n' 'true'
else
  exit 1
fi
EOF

cat > "$TMP_ROOT/curl" <<'EOF'
#!/bin/zsh
exit "${CODEPILOT_FAKE_CURL_EXIT:-0}"
EOF

chmod +x "$TMP_ROOT/gh" "$TMP_ROOT/curl"
CODEPILOT_LIVE_AUDIT_GH="$TMP_ROOT/gh" \
  CODEPILOT_LIVE_AUDIT_CURL="$TMP_ROOT/curl" \
  "$ROOT/scripts/public-presence-live-audit.sh"

if CODEPILOT_FAKE_CURL_EXIT=22 \
  CODEPILOT_LIVE_AUDIT_GH="$TMP_ROOT/gh" \
  CODEPILOT_LIVE_AUDIT_CURL="$TMP_ROOT/curl" \
  "$ROOT/scripts/public-presence-live-audit.sh" >/dev/null 2>&1; then
  echo "Live audit accepted unreachable Pages URLs" >&2
  exit 1
fi

echo "CodePilot public presence live audit tests passed."
