import SwiftUI
import XCTest

/// Renders the skeleton of the window, the popover, the Accounts list and the Model mix tab in Thai and English, light and
/// dark, to mac/build/snapshots/ (English names start with "en-", as the other snapshots do). Reduce Motion is on in a
/// snapshot, so the skeleton is drawn static: the shimmer is checked by the unit tests, not by a picture.
@MainActor
final class SkeletonSnapshotTests: XCTestCase {
    private static let loading = AppUsageState(
        result: .missing, now: Fixtures.now, isRefreshing: false, notice: nil, isLoaded: false
    )

    func testRenderTheSkeletonsInThaiAndEnglishInLightAndDark() throws {
        let outputDirectory = Fixtures.macFolder.appendingPathComponent("build/snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        var written = 0
        for language in [UILanguage.th, .en] {
            let prefix = language == .th ? "" : "en-"
            for dark in [false, true] {
                let suffix = dark ? "dark" : "light"
                let window = ContentView(
                    state: Self.loading,
                    modelMixActions: ModelMixActions(),
                    onRefresh: {},
                    onOpenSettings: {},
                    onOpenLogs: {},
                    snapshot: true
                )
                let popover = MenuBarPopoverView(
                    state: Self.loading,
                    onRefresh: {},
                    onOpenApp: {},
                    onQuit: {},
                    startsRevealed: true
                )
                let accounts = AppAccountsSection(
                    state: AccountsPanelState(rows: [], sort: .manual, notice: nil, isRefreshing: false, isLoaded: false),
                    actions: AccountActions(),
                    snapshot: true
                )
                .frame(width: 540)
                let modelMix = SkeletonLoadingView(label: L10n.text(.loading, language), motion: .still) {
                    SkeletonModelMix()
                }
                .frame(width: 498)

                let renders: [(name: String, data: Data?)] = [
                    ("skeleton-window-\(suffix).png", SnapshotRenderer.png(window, size: CGSize(width: 530, height: 560), dark: dark, language: language)),
                    ("skeleton-popover-\(suffix).png", SnapshotRenderer.fitting(popover, dark: dark, language: language)),
                    ("skeleton-accounts-\(suffix).png", SnapshotRenderer.fitting(accounts, dark: dark, language: language)),
                    ("skeleton-modelmix-\(suffix).png", SnapshotRenderer.fitting(modelMix, dark: dark, language: language)),
                ]
                for render in renders {
                    let name = prefix + render.name
                    let data = try XCTUnwrap(render.data, "render failed: \(name)")
                    try data.write(to: outputDirectory.appendingPathComponent(name))
                    XCTAssertGreaterThan(data.count, 1_000, name)
                    written += 1
                }
            }
        }
        XCTAssertEqual(written, 16)
    }
}
