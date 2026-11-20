import SwiftUI

/// The two tabs of an account card. The choice is kept in the card's own state only: it is not saved, and it lasts
/// while the app runs.
enum CardTab: Hashable {
    case quota
    case modelMix
}

/// One account card in the app window. At the top right, a segmented tab "Quota | Model mix" (only for an account that has
/// a mix). Below it, the header and the chosen tab. The tabs slide sideways (about 0.25 s, eased) and the card's height
/// follows; with Reduce Motion they cross-fade.
///
/// The view is Equatable on its data and not on its actions (closures), so the window draws a card again only when that
/// card's account, mix or the minute changes (see `ContentView`).
struct AppAccountCardView: View, Equatable {
    let account: UsageAccount
    let now: Date
    /// The account's mix, or nil when it has none (then there is no tab).
    let mix: AccountModelMix?
    var actions: ModelMixActions
    /// Set only by the snapshot tests: draws the look-alike tab control and the look-alike slider.
    var snapshot: Bool
    @State private var tab: CardTab
    @Environment(\.uiLanguage) private var language
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        account: UsageAccount,
        now: Date,
        mix: AccountModelMix? = nil,
        actions: ModelMixActions = ModelMixActions(),
        snapshot: Bool = false,
        startsOn: CardTab = .quota
    ) {
        self.account = account
        self.now = now
        self.mix = mix
        self.actions = actions
        self.snapshot = snapshot
        _tab = State(initialValue: startsOn)
    }

    static func == (lhs: AppAccountCardView, rhs: AppAccountCardView) -> Bool {
        lhs.account == rhs.account && lhs.now == rhs.now && lhs.mix == rhs.mix && lhs.snapshot == rhs.snapshot
    }

    /// The tab shown now. An account that has no mix always shows its quota.
    private var shownTab: CardTab { mix == nil ? .quota : tab }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if mix != nil {
                tabRow
            }
            header
            if AppUsageInsights.isProblem(account), let error = AppUsageInsights.errorText(account, language: language) {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(LocalPalette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            tabContent
                .clipped()
                .animation(reduceMotion ? .easeInOut(duration: 0.15) : .easeInOut(duration: 0.25), value: shownTab)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
    }

    /// The segmented tab at the top right of the card.
    private var tabRow: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            if snapshot {
                SegmentedLook(selection: tab, options: [
                    (CardTab.quota, L10n.text(.cardTabQuota, language)),
                    (CardTab.modelMix, L10n.text(.cardTabModelMix, language)),
                ])
                .frame(width: 240)
            } else {
                Picker(L10n.text(.cardTabLabel, language), selection: $tab) {
                    Text(L10n.text(.cardTabQuota, language)).tag(CardTab.quota)
                    Text(L10n.text(.cardTabModelMix, language)).tag(CardTab.modelMix)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    /// The chosen tab. Each side slides in from its own edge; with Reduce Motion both fade.
    @ViewBuilder
    private var tabContent: some View {
        ZStack(alignment: .topLeading) {
            if shownTab == .quota {
                quotaBody
                    .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .leading)))
            } else if let mix {
                AccountModelMixView(account: account, mix: mix, actions: actions, snapshot: snapshot)
                    .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var quotaBody: some View {
        let tiles = AppUsageInsights.usageTiles(account, mix: mix, shownPercents: nil, language: language)
        return VStack(alignment: .leading, spacing: 10) {
            if AppUsageInsights.usesCompactLimits(account) {
                compactList
            } else {
                standardRows
            }
            if !tiles.isEmpty {
                Divider()
                HStack(spacing: 10) {
                    ForEach(tiles, id: \.title) { tile in
                        UsageTileView(tile: tile)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One line: the brand icon, the name with its plan, and the Almost-out pill at the right. The provider's subtitle
    /// is in the tooltip and is read by VoiceOver with the name.
    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            LocalBrandIcon(
                letter: AppUsageInsights.brandLetter(for: account),
                color: LocalPalette.brand(for: account.provider),
                size: 24
            )
            Text(AppUsageInsights.displayName(account))
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .layoutPriority(1)
            if let plan = AppUsageInsights.planTag(account) {
                PlanTag(text: plan)
            }
            Spacer(minLength: 8)
            if AppUsageInsights.isNearFull(account) {
                // One pill for the account, in the colour of its worst limit.
                LocalNearFullPill(tier: UsageFormat.tier(AppUsageInsights.highestPercent(account)))
            }
        }
        .help(AppUsageInsights.subtitle(for: account.provider) ?? "")
        .accessibilityElement(children: .combine)
    }

    private var standardRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(account.limits.enumerated()), id: \.offset) { index, limit in
                StandardLimitRow(
                    limit: limit,
                    now: now,
                    credit: index == 0 ? AppUsageInsights.creditText(account, language: language) : nil
                )
            }
        }
    }

    private var compactList: some View {
        VStack(spacing: 0) {
            ForEach(Array(account.limits.enumerated()), id: \.offset) { index, limit in
                CompactLimitRow(limit: limit, now: now)
                if index < account.limits.count - 1 {
                    Divider()
                }
            }
        }
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }
}

/// A limit on ONE line: the label and its reset text, a bar that drains across the middle, and what is left at the end.
/// What is used is in the tooltip and is read by VoiceOver. The bar and the number take the tier colour, so they turn
/// yellow at 80% used and red at 95%. The credit text, when the balance is known, follows the reset text on the first limit.
struct StandardLimitRow: View {
    let limit: UsageLimit
    let now: Date
    let credit: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.uiLanguage) private var language
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let used = limit.usedPercent
        let tier = UsageFormat.tier(used)
        let alert = UsageFormat.isAlert(used)
        let label = UsageFormat.windowLabel(limit, language: language)
        HStack(alignment: .center, spacing: 8) {
            HStack(spacing: 5) {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .fixedSize()
                if let line = resetLine {
                    Text("· \(line)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .layoutPriority(1)
            LocalUsageBar(
                fraction: UsageFormat.remainingFraction(used),
                color: tier.color(colorScheme),
                height: 6
            )
            .frame(minWidth: 40, maxWidth: .infinity)
            if alert {
                Circle()
                    .fill(tier.color(colorScheme))
                    .frame(width: 6, height: 6)
            }
            Text(UsageFormat.leftText(used, language))
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(tier.color(colorScheme))
                .lineLimit(1)
                .fixedSize()
                .contentTransition(.numericText(value: Double(UsageFormat.leftWhole(used) ?? 0)))
        }
        .help(UsageFormat.usedText(used, language))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([label, resetLine].compactMap { $0 }.joined(separator: " "))
        .accessibilityValue("\(UsageFormat.leftText(used, language)), \(UsageFormat.usedText(used, language))")
        .modifier(AlertPulse(isAlert: alert))
        .animation(LocalMotion.spring(reduced: reduceMotion), value: used)
    }

    /// The reset text and, on the first limit, the credit text when the balance is known.
    private var resetLine: String? {
        let parts = [UsageFormat.resetText(resetsAt: limit.resetsAt, now: now, language: language), credit]
            .compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// One line of the compact list: a dot, the label, the reset, a thin bar that drains, and what is left with what is used.
struct CompactLimitRow: View {
    let limit: UsageLimit
    let now: Date
    @Environment(\.uiLanguage) private var language
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let used = limit.usedPercent
        let tier = UsageFormat.tier(used)
        HStack(spacing: 8) {
            Circle()
                .fill(tier.color(colorScheme))
                .frame(width: 6, height: 6)
            Text(UsageFormat.windowLabel(limit, language: language))
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            if let reset = UsageFormat.resetText(resetsAt: limit.resetsAt, now: now, language: language) {
                Text("· \(reset)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            LocalUsageBar(
                fraction: UsageFormat.remainingFraction(used),
                color: tier.color(colorScheme),
                height: 4
            )
            .frame(minWidth: 48, idealWidth: 64, maxWidth: 84)
            VStack(alignment: .trailing, spacing: 0) {
                Text(UsageFormat.leftText(used, language))
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(tier.color(colorScheme))
                    .lineLimit(1)
                    .fixedSize()
                    .contentTransition(.numericText(value: Double(UsageFormat.leftWhole(used) ?? 0)))
                Text(UsageFormat.usedText(used, language))
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(minWidth: 52, idealWidth: 60, alignment: .trailing)
        }
        .padding(.vertical, 7)
        .modifier(AlertPulse(isAlert: UsageFormat.isAlert(used)))
    }
}

/// The "Today" or "This month" tile: the money as the main number, in green, and the tokens under it. While the Model mix
/// is a trial, the big value is the what-if cost with a yellow Trial tag, and the real cost is shown under it with the
/// tokens. A thin colour bar under the numbers splits the period by model, in the same colours as the mix rows.
struct UsageTileView: View {
    let tile: AppUsageInsights.UsageTile
    @Environment(\.uiLanguage) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(tile.title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            if let trial = tile.trialCostText {
                HStack(spacing: 6) {
                    Text(trial)
                        .font(.system(size: 15, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                    TrialTag()
                }
                Text(trialDetail)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(tile.costText ?? tile.tokensText)
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(tile.costText == nil ? Color.primary : LocalPalette.healthy)
                    .lineLimit(1)
                if tile.costText != nil {
                    Text(tile.tokensText)
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            TileShareBar(segments: tile.bar, language: language)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
        )
    }

    /// The real cost and the tokens, under a trial value: "จริง ~$12.40 · 35M tokens".
    private var trialDetail: String {
        [tile.costText.map { L10n.actualValue($0, language) }, tile.tokensText]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

/// The yellow "ทดลอง / Trial" tag: the shown mix is not the real one.
struct TrialTag: View {
    @Environment(\.uiLanguage) private var language

    var body: some View {
        Text(L10n.text(.trialTag, language))
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(LocalPalette.warning)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(LocalPalette.warning.opacity(0.16)))
            .overlay(Capsule().stroke(LocalPalette.warning.opacity(0.45), lineWidth: 0.5))
    }
}

/// A thin bar split by model, in the colours of the mix rows. VoiceOver reads each model's share.
struct TileShareBar: View {
    let segments: [AppUsageInsights.TileBarSegment]
    let language: UILanguage

    var body: some View {
        if segments.isEmpty {
            EmptyView()
        } else {
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                        Rectangle()
                            .fill(ModelMixColor.color(for: segment.family))
                            .frame(width: geometry.size.width * CGFloat(segment.percent) / 100)
                    }
                }
            }
            .frame(height: 4)
            .clipShape(Capsule())
            .background(Capsule().fill(Color.primary.opacity(0.08)))
            .padding(.top, 2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.shareByModel(segments.map { "\($0.label) \($0.percent)%" }, language))
        }
    }
}

/// The pill "ใกล้หมด" / "Almost out", in the tier colour of the limit it marks: yellow or red.
struct LocalNearFullPill: View {
    let tier: UsageTier
    @Environment(\.uiLanguage) private var language
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colour = tier.color(colorScheme)
        Text(L10n.text(.almostOut, language))
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(colour)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(colour.opacity(0.16)))
            .overlay(Capsule().stroke(colour.opacity(0.45), lineWidth: 0.5))
    }
}

/// The plan of an account, such as "Max 5x" or "free-tier".
struct PlanTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
            .overlay(Capsule().stroke(Color.primary.opacity(0.15), lineWidth: 0.5))
    }
}

/// Shown whenever there is no usable data.
struct AppNoDataView: View {
    @Environment(\.uiLanguage) private var language

    var body: some View {
        Text(L10n.text(.noData, language))
            .font(.system(size: 13, weight: .semibold))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
