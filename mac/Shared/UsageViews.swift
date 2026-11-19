import SwiftUI

extension Color {
    /// "#D97757" or "D97757".
    init(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let value = UInt32(digits, radix: 16) ?? 0
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

/// Colours that follow the system appearance: dark ink in light mode, white ink in dark mode.
/// Use these instead of literal white or black, or light mode breaks.
enum UsageTheme {
    /// Secondary text: about 55% of the ink colour.
    static let secondary = Color.primary.opacity(0.55)
    /// Ring and gauge tracks, and hairline separators.
    static let track = Color.primary.opacity(0.14)
    static let hairline = Color.primary.opacity(0.14)
    /// The gauge outline and nub, when the limit is not red.
    static let outline = Color.primary.opacity(0.42)
    /// Background tile of the small widget's update cell.
    static let tile = Color.primary.opacity(0.07)
    /// The green dot in the small widget's update cell.
    static let freshDot = Color(hex: "#30D158")
    /// The grey dot at the end of the large widget's footer.
    static let footerDot = Color.primary.opacity(0.35)
}

extension UsageTier {
    /// The colour of the tier. `plenty` is white on dark and the primary ink in light mode. Yellow and red are fixed
    /// per appearance: `#FFD60A` and `#FF5F57` on dark, `#B58900` and `#D93025` on light.
    func color(_ scheme: ColorScheme) -> Color {
        guard let hex = hex(dark: scheme == .dark) else { return scheme == .dark ? .white : .primary }
        return Color(hex: hex)
    }
}

extension ProviderStyle {
    /// The brand colour as a SwiftUI colour. Only the brand icons use it: gauges and rings never do.
    static func color(for provider: String) -> Color {
        Color(hex: accentHex(for: provider))
    }
}

/// A 20 pt rounded square in the brand colour, with a white letter (C, G or A).
struct BrandIcon: View {
    let provider: String
    var size: CGFloat = 20

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
            .fill(ProviderStyle.color(for: provider))
            .frame(width: size, height: size)
            .overlay {
                Text(ProviderStyle.iconLetter(for: provider))
                    .font(.system(size: size * 0.6, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

/// Apple-style battery capsule: a rounded outline with a nub on the right. The fill is what is LEFT, so it drains as
/// usage grows, and it takes the tier colour. The outline turns red at 95% used. Unknown usage draws an empty gauge.
struct BatteryGauge: View {
    let usedPercent: Double?
    var size = CGSize(width: 24, height: 11)
    var animation: Animation = .smooth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let fraction = UsageFormat.remainingFraction(usedPercent)
        let tier = UsageFormat.tier(usedPercent)
        let outline = tier == .critical ? tier.color(colorScheme) : UsageTheme.outline
        let inset: CGFloat = 2
        let inner = size.width - 2 * inset
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: size.height * 0.3, style: .continuous)
                    .stroke(outline, lineWidth: 1)
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(tier.color(colorScheme))
                    .frame(
                        width: UsageFormat.fillWidth(fraction: fraction, available: inner),
                        height: size.height - 2 * inset
                    )
                    .padding(.leading, inset)
            }
            .frame(width: size.width, height: size.height)
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(outline)
                .frame(width: 1.5, height: size.height * 0.4)
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : animation, value: fraction)
    }
}

/// A ring that fills clockwise from 12 o'clock over a faint track. The arc is what is LEFT, so a full ring means
/// everything is left. The arc takes the tier colour. Unknown usage draws only the track. Put any number in the centre
/// yourself.
struct UsageRing: View {
    let usedPercent: Double?
    var lineWidth: CGFloat = 6
    var animation: Animation = .smooth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let fraction = UsageFormat.remainingFraction(usedPercent)
        let tier = UsageFormat.tier(usedPercent)
        ZStack {
            Circle()
                .stroke(UsageTheme.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(tier.color(colorScheme), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : animation, value: fraction)
    }
}

/// The tag on a row that is yellow or red: "ใกล้หมด" / "Almost out", in the row's own tier colour.
struct NearFullPill: View {
    let tier: UsageTier
    @Environment(\.uiLanguage) private var language
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colour = tier.color(colorScheme)
        Text(L10n.text(.almostOut, language))
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(colour)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(colour.opacity(0.18)))
    }
}

/// The "+N" capsule of the small and medium widgets: the accounts past the first three. It is quiet on purpose, with
/// secondary text on a translucent fill at about 10 pt, so it never competes with the rings and rows. Its spoken text is
/// "อีก N บัญชี" / "N more accounts".
struct MoreAccountsBadge: View {
    let count: Int
    @Environment(\.uiLanguage) private var language

