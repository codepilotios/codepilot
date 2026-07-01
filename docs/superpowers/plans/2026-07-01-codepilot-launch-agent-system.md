# CodePilot Launch Agent System Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development for build tasks and codex recurring automations for ongoing operations. This plan defines always-on launch agents, their scopes, intervention rules, and the work needed before they can run safely.

**Goal:** Roll out CodePilot successfully, keep the Mac app, iOS app, gateway, docs, and marketing presence maintained, and support subscription revenue without requiring constant manual coordination.

**Architecture:** Use a small set of persistent scheduled agents with narrow responsibilities. Agents report only when a human decision, account credential, payment, legal choice, or platform approval is required. Product changes still flow through GitHub issues, branches, tests, builds, and releases.

**Tech Stack:** GitHub Issues, GitHub Pages, App Store Connect/TestFlight, Fastlane/asc, Cloudflare Tunnel, CodePilot Mac app, CodePilot iOS app, Swift/SwiftUI, shell automation, Codex recurring automations.

---

## Operating Principles

- Agents must not invent credentials, create accounts with fake identity, spam communities, or bypass platform rules.
- Reddit promotion must be transparent: disclose the creator relationship and follow subreddit rules.
- Anything involving App Store submission, payments, pricing, legal terms, public claims, or user data policy requires explicit human approval.
- Agents should ping Tony in the current Codex thread only when intervention is necessary.
- Routine findings should become GitHub issues, PRs, docs updates, or release notes without a ping.
- Every code change must be tested before being marked complete.
- Every iOS app change must trigger the project OTA build process before completion.

## Escalation Rules

Ping Tony only for:

- Apple, Cloudflare, GitHub, Reddit, or payment-provider authentication.
- App Store Connect agreements, pricing, tax, banking, privacy, age rating, export compliance, or review submission approval.
- A production outage affecting installs, auth, account switching, gateway availability, or paid users.
- A security issue involving secrets, auth tokens, remote desktop access, user data, or public endpoints.
- A public post, launch announcement, paid promotion, or subreddit submission that needs final approval.
- A product decision that affects subscription value, pricing, usage limits, or public positioning.

Do not ping Tony for:

- Routine dependency updates that pass tests.
- GitHub issue triage.
- Draft docs, draft website copy, draft Reddit posts, draft screenshots, or draft release notes.
- Non-critical bugs that can be filed and prioritized.
- Build failures that can be reproduced and fixed without credentials.

## Agent 1: Setup Experience Agent

**Mission:** Make first-run installation and configuration simple, intuitive, and transparent for ordinary users.

**Continuous cadence:** Daily during pre-launch, weekly after stable public beta.

**Responsibilities:**

- Audit Mac app setup flows for Cloudflare, Codex auth, gateway install, LaunchAgent health, permissions, and account setup.
- Audit iOS app onboarding for gateway URL, pairing, auth status, notifications, file upload, remote desktop, and account switching.
- Convert confusing errors into specific recovery actions.
- Maintain setup docs and screenshots.
- Create issues for every setup friction point found.

**Inputs:**

- GitHub issues tagged `setup`, `onboarding`, `install`, `cloudflare`, `auth`.
- TestFlight feedback.
- Gateway logs.
- Mac app setup status.
- iOS screenshots uploaded from user reports.

**Outputs:**

- Pull requests for setup UX fixes.
- Updated `docs/INSTALL_MAC.md`, `docs/CLOUDFLARE_SETUP.md`, and iOS onboarding text.
- GitHub issues with reproduction steps.
- No direct ping unless credentials, paid accounts, or a platform decision is required.

## Agent 2: Maintenance Agent

**Mission:** Keep the iOS app and gateway healthy based on GitHub issues and automated checks.

**Continuous cadence:** Every 2 hours for issue triage and health checks; daily for dependency/build review.

**Responsibilities:**

