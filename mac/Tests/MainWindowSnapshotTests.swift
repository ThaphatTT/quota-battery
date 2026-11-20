import SwiftUI
import XCTest

/// Renders the app window at its one-column and two-column widths, in Thai and English, light and dark, to
/// mac/build/snapshots/ (English names start with "en-"). Each file is looked at by eye: nothing may be cut off.
@MainActor
final class MainWindowSnapshotTests: XCTestCase {
    private static let windowHeight: CGFloat = 705

    func testRenderTheMainWindowInOneAndTwoColumnsInThaiAndEnglishInLightAndDark() throws {
        let outputDirectory = Fixtures.macFolder.appendingPathComponent("build/snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let documents: [(name: String, document: UsageDocument)] = [
            ("mix", try ModelMixFixtures.document()),
            ("sample", try Fixtures.sample()),
        ]
        let widths: [(columns: Int, width: CGFloat)] = [
            (1, CardGridLayout.minimumWindowWidth),
            (2, CardGridLayout.twoColumnWidth),
        ]

        var written = 0
        for language in [UILanguage.th, .en] {
            let prefix = language == .th ? "" : "en-"
            for fixture in documents {
                for width in widths {
                    for dark in [false, true] {
                        let state = AppUsageState(
                            result: .loaded(fixture.document),
                            now: Fixtures.now,
                            isRefreshing: false,
                            notice: nil,
                            accountMixes: Self.mixes(fixture.document)
                        )
                        let view = ContentView(
                            state: state,
                            modelMixActions: ModelMixActions(),
                            onRefresh: {},
                            onOpenSettings: {},
                            onOpenLogs: {},
                            snapshot: true
                        )
                        let name = "\(prefix)main-window-\(fixture.name)-\(width.columns)col-\(dark ? "dark" : "light").png"
                        let data = try XCTUnwrap(
                            SnapshotRenderer.png(view, size: CGSize(width: width.width, height: Self.windowHeight), dark: dark, language: language),
                            "render failed: \(name)"
                        )
                        try data.write(to: outputDirectory.appendingPathComponent(name))
                        XCTAssertGreaterThan(data.count, 1_000, name)
                        written += 1
                    }
                }
            }
        }
        XCTAssertEqual(written, 16)
    }

    /// The popover's total line with a trial: the first Claude account's mix is a what-if, so the line carries "(trial)" or
    /// "(ทดลอง)" after the Claude part. Checked for truncation in both languages and both appearances.
    func testRenderThePopoverTotalWithATrialInThaiAndEnglishInLightAndDark() throws {
        let outputDirectory = Fixtures.macFolder.appendingPathComponent("build/snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let document = try ModelMixFixtures.document()
        let trialSettings = ModelMixSettings(
            order: ModelMix.defaultOrder,
            percent: ["claude-opus-5-5": 50, "claude-sonnet-5-5": 30, "claude-haiku-5-5": 20, "claude-fable-5-2": 0]
        )
        var mixes = try ModelMixFixtures.allMixes()
        mixes["claude-main"] = try XCTUnwrap(ModelMixFixtures.accountMix(id: "claude-main", json: ModelMixFixtures.json, settings: trialSettings))
        let state = AppUsageState(result: .loaded(document), now: Fixtures.now, isRefreshing: false, notice: nil, accountMixes: mixes)

        var written = 0
        for language in [UILanguage.th, .en] {
            let prefix = language == .th ? "" : "en-"
            for dark in [false, true] {
                let view = MenuBarPopoverView(state: state, onRefresh: {}, onOpenApp: {}, onQuit: {}, startsRevealed: true, startsHovered: 0)
                let name = "\(prefix)popover-total-trial-\(dark ? "dark" : "light").png"
                let data = try XCTUnwrap(SnapshotRenderer.fitting(view, dark: dark, language: language), name)
                try data.write(to: outputDirectory.appendingPathComponent(name))
                XCTAssertGreaterThan(data.count, 1_000, name)
                written += 1
            }
        }
        XCTAssertEqual(written, 4)
    }

    /// The mix of every account of a document that has one.
    static func mixes(_ document: UsageDocument) -> [String: AccountModelMix] {
        var mixes: [String: AccountModelMix] = [:]
        for account in document.accounts {
            mixes[account.id] = ModelMix.accountMix(for: account, prices: document.modelPrices ?? [:], settings: .standard)
        }
        return mixes
    }
}