    var body: some View {
        Text(verbatim: "+\(count)")
            .font(.system(size: 10, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(UsageTheme.secondary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(UsageTheme.track))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.moreAccounts(count, language))
    }
}

/// One limit row: brand icon, title and subtitle, then the pill (yellow or red rows only), the two numbers and the
/// battery gauge. `.stacked` is for the large widget (subtitle under the title). `.inline` is for the medium widget
/// (subtitle after the title on one line). A row with no usage draws no number and no gauge.
struct LimitRow: View {
    enum Layout { case stacked, inline }

    let row: LimitRowModel
    var layout: Layout = .stacked
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            BrandIcon(provider: row.provider)
            textBlock
                .frame(maxWidth: .infinity, alignment: .leading)
            if row.showsNearFull {
                NearFullPill(tier: row.tier)
            }
            if row.hasUsage {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(row.leftText)
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(row.tier.color(colorScheme))
                        .lineLimit(1)
                        .fixedSize()
                        .contentTransition(.numericText(value: Double(UsageFormat.leftWhole(row.usedPercent) ?? 0)))
                    if let usedText = row.usedText {
                        Text(usedText)
                            .font(.system(size: 10))
                            .monospacedDigit()
                            .foregroundStyle(UsageTheme.secondary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                BatteryGauge(usedPercent: row.usedPercent)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.spokenText)
    }

    @ViewBuilder
    private var textBlock: some View {
        switch layout {
        case .stacked:
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if let subtitle = row.subtitle {
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(row.subtitleIsError ? Color.orange : UsageTheme.secondary)
                        .lineLimit(1)
                }
            }
        case .inline:
            if row.hasUsage {
                // The reset text drops first when the row is too wide for it: the window label stays, and then only the title.
                ViewThatFits(in: .horizontal) {
                    inlineLine(row.subtitle)
                    inlineLine(row.label)
                    inlineLine(nil)
                }
            } else {
                inlineLine(row.subtitle)
            }
        }
    }

    /// The title and an optional subtitle on one line. With usage, the subtitle keeps its natural width (`fixedSize`), so
    /// ViewThatFits can measure it and drop it. A row with no usage (an error text) may shrink its subtitle instead.
    private func inlineLine(_ subtitle: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(row.title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .fixedSize()
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(row.subtitleIsError ? Color.orange : UsageTheme.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: row.hasUsage, vertical: false)
            }
        }
    }
}

/// The three layouts. The app and the widget share them.
enum UsageSize: CaseIterable {
    case small, medium, large
}

/// A 0.5 pt separator in the hairline colour.
struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(UsageTheme.hairline)
            .frame(height: 0.5)
    }
}

/// The title row of the medium and large widgets, with an optional note on the right. The medium widget also puts its
/// "+N" badge here, at the far right after the note, so the badge never sits under a row.
struct WidgetHeader: View {
    let trailing: String?
    /// The accounts past the first three, shown as the "+N" badge at the far right. Zero draws no badge.
    var moreCount = 0
    @Environment(\.uiLanguage) private var language

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(L10n.text(.usageTitle, language))
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 4)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 10))
                    .foregroundStyle(UsageTheme.secondary)
                    .lineLimit(1)
            }
            if moreCount > 0 {
                MoreAccountsBadge(count: moreCount)
            }
        }
    }
}

