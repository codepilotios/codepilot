# Setup Friction: iOS Starts Gateway Requests Before Setup Is Verified

Labels: `setup`, `onboarding`, `ios`, `gateway`

## Summary

The iOS root view starts thread and account-status requests before the first-run connection test has verified the saved gateway configuration. Entering a token or reopening the app with an incomplete configuration can therefore show a network or invalid-URL alert on top of setup, even though the user has not tapped **Test Connection**.

## Reproduction

1. Launch CodePilot iOS with no verified gateway configuration.
2. Enter or restore an iOS connection token while the gateway URL is empty, invalid, or unreachable.
3. Observe that root-level thread or account polling can report an error independently of the setup form.
4. Complete **Test Connection** without changing the token and observe that token-keyed account polling is not guaranteed to restart for the newly verified configuration.

## Expected

Only **Test Connection** should contact the gateway while first-run setup is incomplete. Normal thread loading, pull-to-refresh, toolbar actions, and account polling should begin after the current URL, connection mode, and token pass authenticated verification.

## Actual Before The Audit Fix

Root-level tasks ran whenever the view appeared or the token changed. Toolbar actions were disabled only when the token was empty, rather than when the complete configuration was verified.

## Local Fix

The `agent/setup-audit` branch gates root-level gateway requests, pull-to-refresh, and gateway-dependent toolbar actions on the existing verified-configuration predicate. Thread loading and account polling are keyed to the verified configuration so they start after a successful test and restart when a newly changed configuration is verified.
