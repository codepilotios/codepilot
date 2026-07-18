# Changelog

## Unreleased

### Public Beta Preparation

- Added GitHub Pages configuration and narrowed the generated site to user-facing beta documentation.
- Refined the Pages landing page with beta scope, security guidance, and install prerequisites.
- Added public-safe GitHub feature request and pull request templates for beta feedback and contribution review.
- Added public beta docs for GitHub Pages, FAQ, privacy, support, screenshots, and changelog.
- Added a public presence checklist for beta positioning, privacy review, support copy, and approval gates.
- Added a beta feedback guide for Codex CLI users that asks for reproducible setup details without private data.
- Clarified that CodePilot currently targets Codex CLI users and remains beta-focused.
- Documented the Mac, gateway, iPhone, Cloudflare, and troubleshooting paths from a public user perspective.
- Added a local TestFlight/App Store metadata draft for maintainer review before any App Store submission.
- Added guidance for keeping screenshots, logs, support requests, and public issues free of private names, hosts, tokens, and local paths.
- Removed a legacy personal bundle namespace from a tracked implementation plan and added an audit guard against reintroducing that identifier pattern.
- Kept iOS beta installation docs focused on user setup and moved App Store Connect maintainer checks to the release checklist.
- Aligned public-beta iPhone connection copy around Cloudflare Tunnel while LAN setup remains unsupported.
- Tightened beta issue templates and screenshot guidance so public reports ask for recovery context without broad log dumps or private desktop content.
- Aligned beta support and bug-report categories with promoted file upload, notification, and turn-control workflows, plus reporting for the gated Remote Desktop work.
- Clarified the current security-reporting limitation so beta users are not directed to share sensitive evidence publicly.
- Added launch checks for the live Pages URL, repository website field, and a private security-reporting channel.
- Clarified that Codex credentials remain on the Mac while Cloudflare processes gateway traffic and connection metadata for the user-owned tunnel.
- Aligned support, beta feedback, issue-template, and screenshot guidance with the promoted usage and connector/plugin status workflows.
- Removed Remote Desktop from public-beta promotion while its pairing and session-authorization enforcement remains a release blocker.
- Removed Remote Desktop from the default TestFlight beta description and aligned that metadata with the supported thread, usage, account, upload, turn-control, and notification workflows.
- Shortened the App Store promotional text and keyword draft to fit their submission field limits while preserving the Codex CLI beta positioning.
- Clarified that the Mac app builds from source while iPhone access still requires an approved beta build, without implying public TestFlight or App Store availability.
- Added direct privacy-safe bug and feature-request paths to the README, Pages landing page, FAQ, and support copy.
- Added concrete draft support and privacy URLs that remain gated on GitHub Pages enablement and maintainer verification.
- Added the missing repository checkout step and documented the supported macOS 13 and iOS 17 minimums for beta setup.
- Reframed Remote Desktop support categories as availability-guard reports so the gated feature is not presented as a supported beta workflow.
- Expanded the beta privacy draft to disclose Cloudflare data transit, notification and Live Activity payload contents, and the lack of automatic upload cleanup.
- Clarified that the local gateway does not make Codex workflows offline: prompts, conversation context, and selected attachments can still be processed by OpenAI, while Cloudflare and Apple process data only for the enabled tunnel and notification workflows.
- Added a consistent fictional-data capture brief and full-resolution acceptance checklist for the approved public beta screenshot set.
- Added a public beta data-flow map showing what stays on the Mac and what can be processed by Codex, OpenAI, Cloudflare, or Apple.
- Clarified that iPhone access depends on an awake, online Mac running the gateway and Cloudflare Tunnel, with no hosted relay or remote wake promise in the current beta.
- Added FAQ and installation guidance for upload retention and safe account switching during active turns.
- Clarified that notifications are optional, require gateway APNs configuration for background delivery, and use iOS controls separate from Live Activities.
- Removed implied future-provider promises from public copy and focused the App Store promotional draft on current Codex CLI beta workflows.
- Added beta-focused repository description guidance so the GitHub header matches the approved audience and release status.
- Documented the iPhone attachment count and size limits so beta users can recover from rejected uploads without sharing private files.
- Added notification and file-upload recovery checklists to the public iPhone, FAQ, and troubleshooting guidance.
- Aligned Fastlane's default privacy and marketing URLs with the canonical lowercase public repository path and the prepared GitHub Pages privacy page.
- Added a safe source-build update path that preserves active turns and separates Mac updates from approved iPhone beta distribution.
- Documented localhost link opening as a supported beta workflow, including its loopback-only gateway boundary, Cloudflare data flow, privacy guidance, and public-safe reporting and screenshot rules.
- Removed the FAQ's implied future-provider promise and stated that the current beta supports Codex CLI only.

### Recent Product Work

- Added per-account Codex usage reset timing and available reset-credit controls on Mac and iPhone.
- Added Cloudflare setup wizard docs and automation.
- Added gateway health, setup, and recovery guidance.
- Added Remote Desktop foundations, localhost URL opening, file preview, and gateway-backed iPhone control improvements. Remote Desktop remains gated from the supported public beta pending security verification.
