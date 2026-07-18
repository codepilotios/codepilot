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

## Actual Before The Audit

Permissions are only visible from the separate **Remote Desktop...** window, and APNs readiness is documented but not surfaced in setup status.

## Suggested Fix

Add setup rows for Screen Recording, Accessibility, and notification delivery readiness with direct recovery copy.

## Local Audit Progress

The `agent/setup-audit` branch adds Screen Recording and Accessibility rows to the Mac setup checklist and a setup action that opens the existing permission controls. Notification delivery is surfaced as optional, but the row does not yet distinguish configured APNs delivery from an unconfigured gateway. APNs credential setup and production verification still require maintainer-owned credentials.
