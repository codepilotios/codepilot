# Setup Friction: Cloudflare Hostname Input Needs Early Validation

Labels: `setup`, `onboarding`, `cloudflare`, `mac`

## Summary

The manual Cloudflare permanent-hostname setup accepted raw `--hostname` and `--tunnel-name` values before passing them to `cloudflared` and writing YAML config. A first-run user could paste a full `https://` URL or enter an invalid DNS name and get a lower-level Cloudflare or YAML failure instead of a setup-specific recovery message.

## Reproduction

1. Run `scripts/setup-cloudflare-remote-access.sh configure-permanent --hostname https://codepilot.example.com --tunnel-name codepilot`.
2. Or run `scripts/setup-cloudflare-remote-access.sh configure-permanent --hostname bad_host.example.com --tunnel-name codepilot`.

## Expected

The setup helper should reject invalid input before creating or updating Cloudflare resources and explain the expected hostname format.

## Actual

Before this audit fix, the script did not validate the hostname or tunnel name format before invoking `cloudflared`.

## Local Fix

The `agent/setup-audit` branch now validates that `--hostname` is a DNS hostname without schemes, paths, spaces, or underscores, validates simple tunnel names, adds shell regression tests, and documents the expected manual fallback format.

The Mac wizard now also maps invalid setup arguments to that recovery guidance instead of showing the generic Cloudflare setup failure message.
