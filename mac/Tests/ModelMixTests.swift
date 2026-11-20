import Foundation
import XCTest

/// Unit tests for the model mix: the maths, the per-account panels, the ChatGPT (Codex) mix with the long-context rule,
/// the settings file (per account, with the old single value migrated), and the tile values. Expected values are worked
/// out by hand in the comments, from the numbers in ModelMixFixtures.
final class ModelMixTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("model-mix-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private var settingsURL: URL { folder.appendingPathComponent("settings.json") }

    private func account(_ id: String, in json: String = ModelMixFixtures.json) throws -> UsageAccount {
        let document = try Fixtures.document(json)
        return try XCTUnwrap(document.accounts.first { $0.id == id })
    }

    private func writeSettings(_ text: String) throws {
        try Data(text.utf8).write(to: settingsURL)
    }

    // MARK: Largest-remainder rounding

    func testRoundingSumsToTheTotalAndGivesTheExtraToTheEarliestTie() {
        // 1/3 each is 33.33: 33 + 33 + 33 = 99, and the one left goes to the first position.
        XCTAssertEqual(ModelMixMath.largestRemainder([1, 1, 1], total: 100), [34, 33, 33])
    }

    func testRoundingGivesTheExtraUnitToTheLargestFraction() {
        // 0.5 / 0.25 / 0.25 of 100 is 50, 25, 25 exactly: nothing left over.
        XCTAssertEqual(ModelMixMath.largestRemainder([2, 1, 1], total: 100), [50, 25, 25])
        // 70.59 / 29.41 floors to 70 / 29 = 99. The larger fraction (0.59) takes the last unit.
        XCTAssertEqual(ModelMixMath.largestRemainder([12, 5], total: 100), [71, 29])
    }

    func testRoundingOfAllZeroOrNegativeValuesIsAllZero() {
        XCTAssertEqual(ModelMixMath.largestRemainder([0, 0, 0], total: 100), [0, 0, 0])
        XCTAssertEqual(ModelMixMath.largestRemainder([-5, 0, 0], total: 100), [0, 0, 0])
        XCTAssertEqual(ModelMixMath.largestRemainder([], total: 100), [])
    }

    func testRealSharesOfTheFixtureAreOpus33SonnetSixteenHaiku51Fable0() throws {
        // Opus 1.3M, Sonnet 0.65M, Haiku 2.0M, Fable 0 (input + output + cache writes). Total 3.95M.
        // 32.91 / 16.46 / 50.63 / 0: floors 32 + 16 + 50 = 98, and the two largest fractions (opus 0.91, haiku 0.63) take the rest.
        let shares = try XCTUnwrap(ModelMixMath.realShares([1_300_000, 650_000, 2_000_000, 0]))
        XCTAssertEqual(shares, [33, 16, 51, 0])
        XCTAssertEqual(shares.reduce(0, +), 100)
    }

    func testRealSharesOfNoTokensIsNil() {
        XCTAssertNil(ModelMixMath.realShares([0, 0, 0, 0]))
    }

    // MARK: Rescale when one slider moves

    func testMovingOneSliderRescalesTheOthersInProportion() {
        // Sonnet 16 and Haiku 51 share the 76 that is left in the ratio 16 : 51 (23.88 and 76.12): 24 and 76 after rounding.
        // Opus moves from 33 to 0, so the sum is 0 + 24 + 76 + 0.
        XCTAssertEqual(ModelMixMath.rescale([33, 16, 51, 0], index: 0, to: 0), [0, 24, 76, 0])
    }

    func testMovingOneSliderUpSharesTheRestInProportion() {
        // Opus to 60: Sonnet and Haiku share the 40 in the ratio 16 : 51 (9.55 and 30.45), which rounds to 10 and 30.
        XCTAssertEqual(ModelMixMath.rescale([33, 16, 51, 0], index: 0, to: 60), [60, 10, 30, 0])
    }

    func testOneSliderToHundredLeavesEveryOtherAtZero() {
        XCTAssertEqual(ModelMixMath.rescale([33, 16, 51, 0], index: 2, to: 100), [0, 0, 100, 0])
    }

    func testOneSliderToZeroGivesTheWholeTotalToTheOthers() {
        let result = ModelMixMath.rescale([33, 16, 51, 0], index: 2, to: 0)
        XCTAssertEqual(result[2], 0)
        XCTAssertEqual(result.reduce(0, +), 100)
        XCTAssertTrue(result.allSatisfy { $0 >= 0 })
    }

    func testAllZeroDataSharesTheRestEvenly() {
        // Every other row had 0, so there is no ratio: 60 is split over three rows as 20 each.
        XCTAssertEqual(ModelMixMath.rescale([100, 0, 0, 0], index: 0, to: 40), [40, 20, 20, 20])
        // 70 over three rows is 23.33 each. The earliest gets the spare unit: 24, 23, 23.
        XCTAssertEqual(ModelMixMath.rescale([0, 0, 0, 0], index: 1, to: 30), [24, 30, 23, 23])
    }

    func testRescaleClampsTheValueAndKeepsTheSum() {
        XCTAssertEqual(ModelMixMath.rescale([33, 16, 51, 0], index: 0, to: 150), [100, 0, 0, 0])
        XCTAssertEqual(ModelMixMath.rescale([33, 16, 51, 0], index: 0, to: -20), [0, 24, 76, 0])
    }

    func testRescaleWithAnOutOfRangeIndexChangesNothing() {
        XCTAssertEqual(ModelMixMath.rescale([33, 16, 51, 0], index: 9, to: 50), [33, 16, 51, 0])
    }

    func testNormalizedKeepsA100AndScalesAnyOtherTotal() {
        XCTAssertEqual(ModelMixMath.normalized([50, 30, 20, 0]), [50, 30, 20, 0])
        XCTAssertEqual(ModelMixMath.normalized([10, 10, 0, 0]), [50, 50, 0, 0])
        XCTAssertNil(ModelMixMath.normalized([0, 0, 0, 0]))
        XCTAssertEqual(ModelMixMath.normalized([-4, 40, 60, 0]), [0, 40, 60, 0], "a negative value counts as 0")
    }

    // MARK: Cost

    func testCostOfEachRowOfTheRealMixMatchesTheHandCalculation() throws {
        // All tokens at 100%: Opus 19.80, Sonnet 9.90, Haiku 0.51, Fable 0. The real mix takes 33%, 16%, 51% and 0%.
        // Opus 0.33 x 19.80 = 6.534, Sonnet 0.16 x 9.90 = 1.584, Haiku 0.51 x 0.51 = 0.2601. Total 8.3781.
        let panel = try ModelMixFixtures.actualPanel()
        XCTAssertEqual(panel.rows.map(\.cost)[0], 6.534, accuracy: 1e-9)
        XCTAssertEqual(panel.rows.map(\.cost)[1], 1.584, accuracy: 1e-9)
        XCTAssertEqual(panel.rows.map(\.cost)[2], 0.2601, accuracy: 1e-9)
        XCTAssertEqual(panel.rows.map(\.cost)[3], 0, accuracy: 1e-9)
        XCTAssertEqual(panel.totalCost, 8.3781, accuracy: 1e-9)
        XCTAssertEqual(UsageFormat.moneyText(panel.totalCost), "$8.38")
    }

    func testCostOfAWhatIfMixMatchesTheHandCalculation() throws {
        // Opus 50%, Sonnet 30%, Haiku 20%, Fable 0%: 0.5 x 19.80 = 9.90, 0.3 x 9.90 = 2.97, 0.2 x 0.51 = 0.102. Total 12.972.
        let panel = try ModelMixFixtures.whatIfPanel()
        XCTAssertFalse(panel.isActual)
        XCTAssertEqual(panel.percents, [50, 30, 20, 0])
        XCTAssertEqual(panel.rows.map(\.cost)[0], 9.90, accuracy: 1e-9)
        XCTAssertEqual(panel.rows.map(\.cost)[1], 2.97, accuracy: 1e-9)
        XCTAssertEqual(panel.rows.map(\.cost)[2], 0.102, accuracy: 1e-9)
        XCTAssertEqual(panel.totalCost, 12.972, accuracy: 1e-9)
    }

    func testCostOfOneModelTakingEverythingUsesItsOwnPricesForEveryKind() {
        let totals = FamilyTokens(input: 3_600_000, output: 150_000, cacheWrite5m: 200_000, cacheWrite1h: 100_000, cacheRead: 3_000_000)
        let opus = ModelPrice(family: "opus", label: "Opus 5.5", input: 4, cacheWrite5m: 5, cacheWrite1h: 8, cacheRead: 0.2, output: 20)
        // 3.6M x 4 + 150k x 20 + 200k x 5 + 100k x 8 + 3M x 0.2 = 14.4M + 3.0M + 1.0M + 0.8M + 0.6M = 19.8M, per 1M = 19.80.
        XCTAssertEqual(ModelMixMath.cost(percent: 100, price: opus, totals: totals), 19.80, accuracy: 1e-9)
        XCTAssertEqual(ModelMixMath.cost(percent: 0, price: opus, totals: totals), 0, accuracy: 1e-9)
    }

    // MARK: Panels per account

    func testTheDefaultPanelHasTheDefaultOrderAndTheRealMix() throws {
        let panel = try ModelMixFixtures.actualPanel()
        XCTAssertEqual(panel.rows.map(\.id), ModelMix.defaultOrder)
        XCTAssertEqual(panel.rows.map(\.label), ["Opus 5.5", "Sonnet 5.5", "Haiku 5.5", "Fable 5.2"])
        XCTAssertEqual(panel.percents, [33, 16, 51, 0])
        XCTAssertTrue(panel.isActual)
        XCTAssertEqual(panel.mainModelLabel, "Opus 5.5")
    }

    func testEachClaudeAccountHasItsOwnMixFromItsOwnFamilies() throws {
        // claude-claude-2 has only Sonnet input (1.0M): its real mix is Sonnet 100, and the others 0.
        // Its cost at 100% is 1.0M x $2.00 = $2.00. claude-main's numbers are not used.
        let mix = try XCTUnwrap(ModelMixFixtures.accountMix(id: "claude-claude-2", json: ModelMixFixtures.json, settings: .standard))
        XCTAssertEqual(mix.shown.percents, [0, 100, 0, 0])
        XCTAssertTrue(mix.shown.isActual)
        XCTAssertEqual(mix.month.panel(percents: [0, 100, 0, 0]).totalCost, 2.0, accuracy: 1e-9)
        XCTAssertEqual(mix.provider, "claude")
    }

    func testAnAccountWithoutFamilyDataOrPricesHasNoMix() throws {
        let noPrices = ModelMixFixtures.json.replacingOccurrences(of: "\"model_prices\"", with: "\"model_prices_old\"")
        XCTAssertNil(try ModelMixFixtures.accountMix(id: "claude-main", json: noPrices, settings: .standard))

        let noTokens = """
        {"schema": 1,
         "model_prices": {"claude-opus-5-5": {"family": "opus", "label": "Opus 5.5", "input": 4.0,
           "cache_write_5m": 5.0, "cache_write_1h": 8.0, "cache_read": 0.2, "output": 20.0}},
         "accounts": [{"id": "claude-main", "provider": "claude", "status": "ok",
           "usage": {"month": {"tokens": 0, "by_family": {"opus": {"input": 0, "output": 0,
             "cache_write_5m": 0, "cache_write_1h": 0, "cache_read": 0}}}}}]}
        """
        XCTAssertNil(try ModelMixFixtures.accountMix(id: "claude-main", json: noTokens, settings: .standard),
                     "no tokens in the four families hides the tab")
        XCTAssertNil(try ModelMixFixtures.accountMix(id: "claude-main", json: ModelMixFixtures.oldJSON, settings: .standard))
    }

    func testAnAccountOfAnotherProviderHasNoClaudeMix() throws {
        let other = ModelMixFixtures.json.replacingOccurrences(of: "\"provider\": \"claude\"", with: "\"provider\": \"other\"")
        XCTAssertNil(try ModelMixFixtures.accountMix(id: "claude-main", json: other, settings: .standard))
    }

    func testTheOrderFromSettingsSetsTheRowsAndTheMainModel() throws {
        let settings = ModelMixSettings(
            order: ["claude-haiku-5-5", "claude-opus-5-5", "claude-sonnet-5-5", "claude-fable-5-2"],
            percent: nil
        )
        let panel = try ModelMixFixtures.actualPanel(settings: settings)
        XCTAssertEqual(panel.rows.map(\.id), settings.order)
        XCTAssertEqual(panel.mainModelLabel, "Haiku 5.5")
        XCTAssertEqual(panel.percents, [51, 33, 16, 0], "the real shares stay with their model")
    }

    func testAnOrderMissingAModelOrHavingAnUnknownOneStillListsEveryModel() throws {
        let settings = ModelMixSettings(order: ["claude-sonnet-5-5", "claude-unknown-9"], percent: nil)
        let panel = try ModelMixFixtures.actualPanel(settings: settings)
        XCTAssertEqual(panel.rows.map(\.id), [
            "claude-sonnet-5-5", "claude-fable-5-2", "claude-haiku-5-5", "claude-opus-5-5",
        ])
    }

    func testAStoredWhatIfMixIsUsedAndIsATrial() throws {
        let settings = ModelMixSettings(
            order: ModelMix.defaultOrder,
            percent: ["claude-opus-5-5": 50, "claude-sonnet-5-5": 50, "claude-haiku-5-5": 0, "claude-fable-5-2": 0]
        )
        let panel = try ModelMixFixtures.actualPanel(settings: settings)
        XCTAssertFalse(panel.isActual)
        XCTAssertEqual(panel.percents, [50, 50, 0, 0])
        // 0.5 x 19.80 = 9.90 and 0.5 x 9.90 = 4.95: 14.85 in all.
        XCTAssertEqual(panel.totalCost, 14.85, accuracy: 1e-9)
    }

    func testAStoredMixEqualToTheRealOneIsNotATrial() throws {
        let settings = ModelMixSettings(order: ModelMix.defaultOrder, percent: ["claude-opus-5-5": 33, "claude-sonnet-5-5": 16, "claude-haiku-5-5": 51, "claude-fable-5-2": 0])
        let panel = try ModelMixFixtures.actualPanel(settings: settings)
        XCTAssertTrue(panel.isActual, "the tiles show no trial when the shares are the real ones")
    }

    func testAStoredMixThatDoesNotSumToHundredIsScaled() throws {
        let settings = ModelMixSettings(order: ModelMix.defaultOrder, percent: ["claude-opus-5-5": 10, "claude-sonnet-5-5": 10])
        let panel = try ModelMixFixtures.actualPanel(settings: settings)
        XCTAssertEqual(panel.percents, [50, 50, 0, 0])
    }

    func testAStoredMixOfZerosFallsBackToTheRealMix() throws {
        let settings = ModelMixSettings(order: ModelMix.defaultOrder, percent: ["claude-opus-5-5": 0])
        let panel = try ModelMixFixtures.actualPanel(settings: settings)
        XCTAssertTrue(panel.isActual)
        XCTAssertEqual(panel.percents, [33, 16, 51, 0])
    }

    func testTheTodayTileWhatIfPricesTodaysTokensAtTheSameShares() throws {
        // Today: opus input 50K and haiku input 50K, so the real shares are Opus 50, Haiku 50. At Opus 100% today's
        // 100K input tokens cost 0.1M x $4.00 = $0.40.
        let mix = try XCTUnwrap(ModelMixFixtures.accountMix(id: "claude-main", json: ModelMixFixtures.json, settings: .standard))
        let today = try XCTUnwrap(mix.today)
        XCTAssertEqual(today.realPercents, [50, 0, 50, 0])
        XCTAssertEqual(today.panel(percents: [100, 0, 0, 0]).totalCost, 0.40, accuracy: 1e-9)
    }

    // MARK: Trial and tiles

    func testTheTilesShowTheWhatIfAndTheRealCostWhileTheMixIsATrial() throws {
        let settings = ModelMixSettings(order: ModelMix.defaultOrder, percent: ["claude-opus-5-5": 100])
        let mix = try XCTUnwrap(ModelMixFixtures.accountMix(id: "claude-main", json: ModelMixFixtures.json, settings: settings))
        XCTAssertTrue(mix.isTrial)
        let account = try account("claude-main")
        let tiles = AppUsageInsights.usageTiles(account, mix: mix, shownPercents: mix.shown.percents, language: .en)
        XCTAssertEqual(tiles.map(\.title), ["Today", "This month"])
        // Month: all tokens at Opus 100% are $19.80 (the Opus hand calculation above). Today: $0.40.
        XCTAssertEqual(tiles[1].trialCostText, "~$19.80")
        XCTAssertEqual(tiles[1].costText, "~$6.00", "the actual figure is the real cost the Quota tab shows")
        XCTAssertEqual(tiles[0].trialCostText, "~$0.40")
        XCTAssertEqual(tiles[0].costText, "~$1.00")
    }

    func testTheTilesShowNoTrialWhenTheMixIsTheRealOne() throws {
        let mix = try XCTUnwrap(ModelMixFixtures.accountMix(id: "claude-main", json: ModelMixFixtures.json, settings: .standard))
        let tiles = AppUsageInsights.usageTiles(try account("claude-main"), mix: mix, shownPercents: mix.shown.percents, language: .en)
        XCTAssertTrue(tiles.allSatisfy { $0.trialCostText == nil })
    }

    func testTheQuotaTabTilesAlwaysShowTheRealValues() throws {
        let settings = ModelMixSettings(order: ModelMix.defaultOrder, percent: ["claude-opus-5-5": 100])
        let mix = try XCTUnwrap(ModelMixFixtures.accountMix(id: "claude-main", json: ModelMixFixtures.json, settings: settings))
        let tiles = AppUsageInsights.usageTiles(try account("claude-main"), mix: mix, shownPercents: nil, language: .en)
        XCTAssertTrue(tiles.allSatisfy { $0.trialCostText == nil })
        XCTAssertEqual(tiles[1].costText, "~$6.00")
    }

    func testTheColourBarSplitsEachPeriodByModelInTheShownMix() throws {
        let real = try XCTUnwrap(ModelMixFixtures.accountMix(id: "claude-main", json: ModelMixFixtures.json, settings: .standard))
        let quotaTiles = AppUsageInsights.usageTiles(try account("claude-main"), mix: real, shownPercents: nil, language: .en)
        // Month real shares 33, 16, 51, 0; today real shares 50, 0, 50, 0.
        XCTAssertEqual(quotaTiles[1].bar.map(\.percent), [33, 16, 51, 0])
        XCTAssertEqual(quotaTiles[0].bar.map(\.percent), [50, 0, 50, 0])
        XCTAssertEqual(quotaTiles[1].bar.map(\.family), ["opus", "sonnet", "haiku", "fable"])
        XCTAssertEqual(quotaTiles[1].bar.map(\.percent).reduce(0, +), 100)

        let whatIf = try XCTUnwrap(ModelMixFixtures.accountMix(
            id: "claude-main", json: ModelMixFixtures.json,
            settings: ModelMixSettings(order: ModelMix.defaultOrder, percent: ["claude-opus-5-5": 50, "claude-sonnet-5-5": 30, "claude-haiku-5-5": 20])
        ))
        let mixTiles = AppUsageInsights.usageTiles(try account("claude-main"), mix: whatIf, shownPercents: whatIf.shown.percents, language: .en)
        XCTAssertEqual(mixTiles[1].bar.map(\.percent), [50, 30, 20, 0], "the bar follows the shares on screen")
    }

    func testTheChatGPTCardHasTodayAndMonthTilesWithTheRealValuesOnTheQuotaTab() throws {
        // Month: real shares 52 and 48 (see testTheGPTMixHasTheModelsWithTokensMostFirst), cost 6.37 from usage.json.
        // Today has no tokens, so there is no today basis: no colour bar and the today cost is not shown.
        let mix = try XCTUnwrap(ModelMixFixtures.accountMix(id: "codex-main", json: ModelMixFixtures.gptJSON, settings: .standard))
        let tiles = AppUsageInsights.usageTiles(try account("codex-main", in: ModelMixFixtures.gptJSON), mix: mix, shownPercents: nil, language: .en)
        XCTAssertEqual(tiles.map(\.title), ["Today", "This month"])
        XCTAssertEqual(tiles[1].costText, "~$6.37")
        XCTAssertEqual(tiles[1].bar.map(\.percent), [52, 48])
        XCTAssertEqual(tiles[1].bar.map(\.family), ["sol", "luna"])
        XCTAssertTrue(tiles[0].bar.isEmpty)
        XCTAssertNil(tiles[1].trialCostText, "the Quota tab always shows the real values")
    }

    func testTheChatGPTTilesShowTheWhatIfAndTheRealCostWhileTheMixIsATrial() throws {
        // A 50/50 what-if. The month's cost at 50/50 is 0.5 x $11.80 + 0.5 x $0.48 = $6.14, shown big. The real $6.37 stays.
        let settings = ModelMixSettings(order: [], percent: ["gpt-6.2-sol": 50, "gpt-6-luna": 50])
        let mix = try XCTUnwrap(ModelMixFixtures.accountMix(id: "codex-main", json: ModelMixFixtures.gptJSON, settings: settings))
        XCTAssertTrue(mix.isTrial)
        let tiles = AppUsageInsights.usageTiles(try account("codex-main", in: ModelMixFixtures.gptJSON), mix: mix, shownPercents: mix.shown.percents, language: .en)
        XCTAssertEqual(tiles[1].trialCostText, "~$6.14")
        XCTAssertEqual(tiles[1].costText, "~$6.37")
        XCTAssertEqual(tiles[1].bar.map(\.percent), [50, 50], "the bar follows the shares on screen")
        XCTAssertNil(tiles[0].trialCostText, "today has no basis, so no what-if")
    }

    func testAChatGPTAccountWithoutAMixHasTilesButNoBarAndNoTrial() throws {
        // The fixture's codex-main has a month cost of $1.00 and no by_model, so it has no mix and no bar.
        let codex = try account("codex-main")
        let tiles = AppUsageInsights.usageTiles(codex, mix: nil, shownPercents: [100], language: .en)
        XCTAssertEqual(tiles.map(\.title), ["Today", "This month"])
        XCTAssertEqual(tiles[1].costText, "~$1.00")
        XCTAssertTrue(tiles.allSatisfy { $0.bar.isEmpty && $0.trialCostText == nil })
    }

    // MARK: ChatGPT long-context pricing

    /// One ChatGPT account with the given `by_model` entry for gpt-6.2-sol, and gpt-6.2-sol's prices. The long-context
    /// block of the price holds a `cache_write` of 9.0, which must never be used (see the cache-write test).
    private func solOnly(byModel entry: String) throws -> AccountModelMix? {
        let json = """
        {"schema": 1,
         "model_prices": {"gpt-6.2-sol": {"provider": "openai", "family": "sol", "label": "GPT-6.2 Sol", "input": 2.0,
            "cached_input": 0.1, "cache_write": 2.5, "output": 10.0,
            "long_context": {"threshold": 272000, "input": 4.0, "cached_input": 0.2, "cache_write": 9.0, "output": 15.0}}},
         "accounts": [{"id": "codex-main", "provider": "codex", "status": "ok",
           "usage": {"month": {"tokens": 1, "cost_usd": 1, "by_model": {"gpt-6.2-sol": \(entry)}}}}]}
        """
        return try ModelMixFixtures.accountMix(id: "codex-main", json: json, settings: .standard)
    }

    func testWithoutALongContextEveryTokenIsPricedAtTheStandardRates() throws {
        // Input 1.0M x $2.00 + output 0.1M x $10.00 = $3.00. No long part, so the long totals are nil.
        let mix = try XCTUnwrap(solOnly(byModel: #"{"input": 1000000, "cached_input": 0, "cache_write": 0, "output": 100000, "reasoning": 0}"#))
        XCTAssertNil(mix.month.longTotals)
        XCTAssertEqual(mix.month.panel(percents: [100]).totalCost, 3.00, accuracy: 1e-9)
    }

    func testTheLongContextIsASubsetOfTheTotal() throws {
        // The total is input 2.0M and output 0.1M. The long part is input 1.0M and output 0.05M of that total, so the
        // short part is input 1.0M and output 0.05M.
        // Short: 1.0M x $2.00 + 0.05M x $10.00 = $2.50. Long: 1.0M x $4.00 + 0.05M x $15.00 = $4.75. Total $7.25.
        // (Had the long part been added on top of the total, the input would be 3.0M and the cost $11.50.)
        let mix = try XCTUnwrap(solOnly(byModel: #"{"input": 2000000, "cached_input": 0, "cache_write": 0, "output": 100000, "reasoning": 0, "long_context": {"input": 1000000, "cached_input": 0, "cache_write": 0, "output": 50000}}"#))
        XCTAssertEqual(mix.month.panel(percents: [100]).totalCost, 7.25, accuracy: 1e-9)
        XCTAssertEqual(mix.month.totals.input, 1_000_000)
        XCTAssertEqual(mix.month.longTotals?.input, 1_000_000)
    }

    func testALongPartLargerThanTheTotalNeverGivesNegativeTokens() throws {
        // A broken file: the long part is 3.0M input but the total is 1.0M. The short part is clamped at 0, so only the
        // long part is priced: 3.0M x $4.00 = $12.00. (Without the clamp the short part would be -2.0M x $2.00.)
        let mix = try XCTUnwrap(solOnly(byModel: #"{"input": 1000000, "cached_input": 0, "cache_write": 0, "output": 0, "long_context": {"input": 3000000}}"#))
        XCTAssertEqual(mix.month.totals.input, 0)
        XCTAssertEqual(mix.month.panel(percents: [100]).totalCost, 12.00, accuracy: 1e-9)
    }

    func testTheLongPartsCacheWriteIsPricedAtTheStandardCacheWriteRate() throws {
        // Total cache write 100K, of which 40K is long. The short 60K x $2.50 = $0.15 and the long 40K x $2.50 = $0.10,
        // both at the normal cache write rate. The long block's own cache_write of 9.0 is not used. Total $0.25.
        // (With the long rate of 9.0 the long part would be $0.36 and the total $0.51.)
        let mix = try XCTUnwrap(solOnly(byModel: #"{"input": 0, "cached_input": 0, "cache_write": 100000, "output": 0, "long_context": {"input": 0, "cached_input": 0, "cache_write": 40000, "output": 0}}"#))
        XCTAssertEqual(mix.month.panel(percents: [100]).totalCost, 0.25, accuracy: 1e-9)
    }

    // MARK: ChatGPT (Codex) mix

    func testTheGPTMixHasTheModelsWithTokensMostFirst() throws {
        // gpt-6.2-sol: total input 2.0M + output 0.15M = 2.15M, of which the long part is input 1.0M + output 0.05M.
        // gpt-6-luna: input 2.0M = 2.0M. gpt-6.1-sol has no tokens, so it is not a row.
        // Real shares: 2.15 / 4.15 = 51.81 and 48.19, which round to 52 and 48 (the larger fraction gets the spare point).
        let mix = try XCTUnwrap(ModelMixFixtures.accountMix(id: "codex-main", json: ModelMixFixtures.gptJSON, settings: .standard))
        XCTAssertEqual(mix.provider, "codex")
        XCTAssertEqual(mix.month.models.map(\.id), ["gpt-6.2-sol", "gpt-6-luna"])
        XCTAssertEqual(mix.shown.percents, [52, 48])
        XCTAssertTrue(mix.shown.isActual)
        XCTAssertEqual(mix.shown.rows.map(\.label), ["GPT-6.2 Sol", "GPT-6 Luna"])
    }

    func testTheGPTCostsUseTheStandardRatesAndTheLongContextRatesForTheLongPart() throws {
        let mix = try XCTUnwrap(ModelMixFixtures.accountMix(id: "codex-main", json: ModelMixFixtures.gptJSON, settings: .standard))
        // All GPT tokens at Sol 100%: short 3.0M input x $2 + 0.1M output x $10 + 0.5M cached x $0.10 = $7.05.
        // Long 1.0M input x $4 + 0.05M output x $15 = $4.75. Together $11.80.
        XCTAssertEqual(mix.month.panel(percents: [100, 0]).rows[0].cost, 11.80, accuracy: 1e-9)
        // All GPT tokens at Luna 100%. Luna has no long-context rates, so its long part uses the standard ones:
        // short 3.0M x $0.10 + 0.1M x $0.50 + 0.5M x $0.01 = $0.355, long 1.0M x $0.10 + 0.05M x $0.50 = $0.125. Total $0.48.
        XCTAssertEqual(mix.month.panel(percents: [0, 100]).rows[1].cost, 0.48, accuracy: 1e-9)
    }

    func testTheGPTTotalAtTheRealSharesAddsUpTheRows() throws {
        // Sol 52% of $11.80 = $6.136 and Luna 48% of $0.48 = $0.2304. Total $6.3664, shown as $6.37 (637 cents).
        let panel = try XCTUnwrap(ModelMixFixtures.accountMix(id: "codex-main", json: ModelMixFixtures.gptJSON, settings: .standard)?.shown)
        XCTAssertEqual(panel.totalCost, 6.3664, accuracy: 1e-9)
        XCTAssertEqual(panel.totalCents, 637)
        XCTAssertEqual(panel.rows.map(\.cents), [614, 23], "the extra cent goes to the larger fraction (Sol, .6 of a cent)")
        XCTAssertEqual(panel.rows.map(\.cents).reduce(0, +), panel.totalCents)
    }

    func testTheLongContextPartIsOnlyPricedWhereAModelHasLongRates() throws {
        let sol = try XCTUnwrap(ModelMixFixtures.accountMix(id: "codex-main", json: ModelMixFixtures.gptJSON, settings: .standard)).month.models[0].price
        XCTAssertEqual(sol.longContext?.input, 4.0)
        XCTAssertEqual(ModelMixMath.cost(percent: 100, price: sol, totals: FamilyTokens(input: 1_000_000, output: 0, cacheWrite5m: 0, cacheWrite1h: 0, cacheRead: 0)), 2.0, accuracy: 1e-9)
        let withLong = ModelMixMath.cost(percent: 100, price: sol, totals: .zero, longTotals: FamilyTokens(input: 1_000_000, output: 0, cacheWrite5m: 0, cacheWrite1h: 0, cacheRead: 0))
        XCTAssertEqual(withLong, 4.0, accuracy: 1e-9, "1.0M long input tokens at $4.00")
    }

    func testTheGPTOrderSettingWinsOverTheTokenOrder() throws {
        let settings = ModelMixSettings(order: ["gpt-6-luna", "gpt-6.2-sol"], percent: nil)
        let mix = try XCTUnwrap(ModelMixFixtures.accountMix(id: "codex-main", json: ModelMixFixtures.gptJSON, settings: settings))
        XCTAssertEqual(mix.month.models.map(\.id), ["gpt-6-luna", "gpt-6.2-sol"])
        XCTAssertEqual(mix.shown.percents, [48, 52], "the real shares stay with their model")
    }

    func testOnlyOpenAIPricesAreGPTRowsAndOnlyClaudePricesAreClaudeRows() throws {
        // The GPT fixture also has a Claude price (claude-haiku-5-5, no provider). A GPT account must not list it, even
        // with tokens, and a Claude account must not list a GPT model.
        let withHaikuTokens = ModelMixFixtures.gptJSON.replacingOccurrences(
            of: "\"gpt-6-luna\": {\"input\": 2000000,",
            with: "\"claude-haiku-5-5\": {\"input\": 5000000, \"cached_input\": 0, \"cache_write\": 0, \"output\": 0},\n               \"gpt-6-luna\": {\"input\": 2000000,"
        )
        let gpt = try XCTUnwrap(ModelMixFixtures.accountMix(id: "codex-main", json: withHaikuTokens, settings: .standard))
        XCTAssertFalse(gpt.month.models.contains { $0.id == "claude-haiku-5-5" })

        let claudeWithGPTPrices = ModelMixFixtures.gptJSON.replacingOccurrences(
            of: "\"accounts\": [",
            with: "\"accounts\": [{\"id\": \"claude-main\", \"provider\": \"claude\", \"status\": \"ok\", \"usage\": {\"month\": {\"by_family\": {\"haiku\": {\"input\": 1000000}}}}},"
        )
        let claude = try XCTUnwrap(ModelMixFixtures.accountMix(id: "claude-main", json: claudeWithGPTPrices, settings: .standard))
        // Only the Claude price is in this file, so the Claude mix has that one row and no GPT row.
        XCTAssertEqual(claude.month.models.map(\.id), ["claude-haiku-5-5"])
    }

    func testAGPTAccountWithoutPricedTokensHasNoMix() throws {
        let noPrices = ModelMixFixtures.gptJSON.replacingOccurrences(of: "\"provider\": \"openai\"", with: "\"provider\": \"nobody\"")
        XCTAssertNil(try ModelMixFixtures.accountMix(id: "codex-main", json: noPrices, settings: .standard))
        XCTAssertNil(try ModelMixFixtures.accountMix(id: "codex-main", json: ModelMixFixtures.json, settings: .standard),
                     "an account with no by_model has no mix")
    }

    func testTheCodexOutputAlreadyIncludesReasoningSoItIsNotCountedTwice() throws {
        // The collector writes output with the reasoning inside it. A reasoning key, if present, is not read.
        let tokens = try JSONDecoder().decode(OpenAIModelTokens.self, from: Data(#"{"input": 10, "cached_input": 4, "cache_write": 2, "output": 100, "reasoning_output": 40}"#.utf8))
        XCTAssertEqual(tokens.total.output, 100)
        XCTAssertEqual(tokens.total.input, 10)
        XCTAssertEqual(tokens.total.cacheRead, 4)
        XCTAssertEqual(tokens.total.cacheWrite5m, 2)
        XCTAssertEqual(tokens.shareTokens, 112, "input 10 + output 100 + cache write 2; cached input is left out, as for Claude")
        XCTAssertEqual(tokens.long, .zero)
        XCTAssertEqual(tokens.short, tokens.total, "with no long part, the short part is the whole total")
    }

    // MARK: Decoding prices

    func testOneOddPriceEntryDoesNotHideTheOthers() throws {
        let document = try Fixtures.document(ModelMixFixtures.json.replacingOccurrences(
            of: "\"claude-fable-5-2\": {",
            with: "\"odd\": \"not an object\", \"claude-fable-5-2\": {"
        ))
        let prices = try XCTUnwrap(document.modelPrices)
        XCTAssertNil(prices["odd"])
        XCTAssertEqual(prices.count, 4, "the four Claude prices stay")
        XCTAssertNotNil(try ModelMixFixtures.accountMix(id: "claude-main", json: ModelMixFixtures.json, settings: .standard))
    }

    func testAPriceWithoutCacheKeysCountsAsZeroAndKeepsTheRest() throws {
        let document = try Fixtures.document(#"{"schema": 1, "model_prices": {"claude-haiku-5-5": {"family": "haiku", "label": "Haiku 5.5", "input": 0.1, "output": 0.5}}, "accounts": []}"#)
        let price = try XCTUnwrap(document.modelPrices?["claude-haiku-5-5"])
        XCTAssertEqual(price.input, 0.1)
        XCTAssertEqual(price.cacheRead, 0)
        XCTAssertNil(price.longContext)
        XCTAssertTrue(price.isClaude)
    }

    func testTheGPTPricesDecodeWithTheirProviderAndLongContext() throws {
        let document = try Fixtures.document(ModelMixFixtures.gptJSON)
        let sol = try XCTUnwrap(document.modelPrices?["gpt-6.2-sol"])
        XCTAssertEqual(sol.provider, "openai")
        XCTAssertFalse(sol.isClaude)
        XCTAssertEqual(sol.longContext, PriceRates(input: 4, cacheWrite5m: 2.5, cacheWrite1h: 0, cacheRead: 0.2, output: 15))
        XCTAssertEqual(sol.provider, "openai")
        XCTAssertNil(document.modelPrices?["gpt-6-luna"]?.longContext)
    }

    func testTheClaudePriceWithoutAProviderOrWithAnthropicIsClaude() throws {
        XCTAssertTrue(try ModelMixFixtures.document().modelPrices?["claude-opus-5-5"]?.isClaude ?? false)
        let gpt = try Fixtures.document(ModelMixFixtures.gptJSON)
        XCTAssertEqual(gpt.modelPrices?["claude-haiku-5-5"]?.provider, "anthropic")
        XCTAssertTrue(gpt.modelPrices?["claude-haiku-5-5"]?.isClaude ?? false, "the collector writes Claude as anthropic")
        XCTAssertEqual(gpt.modelPrices?["claude-haiku-5-5"]?.cacheRead, 0.01, "Claude keeps cache_read")
    }

    func testTheGPTCachedInputAndCacheWriteKeysAreReadAsTheRates() throws {
        let sol = try XCTUnwrap(Fixtures.document(ModelMixFixtures.gptJSON).modelPrices?["gpt-6.2-sol"])
        XCTAssertEqual(sol.cacheRead, 0.1, "cached_input is the cached-input rate")
        XCTAssertEqual(sol.cacheWrite5m, 2.5, "cache_write is the 30-minute write rate")
        XCTAssertEqual(sol.longContext?.cacheWrite5m, 2.5, "the long-context table has no write rate, so the standard one applies")
        XCTAssertEqual(sol.longContext?.cacheRead, 0.2)
    }

    // MARK: Settings per account

    func testAMissingSettingsFileMeansNoEntries() {
        XCTAssertEqual(AppSettingsStore.loadModelMix(from: settingsURL), [:])
    }

    func testEachAccountsEntrySurvivesASaveAndLoad() throws {
        let claude = ModelMixSettings(
            order: ["claude-haiku-5-5", "claude-opus-5-5", "claude-sonnet-5-5", "claude-fable-5-2"],
            percent: ["claude-opus-5-5": 50, "claude-sonnet-5-5": 30, "claude-haiku-5-5": 20, "claude-fable-5-2": 0]
        )
        let gpt = ModelMixSettings(order: ["gpt-6-luna", "gpt-6.2-sol"], percent: nil)
        try AppSettingsStore.saveModelMix(claude, accountID: "claude-main", at: settingsURL)
        try AppSettingsStore.saveModelMix(gpt, accountID: "codex-main", at: settingsURL)
        let loaded = AppSettingsStore.loadModelMix(from: settingsURL)
        XCTAssertEqual(loaded["claude-main"], claude)
        XCTAssertEqual(loaded["codex-main"], gpt)
    }

    func testSavingOneAccountKeepsTheOthers() throws {
        try AppSettingsStore.saveModelMix(ModelMixSettings(order: [], percent: ["claude-opus-5-5": 100]), accountID: "claude-main", at: settingsURL)
        try AppSettingsStore.saveModelMix(ModelMixSettings(order: ["claude-fable-5-2"], percent: nil), accountID: "claude-claude-2", at: settingsURL)
        let loaded = AppSettingsStore.loadModelMix(from: settingsURL)
        XCTAssertEqual(loaded["claude-main"]?.percent, ["claude-opus-5-5": 100])
        XCTAssertEqual(loaded["claude-claude-2"]?.order, ["claude-fable-5-2"])
    }

    func testTheOrderIsKeptWhenOnlyTheMixChanges() throws {
        let order = ["claude-fable-5-2", "claude-haiku-5-5", "claude-sonnet-5-5", "claude-opus-5-5"]
        try AppSettingsStore.saveModelMix(ModelMixSettings(order: order, percent: nil), accountID: "claude-main", at: settingsURL)
        try AppSettingsStore.saveModelMix(ModelMixSettings(order: order, percent: ["claude-opus-5-5": 100]), accountID: "claude-main", at: settingsURL)
        XCTAssertEqual(AppSettingsStore.loadModelMix(from: settingsURL)["claude-main"]?.order, order)
        XCTAssertEqual(AppSettingsStore.loadModelMix(from: settingsURL)["claude-main"]?.percent, ["claude-opus-5-5": 100])
    }

    func testResetWritesNullForThePercent() throws {
        try AppSettingsStore.saveModelMix(ModelMixSettings(order: [], percent: ["claude-opus-5-5": 100]), accountID: "claude-main", at: settingsURL)
        try AppSettingsStore.saveModelMix(ModelMixSettings(order: [], percent: nil), accountID: "claude-main", at: settingsURL)
        let text = try String(contentsOf: settingsURL, encoding: .utf8)
        XCTAssertTrue(text.contains("\"percent\":null"), text)
        XCTAssertNil(AppSettingsStore.loadModelMix(from: settingsURL)["claude-main"]?.percent)
    }

    func testTheWriteChangesOnlyTheModelMixKey() throws {
        let existing = #"{"accounts":{"claude-main":{"enabled":true,"order":0}},"language":"th","notify":false,"sort":"lowest"}"#
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(existing.utf8).write(to: settingsURL)

        try AppSettingsStore.saveModelMix(
            ModelMixSettings(order: ["claude-sonnet-5-5"], percent: ["claude-sonnet-5-5": 100]),
            accountID: "claude-main",
            at: settingsURL
        )

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["accounts", "language", "notify", "sort", "model_mix"])
        XCTAssertEqual(object["language"] as? String, "th")
        XCTAssertEqual(object["notify"] as? Bool, false)
        XCTAssertEqual(object["sort"] as? String, "lowest")
        XCTAssertEqual(AppSettingsStore.loadAccountSettings(from: settingsURL).sort, .lowest)
    }

    // MARK: The old single value

    func testTheOldSingleValueIsReadAsClaudeMainAndTheFileIsNotChanged() throws {
        let old = #"{"language":"en","model_mix":{"order":["claude-sonnet-5-5"],"percent":{"claude-sonnet-5-5":100,"claude-opus-5-5":0}}}"#
        try writeSettings(old)
        let loaded = AppSettingsStore.loadModelMix(from: settingsURL)
        XCTAssertEqual(loaded, ["claude-main": ModelMixSettings(order: ["claude-sonnet-5-5"], percent: ["claude-sonnet-5-5": 100, "claude-opus-5-5": 0])])
        XCTAssertEqual(try String(contentsOf: settingsURL, encoding: .utf8), old, "reading never writes")
    }

    func testTheOldValueIsWrittenInTheNewShapeWhenAnotherAccountIsSaved() throws {
        try writeSettings(#"{"model_mix":{"order":["claude-sonnet-5-5"],"percent":{"claude-sonnet-5-5":100}}}"#)
        try AppSettingsStore.saveModelMix(ModelMixSettings(order: [], percent: ["gpt-6-luna": 100]), accountID: "codex-main", at: settingsURL)

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as? [String: Any])
        let raw = try XCTUnwrap(object["model_mix"] as? [String: Any])
        XCTAssertEqual(Set(raw.keys), ["claude-main", "codex-main"], "no top-level order or percent is left")
        let claude = try XCTUnwrap(raw["claude-main"] as? [String: Any])
        XCTAssertEqual(claude["order"] as? [String], ["claude-sonnet-5-5"])
        let loaded = AppSettingsStore.loadModelMix(from: settingsURL)
        XCTAssertEqual(loaded["claude-main"]?.percent, ["claude-sonnet-5-5": 100])
        XCTAssertEqual(loaded["codex-main"]?.percent, ["gpt-6-luna": 100])
    }

    func testAJunkModelMixMeansTheDefaults() throws {
        for junk in [#"{"model_mix":"junk"}"#, #"{"model_mix":[1,2]}"#, #"{"model_mix":{"order":"nope","percent":[1,2]}}"#, #"{"model_mix":{"claude-main":"junk"}}"#, "not json"] {
            try writeSettings(junk)
            XCTAssertEqual(AppSettingsStore.loadModelMix(from: settingsURL), [:], junk)
        }
    }

    func testAPercentThatIsNotAWholeNumberIsDropped() throws {
        try writeSettings(#"{"model_mix":{"claude-main":{"order":["claude-opus-5-5"],"percent":{"claude-opus-5-5":40.5,"claude-sonnet-5-5":60}}}}"#)
        let loaded = try XCTUnwrap(AppSettingsStore.loadModelMix(from: settingsURL)["claude-main"])
        XCTAssertEqual(loaded.percent, ["claude-sonnet-5-5": 60])
        XCTAssertEqual(loaded.order, ["claude-opus-5-5"])
    }

    // MARK: Cents that add up to the total

    func testTheRowCentsOfTheFixtureAddUpToTheShownTotal() throws {
        // Exact rows 6.534, 1.584, 0.2601 and 0 make 8.3781, shown as $8.38. Rounded on their own, the rows gave
        // 6.53 + 1.58 + 0.26 = 8.37. In cents: 653.4, 158.4 and 26.01 round down to 653, 158, 26 (837), and one cent is
        // missing. Opus and Sonnet both have .4, so the earlier row (Opus) takes it: 654, 158, 26, 0.
        let panel = try ModelMixFixtures.actualPanel()
        XCTAssertEqual(panel.rows.map(\.cents), [654, 158, 26, 0])
        XCTAssertEqual(panel.totalCents, 838)
        XCTAssertEqual(panel.rows.map(\.cents).reduce(0, +), panel.totalCents)
        XCTAssertEqual(UsageFormat.moneyText(cents: panel.totalCents), "$8.38")
        XCTAssertEqual(panel.totalCost, 8.3781, accuracy: 1e-9, "the exact cost is kept")
    }

    func testThreeRowsEachEndingInHalfACentShareTheMissingCentsInOrder() {
        // 0.105 + 0.205 + 0.305 = 0.615 dollars = 61.5 cents, shown as 62. Rounded down: 10, 20, 30 leaves 2 cents.
        // Every row has .5, so the first two rows take the cents: 11, 21, 30.
        let split = ModelMixMath.centsSplit([0.105, 0.205, 0.305])
        XCTAssertEqual(split.rows, [11, 21, 30])
        XCTAssertEqual(split.total, 62)

        // 0.005 three times is 1.5 cents, shown as 2. Each row is .5, so the first two rows get one cent each.
        let tiny = ModelMixMath.centsSplit([0.005, 0.005, 0.005])
        XCTAssertEqual(tiny.rows, [1, 1, 0])
        XCTAssertEqual(tiny.total, 2)
    }

    func testAllZeroCostsShowZeroCentsEverywhere() {
        let split = ModelMixMath.centsSplit([0, 0, 0, 0])
        XCTAssertEqual(split.rows, [0, 0, 0, 0])
        XCTAssertEqual(split.total, 0)
        XCTAssertEqual(ModelMixMath.centsSplit([]).rows, [])
        XCTAssertEqual(UsageFormat.moneyText(cents: split.total), "$0.00")
    }

    func testARowAt100PercentShowsTheWholeTotalAndTheOthersShowZero() throws {
        // Opus at 100% of all Claude tokens: 19.80 dollars, which is 1980 cents. The other rows stay at $0.00.
        let settings = ModelMixSettings(order: ModelMix.defaultOrder, percent: ["claude-opus-5-5": 100])
        let panel = try ModelMixFixtures.actualPanel(settings: settings)
        XCTAssertEqual(panel.percents, [100, 0, 0, 0])
        XCTAssertEqual(panel.rows.map(\.cents), [1980, 0, 0, 0])
        XCTAssertEqual(panel.totalCents, 1980)
    }

    func testMoneyFromCentsReadsDollarsAndTwoDigitCents() {
        XCTAssertEqual(UsageFormat.moneyText(cents: 838), "$8.38")
        XCTAssertEqual(UsageFormat.moneyText(cents: 5), "$0.05")
        XCTAssertEqual(UsageFormat.moneyText(cents: 0), "$0.00")
        XCTAssertEqual(UsageFormat.moneyText(cents: 123_456), "$1234.56")
    }

    func testRandomMixesAlwaysAddUpExactlyToTheTotal() throws {
        // 2,000 random mixes from a fixed seed, so a failure can be repeated. Each one: random tokens per kind,
        // random shares (some rows 0), the cost of each row, then the cents split.
        let prices = try XCTUnwrap(ModelMixFixtures.document().modelPrices)
        var generator = ModelMixSeededGenerator(state: 20_261_120)
        for iteration in 0..<2_000 {
            let tokens = FamilyTokens(
                input: randomTokens(&generator), output: randomTokens(&generator),
                cacheWrite5m: randomTokens(&generator), cacheWrite1h: randomTokens(&generator),
                cacheRead: randomTokens(&generator)
            )
            let raw = ModelMix.defaultOrder.map { _ in Int.random(in: 0...100, using: &generator) }
            let percents = ModelMixMath.normalized(raw) ?? [100, 0, 0, 0]
            let costs = zip(ModelMix.defaultOrder, percents).map { pair in
                ModelMixMath.cost(percent: pair.1, price: prices[pair.0]!, totals: tokens)
            }

            let split = ModelMixMath.centsSplit(costs)
            let label = "iteration \(iteration), percents \(percents), costs \(costs)"
            XCTAssertEqual(split.rows.reduce(0, +), split.total, label)
            XCTAssertLessThanOrEqual(abs(Double(split.total) - costs.reduce(0, +) * 100), 0.5 + 1e-6, label)
            for (index, cents) in split.rows.enumerated() {
                XCTAssertGreaterThanOrEqual(cents, 0, label)
                XCTAssertLessThan(abs(Double(cents) - costs[index] * 100), 1, label)
                if costs[index] == 0 { XCTAssertEqual(cents, 0, label) }
            }
        }
    }

    private func randomTokens(_ generator: inout ModelMixSeededGenerator) -> Double {
        // One kind in five is 0, so empty families are tested too.
        if Int.random(in: 0..<5, using: &generator) == 0 { return 0 }
        return Double(Int.random(in: 0...5_000_000, using: &generator))
    }

    // MARK: Ordering helper

    func testMovingAModelUsesTheSharedMoveRule() {
        let ids = ModelMix.defaultOrder
        XCTAssertEqual(
            AccountList.moved(ids, id: "claude-fable-5-2", onto: "claude-opus-5-5"),
            ["claude-fable-5-2", "claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5"]
        )
    }
}

/// A small fixed-seed random generator, so the random mixes in ModelMixTests repeat from run to run.
struct ModelMixSeededGenerator: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
