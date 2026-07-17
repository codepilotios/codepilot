# Setup Friction: Mac App Can Miss User-Installed Codex CLI

Labels: `setup`, `onboarding`, `mac`, `install`

## Summary

The Mac setup checklist runs `/usr/bin/which codex` with the menu bar app's inherited environment. Apps launched from Finder or a LaunchAgent commonly have a narrower search path than an interactive shell, so CodePilot can report **Codex CLI: Missing** even when `codex` works in Terminal.

## Reproduction

1. Install Codex in a user-managed binary directory that is added by shell startup configuration.
2. Confirm `codex` runs in Terminal.
3. Launch CodePilot outside Terminal and open **Setup CodePilot...**.
4. Review the **Codex CLI** row.

## Expected

CodePilot should find supported Codex installations independently of Finder or LaunchAgent search-path differences, or let the user select the executable.

## Actual

Detection delegates to `which` without constructing a known search path or consulting the user's login shell.

## Suggested Fix

Check documented installation locations and a sanitized login-shell path, show the resolved executable in advanced details, and provide a direct recovery action when detection fails.

## Local Fix

The `agent/setup-audit` branch checks the inherited search path plus standard Homebrew and user-level install directories. It also ignores files that exist but are not executable, so Finder and LaunchAgent launches no longer depend on shell startup configuration for common Codex installations.
