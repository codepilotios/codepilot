# Setup Friction: Packaged App Cannot Open The CodePilot Cloudflare Guide

Labels: `setup`, `onboarding`, `cloudflare`, `mac`, `docs`

## Summary

The Mac setup window offers **Open Cloudflare Guide**, but the built app did not include `docs/CLOUDFLARE_SETUP.md`. When CodePilot runs from its packaged LaunchAgent working directory, the action cannot find the repository document and falls back to generic Cloudflare documentation.

## Reproduction

1. Build CodePilot with `scripts/build-app.sh`.
2. Start the packaged app outside the repository working directory.
3. Open **Setup CodePilot...**.
4. Choose **Open Cloudflare Guide**.

## Expected

The action should open CodePilot's setup guide, including the product-specific wizard steps, token handoff, and recovery copy.

## Actual Before The Audit Fix

The app bundle contained the setup scripts and gateway runtime, but not the CodePilot Cloudflare guide. The action searched only the process working directory before opening generic Cloudflare documentation.

## Local Fix

The `agent/setup-audit` branch bundles `CLOUDFLARE_SETUP.md` under the app resources and resolves that packaged copy before checking a source checkout or using the generic fallback.
