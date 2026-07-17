# Setup Friction: Mac App Bundle Omits The Gateway Service

Labels: `setup`, `install`, `mac`, `gateway`

## Summary

The built Mac app included the gateway LaunchAgent installer but omitted the Python gateway files that installer references. Using **Restart Gateway When Idle** from the app could therefore install a LaunchAgent whose program path did not exist inside the app bundle.

## Reproduction

1. Run `scripts/build-app.sh`.
2. Launch the resulting CodePilot app.
3. Open **Setup CodePilot...** and choose **Restart Gateway When Idle**.
4. Inspect the installed gateway LaunchAgent program path under the app's `Contents/Resources` directory.

## Expected

The app bundle should contain the gateway entry point and its Remote Desktop gateway dependency so the in-app installer creates a runnable LaunchAgent.

## Actual

Before this audit fix, `Contents/Resources/scripts/install-phone-gateway-agent.sh` existed, but `Contents/Resources/gateway/codex_phone_gateway.py` and `remote_desktop_gateway.py` did not.

## Local Fix

The `agent/setup-audit` branch now packages both production gateway modules and only their required runtime setup scripts in the Mac app. It also updates the Mac install guide to make the in-app action the primary gateway setup path.
