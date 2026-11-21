import XCTest

final class CodexUsageRingPlacementTests: XCTestCase {
    func testRingCentersAboveNativeUsageControl() {
        let window = CGRect(x: 100, y: 40, width: 900, height: 600)
        let usage = CGRect(x: 112, y: 560, width: 28, height: 28)
        let result = CodexUsageRingPlacement.frame(in: window, usage: usage, profile: nil)
        XCTAssertEqual(result?.midX, usage.midX)
        XCTAssertEqual(result?.maxY, usage.minY - 6)
    }

    func testCompactRailFallbackTracksTheWindow() {
        let window = CGRect(x: -200, y: 30, width: 400, height: 500)
        let avatar = CGRect(x: -186, y: 496, width: 24, height: 24)
        let profileFrame = CodexUsageRingPlacement.frame(in: window, usage: nil, profile: avatar)
        XCTAssertEqual(profileFrame, CodexUsageRingPlacement.frame(in: window, usage: nil, profile: nil))
        XCTAssertEqual(profileFrame, CGRect(x: -196, y: 398, width: 44, height: 48))
    }

    func testRejectsControlsOutsideTheLeftRailAndSmallWindows() {
        let window = CGRect(x: 100, y: 40, width: 900, height: 600)
        let unrelatedUsage = CGRect(x: 875, y: 560, width: 28, height: 28)
        XCTAssertNil(CodexUsageRingPlacement.frame(in: window, usage: unrelatedUsage, profile: nil))
        XCTAssertNil(CodexUsageRingPlacement.frame(in: CGRect(x: 0, y: 0, width: 100, height: 100), usage: nil, profile: nil))
    }
}
