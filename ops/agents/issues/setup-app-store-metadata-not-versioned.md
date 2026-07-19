# Setup Friction: App Store Metadata Is Not Versioned Locally

Labels: `setup`, `ios`, `release`, `docs`

## Summary

The repository contains Fastlane build and TestFlight lanes plus maintainer setup notes, but it has no canonical local metadata tree for App Store Connect or TestFlight. Launch copy and review requirements therefore cannot be reviewed, privacy-audited, localized, or diffed before a maintainer performs an approved store action.

## Reproduction

1. Review `ios/CodexPhone/fastlane` and the iOS release documentation.
2. Look for versioned App Store descriptions, subtitle, keywords, support and privacy URLs, review notes, TestFlight **What to Test** copy, and screenshot metadata.
3. Observe that no canonical metadata files exist.

## Expected

Store-facing copy should live in a versioned local metadata directory with placeholders clearly separated from maintainer-approved URLs, privacy/legal text, screenshots, and release-specific notes. Upload and submission must remain separate, explicitly approved actions.

## Actual

The Fastlane lanes use a generic changelog fallback, and the repository has no reviewable metadata source of truth. The App Store Connect setup guide says metadata should be prepared locally but does not define its location or required fields.

## Suggested Fix

Add a local metadata template and validation command that checks required locales and fields without authenticating to App Store Connect. Populate product claims, privacy/support URLs, review notes, and screenshots only after maintainer approval. Keep upload, external TestFlight distribution, pricing, legal metadata, and review submission outside unattended setup audits.

## Audit Constraint

This unattended audit did not invent public claims or legal/privacy URLs and did not contact or mutate App Store Connect.
