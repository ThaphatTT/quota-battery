import SwiftUI

struct QuotaOverlayCycle {
    struct Window: Equatable {
        let marker: String
        let limit: UsageLimit
    }

    struct Selection: Equatable {
        let accountID: String
        let provider: String
        let name: String
        let badgeLabel: String
        let extraAccounts: Int
        let window: Window

        var remaining: String { UsageFormat.leftWhole(window.limit.usedPercent).map { "\($0)%" } ?? "—" }
    }

    private struct Account {
        let usage: UsageAccount
        let windows: [Window]
    }

    private let providers: [[Account]]
    private let accountCounts: [String: Int]

    init(_ accounts: [UsageAccount], hostProvider: String, preferredGPT: String) {
        var seen: Set<String> = []
        let accounts = accounts.filter { !$0.id.isEmpty && seen.insert($0.id).inserted }
        let grouped = Dictionary(grouping: accounts, by: \.provider)
        let order = grouped.keys.sorted {
            if ($0 == hostProvider) != ($1 == hostProvider) { return $0 == hostProvider }
            return (AccountList.providerRank($0), $0) < (AccountList.providerRank($1), $1)
        }
        accountCounts = grouped.mapValues(\.count)
        providers = order.compactMap { provider in
            let group = grouped[provider] ?? []
            let choices = provider == "codex" ? CodexSidebarQuota(group).account(preferredID: preferredGPT).map { [$0] } ?? [] : group
            let usable = choices.compactMap { account -> Account? in
                let windows = Self.windows(for: account)
                return windows.isEmpty ? nil : Account(usage: account, windows: windows)
            }
            return usable.isEmpty ? nil : usable
        }
    }

    var schedule: [[String]] {
        providers.flatMap { group in
            group.map { [$0.usage.id] + $0.windows.map { "\($0.limit.key):\($0.limit.windowSeconds ?? 0)" } }
        }
    }

    func selection(elapsed: Int) -> Selection? {
        guard !providers.isEmpty, elapsed >= 0 else { return nil }
        let slot = elapsed / 20
        let group = providers[slot % providers.count]
        let accountIndex = (slot / providers.count) % group.count
        let account = group[accountIndex]
        let windowIndex = providers.count == 1 && group.count == 1
            ? slot % account.windows.count
            : (elapsed % 20) / (20 / account.windows.count)
        let provider = account.usage.provider
        let label = ProviderStyle.shortName(for: provider)
        return Selection(accountID: account.usage.id, provider: provider,
                         name: CodexSidebarQuota.name(account.usage),
                         badgeLabel: group.count > 1 ? "\(ProviderStyle.iconLetter(for: provider))\(accountIndex + 1)" : label,
                         extraAccounts: max((accountCounts[provider] ?? 1) - 1, 0),
                         window: account.windows[windowIndex])
    }

    private static func windows(for account: UsageAccount) -> [Window] {
        let limits = CodexSidebarQuota.periods(for: account)
        if account.provider == "codex" {
            return limits.prefix(2).map { Window(marker: CodexSidebarQuota.marker(for: $0), limit: $0) }
        }
        let five = mostUsed(limits.filter {
            $0.windowSeconds == 18_000 || $0.key == "five_hour" || $0.key.hasSuffix("-5h")
        })
        let week = limits.first { $0.key == "seven_day" } ?? mostUsed(limits.filter {
            $0.windowSeconds == 604_800 || $0.key.hasPrefix("seven_day_") || $0.key.hasSuffix("-weekly")
        })
        let windows = [five.map { Window(marker: "5", limit: $0) }, week.map { Window(marker: "W", limit: $0) }]
            .compactMap { $0 }
        if !windows.isEmpty { return windows }
        return mostUsed(limits).map {
            [Window(marker: $0.windowSeconds == nil ? ProviderStyle.iconLetter(for: account.provider)
                    : CodexSidebarQuota.marker(for: $0), limit: $0)]
        } ?? []
    }

    private static func mostUsed(_ limits: [UsageLimit]) -> UsageLimit? {
        limits.max { $0.usedPercent < $1.usedPercent }
    }
}

@MainActor
final class QuotaOverlayVisibility: ObservableObject {
    @Published var presentation: UInt64?
}

struct QuotaOverlayButton: View {
    enum Layout {
        case header, sidebar

        var provider: String { self == .header ? "claude" : "codex" }
        var size: CGSize { self == .header ? ClaudeHeaderQuota.size : CodexUsageRingPlacement.size }
        var diameter: CGFloat { self == .header ? 22 : 26 }
    }

    @ObservedObject var model: UsageViewModel
    @ObservedObject var visibility: QuotaOverlayVisibility
    @AppStorage(CodexSidebarQuota.accountKey) private var preferredGPT = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var elapsed = 0
    @State private var step = 0
    @State private var animatedPresentation: UInt64?
    let layout: Layout
    let onOpen: () -> Void

    private struct Rotation: Equatable {
        let presentation: UInt64?
        let schedule: [[String]]
    }

