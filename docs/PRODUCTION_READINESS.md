# CodePilot Production Readiness Design

## Goal

Prepare CodePilot for a public beta where the Mac menu bar app, gateway, and iOS app can be installed, understood, troubleshot, and updated by users who are not familiar with the current local development setup.

The release target is **both in parallel**:

- **TestFlight-first iOS beta** for the phone app.
- **GitHub/source release** for the Mac app, gateway, docs, and build scripts.

The work should keep the current Codex-specific implementation working while making the public product feel provider-neutral enough for future Claude Code compatibility.

## Current State

The project is already functionally strong:

- SwiftPM tests pass for the Mac-side code.
- Gateway Python tests pass.
- iOS simulator build and tests pass.
- Privacy audit passes.
- OTA iOS builds are produced and verified.
- Recent features include WebRTC remote desktop, localhost URL opening through the gateway, preserved chat markup, usage status, account switching, notifications, plugin/connector visibility, file uploads, and turn steering.

The remaining gaps are productization gaps:

- First-run setup is still too script/path-oriented.
- Some visible copy still assumes the user understands Codex homes, bearer token files, launch agents, or Cloudflare routing.
- Error messages often expose raw technical failures instead of recovery steps.
- The Mac and iOS setup flows are not yet one coherent checklist.
- Distribution requirements are not fully documented for public beta users.
- Browser visual companion clicks from the phone did not reach the event log during planning and need reliability work or explicit fallback text.
- Remote Desktop must remain outside the supported public beta until device-pairing and session-authorization enforcement is complete and independently verified.

## Release Principles

1. **No magic without diagnostics.** If CodePilot tries to install, restart, or connect something, the UI must show what happened and what to do next.
2. **No secret leakage.** Tokens, auth file contents, private hostnames, personal names, and account identifiers must not appear in public docs, logs intended for support, or screenshots.
3. **Safe by default.** Gateway restart should still avoid active turns unless the user explicitly forces it. Localhost proxying must remain loopback-only and short-lived.
4. **Public copy first.** User-facing text should say CodePilot, Mac, iPhone, gateway, account, connector, and remote desktop. Internal Codex names are acceptable only where they describe real provider-specific requirements.
5. **One setup mental model.** Mac setup, iOS connection, Cloudflare, permissions, and notifications should all use the same checklist vocabulary: required, optional, ready, blocked, fix.

## Mac App Design

The Mac menu bar app should become the primary setup and operations console.

### Setup Checklist

The setup window should present clear rows with status, explanation, and action:

- Codex CLI installed.
- Codex signed in.
- CodePilot account profiles created.
- Gateway installed and running.
- Gateway token available.
- Cloudflare tunnel configured, if remote access is desired.
- Screen Recording permission granted, if Remote Desktop is used.
- Accessibility permission granted, if Remote Desktop control is used.
- APNs configured, if background turn notifications are desired.

Each row should have:

- A human status label such as `Ready`, `Missing`, `Needs restart`, `Blocked by active turn`, or `Optional`.
- A short explanation.
- One primary action button.
- An advanced details disclosure for paths, logs, commands, or raw script output.

### Menu Bar Copy

The menu bar should keep dense account/usage status, but menu items should use public product language:

- `Setup CodePilot...`
- `Open Gateway Status...`
- `Restart Gateway`
- `Restart Gateway When Idle`
- `Force Restart Gateway...`
- `Refresh Login...`
- `Remote Desktop...`

Force restart must be explicit because it can interrupt active phone turns.

### Gateway Operations

Gateway install/restart status should distinguish:

- Gateway not installed.
- Gateway stopped.
- Gateway running.
- Gateway running old code after a deferred restart.
- Restart deferred because an active turn is running.
- Port is occupied by an unknown process.

The Mac UI should avoid dumping raw shell output as the main result. Raw output can live behind details.

## iOS App Design

The iOS app should guide users from first launch to a verified connection without requiring them to understand token files.

### Connection Wizard

Replace the bare URL/token form with a wizard-like screen:

1. Choose connection type:
   - Same network/local URL.
   - Cloudflare/public URL.
2. Enter or paste gateway URL.
3. Enter or paste token.
4. Test connection.
5. Show verified account, gateway health, and next action.

The simple form can remain available as advanced setup.

### Main Screen

Improve empty and blocked states:

- No threads: explain that threads appear after connecting to a Mac gateway and loading Codex state.
- No accounts: explain how to add accounts from Mac or iPhone.
- No usage data: show that usage is still loading or auth may need refresh.
- Gateway offline: show exact recovery steps.
- Auth stale: show a refresh-login action.
- Account switched but app-server stale: show that new turns will use the active account after the running turn finishes or after gateway restart when idle.