- Triage new GitHub issues.
- Reproduce bugs where possible.
- Label severity and affected component: `ios`, `mac`, `gateway`, `cloudflare`, `auth`, `remote-desktop`, `release`.
- Fix low-risk bugs directly.
- Run focused tests and full verification before PRs.
- Check gateway health, Cloudflare tunnel status, OTA endpoint status, and TestFlight build availability.

**Outputs:**

- GitHub issue comments with diagnosis.
- PRs for fixes.
- Release notes draft when fixes are user-visible.
- Ping only for outages, secrets, credentials, App Store blocks, or ambiguous product decisions.

## Agent 3: Release Agent

**Mission:** Keep TestFlight and OTA builds current and release-ready.

**Continuous cadence:** On merge to main, nightly, and before public announcements.

**Responsibilities:**

- Build Mac app and iOS app.
- Run OTA release when iOS files change.
- Upload TestFlight builds when requested or when a release milestone is ready.
- Track App Store Connect processing.
- Maintain screenshots, metadata, privacy labels, and release notes.
- Prevent bundle-id drift that creates a second app install.

**Outputs:**

- OTA build status.
- TestFlight build number and processing status.
- App Store metadata diff.
- Ping only for App Store credentials, legal/compliance forms, pricing, or submit-for-review approval.

## Agent 4: Presence Agent

**Mission:** Create and maintain CodePilot’s public presence.

**Continuous cadence:** Daily until launch site is complete, weekly afterward.

**Responsibilities:**

- Build GitHub Pages website.
- Maintain README, install guide, privacy policy, terms, changelog, FAQ, and troubleshooting.
- Generate App Store screenshots and marketing visuals.
- Keep public copy aligned with actual product capability.
- Ensure no personal names, tokens, private hosts, private emails, or private paths are present in public content.

**Outputs:**

- GitHub Pages updates.
- App Store screenshot sets.
- Public README/docs PRs.
- Ping only for final public positioning, pricing claims, privacy/legal approval, or brand decisions.

## Agent 5: Community Growth Agent

**Mission:** Promote CodePilot during TestFlight without spam or deceptive behavior.

**Continuous cadence:** Weekly research and draft queue; publish only after approval.

**Responsibilities:**

- Research relevant communities: Reddit, Hacker News, indie dev forums, Swift/iOS communities, AI coding communities, Mac automation communities.
- Draft posts tailored to each community’s rules.
- Track feedback and convert real product problems into GitHub issues.
- Maintain a transparent creator profile.

**Important constraint:** The agent can prepare the Reddit account plan, profile text, and posts, but Tony must create or approve any Reddit account and final posts. Creating accounts and posting must comply with Reddit rules and subreddit rules.

**Outputs:**

- Draft Reddit profile.
- Draft posts and comments.
- Subreddit rule summaries.
- Feedback summaries.
- Ping only for account creation, final post approval, controversial feedback, or paid promotion decisions.

## Agent 6: Revenue Agent

**Mission:** Move CodePilot toward subscription income with realistic conversion work.

**Continuous cadence:** Weekly.

**Responsibilities:**

- Maintain pricing hypotheses.
- Identify features required before charging.
- Track conversion funnel: install, setup success, active gateway, first successful turn, retained weekly use, subscription.
- Propose subscription tiers.
- Watch for support burden that would make passive income unrealistic.

**Outputs:**

- Pricing proposal docs.
- Funnel metrics dashboard issue/spec.
- Subscription readiness checklist.
- Ping for pricing, payment provider, legal/tax, refund policy, or App Store business model decisions.

## Agent 7: Security and Trust Agent

**Mission:** Keep remote access, auth refresh, gateway, uploads, and public distribution safe.

**Continuous cadence:** Weekly and before every public release.

**Responsibilities:**

- Scan for secrets and private data.
- Review public repo contents before push/release.
- Review Cloudflare setup and tunnel exposure.
- Review remote desktop permissions and auth gates.
- Verify file upload handling and localhost proxy restrictions.

**Outputs:**

- Security issues with severity.
- PRs for hardening.
- Release blockers if a high-risk issue is found.
- Immediate ping for secrets, remote access bypass, auth token exposure, or unsafe public endpoints.

