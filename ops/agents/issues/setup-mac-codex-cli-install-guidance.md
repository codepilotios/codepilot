# Setup Friction: Mac Guide Omits Codex CLI Installation

Labels: `setup`, `onboarding`, `mac`, `install`

## Summary

CodePilot requires Codex CLI, but the Mac installation guide previously listed it only as a prerequisite. A first-run user who does not already have `codex` had no installation link or command and could not recover directly from **Codex CLI: Missing**.

## Reproduction

1. Start from a Mac without Codex CLI installed.
2. Follow `docs/INSTALL_MAC.md`.
3. Open **Setup CodePilot...** and see **Codex CLI: Missing**.

## Expected

The Mac guide should link to the current official Codex CLI instructions and show the supported macOS installer before asking the user to sign in.

## Actual Before The Audit

The guide said only that Codex must be installed and available as `codex`.

## Local Fix

The `agent/setup-audit` branch links the official Codex CLI guide, includes OpenAI's current macOS/Linux installer command, and tells the user to run `codex` once to complete sign-in. The README Quick Start now links the same official guide.
