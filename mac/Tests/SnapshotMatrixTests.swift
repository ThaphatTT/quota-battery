import SwiftUI
import XCTest

// Layout fit checks, and the snapshot matrix that uses them.
//
// The checks are geometry checks, not pixel checks. The needed height is the height a view takes when it is laid out at
// the frame's width, so wrapped text is counted. The needed width is the natural width, so text that would be cut off is
// caught. The medium row is measured without its reset text, because that text is allowed to drop when the row is short
// of width. Every PNG is also written, so each case can be looked at.

/// Measures a view without drawing it into a frame. `ImageRenderer` lays the view out at the size it asks for, so the
/// image it makes is the size the view needs. Scale 1 keeps one pixel per point.
@MainActor
enum LayoutFit {
    /// The height the view needs when it is laid out `width` points wide.
    static func height<V: View>(_ view: V, width: CGFloat, language: UILanguage, dark: Bool) -> CGFloat {
        measure(view.frame(width: width).fixedSize(horizontal: false, vertical: true), language: language, dark: dark).height
    }

    /// The width the view needs when nothing may shrink or wrap.
    static func naturalWidth<V: View>(_ view: V, language: UILanguage, dark: Bool) -> CGFloat {
        measure(view.fixedSize(), language: language, dark: dark).width
    }

    private static func measure<V: View>(_ view: V, language: UILanguage, dark: Bool) -> CGSize {
        let content = view
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.uiLanguage, language)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        guard let image = renderer.cgImage else { return .zero }
        return CGSize(width: CGFloat(image.width), height: CGFloat(image.height))
    }
}

/// The medium widget. Its rows may drop their reset text, so the width test uses the row without that text.
@MainActor
enum MediumFit {
    static let horizontalPadding: CGFloat = 16

    /// The problems found for one medium frame. Empty when the widget fits.
    static func problems(_ result: UsageLoadResult, frame: CGSize, language: UILanguage, dark: Bool) -> [String] {
        guard let document = result.document else { return ["no data document"] }
        let now = Fixtures.now
        var found: [String] = []

        let view = UsageScreenView(size: .medium, result: result, now: now)
        let needed = LayoutFit.height(view, width: frame.width, language: language, dark: dark)
        if needed > frame.height + 0.5 {
            found.append("needs \(Int(needed.rounded(.up))) pt tall, the frame is \(Int(frame.height)) pt")
        }

        let contentWidth = frame.width - 2 * horizontalPadding
        let updated = UsagePresenter.updatedValue(for: document, now: now, language: language)
        // The "+N" badge is in the header, beside the updated text. The header with its badge must fit the content width.
        let more = UsagePresenter.hiddenAccountCount(for: document, shown: UsagePresenter.mediumRowLimit)
        let header = WidgetHeader(trailing: updated.map { L10n.updated($0, language) }, moreCount: more)
        let headerWidth = LayoutFit.naturalWidth(header, language: language, dark: dark)
        if headerWidth > contentWidth + 0.5 {
            found.append("header needs \(Int(headerWidth.rounded(.up))) pt wide, the content is \(Int(contentWidth)) pt")
        }

        let cards = UsagePresenter.cards(for: document, now: now, language: language)
        for row in UsagePresenter.mediumRows(for: cards, language: language) {
            let floor = LimitRow(row: MediumRowFloor.row(row), layout: .inline)
            let width = LayoutFit.naturalWidth(floor, language: language, dark: dark)
            if width > contentWidth + 0.5 {
                found.append("\(row.name) row needs \(Int(width.rounded(.up))) pt wide, the content is \(Int(contentWidth)) pt")
            }
        }
        return found
    }
}

/// The part of a medium row that cannot give way: the row without its reset text. A row with no usage has no reset text,
/// so it is returned unchanged.
enum MediumRowFloor {
    static func row(_ row: LimitRowModel) -> LimitRowModel {
        guard row.hasUsage else { return row }
        var floor = row
        floor.subtitle = nil
        floor.subtitleIsError = false
        return floor
    }
}

/// The small and large widgets, which do not drop text: the whole view must fit the frame.
@MainActor
enum WholeFit {
    static func problems(size: UsageSize, result: UsageLoadResult, frame: CGSize, language: UILanguage, dark: Bool) -> [String] {
        let view = UsageScreenView(size: size, result: result, now: Fixtures.now)
        var found: [String] = []
        let needed = LayoutFit.height(view, width: frame.width, language: language, dark: dark)
        if needed > frame.height + 0.5 {
            found.append("needs \(Int(needed.rounded(.up))) pt tall, the frame is \(Int(frame.height)) pt")
        }
        // The no-data message wraps across lines, so its natural width is not a limit; its height at the frame's width is
        // checked above. Every other text in these widgets is one line, so its natural width is a limit.
        let hasAccounts = !(result.document?.accounts.isEmpty ?? true)
        let width = LayoutFit.naturalWidth(view, language: language, dark: dark)
        if hasAccounts, width > frame.width + 0.5 {
            found.append("needs \(Int(width.rounded(.up))) pt wide, the frame is \(Int(frame.width)) pt")
        }
        return found
    }
}

