import AppKit
import SwiftUI

/// How the account cards are laid out in the app window. Two columns when the window is wide enough for two cards at
/// their comfortable minimum width, one column otherwise. Pure numbers, so the breakpoint can be tested.
enum CardGridLayout {
    /// The narrowest a card may be in two columns. The widest card content measured (a card with three or more limits,
    /// in English: 390 pt; in Thai 371 pt; a card with two limits and its tiles: 272 pt) fits in it, so nothing is cut
    /// off (see MainWindowLayoutTests).
    static let minimumCardWidth: CGFloat = 400
    /// The space between two cards, across and down.
    static let spacing: CGFloat = 12
    /// The space between the window's edge and the cards.
    static let outerPadding: CGFloat = 16
    /// The window width from which two columns fit: two minimum cards, the gap between them and the padding on both sides.
    static let twoColumnWidth: CGFloat = 2 * minimumCardWidth + spacing + 2 * outerPadding
    /// The window's narrowest width. It is the one-column width the app has always had.
    static let minimumWindowWidth: CGFloat = 530

    /// The number of columns for a window content width: 2 from `twoColumnWidth`, otherwise 1. Never more than 2.
    static func columns(forWidth width: CGFloat) -> Int {
        width >= twoColumnWidth ? 2 : 1
    }
}

