# Setup Friction: Invalid Auth Files Appear Ready

Labels: `setup`, `onboarding`, `mac`, `auth`

## Summary

The Mac setup checklist treated any file named `auth.json` as a valid Codex login or account profile. An empty, malformed, or empty-object file could therefore make first-run setup look ready even though later authenticated actions would fail.

## Reproduction

1. Create an empty or malformed Codex `auth.json`, or place one in an account profile directory.
2. Open **Setup CodePilot...**.
3. Refresh setup status.

## Expected

Only a readable, non-empty JSON object should satisfy the basic setup readiness check. Provider authentication remains the authoritative runtime validation.

## Actual Before The Audit

Readiness depended only on the file existing at the expected path.

## Local Audit Fix

The `agent/setup-audit` branch now rejects missing, unreadable, malformed, and empty-object auth files when calculating the Codex login and account profile setup rows. It deliberately avoids enforcing provider-specific keys so routine auth schema changes do not break first-run detection.
