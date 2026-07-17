# CodePilot 0.1 TestFlight Notes

## What To Test

Test CodePilot from your iPhone while your Mac gateway handles coding turns, account status, file previews, and remote desktop sessions.

- First connection with a local or Cloudflare gateway URL.
- Gateway token entry and recovery copy for 401, 403, 502, and offline states.
- Account status, account switching, and stale-auth recovery.
- Starting, following, steering, and stopping a coding turn.
- File preview links from local paths, Markdown links, and file URLs.
- Local Mac web URL opening through the gateway.
- Remote desktop pairing, status, input, viewport behavior, and cleanup after backgrounding.

## Beta Requirements

- CodePilot Mac app installed and running.
- CodePilot gateway reachable from the iPhone.
- Valid gateway token copied from the Mac setup flow.
- Screen Recording and Accessibility permissions on the Mac for remote desktop testing.

## Known Gaps

- App Store screenshots and final metadata are draft-only in this branch.
- App Store privacy labels, review details, support URL, and privacy policy URL still require maintainer approval.
- TestFlight upload and group distribution were not run in this readiness pass.
