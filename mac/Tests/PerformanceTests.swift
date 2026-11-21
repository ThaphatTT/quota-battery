import Combine
import SwiftUI
import XCTest

/// Performance gates for the Mac app. Each gate fails when its cost is over the budget, so a slow change shows up as a
/// failing test.
///
/// Every gate compares a ratio, not a time. The thing measured (the subject) and a fixed reference workload are timed in
/// the same rounds, one after the other, using CPU time of this process. On a busy machine both slow down together, so
/// the ratio stays the same, while a real slowdown of the subject still moves it. The absolute times are printed for
/// information only; they are never compared with a budget. Each gate was checked with a positive control: doubling its
/// subject makes it fail (see the test matrix, C-rows).
@MainActor
final class PerformanceTests: XCTestCase {
    /// Ratio budgets. Each is about 1.6 times the median measured on a busy machine (load average 45 to 65), so a 2x
    /// slowdown fails and the noise between rounds does not. The measured values are written next to each budget.
    ///
    /// 1,000 slider steps against the reference workload. Measured 0.36 to 0.45 (median 0.40) on a busy machine.
    private static let sliderRatioBudget: Double = 0.63
    /// Decoding 20 accounts against the reference workload. Measured 0.11 to 0.13 (median 0.12) on a busy machine.
    private static let decodeRatioBudget: Double = 0.19
    /// One whole window draw against the reference view `ReferenceRows`, one column. Measured 10.6 to 11.9 (median 11.2) on
    /// a machine at load 19. The window no longer holds the Accounts list (it moved to the Settings window), so this is
    /// lower than before (it was 26 to 51).
    private static let windowRatioBudget: Double = 18.0
    /// The same window at the two-column width. Measured 9.9 to 12.2 (median 10.7) on the same machine.
    private static let windowTwoColumnRatioBudget: Double = 18.0
    /// The card gate: a card against `ReferenceRows` (measured 1.1 to 3.7) and against the whole window. The window ratio
    /// was 0.04 to 0.11 while the window held the Accounts list. It is 0.10 (quota) and 0.32 (Model mix) now that the window
    /// is smaller, so the budget is raised from 0.25 to 0.5. A card that doubles still fails (see the test matrix).
    private static let cardToReferenceBudget: Double = 6.0
    private static let cardToWindowBudget: Double = 0.5
    /// The skeleton window against the reference view. Measured 0.60 to 1.14 (median about 0.9) on the test machine. Doubling the skeleton measures about 1.6 (see the positive control), so this budget sits between the two.
    private static let skeletonRatioBudget: Double = 1.4
    /// Polls of unchanged files may publish at most this many changes in all (the minute may roll over once).
    private static let idlePublishBudget = 1

