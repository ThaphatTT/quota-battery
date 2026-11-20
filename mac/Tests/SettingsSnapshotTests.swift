import SwiftUI
import XCTest

/// Renders each pane of the Settings window in Thai and English, light and dark, to mac/build/snapshots/ (English names
/// start with "en-"). The native switches and the segmented control are drawn as look-alikes, as the app's other
/// snapshots do. The login item is a fake: nothing is registered.
@MainActor
final class SettingsSnapshotTests: XCTestCase {
    private static let paneWidth: CGFloat = 540

    func testRenderEachSettingsPaneInThaiAndEnglishInLightAndDark() throws {
        let outputDirectory = Fixtures.macFolder.appendingPathComponent("build/snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let accounts = AccountsPanelState(
            rows: try Self.accountRows(),
            sort: .manual,
            notice: nil,
            isRefreshing: false
        )

        var written = 0
        for language in [UILanguage.th, .en] {
            let prefix = language == .th ? "" : "en-"
            for dark in [false, true] {
                let suffix = dark ? "dark" : "light"
                let general = Self.generalPane(status: .notRegistered)
                let needsApproval = Self.generalPane(status: .requiresApproval)
                let views: [(name: String, view: AnyView)] = [
                    ("settings-general", AnyView(general)),
                    ("settings-general-approval", AnyView(needsApproval)),
                    ("settings-accounts", AnyView(
                        AppAccountsSection(state: accounts, actions: AccountActions(), snapshot: true)
                            .frame(width: Self.paneWidth)
                    )),
                    ("settings-notifications", AnyView(
                        NotificationsSettingsPane(notify: .constant(true), snapshot: true)
                            .frame(width: Self.paneWidth)
                    )),
                    ("settings-direct-mode", AnyView(
                        DirectModeSettingsPane(
                            state: DirectModeSettings(codex: false, agy: true),
                            onSetDirectMode: { _, _ in },
                            snapshot: true
                        )
                        .frame(width: Self.paneWidth)
                    )),
                ]
                for item in views {
                    let name = "\(prefix)\(item.name)-\(suffix).png"
                    let data = try XCTUnwrap(
                        SnapshotRenderer.fitting(item.view, dark: dark, language: language),
                        "render failed: \(name)"
                    )
                    try data.write(to: outputDirectory.appendingPathComponent(name))
                    XCTAssertGreaterThan(data.count, 1_000, name)
                    written += 1
                }
            }
        }
        XCTAssertEqual(written, 20)
    }

    private static func generalPane(status: LoginItemStatus) -> some View {
        GeneralSettingsPane(
            choice: .system,
            onSetLanguage: { _ in },
            showMenuBarIcon: .constant(true),
            openAtLogin: OpenAtLoginModel(service: FixedLoginItem(status: status)),
            snapshot: true
        )
        .frame(width: paneWidth)
    }

    /// The rows of the Accounts pane: two Claude accounts and one ChatGPT account.
    private static func accountRows() throws -> [AccountListRow] {
        let document = try ModelMixFixtures.document()
        let known = KnownAccounts.decode(Data(#"""
        [
          {"id": "claude-main", "provider": "claude", "source": "Claude Code (main)", "first_seen": "2026-10-01T00:00:00Z"},
          {"id": "codex-main", "provider": "codex", "source": "Codex (~/.codex)", "first_seen": "2026-10-01T00:00:00Z"}
        ]
        """#.utf8))
        return AccountList.rows(known: known, usage: document.accounts, settings: .init(), now: Fixtures.now)
    }
}

/// A login item that reports a fixed status and does nothing else.
private struct FixedLoginItem: LoginItemService {
    let status: LoginItemStatus
    func register() throws {}
    func unregister() throws {}
}
