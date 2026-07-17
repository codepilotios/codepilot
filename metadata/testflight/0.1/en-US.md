# CodePilot 0.1 TestFlight Notes

## What To Test

Test CodePilot from your iPhone while your Mac gateway handles coding turns, account status, file previews, and local Mac web links.

- First connection with a Cloudflare gateway URL.
- Gateway token entry and recovery copy for 401, 403, 502, and offline states.
- Account status, account switching, and stale-auth recovery.
- Total available credit across configured accounts, including refresh timing and per-account breakdowns.
- Total Credit Live Activity updates on the Lock Screen and Dynamic Island.
- Reset-credit confirmation and refresh behavior for the selected account.
- Starting, following, steering, and stopping a coding turn.
- File preview links from local paths, Markdown links, and file URLs.
- Local Mac web URL opening through the gateway.

Remote Desktop is not included in this beta while its paired-device and session-authorization protections are being completed.

## Beta Requirements

- CodePilot Mac app installed and running.
- CodePilot gateway reachable from the iPhone.
- Valid gateway token copied from the Mac setup flow.
- Live Activities enabled when testing total-credit updates.
