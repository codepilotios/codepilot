# Presence Maintenance Escalation

Approval status: approved by maintainer on 2026-07-06.

The following public-publishing decisions are approved:

- Beta privacy copy in `docs/PRIVACY.md` once that tracked file exists.
- Public positioning in `README.md`, `docs/index.md`, and `docs/FAQ.md`.
- TestFlight/App Store metadata from `docs/APP_STORE_METADATA_DRAFT.md`.
- GitHub Pages source for the repository, preferably the `docs/` folder.
- Sanitized screenshot capture before screenshots are committed or used in App Store/TestFlight metadata.

## Pending Maintainer Action

Reverified on 2026-07-18. The public repository review found two launch-readiness settings that require maintainer access and one unresolved release blocker:

1. Enable GitHub Pages from the approved `main` branch `docs/` folder, verify the site, and add its URL to the repository website field. The Pages endpoint and repository website field are currently unset.
2. Enable GitHub private vulnerability reporting, then link the private reporting form from `docs/SECURITY.md` and the security issue-template contact link. Private vulnerability reporting is currently disabled, so public copy must not imply that a secure reporting channel exists.
3. Do not approve broader beta promotion while the critical Remote Desktop authorization blocker in GitHub issue #25 remains open. Review a fully tested fix before allowing the feature into public-beta copy or builds; the presence docs now describe it as unavailable.

These settings should be completed before broader public-beta promotion. No release, App Store, pricing, legal, credential, or external-system change is authorized by this note.
