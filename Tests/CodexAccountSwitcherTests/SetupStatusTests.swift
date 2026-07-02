import XCTest
@testable import CodexAccountSwitcher

final class SetupStatusTests: XCTestCase {
    func testSetupStatusLabelsAreUserFacing() {
        XCTAssertEqual(CodePilotSetupRequirement.gatewayStopped.statusLabel, "Stopped")
        XCTAssertEqual(CodePilotSetupRequirement.gatewayBlockedByActiveTurn.statusLabel, "Blocked by active turn")
        XCTAssertEqual(CodePilotSetupRequirement.cloudflareOptional.statusLabel, "Optional")
    }

    func testCloudflareStatusLabelsAreUserFacing() {
        XCTAssertEqual(CodePilotSetupRequirement.cloudflareReady.statusLabel, "Ready")
        XCTAssertEqual(CodePilotSetupRequirement.cloudflareMissing.statusLabel, "Missing")
        XCTAssertEqual(CodePilotSetupRequirement.cloudflareNeedsConfiguration.statusLabel, "Needs setup")
        XCTAssertEqual(CodePilotSetupRequirement.cloudflareOptional.statusLabel, "Optional")
    }
}
