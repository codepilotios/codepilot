import XCTest
@testable import CodexAccountSwitcher

final class SetupStatusTests: XCTestCase {
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
}
