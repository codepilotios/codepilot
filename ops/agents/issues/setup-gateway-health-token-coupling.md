# Setup Friction: Gateway Health Check Depends On Token File

Labels: `setup`, `gateway`, `install`, `ios`

## Summary

The Mac setup checklist treated gateway reachability as blocked when the gateway token file was missing, even though the gateway exposes `/api/health` as a public-safe unauthenticated endpoint. This can mislead first-run users by reporting the gateway as stopped when the actual missing setup item is only the iOS token.

## Reproduction

1. Start the CodePilot gateway so `http://127.0.0.1:18790/api/health` returns `{"gateway":{"running":true}}`.
2. Remove or withhold the local phone gateway token file.
3. Open **Setup CodePilot...**.

## Expected

The setup checklist should report **Gateway: Ready** and separately report **Gateway Token: Missing**.

## Actual

The setup checklist reported the gateway as stopped because the health probe required a bearer token before calling the public health endpoint.

## Local Audit Fix

The `agent/setup-audit` branch now probes `/api/health` without an `Authorization` header and only marks the gateway ready when the public health JSON reports `gateway.running: true`.
