# Setup Friction: Setup Status Omits Permissions And Notification Readiness

Labels: `setup`, `onboarding`, `permissions`, `notifications`

## Summary

The Mac setup window checks Codex, account profiles, gateway token, gateway health, and Cloudflare. It does not summarize Remote Desktop permissions or notification readiness, even though those are first-run setup requirements for iOS use.

## Reproduction

1. Open CodePilot on macOS.
2. Choose **Setup CodePilot...**.
3. Review the status rows.

## Expected

The setup window should show Remote Desktop Screen Recording and Accessibility status, plus notification readiness or an explicit optional state.

## Actual

Permissions are only visible from the separate **Remote Desktop...** window, and APNs readiness is documented but not surfaced in setup status.

## Suggested Fix

Add setup rows for Screen Recording, Accessibility, and notification delivery readiness with direct recovery copy.

## Local Audit Fix

The `agent/setup-audit` branch adds these rows to the Mac setup checklist. Notification delivery is surfaced as optional; APNs credential setup still requires maintainer-owned credentials before production delivery can be verified.
