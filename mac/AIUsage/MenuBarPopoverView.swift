import SwiftUI

/// The menu bar popover, 300 pt wide. NSPopover draws the panel, so this view draws only the content.
struct MenuBarPopoverView: View {
    let state: AppUsageState
    let onRefresh: () -> Void
    let onOpenApp: () -> Void
    let onQuit: () -> Void

    @State private var revealed: Bool
    /// How the rows enter. Nil until the rows are first shown; then `slide` the first time the popover opens in the app
    /// session, and `none` after that, so a later opening draws at once.
    @State private var intro: IntroStyle?
    @State private var hovered: Int?
    @State private var quitHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.uiLanguage) private var language

    private var motion: MotionLevel { MotionLevel.resolve(reduceMotion: reduceMotion, snapshot: startsRevealed) }

    /// Snapshots start with every row shown and one row hovered. The live popover fades the rows in when it opens.
    init(
        state: AppUsageState,
        onRefresh: @escaping () -> Void,
        onOpenApp: @escaping () -> Void,
        onQuit: @escaping () -> Void,
        startsRevealed: Bool = false,
        startsHovered: Int? = nil
    ) {
        self.state = state
        self.onRefresh = onRefresh
        self.onOpenApp = onOpenApp
        self.onQuit = onQuit
        _revealed = State(initialValue: startsRevealed)
        _intro = State(initialValue: startsRevealed ? IntroStyle.none : nil)
        _hovered = State(initialValue: startsHovered)
        self.startsRevealed = startsRevealed
    }

    /// Set by a snapshot (the rows start shown). A snapshot draws still motion and no first-open motion.
    private let startsRevealed: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            rows
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            if let total = state.popoverTotal {
                Divider()
                Text(AppUsageInsights.popoverText(total, language: language))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
            }
            Divider()
            footer
            Divider()
            quitRow
        }
        .frame(width: 300)
        .environment(\.motionLevel, motion)
        .onAppear { decideIntro() }
        .onChange(of: state.isLoaded) { _, _ in decideIntro() }
    }

    /// Shows the rows once the first read has finished. The first opening of the popover in the app session plays the
    /// first-open motion; later openings show the rows at once.
    private func decideIntro() {
        guard state.isLoaded, intro == nil else { return }
        intro = IntroStyle.resolve(isFirst: FirstOpenTracker.shared.claim("popover"), reduceMotion: reduceMotion, snapshot: false)
        revealed = true
    }

    private var header: some View {
        HStack {
            typedText(L10n.text(.appName, language), key: "popover.title", motion: motion)
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            RefreshButton(isRefreshing: state.isRefreshing, action: onRefresh)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var rows: some View {
        if !state.isLoaded {
            SkeletonLoadingView(label: L10n.text(.loading, language), motion: motion) {
                VStack(spacing: 2) {
                    ForEach(0..<2, id: \.self) { _ in
                        SkeletonPopoverRow()
                    }
                }
            }
        } else if state.accounts.isEmpty {
            AppNoDataView()
                .frame(maxWidth: .infinity, minHeight: 120)
        } else {
            VStack(spacing: 2) {
                ForEach(Array(state.accounts.enumerated()), id: \.offset) { index, account in
                    PopoverAccountRow(
                        account: account,
                        now: state.now,
                        index: index,
                        revealed: revealed,
                        isHovered: hovered == index,
                        reduceMotion: reduceMotion,
                        intro: intro ?? .none
                    )
                    .onHover { inside in
                        withAnimation(.easeOut(duration: 0.12)) {
                            if inside {
                                hovered = index
                            } else if hovered == index {
                                hovered = nil
                            }
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        let line = AppUsageInsights.statusLine(state, language: language)
        let updated = AppUsageInsights.updatedText(state.document, now: state.now, language: language)
        // A refresh message (progress or failure) replaces the update time. Otherwise the update time stays,
        // even when an account is stale: that account's error text is already on its row.
        let showsMessage = state.isRefreshing || state.notice != nil
        let text = !state.isLoaded ? L10n.text(.loading, language) : (showsMessage ? line.text : (updated ?? line.text))
        let isFailure = state.notice != nil && !state.isRefreshing
        return HStack(spacing: 8) {
            Circle()
                .fill(line.tone.color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(isFailure ? LocalPalette.warning : Color.secondary)
                .lineLimit(2)
            Spacer(minLength: 6)
            Button(L10n.text(.refresh, language), action: onRefresh)
                .font(.system(size: 12, weight: .semibold))
                .disabled(state.isRefreshing)
            Text("|")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button(action: onOpenApp) {
                HStack(spacing: 2) {
                    Text(L10n.text(.openApp, language))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(LocalPalette.accent)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var quitRow: some View {
        Button(action: onQuit) {
            HStack {
                Text(L10n.text(.quit, language))
                    .font(.system(size: 13))
                Spacer()
                Text("⌘Q")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(quitHovered ? 0.10 : 0))
                    .padding(.horizontal, 6)
            )
        }
        .buttonStyle(.plain)
        .keyboardShortcut("q", modifiers: .command)
        .onHover { quitHovered = $0 }
    }
}

/// One account in the popover: brand square, name and plan, the top limit as a line of text,
/// then the highest percentage and the gauge. Hover fills the row.
struct PopoverAccountRow: View {
    let account: UsageAccount
    let now: Date
    let index: Int
    let revealed: Bool
    let isHovered: Bool
    let reduceMotion: Bool
    /// How the row enters: `slide` on the popover's first opening in the app session, `none` after that.
    var intro: IntroStyle = .none
    @Environment(\.motionLevel) private var motion
    @Environment(\.uiLanguage) private var language
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let percent = AppUsageInsights.highestPercent(account)
        let alert = percent.map { UsageFormat.isAlert($0) } ?? false
        let tier = UsageFormat.tier(percent)
        let subline = AppUsageInsights.popoverSubline(account, now: now, language: language)
        HStack(alignment: .center, spacing: 9) {
            slotBrand(
                AppUsageInsights.brandLetter(for: account),
                color: LocalPalette.brand(for: account.provider),
                size: 28,
                key: "popover.brand." + account.id,
                motion: motion
            )
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    typedText(AppUsageInsights.displayName(account), key: "popover.name." + account.id, motion: motion)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        // The name keeps its room before the caption and the pill, so it is never cut to "…".
                        .layoutPriority(1)
                    // A near-full account drops the plan caption, so its name and pill keep their room.
                    if !AppUsageInsights.isNearFull(account), let caption = AppUsageInsights.popoverCaption(account) {
                        Text(caption)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if AppUsageInsights.isNearFull(account) {
                        // One pill for the account, in the colour of its worst limit. The shared pill is the smaller one.
                        NearFullPill(tier: tier)
                    }
                }
                if let subline {
                    // Up to two lines, one limit per line for two limits. It is never cut off with "…" on the first line.
                    Text(subline.text)
                        .font(.system(size: 10.5))
                        .foregroundStyle(subline.isError ? LocalPalette.warning : (isHovered ? Color.primary.opacity(0.8) : Color.secondary))
                        .lineLimit(subline.showsAllLines ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 6)
            HStack(spacing: 6) {
                VStack(alignment: .trailing, spacing: 0) {
                    rollingText(
                        number: UsageFormat.leftWhole(percent).map(Double.init),
                        text: UsageFormat.leftText(percent, language),
                        format: { L10n.percentLeft(Int($0.rounded()), language) },
                        key: "popover.left." + account.id,
                        motion: motion
                    )
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(tier.color(colorScheme))
                        .contentTransition(.numericText(value: Double(UsageFormat.leftWhole(percent) ?? 0)))
                        .animation(LocalMotion.spring(reduced: reduceMotion), value: percent)
                    if let used = UsageFormat.usedWhole(percent) {
                        Text(L10n.percentUsed(used, language))
                            .font(.system(size: 10))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minWidth: 54, alignment: .trailing)
                LocalBatteryGauge(
                    usedPercent: percent,
                    growKey: "popover." + account.id,
                    growDelay: 0.12 + Double(index) * 0.06
                )
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(isHovered ? 0.10 : 0))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(isHovered ? 0.15 : 0), lineWidth: 0.5)
        )
        .opacity(revealed ? 1 : 0)
        .offset(y: revealed || intro != .slide ? 0 : 8)
        .animation(intro == .none ? nil : LocalMotion.rowReveal(index: index, reduced: intro == .fade), value: revealed)
        .modifier(AlertPulse(isAlert: alert))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
    }

    /// The VoiceOver text: "Claude 5 ชม., เหลือ 58 เปอร์เซ็นต์", and the error text of a stale or error account.
    private var spokenLabel: String {
        AppUsageInsights.popoverSpokenText(account, now: now, language: language)
    }
}

/// The refresh arrow. It turns while a refresh runs. With Reduce Motion it fades instead.
struct RefreshButton: View {
    let isRefreshing: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.uiLanguage) private var language

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 13, weight: .medium))
                .rotationEffect(.degrees(isRefreshing && !reduceMotion ? 360 : 0))
                .animation(
                    isRefreshing && !reduceMotion ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default,
                    value: isRefreshing
                )
                .opacity(isRefreshing && reduceMotion ? 0.4 : 1)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isRefreshing)
        .help(L10n.text(.refresh, language))
        .accessibilityLabel(L10n.text(.refresh, language))
    }
}
