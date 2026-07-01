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
            configPath: "/Users/test/.cloudflared/codepilot-config.yaml",
            launchAgentLabel: "io.codepilot.phone-cloudflared",
            lastVerifiedAt: nil
        )

        let summary = metadata.safeSummary
        XCTAssertTrue(summary.contains("codepilot.example.com"))
        XCTAssertFalse(summary.localizedCaseInsensitiveContains("token"))
        XCTAssertFalse(summary.localizedCaseInsensitiveContains("credential"))
    }

    func testCloudflareScriptErrorMapsToRecoveryCopy() {
        XCTAssertEqual(
            CodePilotCloudflareErrorMapper.message(forExitCode: 20),
            "Homebrew is missing. Install Homebrew or use Cloudflare's manual cloudflared installer, then retry."
        )
        XCTAssertEqual(
            CodePilotCloudflareErrorMapper.message(forExitCode: 21),
            "cloudflared is missing. Install it from the Cloudflare setup step before continuing."
        )
    }

    func testTryCloudflareTerminalCommandUsesLongRunningSubcommand() {
        let command = CodePilotTryCloudflareCommand.terminalCommand(
            scriptPath: "/tmp/Code Pilot/scripts/setup-cloudflare-remote-access.sh",
            currentDirectory: "/tmp/Code Pilot"
        )

        XCTAssertTrue(command.contains("cd '/tmp/Code Pilot'"))
        XCTAssertTrue(command.contains("'/tmp/Code Pilot/scripts/setup-cloudflare-remote-access.sh' start-trycloudflare"))
    }
}
