import SwiftUI
import XCTest

/// agy limits grouped into Gemini, add-ons and other (the collector writes "group" on each agy limit). The unit tests
/// check the order, the headers, the popover lines and the widget rows. The snapshot tests write PNG files to
/// mac/build/snapshots/ (gitignored) for the card, the popover and the three widgets, in Thai and English, light and dark.
@MainActor
final class AgyGroupTests: XCTestCase {
    private let contentWidth: CGFloat = 498

    /// Five agy limits, in the file order the collector writes them: the Gemini group, then the add-ons.
    private static let groupedJSON = """
    {"schema": 1, "generated_at": "2026-11-19T04:30:00Z", "accounts": [
      {"id": "agy-main", "provider": "agy", "label": "agy", "plan": "free-tier", "status": "ok",
       "updated_at": "2026-11-19T04:30:00Z",
       "limits": [
         {"key": "gemini-5h", "label": "Gemini Models · 5h", "window_seconds": null, "used_percent": 58,
          "resets_at": "2026-11-19T09:00:00Z", "group": "gemini"},
         {"key": "gemini-weekly", "label": "Gemini Models · Weekly", "window_seconds": null, "used_percent": 40,
          "resets_at": "2026-11-24T02:00:00Z", "group": "gemini"},
         {"key": "gemini-argon-wtu-weekly", "label": "Gemini Argon · Weekly", "window_seconds": null, "used_percent": 0,
          "resets_at": "2026-11-24T02:00:00Z", "group": "gemini"},
         {"key": "3p-5h", "label": "Claude & GPT · 5h", "window_seconds": null, "used_percent": 0,
          "resets_at": "2026-11-19T09:00:00Z", "group": "addon"},
         {"key": "3p-weekly", "label": "Claude & GPT · Weekly", "window_seconds": null, "used_percent": 100,
          "resets_at": "2026-11-24T02:00:00Z", "group": "addon"}
       ], "usage": null, "credits": null}
    ]}
    """

    private func document(_ json: String) throws -> UsageDocument {
        try Fixtures.document(json)
    }

    private func account(_ document: UsageDocument) throws -> UsageAccount {
        try XCTUnwrap(document.accounts.first)
    }

    /// The fixture with the first (or last) occurrence of `find` replaced. Only the spacing-free text is matched.
    private func edited(_ find: String, _ replace: String, last: Bool = false) throws -> UsageDocument {
        let text = Self.groupedJSON
        let range = try XCTUnwrap(text.range(of: find, options: last ? .backwards : []), find)
        return try document(text.replacingCharacters(in: range, with: replace))
    }

    // MARK: Order and headers

    func testGeminiComesFirstThenTheAddOnsWithTheirTag() throws {
        let acc = try account(try document(Self.groupedJSON))
        let sections = try XCTUnwrap(UsagePresenter.sections(for: acc, language: .th))
        XCTAssertEqual(sections.map(\.group), [.gemini, .addon])
        XCTAssertEqual(sections.map(\.indices), [[0, 1, 2], [3, 4]])
        XCTAssertEqual(sections.map(\.title), ["Gemini", "ส่วนเสริม"])
        XCTAssertEqual(sections.map(\.tag), [nil, "ใช้โควตาแยก"])
        let english = try XCTUnwrap(UsagePresenter.sections(for: acc, language: .en))
        XCTAssertEqual(english.map(\.title), ["Gemini", "Add-ons"])
        XCTAssertEqual(english.last?.tag, "Separate quota")
    }

    func testAnUnknownGroupNameIsOtherAndComesLast() throws {
        let doc = try edited("\"group\": \"addon\"", "\"group\": \"weird\"")
        let acc = try account(doc)
        let sections = try XCTUnwrap(UsagePresenter.sections(for: acc, language: .en))
        XCTAssertEqual(sections.map(\.group), [.gemini, .addon, .other])
        XCTAssertEqual(sections.last?.title, "Other")
        XCTAssertEqual(sections.last?.indices, [3])
    }

    func testAFileWithAnyLimitWithoutAGroupIsFlat() throws {
        let doc = try edited(", \"group\": \"addon\"", "", last: true)
        let acc = try account(doc)
        XCTAssertNil(UsagePresenter.sections(for: acc, language: .en))
        XCTAssertNil(UsagePresenter.groupedOrder(acc))
        let cards = UsagePresenter.cards(for: doc, now: Fixtures.now, language: .en)
        XCTAssertNil(cards.first?.sections)
        XCTAssertEqual(cards.first?.rows.map(\.label),
                       ["Gemini Models · 5h", "Gemini Models · Weekly", "Gemini Argon · Weekly", "Claude & GPT · 5h", "Claude & GPT · Weekly"])
        XCTAssertTrue(cards.first?.rows.allSatisfy { $0.group == nil } ?? false)
    }

    func testAnOldFileWithNoGroupsKeepsItsOrderInTheCardAndTheWidgets() throws {
        let flat = Self.groupedJSON.replacingOccurrences(of: ", \"group\": \"gemini\"", with: "")
            .replacingOccurrences(of: ", \"group\": \"addon\"", with: "")
        let doc = try document(flat)
        XCTAssertNil(UsagePresenter.groupedOrder(try account(doc)))
        XCTAssertEqual(UsagePresenter.smallLines(for: doc, language: .en).first?.numberText, "42")
    }