enum MatrixTier: String, CaseIterable {
    case white, yellow, red

    /// The used share of every limit: 32 is white, 85 is yellow and 95 is red.
    var used: Int {
        switch self {
        case .white: return 32
        case .yellow: return 85
        case .red: return 95
        }
    }
}

enum MatrixState: String {
    case ok, stale, error
}

/// One cell of the matrix. Tier and state mean nothing with no accounts, and the error state has no limits, so its tier
/// is nil. Those cells are written once.
struct MatrixCase {
    let accounts: Int
    let tier: MatrixTier?
    let state: MatrixState?

    var name: String {
        guard accounts > 0, let state else { return "acc0" }
        if state == .error { return "acc\(accounts)-error" }
        return "acc\(accounts)-\(tier?.rawValue ?? "na")-\(state.rawValue)"
    }

    /// Per size, language and appearance: 0 accounts once, then 1, 3 and 5 accounts with ok and stale in every tier and
    /// the error state once. That is 22 cases.
    static let all: [MatrixCase] = {
        var out = [MatrixCase(accounts: 0, tier: nil, state: nil)]
        for count in [1, 3, 5] {
            for state in [MatrixState.ok, .stale] {
                for tier in MatrixTier.allCases {
                    out.append(MatrixCase(accounts: count, tier: tier, state: state))
                }
            }
            out.append(MatrixCase(accounts: count, tier: nil, state: .error))
        }
        return out
    }()
}

/// Builds usage files for the matrix as JSON, in the contract's shape. Every account is fresh (ok), stale or in error.
enum MatrixData {
    private struct Person {
        let provider: String
        let label: String
        let plan: String
        let error: String
        let limits: [(key: String, label: String, window: Int?, resets: String)]
        let usage: String
        let credits: String
    }

    private static func claude(_ label: String) -> Person {
        Person(
            provider: "claude", label: label, plan: "Max", error: "ล็อกอิน Claude หมดอายุ เปิด Claude Code สักครั้ง",
            limits: [
                ("five_hour", "5 ชม.", 18_000, "2026-11-19T06:40:00Z"),
                ("seven_day", "สัปดาห์", 604_800, "2026-11-24T02:00:00Z"),
            ],
            usage: #"{"today": {"tokens": 1200000, "cost_usd": 18.4}}"#, credits: "null"
        )
    }

    private static func codex(_ label: String) -> Person {
        Person(
            provider: "codex", label: label, plan: "Plus", error: "ล็อกอิน Codex หมดอายุ เปิด codex สักครั้ง",
            limits: [("primary", "สัปดาห์", 604_800, "2026-11-20T02:00:00Z")],
            usage: "null", credits: #"{"extra_usage_enabled": false, "used_usd": null, "limit_usd": null, "balance_usd": 0}"#
        )
    }

    private static func agy() -> Person {
        Person(
            provider: "agy", label: "agy", plan: "free-tier", error: "ล็อกอิน agy หมดอายุ",
            limits: [
                ("claude", "Claude", nil, "2026-11-19T09:00:00Z"),
                ("gemini_pro", "Gemini Pro", nil, "2026-11-19T09:00:00Z"),
            ],
            usage: "null", credits: "null"
        )
    }

    /// One, three or five accounts. Five is two Claude, two ChatGPT and one agy, so the medium and small widgets show
    /// the "+N" badge with five.
    private static func people(_ count: Int) -> [Person] {
        switch count {
        case 1: return [claude("Claude")]
        case 3: return [claude("Claude"), codex("ChatGPT"), agy()]
        case 5: return [claude("Claude 1"), claude("Claude 2"), codex("ChatGPT 1"), codex("ChatGPT 2"), agy()]
        default: return []
        }
    }

    static func result(for matrixCase: MatrixCase) throws -> UsageLoadResult {
        let state = matrixCase.state ?? .ok
        let used = matrixCase.tier?.used ?? 0
        let accounts = people(matrixCase.accounts).map { account($0, used: used, state: state) }.joined(separator: ",")
        let json = #"{"generated_at": "2026-11-19T04:28:00Z", "accounts": [\#(accounts)]}"#
        return .loaded(try Fixtures.document(json))
    }

