# Cloudflare Setup

Cloudflare Tunnel is the recommended way to reach the CodePilot gateway from outside the Mac's local network.

## Recommended: In-App Setup

Open **CodePilot > Setup CodePilot... > Cloudflare Remote Access > Set Up Remote Access...**.

The wizard explains and can configure:

- `cloudflared`, Cloudflare's local tunnel daemon.
- A Cloudflare sign-in or account creation step.
- A permanent hostname such as `codepilot.example.com`.
- A temporary TryCloudflare URL for testing without a domain.
- A macOS LaunchAgent that keeps the tunnel running.

CodePilot does not open inbound ports. Cloudflare Tunnel makes outbound connections to Cloudflare. The iPhone app still needs the CodePilot gateway token.

## Permanent Hostname

Choose this for regular use. You need a Cloudflare account and a domain managed by Cloudflare.

The wizard creates or reuses a tunnel, writes:

```text
~/.cloudflared/codepilot-config.yaml
```

and installs:

```text
~/Library/LaunchAgents/io.codepilot.phone-cloudflared.plist
```

## Temporary TryCloudflare

Choose this only for testing. Cloudflare creates a temporary `trycloudflare.com` URL. It can change and should not be treated as a permanent iPhone setup URL.

## Manual Fallback

Run:

```sh
scripts/setup-cloudflare-remote-access.sh status
scripts/setup-cloudflare-remote-access.sh install-cloudflared
scripts/setup-cloudflare-remote-access.sh login
scripts/setup-cloudflare-remote-access.sh configure-permanent --hostname codepilot.example.com --tunnel-name codepilot
scripts/setup-cloudflare-remote-access.sh install-service
scripts/setup-cloudflare-remote-access.sh verify --url https://codepilot.example.com
```

## Troubleshooting

- **Homebrew missing**: install Homebrew or install `cloudflared` manually from Cloudflare.
- **Hostname not on Cloudflare**: add the domain to Cloudflare first or use TryCloudflare.
- **502 from Cloudflare**: start the CodePilot gateway and restart the Cloudflare tunnel.
- **401/403**: copy the current gateway token from the Mac app into the iPhone app.
- **Works locally but not remotely**: check the Cloudflare LaunchAgent logs in `~/Library/Logs/`.
