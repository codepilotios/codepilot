#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_ROOT="$(mktemp -d)"

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

cp "$ROOT/scripts/push-desktop-sync.sh" "$TEST_ROOT/push-desktop-sync.sh"
cp "$ROOT/scripts/import-desktop-sync.py" "$TEST_ROOT/import-desktop-sync.py"
cp "$ROOT/scripts/repair-remote-project-hosts.py" "$TEST_ROOT/repair-remote-project-hosts.py"

cat > "$TEST_ROOT/export-desktop-sync.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: > "$CODEPILOT_EXPORT_MARKER"
bundle="$CODEPILOT_TEST_ROOT/codex-desktop-sync.tgz"
: > "$bundle"
printf '%s\n' "$bundle"
EOF

mkdir "$TEST_ROOT/bin"
cat > "$TEST_ROOT/bin/ssh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'ssh' >> "$CODEPILOT_TRANSPORT_CAPTURE"
printf '\t%s' "$@" >> "$CODEPILOT_TRANSPORT_CAPTURE"
printf '\n' >> "$CODEPILOT_TRANSPORT_CAPTURE"
EOF
cat > "$TEST_ROOT/bin/scp" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'scp' >> "$CODEPILOT_TRANSPORT_CAPTURE"
printf '\t%s' "$@" >> "$CODEPILOT_TRANSPORT_CAPTURE"
printf '\n' >> "$CODEPILOT_TRANSPORT_CAPTURE"
EOF
chmod +x "$TEST_ROOT/push-desktop-sync.sh" "$TEST_ROOT/export-desktop-sync.sh" "$TEST_ROOT/bin/ssh" "$TEST_ROOT/bin/scp"

export CODEPILOT_TEST_ROOT="$TEST_ROOT"
export CODEPILOT_EXPORT_MARKER="$TEST_ROOT/exported"
export CODEPILOT_TRANSPORT_CAPTURE="$TEST_ROOT/transport"
export PATH="$TEST_ROOT/bin:$PATH"

for destination in '-oProxyCommand=unsafe' 'host:relative-path' 'host name' 'user@'; do
  rm -f "$CODEPILOT_EXPORT_MARKER"
  if "$TEST_ROOT/push-desktop-sync.sh" "$destination" >/dev/null 2>&1; then
    echo "desktop sync accepted an unsafe SSH destination" >&2
    exit 1
  fi
  if [[ -e "$CODEPILOT_EXPORT_MARKER" ]]; then
    echo "desktop sync exported private metadata before validating the destination" >&2
    exit 1
  fi
done

"$TEST_ROOT/push-desktop-sync.sh" 'tester@example-host' --host-id test-host >/dev/null

[[ "$(wc -l < "$CODEPILOT_TRANSPORT_CAPTURE" | tr -d ' ')" == "5" ]]
if grep -Evq $'^(ssh|scp)\t--\t' "$CODEPILOT_TRANSPORT_CAPTURE"; then
  echo "desktop sync transport omitted the SSH option terminator" >&2
  exit 1
fi
grep -Fq $'ssh\t--\ttester@example-host\tmkdir -p ~/.codex-account-switcher/desktop-sync-import' "$CODEPILOT_TRANSPORT_CAPTURE"
grep -Fq $'scp\t--\t' "$CODEPILOT_TRANSPORT_CAPTURE"
grep -Fq $'ssh\t--\ttester@example-host\tcd ~ &&' "$CODEPILOT_TRANSPORT_CAPTURE"

echo "Desktop sync transport security test passed."
