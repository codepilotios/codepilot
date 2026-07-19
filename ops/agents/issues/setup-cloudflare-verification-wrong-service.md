# Setup Friction: Cloudflare Verification Accepts An Unrelated Service

Labels: `setup`, `onboarding`, `cloudflare`, `validation`

## Summary

Cloudflare verification treats any successful HTTP response from `/api/health` as proof that the configured hostname reaches CodePilot. A parked page, redirect target, or unrelated service returning HTTP 200 can therefore mark remote access ready and expose a URL that fails in the iPhone app.

## Reproduction

1. Configure a permanent Cloudflare hostname in CodePilot metadata.
2. Point that hostname at a service that returns HTTP 200 for `/api/health`, but does not return the CodePilot health payload.
3. Run **Verify Remote Access**.

## Expected

Verification should require valid JSON whose `gateway.running` value is `true` before recording the hostname as verified.

## Actual Before The Audit Fix

The helper used `curl -fsS` and discarded the response body, so HTTP status alone controlled readiness.

## Local Audit Fix

The `agent/setup-audit` branch now validates the health payload before updating verification metadata. The Mac wizard tells users to restart the gateway and tunnel when the remote URL does not report a running CodePilot gateway. Shell regression tests cover an unrelated HTML response, a stopped gateway payload, and a running CodePilot gateway.