## Initial Launch Sequence

1. **Stabilize public repo**
   - Security Agent scans all files.
   - Presence Agent removes private names, hosts, emails, paths, and screenshots.
   - Maintenance Agent ensures tests pass.

2. **Make setup shippable**
   - Setup Experience Agent audits Mac first-run setup.
   - Setup Experience Agent audits iOS first-run setup.
   - Release Agent verifies OTA and TestFlight update paths.

3. **Create public presence**
   - Presence Agent builds GitHub Pages.
   - Presence Agent prepares screenshots, README, install docs, FAQ, privacy policy, and support page.

4. **Prepare community launch**
   - Community Growth Agent drafts Reddit account profile and launch posts.
   - Tony approves account/posting strategy.
   - Agent schedules staged, rule-compliant posts.

5. **Start beta loop**
   - Maintenance Agent triages GitHub issues.
   - Release Agent ships TestFlight updates.
   - Setup Experience Agent reduces onboarding friction.
   - Revenue Agent tracks whether users reach paid-value moments.

6. **Prepare subscription launch**
   - Revenue Agent proposes tiers and pricing.
   - Presence Agent updates website and App Store copy.
   - Security Agent signs off on public release.
   - Tony approves pricing, legal, and App Store submission.

## Proposed Recurring Automations

### `codepilot-issue-triage`

- **Cadence:** Every 2 hours.
- **Task:** Check new GitHub issues, label them, reproduce when possible, and either open a fixing PR or comment with next steps.
- **Ping:** Only for production outages, credentials, or unclear product decisions.

### `codepilot-health-watch`

- **Cadence:** Hourly.
- **Task:** Check gateway health, Cloudflare tunnel reachability, OTA status, and latest TestFlight availability.
- **Ping:** Only if public install/update paths are broken or gateway is down.

### `codepilot-setup-audit`

- **Cadence:** Daily.
- **Task:** Walk through setup docs and app flows, identify friction, file issues, and fix low-risk copy or setup bugs.
- **Ping:** Only for credential or account actions.

### `codepilot-release-readiness`

- **Cadence:** Nightly and on demand before releases.
- **Task:** Run tests/builds, summarize release blockers, verify screenshots/metadata, prepare release notes.
- **Ping:** Only for App Store submission approval or compliance questions.

### `codepilot-presence-maintenance`

- **Cadence:** Weekly.
- **Task:** Keep GitHub Pages, README, docs, screenshots, FAQ, and changelog current.
- **Ping:** Only for public positioning or legal/privacy approval.

### `codepilot-community-drafts`

- **Cadence:** Weekly.
- **Task:** Research communities, draft transparent promotional posts, summarize feedback, and prepare approved posting queue.
- **Ping:** Always before posting publicly.

### `codepilot-security-scan`

- **Cadence:** Weekly and before public release.
- **Task:** Scan for secrets, private data, unsafe remote access, auth problems, and public repo leaks.
- **Ping:** Immediately for high-risk findings.

## First Decisions Needed From Tony

1. Confirm whether the public product name is final: `CodePilot`.
2. Confirm whether Reddit posting should use the `codepilotios` identity or a separate Reddit identity.
3. Confirm whether promotion may say “paid subscription planned” during TestFlight or should stay beta-focused.
4. Confirm the first target audience: indie iOS/Mac developers, AI coding users, remote Mac users, or existing Codex CLI users.
5. Confirm whether agents may create draft GitHub issues/PRs autonomously on `main` or must use branches.

## Success Metrics

- 90%+ of new users can complete Mac setup without support.
- iOS app connects to gateway and sends first prompt within 5 minutes after setup.
- No stale-auth or tunnel setup errors without actionable recovery text.
- TestFlight build is always current within 24 hours of a merged iOS fix.
- Public repo contains no private names, tokens, personal hosts, private screenshots, or local paths.
- Weekly community feedback produces actionable issues.
- Subscription readiness is reached only after setup success, support burden, and retention are measurable.

