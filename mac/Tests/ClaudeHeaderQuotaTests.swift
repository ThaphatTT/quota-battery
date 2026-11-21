import XCTest

final class ClaudeHeaderQuotaTests: XCTestCase {
    func testHeaderGapAndVerticalCenterFollowSessionRail() {
        for rail in [CGRect(x: 900, y: 20, width: 28, height: 28),
                     CGRect(x: 2100, y: -40, width: 28, height: 28)] {
            let ring = ClaudeHeaderQuota.frame(beside: rail)
            XCTAssertEqual(ring.midY, rail.midY)
            XCTAssertEqual(rail.minX - ring.maxX, 5)
        }
    }

    func testNewSessionHasAHeaderSlotWithoutARailAndClearsExistingButtons() throws {
        let window = CGRect(x: 100, y: 200, width: 900, height: 600)
        let empty = try XCTUnwrap(ClaudeHeaderQuota.newSessionFrame(in: window, avoiding: []))
        XCTAssertEqual(empty.maxX, window.maxX - 12)
        XCTAssertEqual(empty.midY, window.minY + 24)

        let button = CGRect(x: 950, y: 209, width: 28, height: 28)
        let shifted = try XCTUnwrap(ClaudeHeaderQuota.newSessionFrame(in: window, avoiding: [button]))
        XCTAssertEqual(shifted.maxX, button.minX - ClaudeHeaderQuota.railGap)
        XCTAssertEqual(shifted.midY, empty.midY)
        XCTAssertFalse(shifted.intersects(button))
        XCTAssertNil(ClaudeHeaderQuota.newSessionFrame(
            in: window, avoiding: [CGRect(x: 860, y: 200, width: 128, height: 42)]
        ))
    }

    func testOnlyNewSessionRoutesQualifyForTheFallback() throws {
        for route in ["https://claude.ai/new?surface=chat", "https://claude.ai/code/", "claude://code/new?source=desktop_action"] {
            XCTAssertTrue(ClaudeHeaderQuota.isNewSessionURL(try XCTUnwrap(URL(string: route))))
        }
        for route in ["https://claude.ai/chat/existing", "https://claude.ai/code/project/existing", "https://example.com/new"] {
            XCTAssertFalse(ClaudeHeaderQuota.isNewSessionURL(try XCTUnwrap(URL(string: route))))
        }
    }

    func testRailAnchorClearsNeighborWithoutLeavingItsHeaderRow() throws {
        let window = CGRect(x: 100, y: 200, width: 900, height: 600)
        let rail = CGRect(x: 940, y: 210, width: 28, height: 28)
        let neighbor = CGRect(x: 887, y: 210, width: 42, height: 28)
        let ideal = ClaudeHeaderQuota.frame(beside: rail)
        let shifted = try XCTUnwrap(ClaudeHeaderQuota.clearingControls(from: ideal, in: window, avoiding: [neighbor]))
        XCTAssertEqual(shifted.maxX, neighbor.minX - ClaudeHeaderQuota.railGap)
        XCTAssertEqual(shifted.midY, rail.midY)
        XCTAssertFalse(shifted.intersects(neighbor))
    }

}
