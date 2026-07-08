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

The iOS flow pairs automatically after signing the challenge. Copy cleanup removed an unused manual pairing-code field, but the approval policy still needs maintainer review before public beta.

## Suggested Fix

Decide the public beta policy, then either add explicit Mac-side approval or update setup/security docs to state that a valid gateway token authorizes pairing.
