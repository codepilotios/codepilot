import XCTest
@testable import CodexAccountSwitcher

final class CloudflareSetupTests: XCTestCase {
    func testCloudflareStatusLabelsAreSpecific() {
        XCTAssertEqual(CodePilotSetupRequirement.cloudflareMissing.statusLabel, "Missing")
        XCTAssertEqual(CodePilotSetupRequirement.cloudflareNeedsConfiguration.statusLabel, "Needs setup")
        XCTAssertEqual(CodePilotSetupRequirement.cloudflareReady.statusLabel, "Ready")
    }

    func testCloudflareMetadataDoesNotExposeSecrets() throws {
        let metadata = CodePilotCloudflareMetadata(
            mode: "permanent",
            hostname: "codepilot.example.com",
            tunnelName: "codepilot",
            tunnelId: "tun_123",
            configPath: "/tmp/codepilot-test/.cloudflared/codepilot-config.yaml",
            launchAgentLabel: "io.codepilot.phone-cloudflared",
            lastVerifiedAt: nil
        )

        let summary = metadata.safeSummary
        XCTAssertTrue(summary.contains("codepilot.example.com"))
        XCTAssertFalse(summary.localizedCaseInsensitiveContains("token"))
        XCTAssertFalse(summary.localizedCaseInsensitiveContains("credential"))
        XCTAssertEqual(metadata.remoteAccessURL?.absoluteString, "https://codepilot.example.com")
    }

    func testTemporaryCloudflareMetadataDoesNotOfferStableRemoteAccessURL() {
        let metadata = CodePilotCloudflareMetadata(
            mode: "temporary",
            hostname: "temporary.example.com",
            tunnelName: "codepilot",
            tunnelId: "",
            configPath: "",
            launchAgentLabel: "",
            lastVerifiedAt: nil
        )

        XCTAssertNil(metadata.remoteAccessURL)
    }

    func testCloudflareMetadataRequiresSuccessfulVerificationForReadyState() {
        let unverified = CodePilotCloudflareMetadata(
            mode: "permanent",
            hostname: "codepilot.example.com",
            tunnelName: "codepilot",
            tunnelId: "tun_123",
            configPath: "/tmp/codepilot-config.yaml",
            launchAgentLabel: "io.codepilot.phone-cloudflared",
            lastVerifiedAt: nil
        )
        let verified = CodePilotCloudflareMetadata(
            mode: "permanent",
            hostname: "codepilot.example.com",
            tunnelName: "codepilot",
            tunnelId: "tun_123",
            configPath: "/tmp/codepilot-config.yaml",
            launchAgentLabel: "io.codepilot.phone-cloudflared",
            lastVerifiedAt: "2026-07-17T12:00:00+00:00"
        )

        XCTAssertFalse(unverified.isVerified)
        XCTAssertNil(unverified.verifiedRemoteAccessURL)
        XCTAssertTrue(verified.isVerified)
        XCTAssertEqual(verified.verifiedRemoteAccessURL?.absoluteString, "https://codepilot.example.com")
    }

    func testCloudflareScriptErrorMapsToRecoveryCopy() {
        XCTAssertEqual(
            CodePilotCloudflareErrorMapper.message(forExitCode: 2),
            "Check the hostname and tunnel name. Use a DNS hostname such as codepilot.example.com without https:// or a path, then retry."
        )
        XCTAssertEqual(
            CodePilotCloudflareErrorMapper.message(forExitCode: 20),
            "Homebrew is missing. Install Homebrew or use Cloudflare's manual cloudflared installer, then retry."
        )
        XCTAssertEqual(
            CodePilotCloudflareErrorMapper.message(forExitCode: 21),
            "cloudflared is missing. Install it from the Cloudflare setup step before continuing."
        )
        XCTAssertEqual(
            CodePilotCloudflareErrorMapper.message(forExitCode: 22),
            "Cloudflare did not create a new tunnel. Confirm you are signed in, choose an unused tunnel name, then retry."
        )
        XCTAssertEqual(
            CodePilotCloudflareErrorMapper.message(forExitCode: 23),
            "The remote URL did not report a running CodePilot gateway. Start or restart the gateway and tunnel, then retry verification."
        )
        XCTAssertEqual(
            CodePilotCloudflareErrorMapper.message(forExitCode: 24),
            "Could not reach the remote URL within 15 seconds. Confirm the Mac gateway and Cloudflare tunnel are running, then retry."
        )
    }
}
