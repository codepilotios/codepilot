# Setup Friction: iOS Cloudflare Mode Accepted IP Addresses

Labels: `setup`, `onboarding`, `ios`, `cloudflare`

## Summary

The iOS first-run form accepted any non-loopback HTTPS IP address in **Cloudflare** mode. A tester could therefore verify a LAN endpoint while near the Mac and believe remote access was configured, only for the connection to fail away from that network.

## Reproduction

1. Launch the iOS app in the first-run setup state.
2. Keep **Cloudflare** selected.
3. Enter an HTTPS IP address such as `https://192.0.2.10:18790`.
4. Enter a non-empty iOS connection token.

## Expected

Cloudflare mode should require the public tunnel hostname copied from the Mac setup screen. IP-address connections belong to deliberately configured advanced networking, not the Cloudflare setup path.

## Actual Before The Audit Fix

The form rejected loopback addresses and non-HTTPS URLs but accepted other IPv4 and IPv6 addresses in Cloudflare mode.

## Local Fix

The `agent/setup-audit` branch now rejects IPv4 and IPv6 addresses in Cloudflare mode, keeps the first-run form incomplete, and explains that a public tunnel hostname is required. Focused tests cover both address families and the iOS install guide states the requirement.
