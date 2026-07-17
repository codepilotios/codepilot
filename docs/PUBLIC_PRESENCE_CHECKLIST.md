# Public Presence Checklist

Use this checklist before updating GitHub Pages, README copy, public docs, screenshots, changelog entries, FAQ, privacy copy, support copy, issue templates, or App Store metadata drafts.

## Positioning

- Keep the current release track clearly labeled as a public beta.
- Target AI coding users and existing Codex CLI users.
- Avoid promising production-team readiness, hosted CodePilot accounts, LAN setup, non-Codex providers, pricing, subscriptions, App Store availability, or release dates unless those items have maintainer approval.
- Describe Cloudflare Tunnel as the supported public-beta iPhone access path.

## Privacy Review

Before committing public content, check for:

- Private names, private email addresses, personal account names, Apple identifiers, and team identifiers.
- Hostnames, tunnel URLs, gateway URLs, tokens, auth file contents, and API keys.
- Machine-specific paths, local usernames, private repository names, private prompts, uploaded files, and live desktop contents.
- Screenshots or logs that include any private value above.

Use demo data such as `Work`, `Personal`, `Demo`, `codepilot.example.com`, and generic sample files.

## Support Copy

Public support and feedback copy should ask for:

- Affected area: Mac app, iPhone app, gateway, Cloudflare setup, account switching, remote desktop, file upload, notifications, or docs.
- Failing step and visible recovery message.
- macOS version, iOS version, CodePilot build or commit, and Codex CLI version when available.
- Sanitized logs or screenshots only when they materially help reproduce the issue.

## Approval Gates

Maintainer approval is required before publishing or submitting:

- App Store privacy labels, age rating, export compliance, pricing, subscriptions, or legal terms.
- TestFlight external testing, App Store review, public launch announcements, paid promotion, or community posts.
- Claims about hosted services, production readiness, non-Codex provider support, or subscription value.
