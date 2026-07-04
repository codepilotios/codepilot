#!/usr/bin/env zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="${CODEPILOT_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
PLIST_DIR="$HOME/Library/LaunchAgents"
RUNNER="$ROOT/scripts/codepilot-agent-runner.sh"

if [[ "${1:-}" != "--install" ]]; then
  cat <<'EOF'
This installs local LaunchAgents for CodePilot background agents.

Important limitation:
Local LaunchAgents cannot ping the current Codex thread. They write logs to
~/Library/Logs/CodePilotAgents and intervention notes to ops/agents/escalations.

Run with --install only if that fallback escalation path is acceptable.
EOF
  exit 64
fi

chmod +x "$RUNNER"
mkdir -p "$PLIST_DIR"

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
  <false/>
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