    private static func account(_ person: Person, used: Int, state: MatrixState) -> String {
        let status = state.rawValue
        let updated = state == .ok ? "\"2026-11-19T04:28:00Z\"" : (state == .stale ? "\"2026-11-19T01:30:00Z\"" : "null")
        let error = state == .ok ? "null" : "\"\(person.error)\""
        let code = state == .ok ? "null" : "\"login_expired\""
        let limits: [String] = state == .error ? [] : person.limits.map { limit -> String in
            let window = limit.window.map { String($0) } ?? "null"
            return #"{"key": "\#(limit.key)", "label": "\#(limit.label)", "window_seconds": \#(window), "used_percent": \#(used), "resets_at": "\#(limit.resets)"}"#
        }
        return #"{"provider": "\#(person.provider)", "label": "\#(person.label)", "plan": "\#(person.plan)", "status": "\#(status)", "error": \#(error), "error_code": \#(code), "updated_at": \#(updated), "limits": [\#(limits.joined(separator: ", "))], "usage": \#(person.usage), "credits": \#(person.credits)}"#
    }
}

/// The contact sheet: every PNG of the matrix in a grid, with its label.
enum ContactSheet {
    struct Entry {
        let section: String
        let file: String
        let caption: String
    }

    static func html(_ entries: [Entry]) -> String {
        var sections: [String] = []
        var order: [String] = []
        for entry in entries where !order.contains(entry.section) {
            order.append(entry.section)
        }
        for section in order {
            let figures = entries.filter { $0.section == section }.map { entry in
                "<figure><img src=\"\(entry.file)\" alt=\"\(entry.caption)\" loading=\"lazy\"><figcaption>\(entry.caption)</figcaption></figure>"
            }.joined(separator: "\n")
            sections.append("<section><h2>\(section)</h2><div class=\"grid\">\n\(figures)\n</div></section>")
        }
        return """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>AI Usage snapshot matrix</title>
        <style>
        body { font: 13px -apple-system, system-ui, sans-serif; margin: 16px; background: #f4f4f5; color: #1c1c1e; }
        h1 { font-size: 18px; } h2 { font-size: 15px; margin: 28px 0 8px; }
        .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(260px, 1fr)); gap: 12px; }
        figure { margin: 0; background: #fff; border-radius: 8px; padding: 8px; box-shadow: 0 1px 2px rgba(0,0,0,.08); }
        figure img { width: 100%; height: auto; display: block; border: 1px solid #d1d1d6; border-radius: 6px; }
        figcaption { margin-top: 6px; font-size: 11px; color: #3a3a3c; word-break: break-all; }
        </style>
        </head>
        <body>
        <h1>AI Usage snapshot matrix (\(entries.count) images)</h1>
        <p>Each image is a widget at its frame. Labels: size and frame, language, appearance, accounts, tier, state. "na" means the dimension cannot show for that case.</p>
        \(sections.joined(separator: "\n"))
        </body>
        </html>
        """
    }
}

/// The medium widget at the real frames and at 90% of them, with the medium rows at their most crowded.
@MainActor
final class MediumFitTests: XCTestCase {
    private let frames: [(name: String, size: CGSize)] = [
        ("329x155", CGSize(width: 329, height: 155)),
        ("364x170", CGSize(width: 364, height: 170)),
        ("329x155 at 90%", CGSize(width: 329 * 0.9, height: 155 * 0.9)),
        ("364x170 at 90%", CGSize(width: 364 * 0.9, height: 170 * 0.9)),
    ]

    func testTheMediumWidgetFitsEveryRealFrameAndItsNinetyPercentSize() throws {
        for count in [3, 5] {
            for tier in [MatrixTier.yellow, .red] {
                let result = try MatrixData.result(for: MatrixCase(accounts: count, tier: tier, state: .ok))
                for language in [UILanguage.th, .en] {
                    for dark in [false, true] {
                        for frame in frames {
                            let label = "\(count) accounts, \(tier.rawValue), \(language.rawValue), \(dark ? "dark" : "light"), \(frame.name)"
                            let view = UsageScreenView(size: .medium, result: result, now: Fixtures.now)
                            let needed = LayoutFit.height(view, width: frame.size.width, language: language, dark: dark)
                            print("MEDIUM-FIT \(label): needs \(String(format: "%.1f", needed)) of \(String(format: "%.1f", frame.size.height))")
                            let problems = MediumFit.problems(result, frame: frame.size, language: language, dark: dark)
                            XCTAssertEqual(problems, [], label)
                        }
                    }
                }
            }
        }
    }

