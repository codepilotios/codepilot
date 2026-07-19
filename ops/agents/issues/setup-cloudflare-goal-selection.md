# Setup Friction: Cloudflare Requirement Depends On User Goal

Labels: `setup`, `onboarding`, `cloudflare`, `mac`

## Summary

The Mac setup checklist now treats missing `cloudflared` as optional, which avoids making local-only setup look broken. The remaining friction is that the setup window does not let users state whether they want local-only iPhone access or remote access through Cloudflare, so the same row must serve both goals.

## Reproduction

1. Open CodePilot on a Mac without `cloudflared` installed.
2. Choose **Setup CodePilot...**.
3. Review the **Cloudflare** setup row.

## Expected

The setup flow should ask whether the user wants remote iPhone access. If yes, the Cloudflare row should become a required setup task with a direct install/configure action. If no, it should remain optional and not block first-run success.

## Actual

The checklist has one static Cloudflare row. It can explain optional remote access, but it cannot distinguish a local-only setup from a remote-access setup goal.

## Local Audit Fix

The `agent/setup-audit` branch changes the missing-`cloudflared` row from **Missing** to **Optional** with recovery copy for users who want remote iPhone access. A future guided setup mode should make the user's connection goal explicit.
