# Setup Friction: LaunchAgent Health Is Not Visible

Labels: `setup`, `onboarding`, `mac`, `gateway`, `cloudflare`

## Summary

First-run setup can install LaunchAgents for CodePilot, the gateway, and the Cloudflare tunnel, but the setup checklist does not report whether those jobs are installed, loaded, or repeatedly failing. A currently reachable process can therefore look ready even though it will not return after logout, restart, or a crash.

## Reproduction

1. Build CodePilot and install one or more documented LaunchAgents.
2. Unload a job, remove its property list, or configure it to exit repeatedly.
3. Open **Setup CodePilot...** and refresh status.

## Expected

The setup window distinguishes service reachability from persistence health for the CodePilot app, gateway, and permanent Cloudflare tunnel. Missing or failed jobs have a direct install, reload, or log-viewing recovery action.

## Actual

The checklist probes gateway HTTP health and Cloudflare metadata, but does not inspect `launchctl` state for any setup service. Start-at-login setup is documented only as a source-checkout helper and is not represented in the checklist.

## Suggested Fix

Add public-safe LaunchAgent status rows backed by `launchctl print` and property-list existence checks. Report only stable states such as **Not installed**, **Stopped**, **Running**, or **Needs attention**; keep job output and user-specific paths behind an advanced details view.
