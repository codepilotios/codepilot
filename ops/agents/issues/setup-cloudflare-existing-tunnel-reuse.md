# Setup Friction: Permanent Setup Does Not Reuse Existing Tunnel

Labels: `setup`, `onboarding`, `cloudflare`, `mac`

## Summary

The Cloudflare guide says the wizard creates or reuses a named tunnel, but the helper always runs `cloudflared tunnel create`. If that name already exists, setup stops because it cannot obtain a tunnel ID and tells the user to choose another name or remove the tunnel.

## Reproduction

1. Create a Cloudflare Tunnel named `codepilot`.
2. Run permanent setup again with the same tunnel name.
3. Observe that configuration stops before writing a usable config or installing the service.

## Expected

Setup should safely reuse the existing named tunnel when its local credentials are present, or clearly state before setup that a new unique name is required.

## Actual

The documented reuse path is not implemented. The helper treats an existing tunnel as a missing-ID failure.

## Suggested Fix

Query `cloudflared tunnel list --output json`, match one exact tunnel name, verify the corresponding local credentials file, and reuse its ID. Keep ambiguous matches and missing credentials as actionable failures.
