# Setup Friction: Cloudflare Verification Can Wait Indefinitely

Labels: `setup`, `onboarding`, `cloudflare`, `mac`

## Summary

The permanent-hostname verification step calls the public health endpoint without a connection or overall timeout. DNS, routing, or tunnel failures can therefore leave the Mac setup flow waiting without a recovery action.

## Reproduction

1. Configure a permanent hostname in **Setup CodePilot... > Cloudflare Remote Access**.
2. Stop the tunnel, make the hostname unroutable, or use a network that silently drops the request.
3. Choose **Verify Remote Access**.

## Expected

Verification ends within a bounded interval and tells the tester to check the Mac gateway and Cloudflare tunnel before retrying.

## Actual Before The Audit Fix

The health request has no explicit timeout, and the setup window can continue showing the verification step as running.

## Local Audit Fix

The `agent/setup-audit` branch adds a five-second connection timeout and a 15-second total timeout. An unreachable endpoint now produces CodePilot-specific gateway-and-tunnel recovery copy, with shell and Swift regression coverage.