    /// The Task 1 verification images: eleven medium widgets at the real frames and at 90%. They cover both languages and
    /// both appearances, the three- and five-account (badge) cases, the red and yellow tiers, the stale and error states.
    /// The five-account red case is at 90% in both languages and both appearances. Written to mac/build/snapshots/medium-fit.
    func testWriteTheMediumVerificationSnapshots() throws {
        let outputDirectory = Fixtures.macFolder.appendingPathComponent("build/snapshots/medium-fit", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let real = CGSize(width: 329, height: 155)
        let realWide = CGSize(width: 364, height: 170)
        let ninety = CGSize(width: 329 * 0.9, height: 155 * 0.9)
        let ninetyWide = CGSize(width: 364 * 0.9, height: 170 * 0.9)
        let shots: [(language: UILanguage, dark: Bool, count: Int, tier: MatrixTier, state: MatrixState, frame: CGSize, name: String)] = [
            (.th, false, 3, .red, .ok, real, "3acc-red-ok-329x155"),
            (.th, false, 3, .red, .ok, ninety, "3acc-red-ok-329x155-at90"),
            (.en, true, 3, .yellow, .stale, realWide, "3acc-yellow-stale-364x170"),
            (.en, true, 3, .yellow, .stale, ninetyWide, "3acc-yellow-stale-364x170-at90"),
            (.th, true, 5, .red, .ok, real, "5acc-red-ok-329x155"),
            (.en, false, 5, .red, .ok, real, "5acc-red-ok-329x155"),
            (.th, false, 5, .red, .ok, ninety, "5acc-red-ok-329x155-at90"),
            (.en, false, 5, .red, .ok, ninety, "5acc-red-ok-329x155-at90"),
            (.th, true, 5, .red, .ok, ninety, "5acc-red-ok-329x155-at90"),
            (.en, true, 5, .red, .ok, ninety, "5acc-red-ok-329x155-at90"),
            (.en, true, 5, .yellow, .error, real, "5acc-error-329x155"),
        ]
        for shot in shots {
            let result = try MatrixData.result(for: MatrixCase(accounts: shot.count, tier: shot.tier, state: shot.state))
            let file = "\(shot.language.rawValue)-\(shot.dark ? "dark" : "light")-\(shot.name).png"
            let view = UsageScreenView(size: .medium, result: result, now: Fixtures.now)
            let data = try XCTUnwrap(SnapshotRenderer.png(view, size: shot.frame, dark: shot.dark, language: shot.language), file)
            try data.write(to: outputDirectory.appendingPathComponent(file))
        }
        XCTAssertEqual(shots.count, 11)
    }

    /// A positive control: the check must catch a row that cannot fit. A nickname far longer than any real one must fail.
    func testTheCheckCatchesAPlantedOverlongNickname() throws {
        let longName = String(repeating: "งานพิเศษ", count: 8)
        let json = #"{"generated_at": "2026-11-19T04:28:00Z", "accounts": [{"provider": "claude", "label": "\#(longName)", "plan": "Max", "status": "ok", "error": null, "updated_at": "2026-11-19T04:28:00Z", "limits": [{"key": "five_hour", "label": "5 ชม.", "window_seconds": 18000, "used_percent": 32, "resets_at": "2026-11-19T06:40:00Z"}], "usage": null, "credits": null}]}"#
        let result = UsageLoadResult.loaded(try Fixtures.document(json))
        let problems = MediumFit.problems(result, frame: CGSize(width: 329, height: 155), language: .th, dark: false)
        XCTAssertFalse(problems.isEmpty, "the check did not catch a nickname that cannot fit")
    }
}

/// The small widget at its real frame and at 90% of it. The five-account case is the badge case: the "+2" badge sits in the
/// update cell under the age text. The real frame is checked. The 90% frame is measured and written, not checked: the small
/// widget was never laid out to fit it (docs/TESTING.md, section 4).
@MainActor
final class SmallFitTests: XCTestCase {
    func testTheSmallWidgetFitsItsRealFrame() throws {
        for count in [3, 5] {
            for tier in [MatrixTier.yellow, .red] {
                let result = try MatrixData.result(for: MatrixCase(accounts: count, tier: tier, state: .ok))
                for language in [UILanguage.th, .en] {
                    for dark in [false, true] {
                        let label = "\(count) accounts, \(tier.rawValue), \(language.rawValue), \(dark ? "dark" : "light"), 170x170"
                        let problems = WholeFit.problems(size: .small, result: result, frame: CGSize(width: 170, height: 170), language: language, dark: dark)
                        XCTAssertEqual(problems, [], label)
                    }
                }
            }
        }
    }

