#!/usr/bin/env zsh
set -euo pipefail

ROOT="${CODEPILOT_REPO_ROOT:-/Users/homeserver/Developer/CodexAccountSwitcher}"
PLIST_DIR="$HOME/Library/LaunchAgents"
RUNNER="$ROOT/scripts/codepilot-agent-runner.sh"
STATE_DIR="${CODEPILOT_AGENT_STATE_DIR:-$HOME/.codex-account-switcher/agents}"
THREAD_ID="${CODEPILOT_AGENT_THREAD_ID:-${CODEX_THREAD_ID:-}}"

if [[ "${1:-}" != "--install" ]]; then
  cat <<'EOF'
This installs local LaunchAgents for CodePilot background agents.

Escalations are sent back to the configured Codex thread with `codex exec resume`.
Agent logs are written to ~/Library/Logs/CodePilotAgents.

Run with --install only if that fallback escalation path is acceptable.
EOF
  exit 64
fi

if [[ -z "$THREAD_ID" ]]; then
  echo "No thread id found. Set CODEPILOT_AGENT_THREAD_ID or run from a Codex thread with CODEX_THREAD_ID." >&2
  exit 66
fi

chmod +x "$RUNNER" "$ROOT/scripts/codepilot-agent-escalate.sh"
mkdir -p "$PLIST_DIR"
mkdir -p "$STATE_DIR"
printf '%s\n' "$THREAD_ID" > "$STATE_DIR/thread-id"

write_plist() {
  local name="$1"
  local interval="$2"
  local plist="$PLIST_DIR/io.codepilot.agent.$name.plist"
  cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>io.codepilot.agent.$name</string>
  <key>ProgramArguments</key>
  <array>
    <string>$RUNNER</string>
    <string>$name</string>
  </array>
  <key>StartInterval</key>
  <integer>$interval</integer>
  <key>RunAtLoad</key>
  <true/>
  <key>EnvironmentVariables</key>
  <dict>
    <key>CODEPILOT_REPO_ROOT</key>
    <string>$ROOT</string>
    <key>CODEPILOT_AGENT_THREAD_ID</key>
    <string>$THREAD_ID</string>
  </dict>
  <key>StandardOutPath</key>
  <string>$HOME/Library/Logs/CodePilotAgents/$name.launchd.out.log</string>
  <key>StandardErrorPath</key>
  <string>$HOME/Library/Logs/CodePilotAgents/$name.launchd.err.log</string>
</dict>
</plist>
EOF
  launchctl unload "$plist" 2>/dev/null || true
  launchctl load "$plist"
}

write_plist health-watch 3600
write_plist issue-triage 7200
write_plist setup-audit 86400
write_plist release-readiness 86400
write_plist presence-maintenance 604800
write_plist community-drafts 604800
write_plist security-scan 604800

echo "Installed CodePilot local LaunchAgents."
echo "Escalations will be sent to Codex thread: $THREAD_ID"
