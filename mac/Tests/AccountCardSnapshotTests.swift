import SwiftUI
import XCTest

/// Renders one Claude card and one ChatGPT card, each in both tabs, to PNG files in mac/build/snapshots/ (gitignored).
/// Names: card-claude-{quota|mix}-{th|en}-{light|dark}.png and card-chatgpt-... The Model mix tabs show a trial (a
/// what-if that differs from the real mix), so the trial tag and the what-if values are in the pictures. The tests also
/// check that every card fits the window width in both languages.
@MainActor
final class AccountCardSnapshotTests: XCTestCase {
    /// The app window is 530 pt wide, with 16 pt on each side of the content.
    private let contentWidth: CGFloat = 498

    private var outputDirectory: URL {
        Fixtures.macFolder.appendingPathComponent("build/snapshots", isDirectory: true)
    }

    /// The Claude card: claude-main from the mix fixture, with two limits so it shows the standard rows. Its what-if is
    /// Opus 50, Sonnet 30, Haiku 20, Fable 0 (a trial).
    private func claudeCard(trial: Bool) throws -> (UsageAccount, AccountModelMix) {
        let json = ModelMixFixtures.json.replacingOccurrences(
            of: "\"plan\": \"Max\", \"status\": \"ok\",",
            with: "\"plan\": \"Max\", \"status\": \"ok\", \"limits\": [{\"key\": \"five_hour\", \"window_seconds\": 18000, \"used_percent\": 42, \"resets_at\": \"2026-11-19T06:40:00Z\"}, {\"key\": \"seven_day\", \"window_seconds\": 604800, \"used_percent\": 67, \"resets_at\": \"2026-11-24T02:00:00Z\"}],"
        )
        let settings = trial
            ? ModelMixSettings(order: ModelMix.defaultOrder, percent: ["claude-opus-5-5": 50, "claude-sonnet-5-5": 30, "claude-haiku-5-5": 20, "claude-fable-5-2": 0])
            : .standard
        let document = try Fixtures.document(json)
        let account = try XCTUnwrap(document.accounts.first { $0.id == "claude-main" })
        let mix = try XCTUnwrap(ModelMix.accountMix(for: account, prices: document.modelPrices ?? [:], settings: settings))
        return (account, mix)
    }

    /// The ChatGPT card: codex-main from the GPT fixture, with one limit at 93% (so it has the pill). Its what-if is
    /// 50/50 Sol and Luna (a trial).
    private func chatGPTCard(trial: Bool) throws -> (UsageAccount, AccountModelMix) {
        let json = ModelMixFixtures.gptJSON.replacingOccurrences(
            of: "\"plan\": \"Pro Lite\", \"status\": \"ok\",",
            with: "\"plan\": \"Pro Lite\", \"status\": \"ok\", \"limits\": [{\"key\": \"primary\", \"window_seconds\": 604800, \"used_percent\": 93, \"resets_at\": \"2026-11-20T02:35:51Z\"}],"
        )
        let settings = trial ? ModelMixSettings(order: [], percent: ["gpt-6.2-sol": 50, "gpt-6-luna": 50]) : .standard
        let document = try Fixtures.document(json)
        let account = try XCTUnwrap(document.accounts.first { $0.id == "codex-main" })
        let mix = try XCTUnwrap(ModelMix.accountMix(for: account, prices: document.modelPrices ?? [:], settings: settings))
        return (account, mix)
    }

    private func card(_ account: UsageAccount, _ mix: AccountModelMix, tab: CardTab) -> some View {
        AppAccountCardView(account: account, now: Fixtures.now, mix: mix, snapshot: true, startsOn: tab)
            .frame(width: contentWidth)
    }

    func testRenderTheClaudeCardInBothTabsInThaiAndEnglishInLightAndDark() throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let (account, mix) = try claudeCard(trial: true)
        try renderBothTabs(account, mix, prefix: "card-claude")
    }

    func testRenderTheChatGPTCardInBothTabsInThaiAndEnglishInLightAndDark() throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let (account, mix) = try chatGPTCard(trial: true)
        try renderBothTabs(account, mix, prefix: "card-chatgpt")
    }

    private func renderBothTabs(_ account: UsageAccount, _ mix: AccountModelMix, prefix: String) throws {
        var written = 0
        for (tab, tabName) in [(CardTab.quota, "quota"), (CardTab.modelMix, "mix")] {
            for language in [UILanguage.th, .en] {
                for dark in [false, true] {
                    let name = "\(prefix)-\(tabName)-\(language.rawValue)-\(dark ? "dark" : "light").png"
                    let data = try XCTUnwrap(SnapshotRenderer.fitting(card(account, mix, tab: tab), dark: dark, language: language), name)
                    try data.write(to: outputDirectory.appendingPathComponent(name))
                    XCTAssertGreaterThan(data.count, 1_000, name)
                    written += 1
                }
            }
        }
        XCTAssertEqual(written, 8)
    }

    /// Every card, in both tabs, needs no more width than the window gives it, in both languages and appearances. The
    /// header (name, the near-full pill, the plan tag) and the rows of the Model mix tab are the widest parts.
    func testEveryCardFitsTheWindowWidthInBothTabsLanguagesAndAppearances() throws {
        let claude = try claudeCard(trial: true)
        let chatGPT = try chatGPTCard(trial: true)
        for (account, mix) in [claude, chatGPT] {
            for tab in [CardTab.quota, .modelMix] {
                for language in [UILanguage.th, .en] {
                    for dark in [false, true] {
                        let needed = LayoutFit.naturalWidth(card(account, mix, tab: tab), language: language, dark: dark)
                        XCTAssertLessThanOrEqual(
                            needed, contentWidth,
                            "\(account.id) \(tab) needs \(Int(needed.rounded(.up))) pt in \(language), the window gives \(Int(contentWidth)) pt"
                        )
                    }
                }
            }
        }
    }
}