    /// The verification images: eight small widgets with five accounts (red, ok), in both languages and both appearances, at
    /// the real frame and at 90%. Written to mac/build/snapshots/small-fit. The natural width of each is printed, so the 90%
    /// frame can be read against it.
    func testWriteTheSmallVerificationSnapshots() throws {
        let outputDirectory = Fixtures.macFolder.appendingPathComponent("build/snapshots/small-fit", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let result = try MatrixData.result(for: MatrixCase(accounts: 5, tier: .red, state: .ok))
        let frames: [(suffix: String, size: CGSize)] = [
            ("170x170", CGSize(width: 170, height: 170)),
            ("170x170-at90", CGSize(width: 170 * 0.9, height: 170 * 0.9)),
        ]
        var written = 0
        for language in [UILanguage.th, .en] {
            for dark in [false, true] {
                for frame in frames {
                    let file = "\(language.rawValue)-\(dark ? "dark" : "light")-5acc-red-ok-\(frame.suffix).png"
                    let view = UsageScreenView(size: .small, result: result, now: Fixtures.now)
                    let needed = LayoutFit.naturalWidth(view, language: language, dark: dark)
                    print("SMALL-FIT \(file): needs \(String(format: "%.1f", needed)) pt wide, the frame is \(String(format: "%.1f", frame.size.width)) pt")
                    let data = try XCTUnwrap(SnapshotRenderer.png(view, size: frame.size, dark: dark, language: language), file)
                    try data.write(to: outputDirectory.appendingPathComponent(file))
                    written += 1
                }
            }
        }
        XCTAssertEqual(written, 8)
    }
}

/// The snapshot matrix: small, medium (at both real frames) and large, in Thai and English, light and dark, with 0, 1, 3
/// and 5 accounts, the three tiers and the three states. Each PNG goes to mac/build/snapshots/matrix, and index.html is
/// the contact sheet. Each image is also checked against its frame.
@MainActor
final class SnapshotMatrixTests: XCTestCase {
    private struct FrameSpec {
        let size: UsageSize
        let label: String
        let frame: CGSize
    }

    private let frames: [FrameSpec] = [
        FrameSpec(size: .small, label: "170x170", frame: CGSize(width: 170, height: 170)),
        FrameSpec(size: .medium, label: "329x155", frame: CGSize(width: 329, height: 155)),
        FrameSpec(size: .medium, label: "364x170", frame: CGSize(width: 364, height: 170)),
        FrameSpec(size: .large, label: "364x382", frame: CGSize(width: 364, height: 382)),
    ]

    func testEveryMatrixImageFitsItsFrameAndTheContactSheetIsWritten() throws {
        let outputDirectory = Fixtures.macFolder.appendingPathComponent("build/snapshots/matrix", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        var failures: [String] = []
        var entries: [ContactSheet.Entry] = []
        var written = 0
        for spec in frames {
            for language in [UILanguage.th, .en] {
                for dark in [false, true] {
                    for matrixCase in MatrixCase.all {
                        let result = try MatrixData.result(for: matrixCase)
                        let appearance = dark ? "dark" : "light"
                        let file = "\(spec.size)-\(spec.label)_\(language.rawValue)_\(appearance)_\(matrixCase.name).png"
                        let view = UsageScreenView(size: spec.size, result: result, now: Fixtures.now)
                        let data = try XCTUnwrap(
                            SnapshotRenderer.png(view, size: spec.frame, dark: dark, language: language), file
                        )
                        try data.write(to: outputDirectory.appendingPathComponent(file))
                        written += 1

                        let problems = spec.size == .medium
                            ? MediumFit.problems(result, frame: spec.frame, language: language, dark: dark)
                            : WholeFit.problems(size: spec.size, result: result, frame: spec.frame, language: language, dark: dark)
                        for problem in problems {
                            failures.append("\(file): \(problem)")
                        }
                        let caption = "\(spec.size) \(spec.label) · \(language.rawValue) · \(appearance) · \(matrixCase.name)"
                        entries.append(ContactSheet.Entry(section: "\(spec.size) \(spec.label)", file: file, caption: caption))
                    }
                }
            }
        }

        let sheet = ContactSheet.html(entries)
        try sheet.write(to: outputDirectory.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        print("MATRIX written \(written) images, \(failures.count) fit problems")
        XCTAssertEqual(written, frames.count * 2 * 2 * MatrixCase.all.count)
        XCTAssertEqual(failures, [], "matrix images that do not fit:\n" + failures.joined(separator: "\n"))
    }
}
