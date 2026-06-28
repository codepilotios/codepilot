# Cloudflare Setup

Cloudflare Tunnel is the recommended way to reach the CodePilot gateway from outside the Mac's local network.

## Requirements

- A Cloudflare account.
- A domain or subdomain managed by Cloudflare.
- `cloudflared` installed on the Mac.

## Local Gateway

The gateway listens locally on:

```text
http://127.0.0.1:18790
```

Never expose the gateway without the bearer token check.

## Tunnel

The helper script expects a Cloudflare tunnel config that forwards a public hostname to the local gateway.

```sh
scripts/install-phone-cloudflared-agent.sh
```

The public hostname should be entered as the iOS gateway URL.

Success means the iOS app can test the connection from cellular data or another network and shows the active account from the Mac gateway.

## Troubleshooting

- **502 from Cloudflare**: gateway is not running or tunnel cannot reach `127.0.0.1:18790`.
- **401/403**: token is missing or incorrect.
- **Connection lost**: check tunnel health and gateway LaunchAgent logs.
- **Works locally but not remotely**: verify Cloudflare hostname routing and Access policies.
- **Gateway works locally but Cloudflare is stale**: restart the Cloudflare LaunchAgent after changing tunnel configuration.
