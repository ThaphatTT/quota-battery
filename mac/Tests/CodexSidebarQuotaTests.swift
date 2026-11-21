import XCTest

final class CodexSidebarQuotaTests: XCTestCase {
    func testPrefersTheSelectedCodexAccountAndKeepsItsPeriodsSeparate() throws {
        let accounts = [
            try account("codex-work", provider: "codex", limits: [(10_800, 62)]),
            try account("claude-main", provider: "claude", limits: [(18_000, 98)]),
            try account("codex-main", provider: "codex", limits: [(18_000, 42), (604_800, 68)])
        ]
        let quota = CodexSidebarQuota(accounts)
        XCTAssertEqual(quota.accounts.map(\.id), ["codex-work", "codex-main"])
        let primary = quota.account(preferredID: "")
        XCTAssertEqual(primary?.id, "codex-main")
        XCTAssertEqual(CodexSidebarQuota.periods(for: primary).map(CodexSidebarQuota.marker), ["5", "W"])
        let selected = quota.account(preferredID: "codex-work")
        XCTAssertEqual(CodexSidebarQuota.periods(for: selected).map(\.usedPercent), [62])
        XCTAssertEqual(CodexSidebarQuota.periods(for: selected).map(CodexSidebarQuota.marker), ["3h"])
        XCTAssertEqual(quota.account(preferredID: "claude-main")?.id, primary?.id)
    }

    func testUnknownDurationsUseSlotNamesAndDoNotGuessAWeeklyLimit() throws {
        let account = try account("codex-main", provider: "codex", limits: [(nil, 15), (nil, 49)])
        XCTAssertEqual(account.limits.map(CodexSidebarQuota.marker), ["P", "S"])
        XCTAssertEqual(account.limits.map { CodexSidebarQuota.windowName($0, language: .en) },
                       ["Primary limit", "Secondary limit"])
    }

    private func account(_ id: String, provider: String, limits: [(Int?, Double)]) throws -> UsageAccount {
        let windows: [[String: Any]] = limits.enumerated().map { index, limit in
            var window: [String: Any] = ["key": index == 0 ? "primary" : "secondary", "used_percent": limit.1]
            window["window_seconds"] = limit.0
            return window
        }
        let raw: [String: Any] = ["id": id, "provider": provider, "limits": windows]
        return try JSONDecoder().decode(UsageAccount.self, from: JSONSerialization.data(withJSONObject: raw))
    }
}