/// The account cards in a grid of `columns`. Every card in a row gets the same width, and a row is as tall as its tallest
/// card. It is a `Layout` rather than a lazy grid, so every card is laid out and drawn at once.
struct CardGrid: Layout {
    let columns: Int
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        let itemWidth = itemWidth(for: width)
        var height: CGFloat = 0
        for start in stride(from: 0, to: subviews.count, by: columns) {
            height += rowHeight(start, subviews, itemWidth) + spacing
        }
        return CGSize(width: width, height: max(0, height - spacing))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let itemWidth = itemWidth(for: bounds.width)
        var y = bounds.minY
        for start in stride(from: 0, to: subviews.count, by: columns) {
            let height = rowHeight(start, subviews, itemWidth)
            for offset in 0..<min(columns, subviews.count - start) {
                let x = bounds.minX + CGFloat(offset) * (itemWidth + spacing)
                subviews[start + offset].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: itemWidth, height: height)
                )
            }
            y += height + spacing
        }
    }

    private func itemWidth(for width: CGFloat) -> CGFloat {
        max(0, (width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
    }

    /// The height of the row that starts at `start`: the tallest card in it, at the column width.
    private func rowHeight(_ start: Int, _ subviews: Subviews, _ itemWidth: CGFloat) -> CGFloat {
        (0..<min(columns, subviews.count - start)).map { offset in
            subviews[start + offset].sizeThatFits(ProposedViewSize(width: itemWidth, height: nil)).height
        }.max() ?? 0
    }
}

/// The app window: a title row with Refresh and Settings at the top right, one card per account (each with its own
/// Quota | Model mix tab) in one or two columns, then a status line and the log folder link. Every setting is in the
/// Settings window.
struct ContentView: View {
    let state: AppUsageState
    let modelMixActions: ModelMixActions
    let onRefresh: () -> Void
    let onOpenSettings: () -> Void
    let onOpenLogs: () -> Void
    /// Set only by the snapshot and performance tests. ImageRenderer draws nothing inside a ScrollView, so the snapshot
    /// draws the same grid without it, and with the cards' look-alike tab control (see `AppAccountCardView.snapshot`).
    /// The window always scrolls.
    var snapshot: Bool = false

    @Environment(\.uiLanguage) private var language
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The cards have been shown once in this app session, so the first-open motion has been played (or is playing).
    @State private var entered = false
    /// How the cards entered: `slide` on the first appearance of the window in the app session, otherwise `none`.
    @State private var intro: IntroStyle = .none

    private var motion: MotionLevel { MotionLevel.resolve(reduceMotion: reduceMotion, snapshot: snapshot) }

    var body: some View {
        VStack(spacing: 0) {
            titleRow
            Divider()
            GeometryReader { geometry in
                if snapshot {
                    grid(width: geometry.size.width)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                } else {
                    ScrollView {
                        grid(width: geometry.size.width)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
            }
            Divider()
            footer
        }
        .frame(minWidth: CardGridLayout.minimumWindowWidth, maxWidth: .infinity, minHeight: 420, maxHeight: .infinity)
        .environment(\.motionLevel, motion)
        .onAppear { decideIntro() }
        .onChange(of: state.isLoaded) { _, _ in decideIntro() }
    }

    /// Plays the first-open motion once, when the real content first shows. Until the first read has finished, the
    /// cards are not shown at all (the skeleton is).
    private func decideIntro() {
        guard state.isLoaded, !entered else { return }
        let isFirst = snapshot ? false : FirstOpenTracker.shared.claim("window")
        intro = IntroStyle.resolve(isFirst: isFirst, reduceMotion: reduceMotion, snapshot: snapshot)
        entered = true
    }

    /// The window has a hidden title bar, so this row takes the place of the title bar. The traffic lights stay at the left.
    private var titleRow: some View {
        ZStack {
            typedText(L10n.text(.appName, language), key: "window.title", motion: motion)
                .font(.system(size: 13, weight: .semibold))
            HStack(spacing: 10) {
                Spacer()
                if let updated = AppUsageInsights.updatedText(state.document, now: state.now, language: language) {
                    Text(updated)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                RefreshButton(isRefreshing: state.isRefreshing, action: onRefresh)
                SettingsButton(action: onOpenSettings)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    /// The cards, in the grid for the window's width, with the window's padding around them.
    private func grid(width: CGFloat) -> some View {
        cards(columns: CardGridLayout.columns(forWidth: width))
            .padding(CardGridLayout.outerPadding)
    }

    @ViewBuilder
    private func cards(columns: Int) -> some View {
        if !state.isLoaded {
            SkeletonLoadingView(label: L10n.text(.loading, language), motion: motion) {
                CardGrid(columns: columns, spacing: CardGridLayout.spacing) {
                    ForEach(0..<2, id: \.self) { _ in
                        SkeletonAccountCard()
                    }
                }
            }
        } else if state.accounts.isEmpty {
            AppNoDataView()
                .frame(maxWidth: .infinity, minHeight: 300)
        } else {
            // One grid for every account, so a card keeps its identity (and its tab) when the column count changes.
            CardGrid(columns: columns, spacing: CardGridLayout.spacing) {
                ForEach(Array(state.accounts.enumerated()), id: \.offset) { index, account in
                    // The id keeps each card's tab with its account when the list is reordered. An account with no id
                    // falls back to its position.
                    AppAccountCardView(
                        account: account,
                        now: state.now,
                        mix: state.accountMixes[account.id],
                        actions: modelMixActions,
                        snapshot: snapshot
                    )
                    .equatable()
                    .id(account.id.isEmpty ? "position-\(index)" : account.id)
                    .modifier(FirstOpenReveal(shown: entered || snapshot, style: intro, index: index))
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: columns)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            statusLine
            Spacer(minLength: 8)
            Button(action: onOpenLogs) {
                Label(L10n.text(.openLogFolder, language), systemImage: "folder")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.03))
    }

    private var statusLine: some View {
        let line = AppUsageInsights.statusLine(state, language: language)
        return HStack(spacing: 6) {
            Circle()
                .fill(line.tone.color)
                .frame(width: 7, height: 7)
            Text(state.isLoaded ? line.text : L10n.text(.loading, language))
                .font(.system(size: 12))
                .foregroundStyle(line.tone == .warning ? LocalPalette.warning : Color.secondary)
                .lineLimit(1)
        }
    }
}

/// The gear at the top right of the app window. It opens the Settings window.
struct SettingsButton: View {
    let action: () -> Void
    @Environment(\.uiLanguage) private var language

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape")
                .font(.system(size: 13, weight: .medium))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L10n.text(.settings, language))
        .accessibilityLabel(L10n.text(.settings, language))
    }
}

/// Opens the log folder the collector writes to. The folder is created first, so the link always works.
enum AppLinks {
    static func openLogsFolder() {
        let folder = UsageLoader.realHomeDirectory()
            .appendingPathComponent("Library/Logs/AIUsage", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }
}
