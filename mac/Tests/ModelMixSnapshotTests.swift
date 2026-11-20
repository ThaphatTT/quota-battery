import SwiftUI
import XCTest

/// Renders the popover line to PNG files in mac/build/snapshots/ (gitignored), in Thai and English, light and dark. The
/// names start with "model-mix-". The card tabs are in AccountCardSnapshotTests. The tests also check that the popover
/// line is only there when the data is.
@MainActor
final class ModelMixSnapshotTests: XCTestCase {
    private var outputDirectory: URL {
        Fixtures.macFolder.appendingPathComponent("build/snapshots", isDirectory: true)
    }

    func testRenderThePopoverLineInThaiAndEnglishInLightAndDark() throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let state = AppUsageState(
            result: .loaded(try ModelMixFixtures.document()),
            now: Fixtures.now,
            isRefreshing: false,
            notice: nil,
            accountMixes: try ModelMixFixtures.allMixes()
        )

        var written = 0
        for language in [UILanguage.th, .en] {
            let prefix = language == .th ? "" : "en-"
            for dark in [false, true] {
                let view = MenuBarPopoverView(
                    state: state,
                    onRefresh: {},
                    onOpenApp: {},
                    onQuit: {},
                    startsRevealed: true,
                    startsHovered: 0
                )
                let name = "model-mix-\(prefix)popover-\(dark ? "dark" : "light").png"
                let data = try XCTUnwrap(SnapshotRenderer.fitting(view, dark: dark, language: language), name)
                try data.write(to: outputDirectory.appendingPathComponent(name))
                XCTAssertGreaterThan(data.count, 1_000, name)
                written += 1
            }
        }
        XCTAssertEqual(written, 4)
    }

    /// The popover line adds height only when the model data exists. Without it (an old usage.json) the popover is
    /// the same as before.
    func testThePopoverLineIsHiddenWhenTheModelDataIsMissing() throws {
        let document = try Fixtures.document(ModelMixFixtures.oldJSON)
        func popover(_ mix: [String: AccountModelMix]) -> MenuBarPopoverView {
            MenuBarPopoverView(
                state: AppUsageState(result: .loaded(document), now: Fixtures.now, isRefreshing: false, notice: nil, accountMixes: mix),
                onRefresh: {},
                onOpenApp: {},
                onQuit: {},
                startsRevealed: true
            )
        }
        let without = LayoutFit.height(popover([:]), width: 300, language: .en, dark: false)
        let with = LayoutFit.height(popover(try ModelMixFixtures.allMixes()), width: 300, language: .en, dark: false)
        XCTAssertGreaterThan(with, without)
    }
}
