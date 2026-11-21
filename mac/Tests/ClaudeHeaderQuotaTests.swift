import XCTest

final class ClaudeHeaderQuotaTests: XCTestCase {
    private let primary = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    func testPlacementMatrixKeepsTheRailAnchorOnEachWindowAndDisplay() throws {
        let fixtures: [(name: String, window: CGRect, display: CGRect)] = [
            ("regular", CGRect(x: 90, y: 100, width: 1100, height: 760), primary),
            ("narrow", CGRect(x: 900, y: 70, width: 390, height: 600), primary),
            ("full screen", CGRect(x: 0, y: 0, width: 1920, height: 1080), primary),
            ("right display", CGRect(x: 2100, y: 110, width: 900, height: 620),
             CGRect(x: 1920, y: -68, width: 1710, height: 1107)),
            ("left display", CGRect(x: -1500, y: 110, width: 920, height: 620),
             CGRect(x: -1600, y: 120, width: 1600, height: 900)),
            ("above primary", CGRect(x: 200, y: -998, width: 960, height: 700),
             CGRect(x: 0, y: 1080, width: 1920, height: 1080)),
            ("below primary", CGRect(x: 250, y: 1120, width: 980, height: 660),
             CGRect(x: 0, y: -900, width: 1600, height: 900))
        ]

        for fixture in fixtures {
            let window = fixture.window
            let screens = [primary, fixture.display]
            let rail = CGRect(x: window.maxX - 33, y: window.minY + 9.5, width: 27.5, height: 28)
            let expected = CGRect(x: rail.minX - 73, y: rail.midY - 18, width: 68, height: 36)
            let neighboringControl = CGRect(x: expected.minX + 16, y: rail.minY, width: 28, height: 28)
            var layout = ClaudeHeaderQuota.Layout()
            let scenarios: [(name: String, rail: CGRect?, newSession: Bool, controls: [CGRect], anchor: ClaudeHeaderQuota.Placement.Anchor?)] = [
                ("existing session", rail, false, [rail], .sessionRail),
                ("new session with rail", rail, true, [rail], .sessionRail),
                ("new session before rail mounts", nil, true, [], .newSessionSlot),
                ("rail returns", rail, false, [rail], .sessionRail),
                ("blocked slot", rail, false, [neighboringControl], nil),
                ("ordinary screen with no verified rail", nil, false, [], nil)
            ]

            for scenario in scenarios {
                let label = "\(fixture.name) / \(scenario.name)"
                let result = layout.placement(windowID: 1, window: window, rail: scenario.rail,
                                              isNewSession: scenario.newSession, controls: scenario.controls)
                XCTAssertEqual(result?.anchor, scenario.anchor, label)
                guard scenario.anchor != nil else { continue }
                let position = try XCTUnwrap(result, label)
                XCTAssertEqual(position.frame, expected, label)
                XCTAssertEqual(rail.minX - position.frame.maxX, 5, label)
                XCTAssertEqual(position.frame.midY, rail.midY, label)
                let actual = try XCTUnwrap(QuotaOverlayAnchor.screenFrame(for: position.frame, screens: screens), label)
                XCTAssertEqual(actual.midY, primary.maxY - rail.midY, label)
                XCTAssertTrue(fixture.display.contains(actual), label)
            }
        }
    }

    func testNewSessionUsesSameWindowOffsetsAfterMoveAndResize() throws {
        var layout = ClaudeHeaderQuota.Layout()
        let window = CGRect(x: 100, y: 200, width: 900, height: 600)
        let rail = CGRect(x: 950, y: 208, width: 32, height: 26)
        let regular = try XCTUnwrap(layout.placement(windowID: 1, window: window, rail: rail,
                                                    isNewSession: false, controls: []))
        let moved = CGRect(x: 2100, y: 350, width: 640, height: 600)
        let fresh = try XCTUnwrap(layout.placement(windowID: 1, window: moved, rail: nil,
                                                  isNewSession: true, controls: []))
        XCTAssertEqual(moved.maxX - fresh.frame.maxX, window.maxX - regular.frame.maxX)
        XCTAssertEqual(fresh.frame.midY - moved.minY, regular.frame.midY - window.minY)

        let separate = try XCTUnwrap(layout.placement(windowID: 2, window: moved, rail: nil,
                                                      isNewSession: true, controls: []))
        XCTAssertEqual(moved.maxX - separate.frame.maxX, 45)
        XCTAssertEqual(separate.frame.midY - moved.minY, 24)
        XCTAssertNil(layout.placement(windowID: 2, window: moved, rail: nil,
                                      isNewSession: true, controls: [separate.frame]))
    }

    func testGateRejectsAnOldAnchorAndAnyFrameBetweenDisplays() {
        let old = QuotaOverlayAnchor(frame: CGRect(x: 1130, y: 45, width: 68, height: 36),
                                     windowID: 1, surface: "sessionRail")
        let next = QuotaOverlayAnchor(frame: old.frame.offsetBy(dx: 900, dy: 32),
                                      windowID: 2, surface: "newSessionSlot")
        var gate = QuotaOverlayGate()
        XCTAssertEqual(gate.check(old), .confirming)
        XCTAssertEqual(gate.check(old), .show)
        XCTAssertEqual(gate.check(nil), .hidden)
        XCTAssertEqual(gate.check(next), .confirming)
        XCTAssertEqual(gate.check(next), .show)
        XCTAssertNil(QuotaOverlayAnchor.screenFrame(for: CGRect(x: 1900, y: 40, width: 68, height: 36),
                                                    screens: [primary, CGRect(x: 1920, y: 0, width: 1680, height: 1050)]))
    }

    func testOnlyNewSessionRoutesQualifyForTheFallback() throws {
        for route in ["https://claude.ai/new?surface=chat", "https://claude.ai/code/", "claude://code/new?source=desktop_action"] {
            XCTAssertTrue(ClaudeHeaderQuota.isNewSessionURL(try XCTUnwrap(URL(string: route))))
        }
        for route in ["https://claude.ai/chat/existing", "https://claude.ai/code/project/existing", "https://example.com/new"] {
            XCTAssertFalse(ClaudeHeaderQuota.isNewSessionURL(try XCTUnwrap(URL(string: route))))
        }
    }

    func testRailSelectionPrefersTheRightmostHeaderControlAndRecognizesAccessibleLabels() {
        for label in ["Session rail", "session-rail-toggle", "Show Session Rail", "Session rail, expanded"] {
            XCTAssertTrue(ClaudeHeaderQuota.isSessionRailLabel(label), label)
        }
        for label in ["Session details", "Open sidebar", "Close", ""] {
            XCTAssertFalse(ClaudeHeaderQuota.isSessionRailLabel(label), label)
        }
        let window = CGRect(x: 30, y: 80, width: 920, height: 700)
        let rail = CGRect(x: 910, y: 90, width: 28, height: 28)
        let otherControls = [CGRect(x: 936, y: 90, width: 28, height: 28),
                             CGRect(x: 912, y: 250, width: 28, height: 28),
                             CGRect(x: 900, y: 90, width: 48, height: 80),
                             CGRect(x: 39, y: 90, width: 28, height: 28),
                             CGRect(x: 870, y: 90, width: 28, height: 28)]
        XCTAssertEqual(ClaudeHeaderQuota.rail(in: otherControls + [rail], window: window), rail)
        XCTAssertEqual(ClaudeHeaderQuota.rail(in: [rail] + otherControls, window: window), rail)
    }
}
