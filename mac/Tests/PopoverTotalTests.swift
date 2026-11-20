import XCTest

/// The popover's money line: the month's total over every shown account with a mix, split into Claude and GPT. The
/// numbers are the fixtures' real mixes, written out here by hand.
final class PopoverTotalTests: XCTestCase {
    /// The Claude fixture's real month: 838 cents (the old popover line said $8.38 for it). Only its own account is taken, so
    /// an account is never counted twice.
    private func claudeAccounts() throws -> (accounts: [UsageAccount], mixes: [String: AccountModelMix]) {
        let document = try Fixtures.document(ModelMixFixtures.json)
        let mix = try XCTUnwrap(ModelMixFixtures.accountMix(id: "claude-main", json: ModelMixFixtures.json, settings: .standard))
        return (document.accounts.filter { $0.id == "claude-main" }, ["claude-main": mix])
    }

    private func codexAccounts() throws -> (accounts: [UsageAccount], mixes: [String: AccountModelMix]) {
        let document = try Fixtures.document(ModelMixFixtures.gptJSON)
        let mix = try XCTUnwrap(ModelMixFixtures.accountMix(id: "codex-main", json: ModelMixFixtures.gptJSON, settings: .standard))
        return (document.accounts.filter { $0.id == "codex-main" }, ["codex-main": mix])
    }

    func testNoTotalWhenNoAccountHasAMix() throws {
        let document = try Fixtures.document(ModelMixFixtures.oldJSON)
        XCTAssertNil(AppUsageInsights.popoverTotal(accounts: document.accounts, mixes: [:]))
    }

    func testOneClaudeAccountIsTheWholeTotal() throws {
        let (accounts, mixes) = try claudeAccounts()
        let total = try XCTUnwrap(AppUsageInsights.popoverTotal(accounts: accounts, mixes: mixes))
        XCTAssertEqual(total.parts, [PopoverTotal.Part(provider: "claude", cents: 838, isTrial: false)])
        XCTAssertEqual(total.totalCents, 838)
    }

    /// The line reads the total, then each provider's part, in English and Thai.
    func testTheLineReadsTotalThenParts() throws {
        let (accounts, mixes) = try claudeAccounts()
        let total = try XCTUnwrap(AppUsageInsights.popoverTotal(accounts: accounts, mixes: mixes))
        XCTAssertEqual(AppUsageInsights.popoverText(total, language: .en), "≈ $8.38 this month · Claude $8.38")
        XCTAssertEqual(AppUsageInsights.popoverText(total, language: .th), "≈ $8.38 เดือนนี้ · Claude $8.38")
    }

    /// Claude and GPT: two parts, Claude first, and the total is their sum in whole cents.
    func testClaudeAndGPTAddUpToTheTotal() throws {
        let claude = try claudeAccounts()
        let codex = try codexAccounts()
        let accounts = claude.accounts + codex.accounts
        let mixes = claude.mixes.merging(codex.mixes) { first, _ in first }
        let total = try XCTUnwrap(AppUsageInsights.popoverTotal(accounts: accounts, mixes: mixes))
        XCTAssertEqual(total.parts.map(\.provider), ["claude", "codex"])
        XCTAssertEqual(total.totalCents, total.parts.reduce(0) { $0 + $1.cents })
        let gpt = try XCTUnwrap(codex.mixes["codex-main"]).shown.totalCents
        XCTAssertEqual(total.parts.last?.cents, gpt)
        XCTAssertEqual(AppUsageInsights.popoverName("codex"), "GPT")
        XCTAssertEqual(AppUsageInsights.popoverName("claude"), "Claude")
    }

    /// Two Claude accounts give one Claude part: the sum of their cents, not one part per account.
    func testTwoAccountsOfOneProviderShareOnePart() throws {
        let (accounts, mixes) = try claudeAccounts()
        let mix = try XCTUnwrap(mixes["claude-main"])
        var copy = try XCTUnwrap(accounts.first)
        copy.id = "claude-second"
        let second = AccountModelMix(accountID: "claude-second", provider: "claude", month: mix.month, shown: mix.shown, today: mix.today)
        let total = try XCTUnwrap(AppUsageInsights.popoverTotal(
            accounts: accounts + [copy],
            mixes: mixes.merging(["claude-second": second]) { first, _ in first }
        ))
        XCTAssertEqual(total.parts, [PopoverTotal.Part(provider: "claude", cents: 1676, isTrial: false)])
    }

    /// A part with a trial account is marked, and the marker is named in both languages. The total still counts the
    /// trial's what-if cost, as the card's tile does.
    func testATrialPartIsMarked() throws {
        let document = try Fixtures.document(ModelMixFixtures.json)
        let trialSettings = ModelMixSettings(
            order: ModelMix.defaultOrder,
            percent: ["claude-opus-5-5": 50, "claude-sonnet-5-5": 30, "claude-haiku-5-5": 20, "claude-fable-5-2": 0]
        )
        let mix = try XCTUnwrap(ModelMixFixtures.accountMix(id: "claude-main", json: ModelMixFixtures.json, settings: trialSettings))
        XCTAssertTrue(mix.isTrial)
        let total = try XCTUnwrap(AppUsageInsights.popoverTotal(accounts: document.accounts, mixes: ["claude-main": mix]))
        XCTAssertEqual(total.parts.first?.isTrial, true)
        XCTAssertEqual(total.totalCents, mix.shown.totalCents)
        let english = AppUsageInsights.popoverText(total, language: .en)
        XCTAssertTrue(english.hasSuffix("Claude \(UsageFormat.moneyText(cents: mix.shown.totalCents)) (trial)"), english)
        let thai = AppUsageInsights.popoverText(total, language: .th)
        XCTAssertTrue(thai.hasSuffix("Claude \(UsageFormat.moneyText(cents: mix.shown.totalCents)) (ทดลอง)"), thai)
    }

    /// Only the Claude part is a trial when the GPT account is the real mix.
    func testOnlyTheTrialProviderIsMarked() throws {
        let claude = try claudeAccounts()
        let codex = try codexAccounts()
        let trialSettings = ModelMixSettings(
            order: ModelMix.defaultOrder,
            percent: ["claude-opus-5-5": 50, "claude-sonnet-5-5": 30, "claude-haiku-5-5": 20, "claude-fable-5-2": 0]
        )
        let trialMix = try XCTUnwrap(ModelMixFixtures.accountMix(id: "claude-main", json: ModelMixFixtures.json, settings: trialSettings))
        let total = try XCTUnwrap(AppUsageInsights.popoverTotal(
            accounts: claude.accounts + codex.accounts,
            mixes: ["claude-main": trialMix].merging(codex.mixes) { first, _ in first }
        ))
        XCTAssertEqual(total.parts.map(\.isTrial), [true, false])
    }
}
