# Setup Friction: Gateway Misses User-Installed Codex CLI

Labels: `setup`, `onboarding`, `gateway`, `install`

## Summary

The Mac setup checklist recognizes Codex CLI installations in common user directories, including `~/.local/bin`, but the gateway LaunchAgent previously searched only its restricted inherited path and system or Homebrew directories. Setup could therefore report **Codex CLI: Ready** while iPhone requests failed because the gateway could not launch Codex.

## Reproduction

1. Install Codex CLI in `~/.local/bin`, `~/.npm-global/bin`, or `~/.bun/bin`.
2. Launch CodePilot and confirm the setup checklist reports **Codex CLI: Ready**.
3. Install or restart the gateway LaunchAgent.
4. Start a Codex action from the iPhone app.

## Expected

The gateway uses the same supported Codex CLI search locations as the Mac setup readiness check.

## Actual Before The Audit Fix

The gateway child environment included Homebrew and `/usr/local/bin`, but not the supported user install directories. Its executable fallback also used the LaunchAgent's restricted path before falling back to the Codex app bundle location.

## Local Fix

The `agent/setup-audit` branch adds the three user install directories to the gateway child path and executable fallback. A focused gateway test covers resolution when the inherited LaunchAgent path is restricted.
