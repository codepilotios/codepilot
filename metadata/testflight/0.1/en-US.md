# CodePilot 0.1 TestFlight Notes

## What To Test

Test CodePilot from your iPhone while your Mac gateway handles Codex turns, account status, file uploads, and loopback web links.

- First connection with a permanent Cloudflare Tunnel URL and the gateway token from the Mac setup screen.
- Gateway token entry and recovery copy for 401, 403, 502, and offline states.
- Account status, account switching, and stale-auth recovery.
- Total available credit across configured accounts, including refresh timing and per-account breakdowns.
- Total Credit Live Activity updates on the Lock Screen and Dynamic Island.
- Reset-credit confirmation and refresh behavior for the selected account.
- Starting, following, steering, and stopping a coding turn.
- Uploading up to eight non-sensitive sample files within the 25 MB per-file and 50 MB combined limits.
- Opening a purpose-built loopback demo page through the authenticated gateway without exposing development data.
- Turn-finished notifications when APNs is configured for the gateway.

Remote Desktop is not included in this beta while its paired-device and session-authorization protections are being completed.

When reporting a failure, name the step that failed and remove account names, gateway URLs, tokens, hostnames, localhost or local-web session URLs, local page contents, local paths, private prompts, screenshots, and logs containing private data.

## Beta Requirements

- CodePilot Mac app installed and running.
- Mac running macOS 13 or later with Codex CLI already working.
- Approved beta build on an iPhone running iOS 17 or later.
- CodePilot gateway and Cloudflare Tunnel reachable from the iPhone.
- Valid gateway token copied from the Mac setup flow.
- Live Activities enabled when testing total-credit updates.