    private func render<V: View>(_ view: V) -> CGImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.cgImage
    }

    /// User and system CPU time used by this process so far, all threads together.
    private func processCPUSeconds() -> TimeInterval {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
        let system = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
        return user + system
    }

    /// CPU time per call of `work`, averaged over `iterations` calls.
    private func cpuPerCall(_ iterations: Int, _ work: () -> Void) -> TimeInterval {
        let start = processCPUSeconds()
        for _ in 0..<iterations { work() }
        return (processCPUSeconds() - start) / Double(iterations)
    }

    /// The middle value, or the mean of the two middle values for an even count.
    private static func median(of values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
    }

    /// The result of timing a subject against a reference in the same rounds.
    private struct RatioRounds {
        /// The median of the per-round ratios: the number a gate compares with its budget.
        let median: Double
        /// The ratio of each round, in order.
        let ratios: [Double]
        /// CPU seconds per call of the subject and of the reference, per round (printed as information only).
        let subjectSeconds: [TimeInterval]
        let referenceSeconds: [TimeInterval]

        var ratiosText: String { "[" + ratios.map { String(format: "%.2f", $0) }.joined(separator: ", ") + "]" }

        /// The per-round times, in ms, for the log and the failure message. Information only.
        var detailText: String {
            "subject ms \(Self.ms(subjectSeconds)), reference ms \(Self.ms(referenceSeconds))"
        }

        private static func ms(_ seconds: [TimeInterval]) -> String {
            "[" + seconds.map { String(format: "%.1f", $0 * 1000) }.joined(separator: ", ") + "]"
        }
    }

    /// Times `subject` and `reference` in the same rounds. One warm-up of each, then `rounds` rounds: in each round the
    /// subject runs `subjectIterations` calls and the reference `referenceIterations` calls, and the round's ratio is the
    /// subject's CPU time per call over the reference's.
    private func ratioRounds(
        rounds: Int = 5,
        subjectIterations: Int, subject: () -> Void,
        referenceIterations: Int, reference: () -> Void
    ) -> RatioRounds {
        subject()
        reference()
        var subjectSeconds: [TimeInterval] = [], referenceSeconds: [TimeInterval] = []
        for _ in 0..<rounds {
            subjectSeconds.append(cpuPerCall(subjectIterations, subject))
            referenceSeconds.append(cpuPerCall(referenceIterations, reference))
        }
        let ratios = zip(subjectSeconds, referenceSeconds).map { $0 / $1 }
        return RatioRounds(
            median: Self.median(of: ratios), ratios: ratios,
            subjectSeconds: subjectSeconds, referenceSeconds: referenceSeconds
        )
    }

    /// A fixed CPU workload that does not touch product code: square roots over a fixed range. It is the reference of the
    /// slider and decode gates. Its result is passed to `blackHole` so the loop is not removed.
    private static func referenceLoad() -> Double {
        var sum = 0.0
        for index in 0..<400_000 { sum += Double(index).squareRoot() }
        return sum
    }

    @inline(never)
    private func blackHole<T>(_ value: T) {}

    // MARK: Model mix

    func testThousandSliderStepsComputeWithinBudget() throws {
        let base = try ModelMixFixtures.actualPanel()
        let run = {
            var drag = ModelMixDrag(panel: base)
            for step in 0..<1000 {
                drag.move(row: step % 4, to: (step * 37) % 101)
            }
            XCTAssertNotNil(drag.savedPercent)
        }
        let rounds = ratioRounds(
            subjectIterations: 2, subject: run,
            referenceIterations: 4, reference: { blackHole(Self.referenceLoad()) }
        )
        print("PERF slider-1000-steps ratio_to_reference=\(rounds.median) rounds: \(rounds.detailText) ratios \(rounds.ratiosText)")
        XCTAssertLessThan(
            rounds.median, Self.sliderRatioBudget,
            "1,000 slider steps take \(String(format: "%.2f", rounds.median)) times the reference workload (median of 5 rounds, ratios \(rounds.ratiosText); \(rounds.detailText)), budget \(Self.sliderRatioBudget)"
        )
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()]) { run() }
    }

    /// Switching a card's tab draws the other tab. Each tab must stay cheap, so the slide starts without a stall. The slide
    /// itself and its 60 fps are not measured here: that is a named gap.
    ///
    /// The card is timed against `ReferenceRows` and against the whole window, in the same rounds. The gate compares the
    /// ratios (see the class comment). A real slowdown of the card moves both ratios, so it still fails.
    func testAccountCardInEachTabRendersWithinOneFrame() throws {
        let document = try ModelMixFixtures.document()
        let account = try XCTUnwrap(document.accounts.first { $0.id == "claude-main" })
        let mix = try XCTUnwrap(ModelMixFixtures.accountMix(id: "claude-main", json: ModelMixFixtures.json, settings: .standard))
        let window = try windowFixture()
        for tab in [CardTab.quota, .modelMix] {
            let card = {
                AppAccountCardView(account: account, now: Fixtures.now, mix: mix, snapshot: true, startsOn: tab)
                    .frame(width: 498)
                    .environment(\.uiLanguage, .th)
            }
            let windowView = windowContent(window, width: CardGridLayout.minimumWindowWidth)
            let toReference = ratioRounds(
                subjectIterations: 6, subject: { _ = render(card()) },
                referenceIterations: 6, reference: { _ = render(ReferenceRows()) }
            )
            let toWindow = ratioRounds(
                subjectIterations: 6, subject: { _ = render(card()) },
                referenceIterations: 2, reference: { _ = render(windowView) }
            )
            print("PERF account-card-\(tab) ratio_to_reference=\(toReference.median) ratio_to_window=\(toWindow.median) rounds: \(toReference.detailText), window ms \(toWindow.referenceSeconds.map { String(format: "%.1f", $0 * 1000) })")
            XCTAssertLessThan(
                toReference.median, Self.cardToReferenceBudget,
                "card (\(tab)) is \(String(format: "%.2f", toReference.median)) times the reference view (median of 5 rounds, ratios \(toReference.ratiosText); \(toReference.detailText)), budget \(String(format: "%.1f", Self.cardToReferenceBudget))"
            )
            XCTAssertLessThan(
                toWindow.median, Self.cardToWindowBudget,
                "card (\(tab)) is \(String(format: "%.2f", toWindow.median)) of the window draw (median of 5 rounds, ratios \(toWindow.ratiosText); \(toReference.detailText)), budget \(String(format: "%.2f", Self.cardToWindowBudget))"
            )
        }
    }

    // MARK: Window

    func testAppWindowContentRendersWithinOneFrame() throws {
        let window = try windowFixture()
        let view = windowContent(window, width: CardGridLayout.minimumWindowWidth)
        let rounds = ratioRounds(
            subjectIterations: 2, subject: { _ = render(view) },
            referenceIterations: 6, reference: { _ = render(ReferenceRows()) }
        )
        print("PERF window-content-render ratio_to_reference=\(rounds.median) rounds: \(rounds.detailText) ratios \(rounds.ratiosText)")
        XCTAssertLessThan(
            rounds.median, Self.windowRatioBudget,
            "one full window draw takes \(String(format: "%.2f", rounds.median)) times the reference view (median of 5 rounds, ratios \(rounds.ratiosText); \(rounds.detailText)), budget \(Self.windowRatioBudget)"
        )
    }

    /// The same window at the width where the cards sit in two columns. It is a gate of its own, because the two-column
    /// grid lays out every card side by side in one pass.
    func testAppWindowContentAtTwoColumnsRendersWithinOneFrame() throws {
        let window = try windowFixture()
        let view = windowContent(window, width: CardGridLayout.twoColumnWidth)
        let rounds = ratioRounds(
            subjectIterations: 2, subject: { _ = render(view) },
            referenceIterations: 6, reference: { _ = render(ReferenceRows()) }
        )
        print("PERF window-two-columns-render ratio_to_reference=\(rounds.median) rounds: \(rounds.detailText) ratios \(rounds.ratiosText)")
        XCTAssertLessThan(
            rounds.median, Self.windowTwoColumnRatioBudget,
            "one full window draw at two columns takes \(String(format: "%.2f", rounds.median)) times the reference view (median of 5 rounds, ratios \(rounds.ratiosText); \(rounds.detailText)), budget \(Self.windowTwoColumnRatioBudget)"
        )
    }

    /// The skeleton window (two grey cards, before the first read has finished) against the same reference view. It is
    /// the first thing the window draws, so it must not cost more than the loaded window.
    func testSkeletonWindowRendersWithinOneFrame() throws {
        let loading = AppUsageState(result: .missing, now: Fixtures.now, isRefreshing: false, notice: nil, isLoaded: false)
        let view = ContentView(
            state: loading,
            modelMixActions: ModelMixActions(),
            onRefresh: {},
            onOpenSettings: {},
            onOpenLogs: {},
            snapshot: true
        )
        .frame(width: CardGridLayout.minimumWindowWidth, height: 900)
        .environment(\.uiLanguage, .th)
        .environment(\.colorScheme, .light)
        let rounds = ratioRounds(
            subjectIterations: 6, subject: { _ = render(view) },
            referenceIterations: 6, reference: { _ = render(ReferenceRows()) }
        )
        print("PERF skeleton-window-render ratio_to_reference=\(rounds.median) rounds: \(rounds.detailText) ratios \(rounds.ratiosText)")
        XCTAssertLessThan(
            rounds.median, Self.skeletonRatioBudget,
            "the skeleton window takes \(String(format: "%.2f", rounds.median)) times the reference view (median of 5 rounds, ratios \(rounds.ratiosText); \(rounds.detailText)), budget \(Self.skeletonRatioBudget)"
        )
    }

    /// Positive control for the skeleton gate: two skeleton windows stacked (twice the work) must be over the budget. If
    /// they are not, the gate cannot tell a doubled skeleton from a normal one.
    func testDoublingTheSkeletonFailsTheGate() throws {
        let loading = AppUsageState(result: .missing, now: Fixtures.now, isRefreshing: false, notice: nil, isLoaded: false)
        let one = ContentView(
            state: loading,
            modelMixActions: ModelMixActions(),
            onRefresh: {},
            onOpenSettings: {},
            onOpenLogs: {},
            snapshot: true
        )
        .frame(width: CardGridLayout.minimumWindowWidth, height: 900)
        .environment(\.uiLanguage, .th)
        .environment(\.colorScheme, .light)
        let doubled = VStack(spacing: 0) { one; one }
        let rounds = ratioRounds(
            subjectIterations: 6, subject: { _ = render(doubled) },
            referenceIterations: 6, reference: { _ = render(ReferenceRows()) }
        )
        print("PERF skeleton-window-doubled ratio_to_reference=\(rounds.median) rounds: \(rounds.detailText) ratios \(rounds.ratiosText)")
        XCTAssertGreaterThan(
            rounds.median, Self.skeletonRatioBudget,
            "positive control: a doubled skeleton must fail the gate, but it measured \(String(format: "%.2f", rounds.median)) against budget \(Self.skeletonRatioBudget)"
        )
    }

    // MARK: Files

    func testDecodingTwentyAccountsWithinBudget() throws {
        let data = Data(Self.twentyAccountsJSON().utf8)
        guard case .loaded(let document) = UsageLoader.decode(data) else {
            return XCTFail("the 20-account fixture does not decode")
        }
        XCTAssertEqual(document.accounts.count, 20)
        let rounds = ratioRounds(
            subjectIterations: 10, subject: { blackHole(UsageLoader.decode(data)) },
            referenceIterations: 4, reference: { blackHole(Self.referenceLoad()) }
        )
        print("PERF decode-20-accounts ratio_to_reference=\(rounds.median) rounds: \(rounds.detailText) ratios \(rounds.ratiosText)")
        XCTAssertLessThan(
            rounds.median, Self.decodeRatioBudget,
            "decoding 20 accounts takes \(String(format: "%.2f", rounds.median)) times the reference workload (median of 5 rounds, ratios \(rounds.ratiosText); \(rounds.detailText)), budget \(Self.decodeRatioBudget)"
        )
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()]) {
            _ = UsageLoader.decode(data)
        }
    }

    /// The poll runs every 60 s and the folder watch runs on each write. When nothing changed, the window must not be
    /// told about anything.
    func testRepeatedPollsWithNoChangePublishAtMostOnce() throws {
        let folder = try makeFolder()
        let usageURL = folder.appendingPathComponent("usage.json")
        try Data(contentsOf: Fixtures.sampleURL).write(to: usageURL)
        let model = UsageViewModel(
            fileURL: usageURL,
            settingsURL: folder.appendingPathComponent("settings.json"),
            knownAccountsURL: folder.appendingPathComponent("known-accounts.json"),
            uid: getuid()
        )
        var changes = 0
        let subscription = model.objectWillChange.sink { changes += 1 }
        defer { subscription.cancel() }

        for _ in 0..<100 { model.reload() }
        print("PERF idle-polls-100 publishes=\(changes)")
        XCTAssertLessThanOrEqual(changes, Self.idlePublishBudget, "100 polls with no change published \(changes) times")
    }

    // MARK: Helpers

    /// The data the app window draws: twenty accounts with their rows and mixes. Built once per test.
    private struct WindowFixture {
        let state: AppUsageState
    }

    private func windowFixture() throws -> WindowFixture {
        let document = try Fixtures.document(Self.twentyAccountsJSON())
        var accountMixes: [String: AccountModelMix] = [:]
        for account in document.accounts {
            accountMixes[account.id] = ModelMix.accountMix(for: account, prices: document.modelPrices ?? [:], settings: .standard)
        }
        let state = AppUsageState(
            result: .loaded(document), now: Fixtures.now, isRefreshing: false, notice: nil,
            accountMixes: accountMixes
        )
        return WindowFixture(state: state)
    }

    /// The window at a given content width. The height is fixed, so every run draws the same amount of the grid.
    private func windowContent(_ window: WindowFixture, width: CGFloat) -> some View {
        ContentView(
            state: window.state,
            modelMixActions: ModelMixActions(),
            onRefresh: {},
            onOpenSettings: {},
            onOpenLogs: {},
            snapshot: true
        )
        .frame(width: width, height: 900)
        .environment(\.uiLanguage, .th)
        .environment(\.colorScheme, .light)
    }

    /// A fixed reference view for the card and window gates: twelve rows of text and shapes, the same in every run. It is
    /// not product code, so a change in the app never changes it, only the machine does.
    private struct ReferenceRows: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(0..<12, id: \.self) { index in
                    HStack(spacing: 8) {
                        Circle().fill(Color.blue).frame(width: 8, height: 8)
                        Text("Reference row \(index)")
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text("\(index * 7)%")
                            .font(.system(size: 13))
                            .monospacedDigit()
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.1)))
                }
            }
            .frame(width: 498, alignment: .leading)
        }
    }

    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("perf-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder
    }

    /// A usage.json with 20 accounts (Claude and ChatGPT, two limits each), generated in code.
    static func twentyAccountsJSON() -> String {
        let accounts = (0..<20).map { index -> String in
            let provider = index % 2 == 0 ? "claude" : "codex"
            let used = (index * 37) % 100
            return """
            {"id": "\(provider)-\(index)", "provider": "\(provider)", "label": "Account \(index)", "plan": "Max",
             "status": "ok", "updated_at": "2026-11-19T04:30:00Z",
             "limits": [
               {"key": "five_hour", "window_seconds": 18000, "used_percent": \(used), "resets_at": "2026-11-19T06:40:00Z"},
               {"key": "seven_day", "window_seconds": 604800, "used_percent": \(100 - used), "resets_at": "2026-11-24T02:00:00Z"}
             ]}
            """
        }
        return "{\"schema\": 1, \"generated_at\": \"2026-11-19T04:30:00Z\", \"accounts\": [\(accounts.joined(separator: ","))]}"
    }
}