### Error Messages

Map common gateway failures into actionable copy:

- `401/403`: token missing, wrong, or stale; show where to find/copy it.
- `502`: Cloudflare reached the hostname but the Mac gateway is unavailable.
- Network lost: distinguish transient network loss from gateway stopped.
- Stale auth: offer refresh login.
- Active-turn restart deferral: explain that CodePilot is protecting a running turn.
- Missing job/thread: reload saved messages and explain the live stream was lost.

### Localhost URL Opening

The newly added localhost feature should be treated as a production feature:

- Links to `localhost`, `127.0.0.1`, and `::1` should open through the Mac gateway in an in-app browser.
- Non-local links should open normally.
- The app should explain errors such as `local service unavailable`, `session expired`, or `response too large`.

## Gateway Design

The gateway remains a local trusted bridge between iOS and the Mac.

### Health Endpoint

Expose structured health without secrets:

- Gateway version/build time.
- Active account name.
- App-server auth sync status.
- Whether active phone turns are running.
- Notification configuration present/missing.
- Remote Desktop host status.
- Localhost proxy availability.
- Cloudflare-visible base URL, if configured, without exposing tokens.

### Error Model

Add or normalize error codes alongside readable messages:

- `unauthorized`
- `gateway_unavailable`
- `app_server_unavailable`
- `active_turn_running`
- `auth_stale`
- `account_unavailable`
- `thread_not_found`
- `job_not_found`
- `local_web_invalid_target`
- `local_web_unavailable`
- `remote_desktop_permission_missing`

iOS and Mac can then map errors to stable recovery text without parsing arbitrary strings.

### Localhost Proxy Boundary

The local-web proxy must stay constrained:

- Only `http` and `https`.
- Only loopback hosts.
- Short-lived random session IDs.
- Bounded response size.
- No bearer token in proxied page URLs.
- Root-relative links rewritten through the session path.

## Distribution Design

### TestFlight

The iOS release should include:

- Correct bundle identity for updating the existing installed app.
- Current display name `CodePilot`.
- Beta notes explaining gateway requirement.
- Privacy text describing local gateway, uploads, notifications, and remote desktop.
- Internal tester/audience configuration.
- A repeatable build/upload path using existing Fastlane or asc tooling.

### GitHub/Source Release

The public repository should include:

- README that explains what CodePilot is, current Codex support, and future provider-neutral intent.
- Mac install guide.
- iOS install guide.
- Cloudflare setup guide.
- Security and privacy guide.
- License/NOTICE/commercial terms.
- Troubleshooting guide.
- Release checklist.

Public docs should not contain personal hostnames, personal account names, private email addresses, private Apple team IDs, tokens, or machine-specific paths except generic examples under `~`.

## Visual Companion Reliability

During planning, browser clicks from the phone did not create an `events` file in the companion state directory. This should be tracked as release-prep tooling work because the visual companion is being used to make product decisions.

Required behavior:

- A click visibly changes the selected option in the browser.
- The server records the click in `state/events`.
- The page shows “selection received” after the event is acknowledged.
- Each visual page includes fallback text telling the user to reply in chat if selection does not register.

Until fixed, terminal replies remain the source of truth.

## Testing And Verification

Every implementation pass should run:

- `swift test`
- `python3 -m unittest test_codex_phone_gateway test_remote_desktop_gateway` from `gateway/`
- `xcodebuild -project ios/CodexPhone/CodexPhone.xcodeproj -scheme CodexPhone -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build`
- iOS unit tests on the configured simulator
- `scripts/privacy-audit.sh`
- OTA build if any iOS app files changed

Manual checks:

- Fresh Mac app setup window with missing dependencies.
- Gateway restart when idle.
- Gateway restart deferred while a turn is running.
- Force restart warning path.
- Fresh iOS connection wizard.
- Cloudflare 502 messaging.
- Stale auth refresh path.
- Localhost URL opening through the gateway.

## Non-Goals For This Pass

- Full Claude Code compatibility.
- A paid licensing backend.
- A fully hosted cloud service.
- Replacing the current Codex app-server integration.
- Rewriting the whole iOS app architecture.

## Open Decisions

1. Whether Mac public distribution is initially source-build only or signed/notarized binary as well.
2. Whether TestFlight release notes should call the app beta/private preview or public beta.
3. Whether Cloudflare setup should remain guide-driven or become a guided Mac setup flow using `cloudflared`.
