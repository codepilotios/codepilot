#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/setup-cloudflare-remote-access.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export PATH="$TMP/bin:/usr/bin:/bin:/usr/sbin:/sbin"
mkdir -p "$HOME" "$TMP/bin"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

write_stub() {
  local name="$1"
  local body="$2"
  {
    echo '#!/bin/zsh'
    echo 'set -euo pipefail'
    printf '%s\n' "$body"
  } > "$TMP/bin/$name"
  chmod +x "$TMP/bin/$name"
}

write_stub cloudflared '
case "$*" in
  "--version") echo "cloudflared version 2026.6.1";;
  "tunnel list --output json") echo "[]";;
  "tunnel create codepilot") echo "{\"id\":\"tun_123\",\"name\":\"codepilot\"}";;
  "tunnel route dns codepilot codepilot.example.com") echo "Added CNAME codepilot.example.com";;
  "tunnel --url http://127.0.0.1:18790") echo "https://temporary.trycloudflare.com";;
  *) echo "cloudflared $*";;
esac
'
write_stub brew 'echo "brew $*"'
write_stub launchctl 'echo "launchctl $*"'
write_stub curl 'echo "{\"ok\":true}"'

"$SCRIPT" status >/tmp/codepilot-status.json 2>/tmp/codepilot-status.err || true
grep -q "No such file" /tmp/codepilot-status.err && fail "status should not crash when config is missing"

"$SCRIPT" configure-permanent --hostname codepilot.example.com --tunnel-name codepilot
[ -f "$HOME/.cloudflared/codepilot-config.yaml" ] || fail "config file missing"
grep -q "hostname: codepilot.example.com" "$HOME/.cloudflared/codepilot-config.yaml" || fail "hostname missing from config"
grep -q "service: http://127.0.0.1:18790" "$HOME/.cloudflared/codepilot-config.yaml" || fail "gateway service missing from config"
[ "$(stat -f '%Lp' "$HOME/.cloudflared/codepilot-config.yaml")" = "600" ] || fail "config must be owner-only"
[ -f "$HOME/.codex-account-switcher/cloudflare-setup.json" ] || fail "metadata missing"
! grep -qi "token" "$HOME/.codex-account-switcher/cloudflare-setup.json" || fail "metadata must not contain token"
[ "$(stat -f '%Lp' "$HOME/.codex-account-switcher/cloudflare-setup.json")" = "600" ] || fail "metadata must be owner-only"

if "$SCRIPT" configure-permanent --hostname $'safe.example.com\nservice: http://169.254.169.254' --tunnel-name codepilot >/dev/null 2>&1; then
  fail "hostname YAML injection was accepted"
fi
if "$SCRIPT" configure-permanent --hostname codepilot.example.com --tunnel-name $'codepilot\ningress' >/dev/null 2>&1; then
  fail "tunnel-name YAML injection was accepted"
fi
if CODEPILOT_GATEWAY_URL="http://192.0.2.10:18790" "$SCRIPT" start-trycloudflare >/dev/null 2>&1; then
  fail "non-loopback tunnel target was accepted"
fi

"$SCRIPT" install-service
[ -f "$HOME/Library/LaunchAgents/io.codepilot.phone-cloudflared.plist" ] || fail "LaunchAgent plist missing"

"$SCRIPT" verify --url https://codepilot.example.com >/tmp/codepilot-verify.out
grep -q "verified" /tmp/codepilot-verify.out || fail "verify output should say verified"

"$SCRIPT" start-trycloudflare >/tmp/codepilot-try.out
grep -q "temporary.trycloudflare.com" /tmp/codepilot-try.out || fail "temporary URL missing"

echo "PASS: cloudflare setup script tests"
