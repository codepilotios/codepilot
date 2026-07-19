# Setup Friction: Cloudflare Verification Accepted The Wrong Origin

Labels: `setup`, `onboarding`, `cloudflare`, `validation`

## Summary

The manual `verify --url` path could probe an HTTP URL, a different healthy hostname, or a URL with an unexpected path and still print a successful verification message. In some cases setup metadata remained unverified; in others CodePilot could later offer an HTTPS origin that the verification step had never tested.

## Reproduction

1. Configure the permanent hostname `codepilot.example.com`.
2. Run `scripts/setup-cloudflare-remote-access.sh verify --url http://codepilot.example.com`.
3. Or run verification against another healthy gateway hostname.

## Expected

Verification should require the configured permanent HTTPS tunnel origin, reject paths, queries, credentials, and hostname mismatches before making a request, and only report success when readiness metadata is updated.

## Actual Before The Audit Fix

The helper curled the supplied URL first and printed `verified` after any successful health response. Its metadata update silently did nothing when the hostname did not match.

## Local Audit Fix

The `agent/setup-audit` branch validates the verification URL and permanent setup metadata before probing health. Shell regression tests cover HTTP, hostname mismatch, path/query input, and the successful configured HTTPS origin.
