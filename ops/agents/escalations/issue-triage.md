# Issue Triage Escalations

Date: 2026-07-19

- Issue #25 remains a critical distribution blocker after fail-closed containment merged in PR #22. Keep Remote Desktop disabled until approved-device signed leases, expiry and revocation, and HTTP/WebRTC/native-boundary authorization regression coverage pass.
- Issue #27 now has its documentation prerequisite merged, but repository administration is still required to enable Pages from `main`/`docs`, verify and set the public website, update the approved beta description, enable private vulnerability reporting, and align the security-reporting links.
- Issue #8 remains pending a sanitized demo capture session and manual full-resolution privacy review. No additional approval is needed for the already approved demo-only capture set.
- No pricing, legal, App Store, credential, or public-posting decision is requested.

Date: 2026-07-17

- No active maintainer decision escalations for issue triage.
- Follow-up check found no new GitHub issues created on 2026-07-04.
- OTA build and public OTA asset verification are still required for the iOS changes, but were not run in this unattended pass because non-GitHub external system mutation is prohibited by the current public write policy.

Date: 2026-07-08

- GitHub cleanup needed: issues #2 and #3 remain open even though the approved setup/pairing implementation appears merged through PR #14 on 2026-07-04. Draft PR #15 remains open and merge-conflicted from the same branch after PR #14 merged. Maintainer should close or supersede these public GitHub items as appropriate.

Date: 2026-07-13

- Issue #2 follow-up patch prepared on `agent/issue-triage-2026-07-08`: Settings still exposed Same Network even though first-run setup was Cloudflare-only. Maintainer cleanup is still needed for stale issue/PR closure after review because unattended policy does not explicitly allow closing existing public GitHub items.
