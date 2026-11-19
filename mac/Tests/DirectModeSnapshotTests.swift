import SwiftUI
import XCTest

/// Draws the direct mode screens to PNG files in mac/build/snapshots/ (gitignored): the consent screen, unticked and
/// ticked, and the account rows with their control. Thai and English, light and dark. Each render pins its language at
/// the root. The files are consent-*.png and direct-rows-*.png.
@MainActor
final class DirectModeSnapshotTests: XCTestCase {
    /// The consent screen for ChatGPT with the box unticked and ticked, and for agy with the box unticked.
    func testRenderTheConsentScreenInThaiAndEnglishInLightAndDark() throws {
        let outputDirectory = Fixtures.macFolder.appendingPathComponent("build/snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let variants: [(name: String, provider: String, ticked: Bool)] = [
            ("consent-codex", "codex", false),
            ("consent-codex-ticked", "codex", true),
            ("consent-agy", "agy", false),
        ]

        var written = 0
        for language in [UILanguage.th, .en] {
            for dark in [false, true] {
                for variant in variants {
                    let view = DirectModeConsentView(
                        provider: variant.provider,
                        startsConsented: variant.ticked,
                        snapshot: true
                    ) { _ in }
                    let name = "\(variant.name)-\(language.rawValue)-\(dark ? "dark" : "light").png"
                    let data = try XCTUnwrap(SnapshotRenderer.fitting(view, dark: dark, language: language), name)
                    try data.write(to: outputDirectory.appendingPathComponent(name))
                    XCTAssertGreaterThan(data.count, 1_000, name)
                    written += 1
                }
            }
        }
        XCTAssertEqual(written, 12)
    }

    /// The Accounts section with a ChatGPT account (direct mode off), an agy account (on) and a Claude account, which has
    /// no control at all. In Thai and English, light and dark.
    func testRenderTheAccountRowsWithTheDirectModeControl() throws {
        let outputDirectory = Fixtures.macFolder.appendingPathComponent("build/snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let usage = try Fixtures.document(#"""
        {"accounts": [
          {"id": "claude-main", "provider": "claude", "label": "Claude", "plan": "Max", "status": "ok",
           "limits": [{"key": "five_hour", "window_seconds": 18000, "used_percent": 42, "resets_at": "2026-11-19T06:40:00Z"}]},
          {"id": "codex-main", "provider": "codex", "label": "ChatGPT", "plan": "Pro Lite", "status": "ok",
           "limits": [{"key": "primary", "window_seconds": 604800, "used_percent": 61, "resets_at": "2026-11-20T02:35:51Z"}]},
          {"id": "agy-main", "provider": "agy", "label": "agy", "plan": "free-tier", "status": "ok", "limits": []}
        ]}
        """#).accounts
        let known = KnownAccounts.decode(Data(#"""
        [
          {"id": "claude-main", "provider": "claude", "source": "Claude Code (main)", "first_seen": "2026-10-01T00:00:00Z"},
          {"id": "codex-main", "provider": "codex", "source": "Codex (~/.codex)", "first_seen": "2026-10-01T00:00:00Z"},
          {"id": "agy-main", "provider": "agy", "source": "Antigravity", "first_seen": "2026-10-01T00:00:00Z"}
        ]
        """#.utf8))
        let rows = AccountList.sorted(
            AccountList.rows(known: known, usage: usage, settings: AccountSettings(), now: Fixtures.now),
            by: .manual
        )
        let state = AccountsPanelState(
            rows: rows,
            sort: .manual,
            notice: nil,
            isRefreshing: false,
            directMode: DirectModeSettings(codex: false, agy: true)
        )

        var written = 0
        for language in [UILanguage.th, .en] {
            for dark in [false, true] {
                let view = AppAccountsSection(state: state, actions: AccountActions(), snapshot: true)
                    .frame(width: 498)
                let name = "direct-rows-\(language.rawValue)-\(dark ? "dark" : "light").png"
                let data = try XCTUnwrap(SnapshotRenderer.fitting(view, dark: dark, language: language), name)
                try data.write(to: outputDirectory.appendingPathComponent(name))
                XCTAssertGreaterThan(data.count, 1_000, name)
                written += 1
            }
        }
        XCTAssertEqual(written, 4)
    }
}
