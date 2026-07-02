# CodePilot Cloudflare Setup Wizard Design

## Goal

Make remote access setup in the Mac app smooth enough for public beta users who may not know Cloudflare Tunnel, launch agents, DNS routing, or gateway tokens. The app should explain what it is about to install or configure, ask for consent before making changes, automate the happy path, and leave the user with a verified iPhone connection URL.

## Scope

This design covers the Mac menu bar app and Mac-side helper scripts. It does not change the iOS app connection model, gateway authentication model, or Cloudflare account billing/domain setup. Users can either configure a permanent Cloudflare-managed hostname or create a temporary TryCloudflare URL for testing.

## Current State

CodePilot already has:

- A setup window with a Cloudflare row that only checks whether `cloudflared` exists.
- `scripts/install-phone-cloudflared-agent.sh`, which installs a LaunchAgent around `scripts/start-phone-cloudflared.sh`.
- `scripts/start-phone-cloudflared.sh`, which expects `~/.cloudflared/codex-phone-config.yaml`.
- Documentation in `docs/CLOUDFLARE_SETUP.md`.

The missing pieces are guided login, CLI installation, tunnel creation, DNS routing, config generation, public URL verification, and clear recovery actions.

## User Experience

The setup window gets a richer **Cloudflare Remote Access** section with one primary action: **Set Up Remote Access...**. That opens a guided sheet or window.

The wizard starts with a plain explanation:

- CodePilot Gateway runs locally on `127.0.0.1:18790`.
- Cloudflare Tunnel lets the iPhone reach that gateway away from the local network.
- The setup may install `cloudflared`, create a tunnel, create a DNS route, write a config file, and install a LaunchAgent.
- CodePilot does not open inbound ports. The tunnel creates outbound connections to Cloudflare.
- The gateway bearer token is still required by the iOS app.

Each step shows:

- What will happen.
- Why it is needed.
- The exact command category or file path, without exposing secrets.
- A visible success/failure state.
- A disclosure for raw output and log paths.

## Setup Paths

### Permanent Hostname

This is the recommended path for regular use.

Inputs:

- Public hostname, for example `codepilot.example.com`.
- Optional tunnel name, default `codepilot`.

Flow:

1. Ensure the local gateway token exists and gateway health is reachable.
2. Ensure `cloudflared` is installed.
3. Run `cloudflared tunnel login` in Terminal or a visible process so the user can sign in or create a Cloudflare account.
4. Create or reuse a named tunnel.
5. Write a config file at `~/.cloudflared/codepilot-config.yaml`.
6. Route DNS for the chosen hostname to the tunnel.
7. Install or update the LaunchAgent.
8. Verify local health and public health.
9. Show the iOS gateway URL and offer to copy it with the token.

If a tunnel or DNS route already exists, the wizard should detect that and offer to reuse it rather than creating duplicates.

### Temporary TryCloudflare

This path is for testing without a Cloudflare-managed domain.

Flow:

1. Ensure the gateway is running.
2. Ensure `cloudflared` is installed.
3. Start `cloudflared tunnel --url http://127.0.0.1:18790`.
4. Parse the generated `trycloudflare.com` URL.
5. Verify public health through the temporary URL.
6. Mark the result as temporary and not suitable for long-term iPhone setup.

TryCloudflare should not install the persistent LaunchAgent by default because the hostname is temporary.

## Installation Behavior

The app should detect prerequisites in this order:

1. Existing `cloudflared` on `PATH` or common Homebrew paths.
2. Homebrew at `/opt/homebrew/bin/brew` or `/usr/local/bin/brew`.
3. Missing Homebrew.

If `cloudflared` is missing and Homebrew is present, show an explanation and ask before running `brew install cloudflared`.

If Homebrew is missing, do not run a blind shell installer. Show why Homebrew is needed, link to Homebrew and Cloudflare installation docs, and let the user retry after installation.

## Files And Services

Use CodePilot naming for new artifacts while remaining compatible with the old script path during migration.

New preferred paths:

- Config: `~/.cloudflared/codepilot-config.yaml`
- Metadata: `~/.codex-account-switcher/cloudflare-setup.json`
- LaunchAgent label: `io.codepilot.phone-cloudflared`
- Logs:
  - `~/Library/Logs/codepilot-cloudflared.out.log`
  - `~/Library/Logs/codepilot-cloudflared.err.log`

The metadata file stores non-secret setup state:

- mode: `permanent` or `trycloudflare`
- hostname
- tunnel name
- tunnel id if available
- config path
- launch agent label
- last verified time

It must not store Cloudflare credentials, gateway tokens, account ids, or raw certificate contents.

## Script Design

Add a single setup script with subcommands, for example `scripts/setup-cloudflare-remote-access.sh`.

Suggested subcommands:

- `status`
- `install-cloudflared`
- `login`
- `configure-permanent --hostname <host> --tunnel-name <name>`
- `start-trycloudflare`
- `install-service`
- `restart-service`
- `verify --url <url>`

The Mac app calls these subcommands and streams compact output into the wizard. Scripts should be idempotent and safe to rerun.

## Error Handling

Errors should map to user-facing recovery text:

- `cloudflared` missing: install with Homebrew or open Cloudflare downloads.
- Homebrew missing: install Homebrew or use Cloudflare manual package.
- Not logged in: sign in or create a Cloudflare account in the browser opened by `cloudflared tunnel login`.
- Hostname not on Cloudflare: add the domain to Cloudflare first or use TryCloudflare.
- DNS route conflict: choose a different hostname or reuse existing route.
- Gateway down: restart gateway before configuring tunnel.
- Public verification failed: show local gateway status, tunnel service status, hostname, and last Cloudflare log lines.

Do not show generic “failed” without next steps.

## Security

- Keep the gateway bearer token required for all iOS calls.
- Do not write secrets to logs or setup metadata.
- Do not expose the gateway directly to the LAN or internet.
- Show that Cloudflare Tunnel is an outbound connection.
- Keep raw output behind a disclosure so ordinary users are not overwhelmed, but diagnostics are available.
- Reuse the existing “restart gateway when idle” safety model; Cloudflare setup should not interrupt active turns.

## Testing

Mac-side tests should cover:

- Setup status labels for Cloudflare states.
- Parsing `cloudflared` status output.
- Config generation for permanent tunnels.
- Metadata redaction and serialization.
- Error mapping from script exit codes to recovery copy.

Script tests should run with temporary HOME directories and stub `cloudflared`, `brew`, and `launchctl` executables so they do not touch the real machine.

Manual verification should cover:

- Existing `cloudflared` path.
- Missing `cloudflared` with Homebrew present.
- Missing Homebrew.
- Permanent hostname setup.
- TryCloudflare temporary URL.
- LaunchAgent restart.
- Public health verification.

## Documentation

Update:

- `docs/CLOUDFLARE_SETUP.md`: explain the new in-app flow first, manual commands second.
- `docs/INSTALL_MAC.md`: mention remote access setup from the Mac app.
- `docs/TROUBLESHOOTING.md`: include Cloudflare setup failures and recovery steps.

## Implementation Decisions

The implementation should prefer an in-app wizard over a terminal-only setup script. Terminal is still acceptable for `cloudflared tunnel login` because Cloudflare owns that browser-based sign-in flow.

The permanent setup path should be the default recommendation. TryCloudflare should be clearly labelled as temporary testing.
