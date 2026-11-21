import SwiftUI
import XCTest

/// The first-open motion and the skeleton: who plays it, when the content counts as loaded, and that no motion is left
/// running once everything has settled. The drawn result is checked in SkeletonSnapshotTests.
@MainActor
final class FirstOpenMotionTests: XCTestCase {
    // MARK: First appearance

    func testEachViewIdPlaysItsFirstAppearanceOnlyOnce() {
        let tracker = FirstOpenTracker()
        XCTAssertTrue(tracker.claim("window"))
        XCTAssertFalse(tracker.claim("window"), "a second appearance of the window must not play again")
        XCTAssertTrue(tracker.claim("popover"), "another view id has its own first appearance")
        XCTAssertFalse(tracker.claim("popover"))
    }

    func testANewTrackerPlaysAgain() {
        XCTAssertTrue(FirstOpenTracker().claim("window"), "a new launch (a new tracker) plays the first appearance again")
    }

    func testDesktopPopoverReplaysTheEntranceAfterEachFullDismissal() {
        let presentation = DesktopPopoverPresentation()
        for _ in 0..<3 {
            XCTAssertEqual(presentation.toggle(), .mount)
            XCTAssertFalse(presentation.isRevealed)
            presentation.didShow()
            XCTAssertTrue(presentation.isRevealed)
            XCTAssertEqual(presentation.toggle(), .dismiss)
            XCTAssertFalse(presentation.isRevealed)
            presentation.reset()
        }
    }

    func testSecondClickOnTheDesktopRingClosesEvenBeforeTheEntranceFinishes() {
        let presentation = DesktopPopoverPresentation()
        XCTAssertEqual(presentation.toggle(), .mount)
        XCTAssertEqual(presentation.toggle(), .dismiss)
        presentation.didShow()
        XCTAssertEqual(presentation.phase, .closing)
        XCTAssertFalse(presentation.isRevealed)
    }

    func testDesktopPopoverReversesDismissalImmediatelyOnRapidClick() {
        let presentation = DesktopPopoverPresentation()
        XCTAssertEqual(presentation.toggle(), .mount)
        presentation.didShow()
        XCTAssertEqual(presentation.toggle(), .dismiss)
        XCTAssertEqual(presentation.toggle(), .reverseDismissal)
        XCTAssertTrue(presentation.isRevealed)
        XCTAssertEqual(presentation.toggle(), .dismiss)
    }

    func testDesktopPopoverIgnoresStaleShowAndDismissesOutsideOnlyOnce() {
        let presentation = DesktopPopoverPresentation()
        XCTAssertEqual(presentation.toggle(), .mount)
        XCTAssertTrue(presentation.beginClosing())
        XCTAssertFalse(presentation.beginClosing())
        presentation.didShow()
        XCTAssertEqual(presentation.phase, .closing)
        presentation.reset()
        presentation.didShow()
        XCTAssertEqual(presentation.phase, .hidden)
    }

    func testTheIntroStyleIsSlideOnTheFirstAppearanceWithMotion() {
        XCTAssertEqual(IntroStyle.resolve(isFirst: true, reduceMotion: false, snapshot: false), .slide)
    }

    func testReduceMotionOnTheFirstAppearanceCrossFadesOnly() {
        XCTAssertEqual(IntroStyle.resolve(isFirst: true, reduceMotion: true, snapshot: false), .fade)
    }

    func testALaterAppearanceAndASnapshotShowAtOnce() {
        XCTAssertEqual(IntroStyle.resolve(isFirst: false, reduceMotion: false, snapshot: false), .none)
        XCTAssertEqual(IntroStyle.resolve(isFirst: true, reduceMotion: false, snapshot: true), .none)
        XCTAssertEqual(IntroStyle.resolve(isFirst: false, reduceMotion: true, snapshot: true), .none)
    }

    func testStillMotionForReduceMotionAndSnapshots() {
        XCTAssertEqual(MotionLevel.resolve(reduceMotion: true, snapshot: false), .still)
        XCTAssertEqual(MotionLevel.resolve(reduceMotion: false, snapshot: true), .still)
        XCTAssertEqual(MotionLevel.resolve(reduceMotion: false, snapshot: false), .live)
    }

