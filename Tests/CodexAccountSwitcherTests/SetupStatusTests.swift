import XCTest
@testable import CodexAccountSwitcher

final class SetupStatusTests: XCTestCase {
    func testExecutableDetectionChecksUserInstallLocationsWhenPATHIsRestricted() throws {
        let temporaryHome = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let executable = temporaryHome.appendingPathComponent(".local/bin/codex")
        try FileManager.default.createDirectory(
            at: executable.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("#!/bin/sh\n".utf8).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        defer { try? FileManager.default.removeItem(at: temporaryHome) }

        XCTAssertEqual(
            CodePilotSetupStatus.executablePath(
                named: "codex",
                environment: ["PATH": "/usr/bin:/bin"],
                home: temporaryHome
            ),
            executable.path
        )
    }

    func testExecutableDetectionRejectsNonExecutableFiles() throws {
        let temporaryHome = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let candidate = temporaryHome.appendingPathComponent(".local/bin/codex")
        try FileManager.default.createDirectory(
            at: candidate.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not executable\n".utf8).write(to: candidate)
        defer { try? FileManager.default.removeItem(at: temporaryHome) }

        XCTAssertNil(CodePilotSetupStatus.executablePath(
            named: "codex",
            environment: ["PATH": ""],
            home: temporaryHome
        ))
    }

    func testSetupStatusLabelsAreUserFacing() {
        XCTAssertEqual(CodePilotSetupRequirement.gatewayStopped.statusLabel, "Stopped")
        XCTAssertEqual(CodePilotSetupRequirement.gatewayBlockedByActiveTurn.statusLabel, "Blocked by active turn")
        XCTAssertEqual(CodePilotSetupRequirement.cloudflareOptional.statusLabel, "Optional")
        XCTAssertEqual(CodePilotSetupRequirement.screenRecordingReady.statusLabel, "Ready")
        XCTAssertEqual(CodePilotSetupRequirement.screenRecordingMissing.statusLabel, "Missing")
        XCTAssertEqual(CodePilotSetupRequirement.accessibilityReady.statusLabel, "Ready")
        XCTAssertEqual(CodePilotSetupRequirement.accessibilityMissing.statusLabel, "Missing")
        XCTAssertEqual(CodePilotSetupRequirement.notificationsOptional.statusLabel, "Optional")
    }

    func testCloudflareStatusLabelsAreUserFacing() {
        XCTAssertEqual(CodePilotSetupRequirement.cloudflareReady.statusLabel, "Ready")
        XCTAssertEqual(CodePilotSetupRequirement.cloudflareMissing.statusLabel, "Missing")
        XCTAssertEqual(CodePilotSetupRequirement.cloudflareNeedsConfiguration.statusLabel, "Needs setup")
        XCTAssertEqual(CodePilotSetupRequirement.cloudflareOptional.statusLabel, "Optional")
    }

    func testCloudflareMissingToolCopyDoesNotReadAsRequiredFailure() {
        let row = CodePilotSetupRow(
            title: "Cloudflare",
            requirement: .cloudflareOptional,
            detail: "Optional for remote iPhone access; install cloudflared to use Cloudflare."
        )

        XCTAssertEqual(row.requirement.statusLabel, "Optional")
        XCTAssertTrue(row.detail.contains("remote iPhone access"))
    }

    func testGatewayHealthProbeUsesPublicHealthWithoutBearerToken() {
        let request = CodePilotGatewayHealthProbe.request()
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))

        let runningPayload = #"{"gateway":{"running":true}}"#.data(using: .utf8)
        XCTAssertEqual(CodePilotGatewayHealthProbe.requirement(from: runningPayload), .gatewayRunning)

        let stoppedPayload = #"{"gateway":{"running":false}}"#.data(using: .utf8)
        XCTAssertEqual(CodePilotGatewayHealthProbe.requirement(from: stoppedPayload), .gatewayStopped)
        XCTAssertEqual(CodePilotGatewayHealthProbe.requirement(from: Data("not json".utf8)), .gatewayStopped)
    }

    func testGatewayHealthDetailGivesRecoveryActionWhenStopped() {
        XCTAssertEqual(
            CodePilotSetupStatus.gatewayHealthDetail(for: .gatewayStopped),
            "Start or restart the gateway from the setup window"
        )
        XCTAssertEqual(
            CodePilotSetupStatus.gatewayHealthDetail(for: .gatewayRunning),
            "Reachable on 127.0.0.1:18790"
        )
    }

    func testPrimaryAccountSetupCopyUsesRecoveryActionsInsteadOfPaths() {
        XCTAssertEqual(CodePilotSetupStatus.codexCLIDetail(installed: true), "Installed")
        XCTAssertEqual(CodePilotSetupStatus.codexCLIDetail(installed: false), "Install Codex, then refresh status")
        XCTAssertEqual(CodePilotSetupStatus.codexLoginDetail(signedIn: true), "Signed in")
        XCTAssertEqual(CodePilotSetupStatus.codexLoginDetail(signedIn: false), "Sign in to Codex, then refresh status")
        XCTAssertEqual(CodePilotSetupStatus.accountProfilesDetail(count: 0), "Create an account profile from the CodePilot menu")
        XCTAssertEqual(CodePilotSetupStatus.accountProfilesDetail(count: 1), "1 profile")
        XCTAssertEqual(CodePilotSetupStatus.accountProfilesDetail(count: 2), "2 profiles")
    }

    func testGatewayTokenMustContainANonWhitespaceValue() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let tokenPath = temporaryDirectory.appendingPathComponent("phone-gateway-token")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        XCTAssertEqual(CodePilotSetupStatus.gatewayTokenRequirement(at: tokenPath), .gatewayTokenMissing)

        try Data("\n  \t".utf8).write(to: tokenPath)
        XCTAssertEqual(CodePilotSetupStatus.gatewayTokenRequirement(at: tokenPath), .gatewayTokenMissing)

        try Data("test-token\n".utf8).write(to: tokenPath)
        XCTAssertEqual(CodePilotSetupStatus.gatewayTokenRequirement(at: tokenPath), .gatewayTokenPresent)
        XCTAssertEqual(
            CodePilotSetupStatus.gatewayTokenDetail(for: .gatewayTokenMissing),
            "Start or restart the gateway to create it"
        )
    }
}
