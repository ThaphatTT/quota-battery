import SwiftUI
import XCTest

/// Renders the real views to PNG files in mac/build/snapshots/ (gitignored) so the layout, dark mode and both
/// languages can be checked by eye. Each render pins its language at the root. The test fails if a render is empty.
/// Thai file names have no prefix; English names start with "en-".
@MainActor
final class SnapshotTests: XCTestCase {
    /// Widget frame sizes in points. These are assumed, not measured on a real widget.
    private let frames: [UsageSize: CGSize] = [
        .small: CGSize(width: 170, height: 170),
        .medium: CGSize(width: 364, height: 170),
        .large: CGSize(width: 364, height: 382),
    ]

    func testRenderWidgetLayoutsInThaiAndEnglishInLightAndDarkAtFullAndNinetyPercentSize() throws {
        let variants: [(name: String, result: UsageLoadResult, sizes: [UsageSize])] = [
            ("sample", UsageLoader.load(from: Fixtures.sampleURL), UsageSize.allCases),
            ("image", try sampleImageCase(), UsageSize.allCases),
            ("stale-error", try staleAndErrorCase(), UsageSize.allCases),
            ("nodata", .missing, UsageSize.allCases),
            ("worst", try worstCase(), [.medium, .large]),
            ("used32", try uniformCase(used: 32), UsageSize.allCases),
            ("used85", try uniformCase(used: 85), UsageSize.allCases),
            ("used95", try uniformCase(used: 95), UsageSize.allCases),
            ("tiers", try tiersCase(), UsageSize.allCases),
        ]
        let outputDirectory = Fixtures.macFolder.appendingPathComponent("build/snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        var written = 0
        for language in [UILanguage.th, .en] {
            let prefix = language == .th ? "" : "en-"
            for variant in variants {
                for size in variant.sizes {
                    for dark in [false, true] {
                        for scale in [1.0, 0.9] as [CGFloat] {
                            let frame = try XCTUnwrap(frames[size])
                            let target = CGSize(width: frame.width * scale, height: frame.height * scale)
                            let view = UsageScreenView(size: size, result: variant.result, now: Fixtures.now)
                            let name = "\(prefix)\(variant.name)-\(size)-\(dark ? "dark" : "light")-\(Int(scale * 100)).png"
                            let data = try XCTUnwrap(
                                SnapshotRenderer.png(view, size: target, dark: dark, language: language),
                                "render failed: \(name)"
                            )
                            try data.write(to: outputDirectory.appendingPathComponent(name))
                            XCTAssertGreaterThan(data.count, 1_000, name)
                            written += 1
                        }
                    }
                }
            }
        }
        XCTAssertEqual(written, 208)
    }

    /// The popover (the app's menu bar panel) with the sample data, in both languages and both appearances.
    func testRenderThePopoverInThaiAndEnglishInLightAndDark() throws {
        let outputDirectory = Fixtures.macFolder.appendingPathComponent("build/snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let state = AppUsageState(
            result: UsageLoader.load(from: Fixtures.sampleURL),
            now: Fixtures.now,
            isRefreshing: false,
            notice: nil
        )

        let noData = AppUsageState(result: .missing, now: Fixtures.now, isRefreshing: false, notice: nil)

        var written = 0
        for language in [UILanguage.th, .en] {
            for dark in [false, true] {
                let view = MenuBarPopoverView(
                    state: state,
                    onRefresh: {},
                    onOpenApp: {},
                    onQuit: {},
                    startsRevealed: true,
                    startsHovered: 0
                )
                let name = "popover-\(language.rawValue)-\(dark ? "dark" : "light").png"
                let data = try XCTUnwrap(SnapshotRenderer.fitting(view, dark: dark, language: language), name)
                try data.write(to: outputDirectory.appendingPathComponent(name))
                XCTAssertGreaterThan(data.count, 1_000, name)
                written += 1
            }
            // The no-data footer is the longest status line, so it is checked in each language.
            let view = MenuBarPopoverView(
                state: noData,
                onRefresh: {},
                onOpenApp: {},
                onQuit: {},
                startsRevealed: true
            )
            let name = "popover-nodata-\(language.rawValue)-light.png"
            let data = try XCTUnwrap(SnapshotRenderer.fitting(view, dark: false, language: language), name)
            try data.write(to: outputDirectory.appendingPathComponent(name))
            XCTAssertGreaterThan(data.count, 1_000, name)
            written += 1
        }
        XCTAssertEqual(written, 6)
    }

    /// The popover at three usage levels (32, 85 and 95 used on every limit) and at the mixed tiers, in both
    /// languages and both appearances, so each image shows the tier it is set to.
    func testRenderThePopoverAtTheLevelsInThaiAndEnglishInLightAndDark() throws {
        let outputDirectory = Fixtures.macFolder.appendingPathComponent("build/snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let levels: [(name: String, result: UsageLoadResult)] = [
            ("used32", try uniformCase(used: 32)),
            ("used85", try uniformCase(used: 85)),
            ("used95", try uniformCase(used: 95)),
            ("tiers", try tiersCase()),
        ]

        var written = 0
        for language in [UILanguage.th, .en] {
            for dark in [false, true] {
                for level in levels {
                    let state = AppUsageState(result: level.result, now: Fixtures.now, isRefreshing: false, notice: nil)
                    let view = MenuBarPopoverView(
                        state: state,
                        onRefresh: {},
                        onOpenApp: {},
                        onQuit: {},
                        startsRevealed: true,
                        startsHovered: 0
                    )
                    let name = "popover-\(level.name)-\(language.rawValue)-\(dark ? "dark" : "light").png"
                    let data = try XCTUnwrap(SnapshotRenderer.fitting(view, dark: dark, language: language), name)
                    try data.write(to: outputDirectory.appendingPathComponent(name))
                    XCTAssertGreaterThan(data.count, 1_000, name)
                    written += 1
                }
            }
        }
        XCTAssertEqual(written, 16)
    }

    /// The Accounts section with five accounts, built from the same files the app reads: usage.json, known-accounts.json
    /// and settings.json. One account is hidden, one is new and has a nickname, and one (agy) has no limits. In Thai and
    /// English, light and dark, in the manual order, and once in the lowest-left order.
    func testRenderTheAccountsSectionWithFiveAccountsInThaiAndEnglishInLightAndDark() throws {
        let outputDirectory = Fixtures.macFolder.appendingPathComponent("build/snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let usage = try Fixtures.document(#"""
        {"accounts": [
          {"id": "claude-main", "provider": "claude", "label": "Claude", "plan": "Max", "status": "ok",
           "limits": [{"key": "five_hour", "window_seconds": 18000, "used_percent": 42, "resets_at": "2026-11-19T06:40:00Z"},
                      {"key": "seven_day", "window_seconds": 604800, "used_percent": 67, "resets_at": "2026-11-24T02:00:00Z"}]},
          {"id": "claude-claude-2", "provider": "claude", "label": "Claude งาน", "plan": "Max", "status": "ok",
           "limits": [{"key": "five_hour", "window_seconds": 18000, "used_percent": 12, "resets_at": "2026-11-19T06:40:00Z"}]},
          {"id": "codex-main", "provider": "codex", "label": "ChatGPT", "plan": "Pro Lite", "status": "ok",
           "limits": [{"key": "primary", "window_seconds": 604800, "used_percent": 93, "resets_at": "2026-11-20T02:35:51Z"}]},
          {"id": "agy-main", "provider": "agy", "label": "agy", "plan": "free-tier", "status": "ok", "limits": []}
        ]}
        """#).accounts
        let known = KnownAccounts.decode(Data(#"""
        [
          {"id": "claude-main", "provider": "claude", "source": "Claude Code (main)", "first_seen": "2026-10-01T00:00:00Z"},
          {"id": "claude-claude-2", "provider": "claude", "source": "Claude Code (~/.claude-2)", "first_seen": "2026-11-19T02:00:00Z"},
          {"id": "codex-main", "provider": "codex", "source": "Codex (~/.codex)", "first_seen": "2026-10-01T00:00:00Z"},
          {"id": "codex-codex-2", "provider": "codex", "source": "Codex (~/.codex-2)", "first_seen": "2026-10-20T00:00:00Z"},
          {"id": "agy-main", "provider": "agy", "source": "Antigravity", "first_seen": "2026-10-01T00:00:00Z"}
        ]
        """#.utf8))
        let manual = AccountSettings(sort: .manual, accounts: [
            "claude-main": AccountPreference(label: nil, enabled: true, order: 0),
            "claude-claude-2": AccountPreference(label: "Claude งาน", enabled: true, order: 1),
            "codex-main": AccountPreference(label: nil, enabled: true, order: 2),
            "codex-codex-2": AccountPreference(label: nil, enabled: false, order: 3),
            "agy-main": AccountPreference(label: nil, enabled: true, order: 4),
        ])
        var lowest = manual
        lowest.sort = .lowest
        let variants: [(name: String, settings: AccountSettings)] = [("manual", manual), ("lowest", lowest)]

        var written = 0
        for variant in variants {
            let rows = AccountList.sorted(
                AccountList.rows(known: known, usage: usage, settings: variant.settings, now: Fixtures.now),
                by: variant.settings.sort
            )
            let state = AccountsPanelState(rows: rows, sort: variant.settings.sort, notice: nil, isRefreshing: false)
            for language in [UILanguage.th, .en] {
                for dark in [false, true] {
                    let view = AppAccountsSection(state: state, actions: AccountActions(), snapshot: true)
                        .frame(width: 498)
                    let name = "accounts-\(variant.name)-\(language.rawValue)-\(dark ? "dark" : "light").png"
                    let data = try XCTUnwrap(SnapshotRenderer.fitting(view, dark: dark, language: language), name)
                    try data.write(to: outputDirectory.appendingPathComponent(name))
                    XCTAssertGreaterThan(data.count, 1_000, name)
                    written += 1
                }
            }
        }
        XCTAssertEqual(written, 8)
    }

    /// The app window's account cards: the mixed tiers, and the sample, whose agy account has three limits and so shows
    /// the compact list. The bars drain and take the tier colour, and each card has its pill. Both languages and both
    /// appearances.
    func testRenderTheAppWindowCardsForTheTiers() throws {
        let outputDirectory = Fixtures.macFolder.appendingPathComponent("build/snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let fixtures: [(name: String, result: UsageLoadResult)] = [
            ("tiers", try tiersCase()),
            ("sample", UsageLoader.load(from: Fixtures.sampleURL)),
        ]

        var written = 0
        for fixture in fixtures {
            let document = try XCTUnwrap(fixture.result.document)
            for language in [UILanguage.th, .en] {
                for dark in [false, true] {
                    let view = VStack(spacing: 12) {
                        ForEach(Array(document.accounts.enumerated()), id: \.offset) { _, account in
                            AppAccountCardView(account: account, now: Fixtures.now)
                        }
                    }
                    .padding(16)
                    .frame(width: 530)
                    let name = "window-\(fixture.name)-\(language.rawValue)-\(dark ? "dark" : "light").png"
                    let data = try XCTUnwrap(SnapshotRenderer.fitting(view, dark: dark, language: language), name)
                    try data.write(to: outputDirectory.appendingPathComponent(name))
                    XCTAssertGreaterThan(data.count, 1_000, name)
                    written += 1
                }
            }
        }
        XCTAssertEqual(written, 8)
    }

    /// Five accounts: the small and medium widgets draw the first three. The "+2" badge sits in the medium header, beside the
    /// updated text, and under the age text in the small update cell.
    /// In Thai and English, light and dark. The files are mac/build/snapshots/more-badge-5-*.png (English: en-more-badge-5-*).
    func testRenderTheSmallAndMediumWidgetsWithFiveAccountsAndTheMoreBadge() throws {
        try renderMoreBadge(count: 5, languages: [.th, .en])
    }

    /// Twelve accounts: the badge reads "+9", the widest case, so it is checked against the rings and rows in Thai.
    func testRenderTheSmallAndMediumWidgetsWithTwelveAccountsForTheWidestBadge() throws {
        try renderMoreBadge(count: 12, languages: [.th])
    }

    private func renderMoreBadge(count: Int, languages: [UILanguage]) throws {
        let outputDirectory = Fixtures.macFolder.appendingPathComponent("build/snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let result = try moreAccountsCase(count: count)

        var written = 0
        for language in languages {
            let prefix = language == .th ? "" : "en-"
            for size in [UsageSize.small, .medium] {
                for dark in [false, true] {
                    let frame = try XCTUnwrap(frames[size])
                    let view = UsageScreenView(size: size, result: result, now: Fixtures.now)
                    let name = "\(prefix)more-badge-\(count)-\(size)-\(dark ? "dark" : "light").png"
                    let data = try XCTUnwrap(SnapshotRenderer.png(view, size: frame, dark: dark, language: language), name)
                    try data.write(to: outputDirectory.appendingPathComponent(name))
                    XCTAssertGreaterThan(data.count, 1_000, name)
                    written += 1
                }
            }
        }
        XCTAssertEqual(written, languages.count * 4)
    }

    /// `count` accounts in file order. The first three are Claude 42 used, a second Claude at 12 used and ChatGPT at 85
    /// used (yellow). The rest are Claude accounts at 30 used, which the small and medium widgets leave out.
    private func moreAccountsCase(count: Int) throws -> UsageLoadResult {
        let shown = [
            accountJSON(id: "claude-main", provider: "claude", label: "Claude", used: 42),
            accountJSON(id: "claude-claude-2", provider: "claude", label: "Claude งาน", used: 12),
            accountJSON(id: "codex-main", provider: "codex", label: "ChatGPT", used: 85),
        ]
        let rest = stride(from: 4, through: count, by: 1).map { n in
            accountJSON(id: "claude-\(n)", provider: "claude", label: "Claude \(n)", used: 30)
        }
        return .loaded(try Fixtures.document(
            #"{"generated_at": "2026-11-19T04:28:00Z", "accounts": ["# + (shown + rest).joined(separator: ",") + "]}"
        ))
    }

    /// One account as usage.json writes it, with one limit (the five-hour window) at `used` percent.
    private func accountJSON(id: String, provider: String, label: String, used: Int) -> String {
        """
        {"id": "\(id)", "provider": "\(provider)", "label": "\(label)", "plan": "Max", "status": "ok", "error": null,
         "updated_at": "2026-11-19T04:28:00Z",
         "limits": [{"key": "five_hour", "label": "5 ชม.", "window_seconds": 18000, "used_percent": \(used), "resets_at": "2026-11-19T05:30:00Z"}],
         "usage": null, "credits": null}
        """
    }

    /// Every limit at the same used share, so the widgets and the popover show that one tier throughout. Claude has
    /// two limits, ChatGPT one, and agy two. Each account is up to date.
    private func uniformCase(used: Double) throws -> UsageLoadResult {
        let value = String(used)
        return .loaded(try Fixtures.document("""
        {"generated_at": "2026-11-19T04:28:00Z", "accounts": [
          {"provider": "claude", "label": "Claude", "plan": "Max", "status": "ok", "error": null,
           "updated_at": "2026-11-19T04:28:00Z",
           "limits": [{"key": "five_hour", "label": "5 ชม.", "window_seconds": 18000, "used_percent": \(value), "resets_at": "2026-11-19T05:30:00Z"},
                      {"key": "seven_day", "label": "สัปดาห์", "window_seconds": 604800, "used_percent": \(value), "resets_at": "2026-11-24T02:00:00Z"}],
           "usage": {"today": {"tokens": 1200000, "cost_usd": 18.4}}, "credits": null},
          {"provider": "codex", "label": "ChatGPT", "plan": "Pro Lite", "status": "ok", "error": null,
           "updated_at": "2026-11-19T04:28:00Z",
           "limits": [{"key": "primary", "label": "สัปดาห์", "window_seconds": 604800, "used_percent": \(value), "resets_at": "2026-11-20T01:30:00Z"}],
           "usage": null, "credits": {"extra_usage_enabled": false, "used_usd": null, "limit_usd": null, "balance_usd": 0}},
          {"provider": "agy", "label": "agy", "plan": "free-tier", "status": "ok", "error": null,
           "updated_at": "2026-11-19T04:28:00Z",
           "limits": [{"key": "claude", "label": "Claude", "used_percent": \(value), "resets_at": "2026-11-19T08:30:00Z"},
                      {"key": "gemini_pro", "label": "Gemini Pro", "used_percent": \(value), "resets_at": "2026-11-19T08:30:00Z"}],
           "usage": null, "credits": null}
        ]}
        """))
    }

    /// The three tiers in one set of data: Claude 32 and 40 used (white), ChatGPT 85 (yellow), agy 95 and 32 (red and
    /// white). The small widget shows one white, one yellow and one red ring; the large one shows all five rows.
    private func tiersCase() throws -> UsageLoadResult {
        .loaded(try Fixtures.document("""
        {"generated_at": "2026-11-19T04:28:00Z", "accounts": [
          {"provider": "claude", "label": "Claude", "plan": "Max", "status": "ok", "error": null,
           "updated_at": "2026-11-19T04:28:00Z",
           "limits": [{"key": "five_hour", "label": "5 ชม.", "window_seconds": 18000, "used_percent": 32, "resets_at": "2026-11-19T05:30:00Z"},
                      {"key": "seven_day", "label": "สัปดาห์", "window_seconds": 604800, "used_percent": 40, "resets_at": "2026-11-24T02:00:00Z"}],
           "usage": {"today": {"tokens": 1200000, "cost_usd": 18.4}}, "credits": null},
          {"provider": "codex", "label": "ChatGPT", "plan": "Pro Lite", "status": "ok", "error": null,
           "updated_at": "2026-11-19T04:28:00Z",
           "limits": [{"key": "primary", "label": "สัปดาห์", "window_seconds": 604800, "used_percent": 85, "resets_at": "2026-11-20T01:30:00Z"}],
           "usage": null, "credits": {"extra_usage_enabled": false, "used_usd": null, "limit_usd": null, "balance_usd": 0}},
          {"provider": "agy", "label": "agy", "plan": "free-tier", "status": "ok", "error": null,
           "updated_at": "2026-11-19T04:28:00Z",
           "limits": [{"key": "claude", "label": "Claude", "used_percent": 95, "resets_at": "2026-11-19T08:30:00Z"},
                      {"key": "gemini_pro", "label": "Gemini Pro", "used_percent": 32, "resets_at": "2026-11-19T08:30:00Z"}],
           "usage": null, "credits": null}
        ]}
        """))
    }

    /// The sample data: Claude 52% and 40%, ChatGPT 93% with a 0 balance, agy at 0% twice.
    /// The file was written two minutes before `Fixtures.now`, so the footers read "2 นาทีก่อน".
    private func sampleImageCase() throws -> UsageLoadResult {
        .loaded(try Fixtures.document("""
        {"generated_at": "2026-11-19T04:28:00Z", "accounts": [
          {"provider": "claude", "label": "Claude", "plan": "Max", "status": "ok", "error": null,
           "updated_at": "2026-11-19T04:28:00Z",
           "limits": [{"key": "five_hour", "label": "5 ชม.", "window_seconds": 18000, "used_percent": 52, "resets_at": "2026-11-19T05:30:00Z"},
                      {"key": "seven_day", "label": "สัปดาห์", "window_seconds": 604800, "used_percent": 40, "resets_at": "2026-11-24T02:00:00Z"}],
           "usage": null, "credits": null},
          {"provider": "codex", "label": "ChatGPT", "plan": "Pro Lite", "status": "ok", "error": null,
           "updated_at": "2026-11-19T04:28:00Z",
           "limits": [{"key": "primary", "label": "สัปดาห์", "window_seconds": 604800, "used_percent": 93, "resets_at": "2026-11-20T01:30:00Z"}],
           "usage": null, "credits": {"extra_usage_enabled": false, "used_usd": null, "limit_usd": null, "balance_usd": 0}},
          {"provider": "agy", "label": "agy", "plan": "free-tier", "status": "ok", "error": null,
           "updated_at": "2026-11-19T04:28:00Z",
           "limits": [{"key": "claude", "label": "Claude", "used_percent": 0, "resets_at": "2026-11-19T08:30:00Z"},
                      {"key": "gemini_pro", "label": "Gemini Pro", "used_percent": 0, "resets_at": "2026-11-19T08:30:00Z"}],
           "usage": null, "credits": null}
        ]}
        """))
    }

    /// Two accounts with data, one with an error. The second is stale, and the third has no data.
    private func staleAndErrorCase() throws -> UsageLoadResult {
        .loaded(try Fixtures.document("""
        {"generated_at": "2026-11-19T04:30:00Z", "accounts": [
          {"provider": "claude", "label": "Claude", "plan": "Max", "status": "ok", "error": null,
           "updated_at": "2026-11-19T04:30:00Z",
           "limits": [{"key": "five_hour", "label": "5 ชม.", "window_seconds": 18000, "used_percent": 80, "resets_at": "2026-11-19T06:40:00Z"},
                      {"key": "seven_day", "label": "สัปดาห์", "window_seconds": 604800, "used_percent": 79.6, "resets_at": "2026-11-24T02:00:00Z"}],
           "usage": {"today": {"tokens": 1200000, "cost_usd": 18.4}, "month": null},
           "credits": {"extra_usage_enabled": true, "used_usd": 12.5, "limit_usd": 50, "balance_usd": null}},
          {"provider": "codex", "label": "ChatGPT", "plan": "Pro Lite", "status": "stale",
           "error_code": "login_expired", "error": "ล็อกอิน Codex หมดอายุ เปิด codex สักครั้ง", "updated_at": "2026-11-19T01:30:00Z",
           "limits": [{"key": "primary", "label": "สัปดาห์", "window_seconds": 604800, "used_percent": 100, "resets_at": "2026-11-20T02:35:51Z"}],
           "usage": null, "credits": null},
          {"provider": "agy", "label": "agy", "plan": "free-tier", "status": "error",
           "error_code": "login_expired", "error": "ล็อกอิน agy หมดอายุ", "updated_at": null, "limits": [], "usage": null, "credits": null}
        ]}
        """))
    }

    /// The largest data the widgets can show. Every account is stale with error text, which is what
    /// "Mac offline" produces.
    private func worstCase() throws -> UsageLoadResult {
        .loaded(try Fixtures.document("""
        {"generated_at": "2026-11-19T04:30:00Z", "accounts": [
          {"provider": "claude", "label": "Claude", "plan": "Max", "status": "stale",
           "error_code": "network", "error": "เชื่อมต่อไม่ได้ ใช้ข้อมูลเดิม", "updated_at": "2026-11-19T01:00:00Z",
           "limits": [
             {"key": "five_hour", "label": "5 ชม.", "window_seconds": 18000, "used_percent": 42, "resets_at": "2026-11-19T06:40:00Z"},
             {"key": "seven_day", "label": "สัปดาห์", "window_seconds": 604800, "used_percent": 67, "resets_at": "2026-11-24T02:00:00Z"},
             {"key": "seven_day_opus", "label": "Opus สัปดาห์", "window_seconds": 604800, "used_percent": 12, "resets_at": "2026-11-24T02:00:00Z"},
             {"key": "seven_day_sonnet", "label": "Sonnet สัปดาห์", "window_seconds": 604800, "used_percent": 90, "resets_at": "2026-11-24T02:00:00Z"}],
           "usage": {"today": {"tokens": 1200000, "cost_usd": 18.4}},
           "credits": {"extra_usage_enabled": true, "used_usd": 12.5, "limit_usd": 50}},
          {"provider": "codex", "label": "ChatGPT", "plan": "Pro Lite", "status": "stale",
           "error_code": "login_expired", "error": "ล็อกอิน Codex หมดอายุ เปิด codex สักครั้ง", "updated_at": "2026-11-19T01:00:00Z",
           "limits": [
             {"key": "primary", "label": "5 ชม.", "window_seconds": 18000, "used_percent": 100, "resets_at": "2026-11-19T06:40:00Z"},
             {"key": "secondary", "label": "สัปดาห์", "window_seconds": 604800, "used_percent": 93, "resets_at": "2026-11-20T02:35:51Z"}],
           "usage": {"today": {"tokens": 640000, "cost_usd": null}}, "credits": null},
          {"provider": "agy", "label": "agy", "plan": "free-tier", "status": "stale",
           "error_code": "login_expired", "error": "ล็อกอิน agy หมดอายุ", "updated_at": "2026-11-19T01:00:00Z",
           "limits": [
             {"key": "claude", "label": "Claude", "used_percent": 0, "resets_at": "2026-11-19T09:21:41Z"},
             {"key": "gemini_pro", "label": "Gemini Pro", "used_percent": 0, "resets_at": "2026-11-19T09:21:41Z"},
             {"key": "gemini_flash", "label": "Gemini Flash", "used_percent": 0, "resets_at": "2026-11-19T09:21:41Z"},
             {"key": "gpt_oss", "label": "GPT-OSS", "used_percent": 0, "resets_at": "2026-11-19T09:21:41Z"}],
           "usage": null, "credits": null}
        ]}
        """))
    }
}

@MainActor
enum SnapshotRenderer {
    /// ImageRenderer does not draw the widget container background, so a plain backing fill
    /// stands in for it, one per colour scheme. The language is set at the root.
    static func png<V: View>(_ view: V, size: CGSize, dark: Bool, language: UILanguage) -> Data? {
        let content = view
            .frame(width: size.width, height: size.height)
            .background(dark ? Color(white: 0.16) : Color(white: 0.95))
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.uiLanguage, language)
        return render(content)
    }

    /// For a view with its own height, such as the popover: the content keeps its size, on a backing fill.
    static func fitting<V: View>(_ view: V, dark: Bool, language: UILanguage) -> Data? {
        let content = view
            .padding(12)
            .background(dark ? Color(white: 0.16) : Color(white: 0.95))
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.uiLanguage, language)
        return render(content)
    }

    private static func render<V: View>(_ content: V) -> Data? {
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}
