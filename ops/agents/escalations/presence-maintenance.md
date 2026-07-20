# Presence Maintenance Escalation

Approval status: approved by maintainer on 2026-07-06.

The following public-publishing decisions are approved:

- Beta privacy copy in `docs/PRIVACY.md` once that tracked file exists.
- Public positioning in `README.md`, `docs/index.md`, and `docs/FAQ.md`.
- TestFlight/App Store metadata from `docs/APP_STORE_METADATA_DRAFT.md`.
- GitHub Pages source for the repository, preferably the `docs/` folder.
- Sanitized screenshot capture before screenshots are committed or used in App Store/TestFlight metadata.

## Pending Maintainer Action

Reverified on 2026-07-20. The read-only live presence audit still reports seven failures: the repository description, repository website field, GitHub Pages configuration, private vulnerability reporting, and the landing, privacy, and support URLs. These map to four launch-readiness settings that require maintainer access, one legal-content decision, and one unresolved release blocker:

Repository-setting follow-up is tracked in GitHub issue #27.

1. Enable GitHub Pages from the approved `main` branch `docs/` folder, verify the site, and add its URL to the repository website field. The Pages endpoint and repository website field are currently unset.
2. Update the repository description so the public header identifies the current release as a beta. Recommended copy: `Public beta Mac and iPhone companion for Codex CLI workflows.`
3. Enable GitHub private vulnerability reporting, then link the private reporting form from `docs/SECURITY.md` and the security issue-template contact link. Private vulnerability reporting is currently disabled, so public copy must not imply that a secure reporting channel exists.
4. Do not approve broader beta promotion while the critical Remote Desktop authorization blocker in GitHub issue #25 remains open. Review a fully tested fix before allowing the feature into public-beta copy or builds; the presence docs now describe it as unavailable.
5. Decide whether the source-distributed beta needs standalone public terms in addition to the repository license files, and approve any legal text before it is added. The launch plan lists terms as a Presence Agent deliverable, but the existing approval covers privacy copy and App Store metadata only.

These settings should be completed before broader public-beta promotion. No release, App Store, pricing, legal, credential, or external-system change is authorized by this note.