/// Small: a 2 x 2 grid. Three rings, each with the most important limit of an account and its name below,
/// and one tile with the age of the data. Each ring shows only the number of what is left.
struct UsageSmallView: View {
    let lines: [SmallLineModel]
    /// The age of the data, for example "2 นาทีก่อน" or "2 min ago", or nil when there is no time.
    let updatedValue: String?
    /// The accounts past the first three, shown as the "+N" badge under the age text in the update cell. Zero draws no badge.
    var moreCount = 0
    @Environment(\.uiLanguage) private var language
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                ringCell(0)
                ringCell(1)
            }
            HStack(spacing: 8) {
                ringCell(2)
                updateCell
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func ringCell(_ index: Int) -> some View {
        if index < lines.count {
            let line = lines[index]
            VStack(spacing: 3) {
                ZStack {
                    UsageRing(usedPercent: line.usedPercent, lineWidth: 6)
                        .frame(width: 48, height: 48)
                    Text(line.numberText)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(line.tier.color(colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText(value: Double(UsageFormat.leftWhole(line.usedPercent) ?? 0)))
                }
                Text(line.name)
                    .font(.system(size: 10.5))
                    .foregroundStyle(UsageTheme.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(line.accessibilityText)
        } else {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var updateCell: some View {
        VStack(spacing: 2) {
            Text(L10n.text(.updatedLabel, language))
                .font(.system(size: 10))
                .foregroundStyle(UsageTheme.secondary)
            Text(updatedValue ?? "—")
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            // The badge sits under the age text, centred in the cell. The age text and the badge cannot share one line in a
            // cell this narrow, so the badge takes the line below it and stays inside the cell, clear of every ring.
            if moreCount > 0 {
                MoreAccountsBadge(count: moreCount)
            }
            Circle()
                .fill(UsageTheme.freshDot)
                .frame(width: 5, height: 5)
                .padding(.top, 3)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(UsageTheme.tile))
    }
}

/// The spacing of the medium widget. A row's numbers column is 30 pt tall, so three rows and the header fit the real
/// 329 x 155 frame only with tight spacing. The "+N" badge is in the header, so it takes no room below the rows and the
/// spacing is the same with or without it.
enum MediumLayout {
    /// Space above the header and below the rows: the content box of the medium widget.
    static let verticalPadding: CGFloat = 6
    /// Space above and below each row.
    static let rowPadding: CGFloat = 2
}

/// Medium: one row per account (the first three), each with its highest limit on one line.
struct UsageMediumView: View {
    let rows: [LimitRowModel]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                if row.id != rows.first?.id {
                    Hairline()
                }
                LimitRow(row: row, layout: .inline)
                    .padding(.vertical, MediumLayout.rowPadding)
                    .transition(.opacity)
            }
        }
        .animation(.smooth, value: rows)
    }
}

/// Large: one row per limit, in file order, at most `UsagePresenter.largeRowLimit` rows.
/// Used on its own by the app window too, so it has no header or footer.
struct UsageLargeView: View {
    let cards: [AccountCardModel]
    @Environment(\.uiLanguage) private var language

    var body: some View {
        let rows = UsagePresenter.largeRows(for: cards, language: language)
        VStack(spacing: 0) {
            ForEach(rows) { row in
                if row.id != rows.first?.id {
                    Hairline()
                }
                LimitRow(row: row, layout: .stacked)
                    .padding(.vertical, 11)
                    .transition(.opacity)
            }
        }
        .animation(.smooth, value: rows)
    }
}

/// Shown whenever there is no usable data.
struct UsageNoDataView: View {
    @Environment(\.uiLanguage) private var language

    var body: some View {
        Text(L10n.text(.noData, language))
            .font(.system(size: 13, weight: .semibold))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The whole widget content for one size. Missing, broken or empty data shows the no-data view.
struct UsageScreenView: View {
    let size: UsageSize
    let result: UsageLoadResult
    let now: Date
    @Environment(\.uiLanguage) private var language

    var body: some View {
        Group {
            if let document = result.document, !document.accounts.isEmpty {
                content(for: document)
            } else {
                UsageNoDataView()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, verticalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The space above and below the content: 10 pt for small, `MediumLayout.verticalPadding` for medium, 14 pt for large.
    private var verticalPadding: CGFloat {
        switch size {
        case .small: return 10
        case .medium: return MediumLayout.verticalPadding
        case .large: return 14
        }
    }

    /// The "+N" count for this size: the accounts the size leaves out. The large widget shows its own rows and has none.
    private func moreCount(for document: UsageDocument) -> Int {
        switch size {
        case .small:
            return UsagePresenter.hiddenAccountCount(for: document, shown: UsagePresenter.smallRingLimit)
        case .medium:
            return UsagePresenter.hiddenAccountCount(for: document, shown: UsagePresenter.mediumRowLimit)
        case .large:
            return 0
        }
    }

    @ViewBuilder
    private func content(for document: UsageDocument) -> some View {
        let cards = UsagePresenter.cards(for: document, now: now, language: language)
        let updated = UsagePresenter.updatedValue(for: document, now: now, language: language)
        let more = moreCount(for: document)
        switch size {
        case .small:
            UsageSmallView(
                lines: UsagePresenter.smallLines(for: document, language: language),
                updatedValue: updated,
                moreCount: more
            )
        case .medium:
            VStack(alignment: .leading, spacing: 6) {
                WidgetHeader(trailing: updated.map { L10n.updated($0, language) }, moreCount: more)
                UsageMediumView(rows: UsagePresenter.mediumRows(for: cards, language: language))
                Spacer(minLength: 0)
            }
        case .large:
            VStack(alignment: .leading, spacing: 6) {
                WidgetHeader(trailing: L10n.text(.limitsHeader, language))
                UsageLargeView(cards: cards)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Text(updated.map { L10n.updated($0, language) } ?? "")
                        .font(.system(size: 10))
                        .foregroundStyle(UsageTheme.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Circle()
                        .fill(UsageTheme.footerDot)
                        .frame(width: 5, height: 5)
                }
            }
        }
    }
}
