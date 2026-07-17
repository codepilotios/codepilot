#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
AUDIT="$ROOT/scripts/privacy-audit.sh"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

REPO="$TEST_ROOT/repo"
mkdir -p "$REPO/scripts"
cp "$AUDIT" "$REPO/scripts/privacy-audit.sh"
cd "$REPO"
git init -q
git config user.name "CodePilot Test"
git config user.email "codepilot-test@users.noreply.github.com"

fail() {
  echo "privacy audit regression failed: $1" >&2
  exit 1
}

write_fixture() {
  print -r -- "$1" > public-fixture.txt
  git add public-fixture.txt scripts/privacy-audit.sh
}

assert_rejected_without_echo() {
  local label="$1"
  local fixture="$2"
  local output
  write_fixture "$fixture"
  if output="$(CODEPILOT_PRIVACY_PATTERNS_FILE="$TEST_ROOT/patterns" zsh scripts/privacy-audit.sh 2>&1)"; then
    fail "$label was accepted"
  fi
  [[ "$output" != *"$fixture"* ]] || fail "$label was printed"
}

: > "$TEST_ROOT/patterns"
write_fixture $'Test iPhone\nhttps://ota.example.com/codexphone/manifest.plist\ncom.example.codepilot'
CODEPILOT_PRIVACY_PATTERNS_FILE="$TEST_ROOT/patterns" zsh scripts/privacy-audit.sh >/dev/null || fail "safe placeholders were rejected"

assert_rejected_without_echo "absolute user path" "/Users/example/private-file"
assert_rejected_without_echo "email address" "person@example.net"
assert_rejected_without_echo "personal device label" "Alice's iPhone"
assert_rejected_without_echo "private bundle namespace" "com.person.codexphone"
assert_rejected_without_echo "non-placeholder OTA host" "https://ota.internal.invalid/build"
assert_rejected_without_echo "secret-looking value" "Bearer AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

print -r -- 'internal-marker-[0-9]+' > "$TEST_ROOT/patterns"
assert_rejected_without_echo "user-configured pattern" "internal-marker-1234"

echo "privacy audit regression tests passed"
