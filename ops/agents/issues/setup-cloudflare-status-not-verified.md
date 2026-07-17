# Setup Friction: Cloudflare Configuration Appears Ready Before Verification

Labels: `setup`, `onboarding`, `mac`, `cloudflare`

## Summary

The Mac setup checklist marks Cloudflare **Ready** when a metadata or configuration file exists. It does not confirm that the LaunchAgent is running or that the public hostname reaches the gateway, so failed verification and stale tunnel configurations look launch-ready.

## Reproduction

1. Configure a permanent Cloudflare hostname.
2. Stop the tunnel LaunchAgent, make the DNS route invalid, or let public verification fail.
3. Return to **Setup CodePilot...** and refresh status.

## Expected

The checklist should distinguish **Configured** from **Verified**, show the last successful verification time, and provide a direct retry action.

## Actual

The presence of setup metadata or either supported config file produces **Ready**. Although metadata defines `lastVerifiedAt`, the verification command does not currently record it.

## Suggested Fix

Record successful verification in metadata, probe LaunchAgent state, and expose a finite **Verify Remote Access** action. Preserve **Configured** for offline Macs instead of treating temporary network failure as loss of configuration.
