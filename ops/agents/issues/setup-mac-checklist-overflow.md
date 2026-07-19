# Setup Friction: Mac Setup Checklist Can Overflow Its Window

Labels: `setup`, `onboarding`, `mac`, `accessibility`

## Summary

The Mac setup window uses a fixed initial height while showing nine status rows, four action sections, refresh controls, and result text. On smaller displays or with larger accessibility text, the lower Cloudflare and refresh controls can extend beyond the visible window with no scrolling.

## Reproduction

1. Open **Setup CodePilot...** on a Mac with a short available screen height.
2. Increase the system text size or resize the setup window vertically.
3. Try to reach **Cloudflare Remote Access**, **Refresh Status**, and the latest action result.

## Expected

Every setup status and recovery action remains reachable at supported window sizes and accessibility text settings.

## Actual Before The Audit Fix

The setup content is a vertical stack attached directly to the window. Its bottom constraint allows overflow, but the window has no scroll view.

## Local Audit Fix

The `agent/setup-audit` branch places the complete setup stack in a vertically scrolling view while preserving the existing layout and window size.
