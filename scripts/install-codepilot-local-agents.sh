#!/usr/bin/env zsh
set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="${CODEPILOT_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
PLIST_DIR="$HOME/Library/LaunchAgents"
RUNNER="$ROOT/scripts/codepilot-agent-runner.sh"
SCHEDULER="$ROOT/scripts/codepilot-agent-scheduler.sh"
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

chmod +x "$RUNNER" "$SCHEDULER" "$ROOT/scripts/codepilot-agent-escalate.sh"
mkdir -p "$PLIST_DIR"
mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"
printf '%s\n' "$THREAD_ID" > "$STATE_DIR/thread-id"
chmod 600 "$STATE_DIR/thread-id"

for old_plist in "$PLIST_DIR"/io.codepilot.agent.*.plist; do
  [ -f "$old_plist" ] || continue
  launchctl unload "$old_plist" 2>/dev/null || true
  rm -f "$old_plist"
done

write_scheduler_plist() {
  local name="$1"
  local interval="$2"
  local plist="$PLIST_DIR/io.codepilot.agents.scheduler.plist"
  cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>io.codepilot.agents.scheduler</string>
  <key>ProgramArguments</key>
  <array>
    <string>$SCHEDULER</string>
  </array>
  <key>StartInterval</key>
  <integer>$interval</integer>
  <key>RunAtLoad</key>
  <true/>
  <key>EnvironmentVariables</key>
  <dict>
    <key>CODEPILOT_REPO_ROOT</key>
    <string>$ROOT</string>
    <key>CODEPILOT_AGENT_ENABLED</key>
    <string>1</string>
    <key>CODEPILOT_AGENT_CONTINUOUS</key>
    <string>1</string>
    <key>CODEPILOT_AGENT_PUBLIC_AUTONOMY</key>
    <string>launch</string>
    <key>CODEPILOT_AGENT_MODEL</key>
    <string>gpt-5.6-sol</string>
    <key>CODEPILOT_AGENT_REASONING_EFFORT</key>
    <string>medium</string>
    <key>CODEPILOT_CODEX_BIN</key>
    <string>/Applications/ChatGPT.app/Contents/Resources/codex</string>
    <key>CODEPILOT_AGENT_THREAD_ID</key>
    <string>$THREAD_ID</string>
  </dict>
  <key>Umask</key>
  <integer>63</integer>
  <key>StandardOutPath</key>
  <string>$HOME/Library/Logs/CodePilotAgents/scheduler.launchd.out.log</string>
  <key>StandardErrorPath</key>
  <string>$HOME/Library/Logs/CodePilotAgents/scheduler.launchd.err.log</string>
</dict>
</plist>
EOF
  chmod 600 "$plist"
  launchctl unload "$plist" 2>/dev/null || true
  launchctl load "$plist"
}

write_scheduler_plist scheduler 60

echo "Installed CodePilot local agent scheduler."
echo "Escalations will be sent to Codex thread: $THREAD_ID"