    // MARK: Popover, small, medium and large

    func testThePopoverShowsOneLinePerGroup() throws {
        let acc = try account(try document(Self.groupedJSON))
        let th = try XCTUnwrap(AppUsageInsights.popoverSubline(acc, now: Fixtures.now, language: .th))
        XCTAssertEqual(th.text, "Gemini: โมเดล 5 ชม. 42% · โมเดล สัปดาห์ 60% · Argon สัปดาห์ 100%\nส่วนเสริม: Claude & GPT 5 ชม. 100% · สัปดาห์ 0%")
        XCTAssertFalse(th.isError)
        XCTAssertTrue(th.showsAllLines, "a group line wraps instead of being cut off")
        let en = try XCTUnwrap(AppUsageInsights.popoverSubline(acc, now: Fixtures.now, language: .en))
        XCTAssertEqual(en.text, "Gemini: Models 5h 42% · Models Weekly 60% · Argon Weekly 100%\nAdd-ons: Claude & GPT 5h 100% · Weekly 0%")
    }

    func testTheSmallWidgetRingIsTheGeminiLimit() throws {
        let doc = try document(Self.groupedJSON)
        let ring = try XCTUnwrap(UsagePresenter.smallLines(for: doc, language: .en).first)
        XCTAssertEqual(ring.windowLabel, "Gemini Models · 5h")
        XCTAssertEqual(ring.numberText, "42")
    }

    func testTheMediumWidgetRowIsTheFirstGeminiLimitNotTheMostUsed() throws {
        let doc = try document(Self.groupedJSON)
        let cards = UsagePresenter.cards(for: doc, now: Fixtures.now, language: .en)
        let row = try XCTUnwrap(UsagePresenter.mediumRows(for: cards, language: .en).first)
        XCTAssertEqual(row.label, "Gemini Models · 5h")
    }

    func testTheLargeWidgetKeepsGeminiBeforeTheAddOnsEvenWhenAnAddOnIsMostUsed() throws {
        let doc = try document(Self.groupedJSON)
        let cards = UsagePresenter.cards(for: doc, now: Fixtures.now, language: .en)
        let rows = UsagePresenter.largeRows(for: cards, language: .en)
        XCTAssertEqual(rows.map(\.label), [
            "Gemini Models · 5h", "Gemini Models · Weekly", "Gemini Argon · Weekly", "Claude & GPT · 5h", "Claude & GPT · Weekly",
        ])
        XCTAssertEqual(rows.map(\.group), [.gemini, .gemini, .gemini, .addon, .addon])
    }

    // MARK: Snapshots

    private var outputDirectory: URL {
        Fixtures.macFolder.appendingPathComponent("build/snapshots", isDirectory: true)
    }

    private func writePNG(_ data: Data?, _ name: String) throws {
        let png = try XCTUnwrap(data, name)
        try png.write(to: outputDirectory.appendingPathComponent(name))
        XCTAssertGreaterThan(png.count, 1_000, name)
    }

    func testRenderTheGroupedAgyCardInThaiAndEnglishInLightAndDark() throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let acc = try account(try document(Self.groupedJSON))
        for language in [UILanguage.th, .en] {
            for dark in [false, true] {
                let view = AppAccountCardView(account: acc, now: Fixtures.now, snapshot: true, startsOn: .quota)
                    .frame(width: contentWidth)
                let name = "agy-groups-card-\(language.rawValue)-\(dark ? "dark" : "light").png"
                try writePNG(SnapshotRenderer.fitting(view, dark: dark, language: language), name)
            }
        }
    }

    func testRenderThePopoverWithTheGroupedAgyLinesInThaiAndEnglishInLightAndDark() throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let state = AppUsageState(
            result: .loaded(try document(Self.groupedJSON)), now: Fixtures.now, isRefreshing: false, notice: nil
        )
        for language in [UILanguage.th, .en] {
            for dark in [false, true] {
                let view = MenuBarPopoverView(
                    state: state, onRefresh: {}, onOpenApp: {}, onQuit: {}, startsRevealed: true, startsHovered: 0
                )
                let name = "agy-groups-popover-\(language.rawValue)-\(dark ? "dark" : "light").png"
                try writePNG(SnapshotRenderer.fitting(view, dark: dark, language: language), name)
            }
        }
    }

    func testRenderTheGroupedAgyWidgetsInThaiAndEnglishInLightAndDark() throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let result = UsageLoadResult.loaded(try document(Self.groupedJSON))
        let frames: [UsageSize: CGSize] = [
            .small: CGSize(width: 170, height: 170),
            .medium: CGSize(width: 364, height: 170),
            .large: CGSize(width: 364, height: 382),
        ]
        for language in [UILanguage.th, .en] {
            for size in UsageSize.allCases {
                for dark in [false, true] {
                    let view = UsageScreenView(size: size, result: result, now: Fixtures.now)
                    let name = "agy-groups-\(size)-\(language.rawValue)-\(dark ? "dark" : "light").png"
                    try writePNG(SnapshotRenderer.png(view, size: try XCTUnwrap(frames[size]), dark: dark, language: language), name)
                }
            }
        }
    }
}