    // MARK: Loading state

    func testTheFirstReadMovesLoadingToLoadedAndNothingMovesItBack() {
        var phase = LoadPhase.loading
        XCTAssertFalse(phase.isLoaded, "before the first read the content is a skeleton")
        phase.finishFirstRead()
        XCTAssertTrue(phase.isLoaded)
        phase.finishFirstRead()
        XCTAssertTrue(phase.isLoaded, "a later read or refresh never returns to loading")
    }

    func testAFileThatIsMissingStillCountsAsRead() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("first-open-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let model = makeDeferredModel(folder: folder, usage: folder.appendingPathComponent("missing.json"))
        for _ in 0..<300 where !model.loadPhase.isLoaded {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(model.loadPhase.isLoaded, "a read that finds no file still finishes, so the no-data view shows, not the skeleton")
        XCTAssertTrue(model.state.isLoaded)
    }

    func testTheModelShowsASkeletonUntilTheDeferredFirstReadFinishes() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("first-open-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let model = makeDeferredModel(folder: folder, usage: Fixtures.sampleURL)
        XCTAssertEqual(model.loadPhase, .loading)
        XCTAssertFalse(model.state.isLoaded)
        XCTAssertFalse(model.accountsPanel.isLoaded)
        for _ in 0..<300 where !model.loadPhase.isLoaded {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(model.state.isLoaded)
        XCTAssertTrue(model.accountsPanel.isLoaded)
        XCTAssertFalse(model.state.accounts.isEmpty, "the first read brings the sample's accounts in")
    }

    func testTheSynchronousInitIsLoadedAtOnce() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("first-open-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let model = UsageViewModel(
            fileURL: Fixtures.sampleURL,
            settingsURL: folder.appendingPathComponent("settings.json"),
            knownAccountsURL: folder.appendingPathComponent("known-accounts.json"),
            uid: getuid()
        )
        XCTAssertTrue(model.state.isLoaded)
        XCTAssertFalse(model.state.accounts.isEmpty)
    }

    private func makeDeferredModel(folder: URL, usage: URL) -> UsageViewModel {
        UsageViewModel(
            fileURL: usage,
            settingsURL: folder.appendingPathComponent("settings.json"),
            knownAccountsURL: folder.appendingPathComponent("known-accounts.json"),
            uid: getuid(),
            deferFirstRead: true
        )
    }

    // MARK: Skeleton shimmer

    func testTheShimmerRunsOnlyWhileLoadingWithLiveMotion() {
        XCTAssertTrue(SkeletonShimmer.isRunning(loading: true, motion: .live), "positive control: a skeleton on screen shimmers")
        XCTAssertFalse(SkeletonShimmer.isRunning(loading: false, motion: .live), "once loaded nothing shimmers")
        XCTAssertFalse(SkeletonShimmer.isRunning(loading: true, motion: .still), "Reduce Motion: a static grey skeleton")
    }

    /// Runs a spring to rest through the counted loop, as the views do. Afterwards no loop is counted and the spring does
    /// not move again: the frames stop when the motion has settled.
    func testNoMotionLoopStaysRunningOnceTheMotionHasSettled() async {
        XCTAssertEqual(MotionLoop.active, 0)
        let spring = LiquidSpring(position: 0, target: 0.7)
        var clock = Fixtures.now
        var sawLoopRunning = false
        var frames = 0
        await MotionLoop.run {
            clock = clock.addingTimeInterval(1.0 / 60)
            spring.advance(to: clock)
            frames += 1
            sawLoopRunning = sawLoopRunning || MotionLoop.active == 1
            return !spring.isSettled
        }
        XCTAssertTrue(sawLoopRunning, "positive control: while it moves, the loop is counted")
        XCTAssertTrue(spring.isSettled)
        XCTAssertLessThan(frames, 400, "the spring rests in a few seconds, not forever")
        XCTAssertEqual(MotionLoop.active, 0, "no loop is left running after the motion settles")

        let rest = spring.position
        spring.advance(to: clock.addingTimeInterval(10))
        XCTAssertEqual(spring.position, rest, "a settled spring does not move")
    }

    func testTheLiquidSpringOvershootsThenRestsOnItsTarget() {
        let spring = LiquidSpring(position: 0, target: 0.6)
        var clock = Fixtures.now
        var highest = 0.0
        for _ in 0..<240 {
            clock = clock.addingTimeInterval(1.0 / 60)
            highest = max(highest, spring.advance(to: clock))
        }
        XCTAssertGreaterThan(highest, 0.6, "a damped spring overshoots its target a little")
        XCTAssertTrue(spring.isSettled)
        XCTAssertEqual(spring.position, 0.6, accuracy: 0.001)
    }

    func testABarWithADelayStaysEmptyUntilItsStart() {
        let start = Fixtures.now
        let spring = LiquidSpring(position: 0, target: 0.5)
        spring.restart(from: 0, startAt: start.addingTimeInterval(1))
        XCTAssertEqual(spring.advance(to: start.addingTimeInterval(0.5)), 0)
        XCTAssertFalse(spring.isSettled)
    }

    // MARK: Numbers, typing and the slot icon

    func testARollingNumberCountsFromZeroToItsValue() {
        XCTAssertEqual(RollingPlan.value(from: 0, to: 58, elapsed: 0), 0)
        XCTAssertEqual(RollingPlan.value(from: 0, to: 58, elapsed: RollingPlan.duration), 58, accuracy: 0.0001)
        XCTAssertGreaterThan(RollingPlan.value(from: 0, to: 58, elapsed: RollingPlan.duration / 2), 29, "ease-out: more than half way at half time")
    }

    func testTypingShowsOneCharacterEach45MillisecondsAndAllOfIt() {
        XCTAssertEqual(TypingPlan.visibleCount(total: 5, elapsed: 0), 0)
        XCTAssertEqual(TypingPlan.visibleCount(total: 5, elapsed: 0.001), 1)
        XCTAssertEqual(TypingPlan.visibleCount(total: 5, elapsed: 0.1), 3)
        XCTAssertEqual(TypingPlan.visibleCount(total: 5, elapsed: 10), 5)
    }

    func testTheSlotIconLandsOnItsLetterWithASmallOvershoot() {
        let strip = SlotPlan.strip(letter: "C")
        XCTAssertEqual(strip.last, "C")
        XCTAssertEqual(SlotPlan.position(progress: 0, count: strip.count), 0, accuracy: 0.0001)
        XCTAssertEqual(SlotPlan.position(progress: 1, count: strip.count), Double(strip.count - 2), accuracy: 0.0001, "it ends on the brand letter")
        let overshoot = stride(from: 0.0, through: 1.0, by: 0.01).map { SlotPlan.position(progress: $0, count: strip.count) }.max() ?? 0
        XCTAssertGreaterThan(overshoot, Double(strip.count - 2), "a small overshoot past the letter")
        XCTAssertLessThan(overshoot, Double(strip.count - 1), "never past the copy of the letter at the end of the strip")
    }

    // MARK: Money tiles

    /// The tile's money counts up from the number behind its text, so the text and the number must agree.
    func testTheTileMoneyTextIsTheFormattedNumberThatCountsUp() throws {
        let document = try ModelMixFixtures.document()
        let account = try XCTUnwrap(document.accounts.first { $0.id == "claude-main" })
        let tiles = AppUsageInsights.usageTiles(account, mix: nil, shownPercents: nil, language: .en)
        XCTAssertFalse(tiles.isEmpty)
        let priced = tiles.filter { $0.costText != nil }
        XCTAssertFalse(priced.isEmpty, "the fixture has a cost for the period")
        for tile in priced {
            let value = try XCTUnwrap(tile.costValue)
            XCTAssertEqual(tile.costText, "~" + UsageFormat.moneyText(value))
        }
    }

    // MARK: Words

    func testTheLoadingWordIsSetInBothLanguages() {
        XCTAssertEqual(L10n.text(.loading, .th), "กำลังโหลด")
        XCTAssertEqual(L10n.text(.loading, .en), "Loading")
    }
}
