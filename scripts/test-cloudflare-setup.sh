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
write_stub curl '
[[ "$*" == *"--config -"* ]] || exit 90
[[ "$*" == *"--proto =https"* ]] || exit 92
[[ "$*" == *"--proto-redir =https"* ]] || exit 93
[[ "$*" == *"--max-redirs 0"* ]] || exit 94
[[ "$*" == *"https://codepilot.example.com/api/health"* ]] || exit 95
config="$(cat)"
[[ "$config" == '\''header = "Authorization: Bearer test-gateway-token"'\'' ]] || exit 91
echo "{\"ok\":true}"
'
mkdir -p "$HOME/.codex-account-switcher"
printf '%s\n' "test-gateway-token" > "$HOME/.codex-account-switcher/phone-gateway-token"

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

if "$SCRIPT" configure-permanent --hostname https://codepilot.example.com --tunnel-name codepilot >/tmp/codepilot-bad-host.out 2>/tmp/codepilot-bad-host.err; then
  fail "configure-permanent should reject hostnames with schemes"
fi
grep -qi "DNS hostname" /tmp/codepilot-bad-host.err || fail "invalid hostname failure should explain the expected hostname format"

if "$SCRIPT" configure-permanent --hostname bad_host.example.com --tunnel-name codepilot >/tmp/codepilot-underscore-host.out 2>/tmp/codepilot-underscore-host.err; then
  fail "configure-permanent should reject hostnames with underscores"
fi
grep -qi "DNS hostname" /tmp/codepilot-underscore-host.err || fail "underscore hostname failure should explain the expected hostname format"

if "$SCRIPT" configure-permanent --hostname codepilot.example.com --tunnel-name "bad name" >/tmp/codepilot-bad-tunnel.out 2>/tmp/codepilot-bad-tunnel.err; then
  fail "configure-permanent should reject tunnel names with spaces"
fi
grep -qi "tunnel-name" /tmp/codepilot-bad-tunnel.err || fail "invalid tunnel name failure should explain the expected tunnel name format"

rm -f "$HOME/.cloudflared/codepilot-config.yaml" "$HOME/.codex-account-switcher/cloudflare-setup.json"
write_stub cloudflared '
case "$*" in
  "--version") echo "cloudflared version 2026.6.1";;
  "tunnel list --output json") echo "[]";;
  "tunnel create existing") echo "Tunnel already exists" >&2; exit 1;;
  "tunnel route dns existing existing.example.com") echo "Added CNAME existing.example.com";;
  *) echo "cloudflared $*";;
esac
'
if "$SCRIPT" configure-permanent --hostname existing.example.com --tunnel-name existing >/tmp/codepilot-no-id.out 2>/tmp/codepilot-no-id.err; then
  fail "configure-permanent should fail when no tunnel ID can be determined"
fi
[ ! -f "$HOME/.cloudflared/codepilot-config.yaml" ] || fail "config should not be written without a tunnel ID"
[ ! -f "$HOME/.codex-account-switcher/cloudflare-setup.json" ] || fail "metadata should not be written without a tunnel ID"
grep -qi "tunnel ID" /tmp/codepilot-no-id.err || fail "no-ID failure should explain the missing tunnel ID"

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

"$SCRIPT" install-service
[ -f "$HOME/Library/LaunchAgents/io.codepilot.phone-cloudflared.plist" ] || fail "LaunchAgent plist missing"

"$SCRIPT" verify --url https://codepilot.example.com >/tmp/codepilot-verify.out
grep -q "verified" /tmp/codepilot-verify.out || fail "verify output should say verified"
for unsafe_url in \
  http://codepilot.example.com \
  https://other.example.com \
  https://codepilot.example.com.evil.test \
  https://user:@codepilot.example.com \
  'https://codepilot.example.com/?next=https://evil.test'; do
  if "$SCRIPT" verify --url "$unsafe_url" >/dev/null 2>&1; then
    fail "unsafe verification URL was accepted"
  fi
done

"$SCRIPT" start-trycloudflare >/tmp/codepilot-try.out
grep -q "temporary.trycloudflare.com" /tmp/codepilot-try.out || fail "temporary URL missing"

echo "PASS: cloudflare setup script tests"
