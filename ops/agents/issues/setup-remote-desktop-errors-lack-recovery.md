# Setup Friction: Remote Desktop Errors Lack Recovery Actions

Labels: `setup`, `onboarding`, `ios`, `remote-desktop`

## Summary

The iOS Remote Desktop setup collapses connection, authentication, pairing-expiration, and host failures into **Host unavailable**, **Pairing failed**, or a raw gateway error code. A tester cannot tell whether to fix the iPhone connection, restart the Mac gateway, or repeat pairing.

## Reproduction

1. Connect the iOS app to a Mac gateway.
2. Open **Remote Desktop**.
3. Stop the gateway, use an outdated iOS connection token, or let a pairing challenge expire.
4. Refresh status or start pairing.

## Expected

The error identifies the failed setup dependency and gives one concrete recovery action without exposing an internal error code.

## Actual Before The Audit Fix

Status failures showed **Host unavailable**. Most pairing failures showed **Pairing failed**, while gateway pairing errors could display raw identifiers such as `pairing_expired`.

## Local Audit Fix

The `agent/setup-audit` branch maps offline and unreachable-network states, invalid gateway settings, stale tokens, expired pairing, known Mac permission errors, and unavailable hosts to specific recovery copy. Focused iOS tests cover the common first-run cases.
