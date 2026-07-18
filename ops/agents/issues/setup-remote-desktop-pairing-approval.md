# Setup Friction: Remote Desktop Pairing Approval Is Ambiguous

Labels: `setup`, `onboarding`, `remote-desktop`, `security`

## Summary

Remote Desktop pairing currently completes from the iOS flow after the device signs a challenge issued by the Mac gateway. Because Remote Desktop can control the Mac, public beta setup needs an explicit decision on whether bearer-token possession is sufficient or whether the Mac must show an approval prompt.

## Reproduction

1. Configure the iOS app with a valid gateway URL and iOS connection token.
2. Open **Remote Desktop**.
3. Tap **Start Pairing**.

## Expected

The setup flow should clearly communicate the trust boundary. If Mac-side approval is required, the iOS app should wait for approval and the Mac app should expose Approve/Reject UI.

## Actual

The Mac Remote Desktop window now shows **Approve** and **Reject** for the pending challenge, but the happy path does not wait for either action. The `pairing.complete` RPC verifies the iPhone signature and immediately persists the device as trusted. The coordinator's separate pending state remains visible until someone approves or rejects it, so the Mac can simultaneously show the device as trusted and still awaiting approval.

## Suggested Fix

Decide the public beta policy, then either make `pairing.complete` return a pending state until the Mac approves the verified challenge, or remove the non-enforcing approval UI and update setup/security docs to state that a valid gateway token authorizes pairing. Add an integration test that proves the selected trust boundary and keeps the pending/trusted states consistent.
