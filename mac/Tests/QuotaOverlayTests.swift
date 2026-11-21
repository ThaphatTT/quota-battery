import XCTest

final class QuotaOverlayTests: XCTestCase {
    func testEachHostStartsWithItsOwnProviderAndUsesThePinnedGPTAccount() throws {
        let accounts = [
            try account("work", "claude", [("five_hour", 36), ("seven_day", 73)]),
            try account("personal", "claude", [("seven_day", 21)]),
            try account("codex-main", "codex", [("five_hour", 42)]),
            try account("codex-work", "codex", [("five_hour", 84), ("seven_day", 52)]),
            try account("agy", "agy", [("gemini-5h", 40)])
        ]
        let claude = QuotaOverlayCycle(accounts, hostProvider: "claude", preferredGPT: "codex-work")
        XCTAssertEqual(claude.selection(elapsed: 0)?.badgeLabel, "C1")
        XCTAssertEqual(claude.selection(elapsed: 9)?.window.marker, "5")
        XCTAssertEqual(claude.selection(elapsed: 10)?.window.marker, "W")
        XCTAssertEqual(claude.selection(elapsed: 10)?.remaining, "27%")
        XCTAssertEqual(claude.selection(elapsed: 20)?.accountID, "codex-work")
        XCTAssertEqual(claude.selection(elapsed: 20)?.extraAccounts, 1)
        XCTAssertEqual(claude.selection(elapsed: 30)?.accountID, "codex-work")
        XCTAssertEqual(claude.selection(elapsed: 40)?.provider, "agy")
        XCTAssertEqual(claude.selection(elapsed: 60)?.badgeLabel, "C2")
        XCTAssertEqual(claude.selection(elapsed: 70)?.window.marker, "W")

        let gpt = QuotaOverlayCycle(accounts, hostProvider: "codex", preferredGPT: "codex-work")
        XCTAssertEqual(gpt.selection(elapsed: 0)?.accountID, "codex-work")
        XCTAssertEqual(gpt.selection(elapsed: 10)?.window.marker, "W")
        XCTAssertEqual(gpt.selection(elapsed: 20)?.provider, "claude")
        XCTAssertEqual(gpt.selection(elapsed: 40)?.provider, "agy")
    }

    func testSingleAccountKeepsTwentySecondPeriodsAndSkipsUnusableAccounts() throws {
        let both = try account("main", "claude", [("five_hour", 10), ("seven_day", 19), ("seven_day_opus", 90)])
        let noQuota = try account("no-quota", "codex", [])
        let cycle = QuotaOverlayCycle([both, noQuota], hostProvider: "codex", preferredGPT: "")
        XCTAssertEqual(cycle.selection(elapsed: 19)?.window.marker, "5")
        XCTAssertEqual(cycle.selection(elapsed: 20)?.window.limit.key, "seven_day")
        XCTAssertEqual(cycle.selection(elapsed: 40)?.window.marker, "5")
        XCTAssertNil(QuotaOverlayCycle([noQuota], hostProvider: "codex", preferredGPT: "").selection(elapsed: 0))
    }

    func testOverlayWaitsForStableWindowAndRevalidatesOnPageChanges() {
        let frame = CGRect(x: 40, y: 50, width: 44, height: 48)
        let chat = QuotaOverlayAnchor(frame: frame, windowID: 1, surface: "chat")
        let newChat = QuotaOverlayAnchor(frame: frame, windowID: 1, surface: "new")
        let second = QuotaOverlayAnchor(frame: frame, windowID: 2, surface: "new")
        var gate = QuotaOverlayGate()
        XCTAssertEqual(gate.check(chat), .confirming)
        XCTAssertEqual(gate.check(chat), .show)
        XCTAssertEqual(gate.check(chat), .keepShowing)
        XCTAssertEqual(gate.check(newChat), .confirming)
        XCTAssertEqual(gate.check(second), .confirming)
        XCTAssertEqual(gate.check(second), .show)

        gate.reset()
        XCTAssertEqual(gate.check(second), .confirming)
        XCTAssertEqual(gate.check(nil), .hidden)
        XCTAssertEqual(gate.check(second), .confirming)
        XCTAssertEqual(gate.check(second), .show)
    }

    private func account(_ id: String, _ provider: String, _ limits: [(String, Double)]) throws -> UsageAccount {
        let raw: [String: Any] = [
            "id": id, "provider": provider, "label": id,
            "limits": limits.map { ["key": $0.0, "used_percent": $0.1] }
        ]
        return try JSONDecoder().decode(UsageAccount.self, from: JSONSerialization.data(withJSONObject: raw))
    }
}
