# Setup Friction: Remote Desktop Session Enables Before Pairing

Labels: `setup`, `onboarding`, `ios`, `remote-desktop`, `security`

## Summary

The iOS Remote Desktop setup enables **Start Session** whenever its display text is anything other than `Not paired`. Refreshing host status replaces that text with a host-reachability or permissions message, so an unpaired device can be offered the session action before trust is established.

## Reproduction

1. Configure the iOS app with a valid gateway URL and iOS connection token on a device that has not been paired.
2. Open **Remote Desktop**.
3. Let the automatic status refresh complete, or tap **Refresh Status**.
4. Observe that **Start Session** becomes enabled even though **Start Pairing** has not completed.

## Expected

The session action should be enabled only when the gateway reports that this exact device ID is trusted and not revoked. Host reachability and macOS permission status should be displayed independently from pairing status.

## Actual

The action is gated by user-facing `statusText` rather than pairing state. Any successful refresh changes that text and enables the action. Starting a session then fails later with an untrusted-device error.

## Suggested Fix

Use the existing authenticated `GET /api/remote/devices` route to load trusted devices, derive pairing state for the current device ID, and gate **Start Session** on that state. Keep host, permission, and pairing messages as separate state. Add iOS tests covering unpaired, paired, and revoked devices.

## Audit Constraint

No iOS code was changed in this unattended audit because repository policy requires OTA verification for iOS changes, while this run may not mutate the OTA service or a non-isolated checkout.