    private var revealStep: Int {
        visibility.presentation != nil && visibility.presentation == animatedPresentation ? step : 0
    }

    var body: some View {
        let cycle = QuotaOverlayCycle(model.result.document?.accounts ?? [], hostProvider: layout.provider,
                                      preferredGPT: preferredGPT)
        let rotation = Rotation(presentation: visibility.presentation, schedule: cycle.schedule)
        let selection = cycle.selection(elapsed: elapsed)
        let language = model.uiLanguage
        let label = [
            L10n.text(.usageTitle, language), selection?.name,
            selection.map { CodexSidebarQuota.windowName($0.window.limit, language: language) },
            selection?.remaining
        ].compactMap { $0 }.joined(separator: " · ")
        let ring = ring(selection)
        let details = details(selection)

        return Button(action: onOpen) {
            Group {
                if layout == .header {
                    HStack(spacing: 6) {
                        ring
                        details.frame(width: 35, alignment: .trailing)
                    }
                    .padding(.trailing, 1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                } else {
                    VStack(spacing: 0) {
                        ring
                        details
                    }
                    .padding(.top, 5)
                }
            }
            .frame(width: layout.size.width, height: layout.size.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(revealStep == 0)
        .accessibilityHidden(visibility.presentation == nil)
        .accessibilityLabel(label)
        .help(label)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: selection)
        .task(id: visibility.presentation) {
            step = 0
            animatedPresentation = visibility.presentation
            guard animatedPresentation != nil else { return }
            if reduceMotion {
                step = 4
                return
            }
            do {
                try await Task.sleep(for: .milliseconds(20))
                withAnimation(.easeOut(duration: 0.15)) { step = 1 }
                try await Task.sleep(for: .milliseconds(55))
                withAnimation(.easeOut(duration: 0.24)) { step = 2 }
                try await Task.sleep(for: .milliseconds(70))
                withAnimation(.easeOut(duration: 0.14)) { step = 3 }
                try await Task.sleep(for: .milliseconds(65))
                withAnimation(.easeOut(duration: 0.18)) { step = 4 }
            } catch { }
        }
        .task(id: rotation) {
            elapsed = 0
            guard rotation.presentation != nil, !rotation.schedule.isEmpty else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
                if Task.isCancelled { return }
                elapsed += 10
            }
        }
    }

    private func details(_ selection: QuotaOverlayCycle.Selection?) -> some View {
        VStack(spacing: 0) {
            Text(selection?.remaining ?? "—")
                .font(.system(size: layout == .header ? 12 : 10, weight: .semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(selection?.badgeLabel ?? " ")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .contentTransition(.opacity)
                .frame(maxWidth: layout == .sidebar ? 38 : nil)
        }
        .opacity(revealStep >= 4 ? 1 : 0)
    }

    @Environment(\.colorScheme) private var colorScheme

    private func ring(_ selection: QuotaOverlayCycle.Selection?) -> some View {
        let progress = revealStep >= 2 ? UsageFormat.remainingFraction(selection?.window.limit.usedPercent) : 0
        let accent = accent(selection?.provider)
        let style = StrokeStyle(lineWidth: 2.5, lineCap: .round)
        return ZStack {
            Circle().strokeBorder(accent.opacity(0.25), lineWidth: style.lineWidth)
            Circle().inset(by: style.lineWidth / 2).trim(from: 0, to: progress)
                .stroke(AngularGradient(
                    colors: [accent, accent.mix(with: .white, by: colorScheme == .dark ? 0.45 : 0.23)],
                    center: .center, startAngle: .zero, endAngle: .degrees(max(progress * 360, 1))
                ), style: style)
                .rotationEffect(.degrees(-90))
            Text(selection?.window.marker ?? "—")
                .font(.system(size: layout.diameter * 0.41, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.52)
                .frame(width: layout.diameter - 7)
                .contentTransition(.opacity)
                .opacity(revealStep >= 3 ? 1 : 0)
        }
        .frame(width: layout.diameter, height: layout.diameter)
        .overlay(alignment: .topTrailing) {
            if let extra = selection?.extraAccounts, extra > 0 {
                Text("+\(extra)")
                    .font(.system(size: 8, weight: .semibold))
                    .monospacedDigit()
                    .padding(.horizontal, 3)
                    .background(Color(nsColor: .windowBackgroundColor), in: Capsule())
                    .foregroundStyle(accent)
                    .offset(x: 8, y: -5)
                    .opacity(revealStep >= 4 ? 1 : 0)
            }
        }
        .scaleEffect(revealStep > 0 ? 1 : 0.88)
        .opacity(revealStep > 0 ? 1 : 0)
    }

    private func accent(_ provider: String?) -> Color {
        guard let provider else { return .secondary }
        if colorScheme == .light {
            if provider == "claude" { return Color(hex: "#A94627") }
            if provider == "codex" { return Color(hex: "#087B60") }
        }
        return Color(hex: ProviderStyle.accentHex(for: provider))
    }
}
