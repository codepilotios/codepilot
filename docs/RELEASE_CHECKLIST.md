# Release Checklist

- [ ] `swift test`
- [ ] `cd gateway && python3 -m unittest test_codex_phone_gateway test_remote_desktop_gateway`
- [ ] `xcodebuild -project ios/CodexPhone/CodexPhone.xcodeproj -scheme CodexPhone -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build`
- [ ] iOS test target compile or simulator tests
- [ ] `scripts/privacy-audit.sh`
- [ ] OTA build if iOS app files changed
- [ ] Public manifest and IPA return HTTP 200 from the OTA domain
- [ ] TestFlight upload if shipping a beta build
- [ ] Public docs checked for personal names, private email addresses, tokens, hostnames, Apple team IDs, and machine-specific paths
- [ ] `.superpowers/` scratch files are not committed
