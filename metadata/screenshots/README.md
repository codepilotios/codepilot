# App Store Screenshot Checklist

No App Store-ready screenshots are currently present in the repository.

The minimum practical submission set is 1–10 screenshots for the 6.9-inch iPhone display. Use an accepted portrait canvas such as 1320×2868, 1290×2796, or 1260×2736 pixels. Export PNG or JPEG files without alpha or transparency. No iPad set is required for the current iPhone-only target.

Use one fictional workspace across the set:

- Account names: `Work`, `Personal`, and `Demo`.
- Gateway hostname: `codepilot.example.com`.
- Thread names: `Review parser tests`, `Improve setup copy`, and `Triage upload error`.
- Sample files: `sample-diff.txt` and `wireframe.png`, created only for capture.

Prepare approved screenshots for:

- First connection screen with the Cloudflare connection choice.
- Gateway health or setup status after a successful connection.
- Total-credit status with synthetic account names and balances.
- Total Credit Live Activity on a supported Lock Screen or Dynamic Island.
- Thread list or active turn view.
- File upload confirmation using a non-sensitive sample file, without showing a local path.
- Purpose-built loopback demo page opened through the gateway, without showing its URL, source code, logs, paths, or query values.
- Error recovery state with non-sensitive copy.

Do not include Remote Desktop in the 0.1 screenshot set while its paired-device and session-authorization protections remain release-blocked.

Capture only the app or simulator window. Exclude desktop content, unrelated menu bar items, browser history, other-app notifications, device names, and unrelated windows. Inspect every full-resolution export, including status bars and window edges.

All screenshots must avoid real tokens, private hostnames, private account names, private file paths, private emails, Apple or signing identifiers, repository names, private prompts, uploaded files, connected personal services, and personal identifiers. Run `scripts/privacy-audit.sh` before committing any image or screenshot metadata.
