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
}
