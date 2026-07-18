# Public Presence Checklist

Use this checklist before updating GitHub Pages, README copy, public docs, screenshots, changelog entries, FAQ, privacy copy, support copy, issue templates, or App Store metadata drafts.

## Positioning

- Keep the current release track clearly labeled as a public beta.
- Target AI coding users and existing Codex CLI users.
- Avoid promising production-team readiness, hosted CodePilot accounts, LAN setup, non-Codex providers, pricing, subscriptions, App Store availability, or release dates unless those items have maintainer approval.
- Describe Cloudflare Tunnel as the supported public-beta iPhone access path.
- Do not promote features with unresolved security or release blockers. Remote Desktop remains outside the supported public beta until its pairing and session-authorization enforcement is verified.

## Privacy Review

Before committing public content, check for:

- Private names, private email addresses, personal account names, Apple identifiers, and team identifiers.
- Hostnames, tunnel URLs, gateway URLs, tokens, auth file contents, and API keys.
- Machine-specific paths, local usernames, private repository names, private prompts, uploaded files, and live desktop contents.
- Screenshots or logs that include any private value above.

Use demo data such as `Work`, `Personal`, `Demo`, `codepilot.example.com`, and generic sample files.

For screenshot, metadata, issue-template, or support-copy changes, also verify:

- The copy asks for the failing step and visible recovery text instead of broad log dumps.
- Remote Desktop screenshots are excluded while the feature remains outside the supported public beta.
- Examples avoid real prompts, private repositories, customer names, local usernames, and machine-specific paths.
- Public wording still says the current iPhone beta path uses Cloudflare Tunnel, not unsupported LAN access.

## Support Copy

Public support and feedback copy should ask for:

- Affected area: Mac app, iPhone app, gateway, Cloudflare setup, account switching, file upload, localhost link opening, notifications, docs, or the Remote Desktop availability guard.
- Failing step and visible recovery message.
- macOS version, iOS version, CodePilot build or commit, and Codex CLI version when available.
- Sanitized logs or screenshots only when they materially help reproduce the issue.

## Approval Gates

Maintainer approval is required before publishing or submitting:

- App Store privacy labels, age rating, export compliance, pricing, subscriptions, or legal terms.
- TestFlight external testing, App Store review, public launch announcements, paid promotion, or community posts.
- Claims about hosted services, production readiness, non-Codex provider support, or subscription value.

## Publishing Readiness

- Run `scripts/public-presence-audit.sh` and `scripts/privacy-audit.sh` before committing public-content changes.
- Run `scripts/public-presence-live-audit.sh` when verifying repository settings and the published site. It checks the approved repository description, website field, Pages source, private vulnerability reporting, and the landing, privacy, and support URLs without changing GitHub settings.
- Confirm GitHub Pages is enabled from the approved `main` branch `docs/` source and the site returns successfully.
- Add the live Pages URL to the repository website field and resolve the App Store support and privacy URL drafts to live pages.
- Keep the repository description beta-focused and specific to the current audience. Recommended copy: `Public beta Mac and iPhone companion for Codex CLI workflows.`
- Confirm a private security-reporting channel is enabled and linked from `SECURITY.md` before broader beta promotion.
- Keep sensitive vulnerability details out of public issues, even when asking for private coordination.
