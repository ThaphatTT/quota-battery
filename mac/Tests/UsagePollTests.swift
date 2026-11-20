import Combine
import XCTest

/// The poll, the folder watch and the slider drag of the window model. Each test uses its own folder.
@MainActor
final class UsagePollTests: XCTestCase {
    private func makeModel(writes: @escaping (String, ModelMixSettings, URL) throws -> Void = { try AppSettingsStore.saveModelMix($1, accountID: $0, at: $2) }) throws -> (UsageViewModel, URL) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("poll-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        try ModelMixFixtures.json.write(to: folder.appendingPathComponent("usage.json"), atomically: true, encoding: .utf8)
        let model = UsageViewModel(
            fileURL: folder.appendingPathComponent("usage.json"),
            settingsURL: folder.appendingPathComponent("settings.json"),
            knownAccountsURL: folder.appendingPathComponent("known-accounts.json"),
            uid: getuid(),
            writeModelMix: writes
        )
        return (model, folder)
    }

    /// A drag of 1,000 steps shows the moves without publishing anything to the window, and saves once at the end.
    func testADragOfAThousandStepsPublishesNothingAndSavesOnce() throws {
        var writes = 0
        let (model, _) = try makeModel { _, _, _ in writes += 1 }
        var publishes = 0
        let subscription = model.objectWillChange.sink { publishes += 1 }
        defer { subscription.cancel() }

        var drag = ModelMixDrag(panel: try XCTUnwrap(model.state.accountMixes["claude-main"]?.shown))
        for step in 0..<1000 {
            drag.move(row: step % 4, to: (step * 37) % 101)
        }
        XCTAssertEqual(publishes, 0, "the moves of a drag must not change the model")
        XCTAssertEqual(writes, 0, "nothing is saved while the slider moves")

        model.commitModelMixPercent("claude-main", try XCTUnwrap(drag.savedPercent))
        XCTAssertEqual(writes, 1, "the drag is saved once when it ends")
        XCTAssertEqual(publishes, 1)
    }

    /// A drag that leaves the shares as they were saves nothing.
    func testADragThatLeavesTheSharesAsTheyWereSavesNothing() throws {
        var writes = 0
        let (model, _) = try makeModel { _, _, _ in writes += 1 }
        var drag = ModelMixDrag(panel: try XCTUnwrap(model.state.accountMixes["claude-main"]?.shown))
        drag.move(row: 0, to: drag.panel.percents[0])
        XCTAssertNil(drag.savedPercent)
        if let percent = drag.savedPercent { model.commitModelMixPercent("claude-main", percent) }
        XCTAssertEqual(writes, 0)
    }

    /// A poll that finds nothing new publishes nothing (the minute can turn over once while the test runs).
    func testAPollWithNoChangeDoesNotPublish() throws {
        let (model, _) = try makeModel()
        var publishes = 0
        let subscription = model.objectWillChange.sink { publishes += 1 }
        defer { subscription.cancel() }
        for _ in 0..<20 { model.reload() }
        XCTAssertLessThanOrEqual(publishes, 1)
    }

    /// The gate must never hide a real change: a new usage.json is read at the next poll.
    func testAChangedUsageFileIsReadAtTheNextPoll() throws {
        let (model, folder) = try makeModel()
        XCTAssertEqual(model.result.document?.accounts.count, 3)
        let richer = ModelMixFixtures.json.replacingOccurrences(
            of: "\"accounts\": [",
            with: "\"accounts\": [{\"id\": \"claude-extra\", \"provider\": \"claude\", \"label\": \"Extra\", \"plan\": \"Pro\", \"status\": \"ok\"},"
        )
        try richer.write(to: folder.appendingPathComponent("usage.json"), atomically: true, encoding: .utf8)
        model.reload()
        XCTAssertEqual(model.result.document?.accounts.count, 4)
    }

    /// Changing one card's mix publishes one change and saves one entry, for that account. The other card's inputs stay
    /// equal, so the window draws only the card that changed (see `AppAccountCardView` and `ContentView`).
    func testChangingOneCardsMixPublishesOnceAndLeavesTheOthersEqual() throws {
        var saved: [String] = []
        let (model, _) = try makeModel { id, _, _ in saved.append(id) }
        let before = model.state.accountMixes
        let other = try XCTUnwrap(model.result.document?.accounts.first { $0.id == "claude-claude-2" })
        let otherBefore = AppAccountCardView(account: other, now: Fixtures.now, mix: before["claude-claude-2"])

        var publishes = 0
        let subscription = model.objectWillChange.sink { publishes += 1 }
        defer { subscription.cancel() }
        model.setModelMixPercent("claude-main", "claude-opus-5-5", to: 80)

        XCTAssertEqual(publishes, 1, "one change for the window")
        XCTAssertEqual(saved, ["claude-main"], "one save, for the card that changed")
        let after = model.state.accountMixes
        XCTAssertEqual(after["claude-claude-2"], before["claude-claude-2"], "the other card's mix is unchanged")
        XCTAssertNotEqual(after["claude-main"], before["claude-main"])
        let otherAfter = AppAccountCardView(account: other, now: Fixtures.now, mix: after["claude-claude-2"])
        XCTAssertTrue(otherBefore == otherAfter, "the other card's inputs are equal, so SwiftUI skips its body")
    }

    /// Saving the same what-if twice saves it once.
    func testAnUnchangedMixSaysNothing() throws {
        var saved = 0
        let (model, _) = try makeModel { _, _, _ in saved += 1 }
        let shares: [String: Int] = ["claude-opus-5-5": 50, "claude-sonnet-5-5": 30, "claude-haiku-5-5": 20, "claude-fable-5-2": 0]
        model.commitModelMixPercent("claude-main", shares)
        model.commitModelMixPercent("claude-main", shares)
        XCTAssertEqual(saved, 1)
    }
}
