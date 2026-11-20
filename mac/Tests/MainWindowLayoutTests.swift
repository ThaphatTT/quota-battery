import SwiftUI
import XCTest

/// The breakpoint of the account grid and the width a card needs. The breakpoint is the number the two-column layout
/// depends on, so it is tested at the value itself and one point either side. The card width is measured, not guessed:
/// a card must need no more than `CardGridLayout.minimumCardWidth`, in Thai and in English, or its text is cut off.
@MainActor
final class MainWindowLayoutTests: XCTestCase {
    func testOneColumnJustBelowTheBreakpointAndTwoColumnsFromIt() {
        let breakpoint = CardGridLayout.twoColumnWidth
        XCTAssertEqual(CardGridLayout.columns(forWidth: breakpoint - 1), 1)
        XCTAssertEqual(CardGridLayout.columns(forWidth: breakpoint), 2)
        XCTAssertEqual(CardGridLayout.columns(forWidth: breakpoint + 1), 2)
    }

    /// Never more than two columns, however wide the window is.
    func testTheGridNeverHasMoreThanTwoColumns() {
        XCTAssertEqual(CardGridLayout.columns(forWidth: 4_000), 2)
    }

    /// The narrowest window is the one-column width the app always had, and it is below the breakpoint.
    func testTheNarrowestWindowIsOneColumn() {
        XCTAssertEqual(CardGridLayout.columns(forWidth: CardGridLayout.minimumWindowWidth), 1)
        XCTAssertLessThan(CardGridLayout.minimumWindowWidth, CardGridLayout.twoColumnWidth)
    }

    /// The breakpoint is two minimum cards, the gap and the padding on both sides: the two columns exactly fit.
    func testTheBreakpointIsTwoMinimumCardsWithTheGapAndPadding() {
        XCTAssertEqual(
            CardGridLayout.twoColumnWidth,
            2 * CardGridLayout.minimumCardWidth + CardGridLayout.spacing + 2 * CardGridLayout.outerPadding
        )
    }

    /// A worst-case card, in both languages, needs no more width than a column gives it. The card has its two tiles,
    /// its tab row, its plan and its Almost-out pill, and its first limit carries the credit text.
    func testTheWorstCaseCardFitsItsColumnInThaiAndEnglish() throws {
        let document = try ModelMixFixtures.document()
        let account = try XCTUnwrap(document.accounts.first { $0.id == "claude-main" })
        let mix = try XCTUnwrap(ModelMixFixtures.accountMix(id: "claude-main", json: ModelMixFixtures.json, settings: .standard))
        for language in [UILanguage.th, .en] {
            let card = AppAccountCardView(account: account, now: Fixtures.now, mix: mix, snapshot: true)
            let needed = LayoutFit.naturalWidth(card, language: language, dark: false)
            print("LAYOUT card-natural-width \(language.rawValue)=\(needed) budget=\(CardGridLayout.minimumCardWidth)")
            XCTAssertLessThanOrEqual(
                needed, CardGridLayout.minimumCardWidth,
                "a card needs \(needed) pt in \(language) and a column gives \(CardGridLayout.minimumCardWidth) pt"
            )
        }
    }

    /// The compact list (three or more limits) is one line per limit too, so it must also fit a column.
    func testTheCompactCardFitsItsColumnInThaiAndEnglish() throws {
        let document = try Fixtures.document(Self.threeLimitJSON)
        let account = try XCTUnwrap(document.accounts.first)
        for language in [UILanguage.th, .en] {
            let card = AppAccountCardView(account: account, now: Fixtures.now)
            let needed = LayoutFit.naturalWidth(card, language: language, dark: false)
            print("LAYOUT compact-card-natural-width \(language.rawValue)=\(needed)")
            XCTAssertLessThanOrEqual(needed, CardGridLayout.minimumCardWidth)
        }
    }

    private static let threeLimitJSON = """
    {"generated_at": "2026-11-19T04:28:00Z", "accounts": [
      {"id": "agy-main", "provider": "agy", "label": "agy ทดสอบบัญชีชื่อยาวมาก", "plan": "free-tier", "status": "ok", "error": null,
       "updated_at": "2026-11-19T04:28:00Z",
       "limits": [
         {"key": "a", "label": "5 ชม.", "window_seconds": 18000, "used_percent": 96, "resets_at": "2026-11-19T05:30:00Z"},
         {"key": "b", "label": "สัปดาห์", "window_seconds": 604800, "used_percent": 85, "resets_at": "2026-11-25T05:30:00Z"},
         {"key": "c", "label": "เดือน", "window_seconds": 2592000, "used_percent": 12, "resets_at": "2026-12-19T05:30:00Z"}
       ],
       "usage": null, "credits": null}
    ]}
    """
}
