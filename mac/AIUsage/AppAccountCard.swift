import SwiftUI

/// One account card in the app window: header, the limits (or the compact list), then the Claude usage tiles.
struct AppAccountCardView: View {
    let account: UsageAccount
    let now: Date
    @Environment(\.uiLanguage) private var language

    var body: some View {
        let tiles = AppUsageInsights.usageTiles(account, language: language)
        VStack(alignment: .leading, spacing: 10) {
            header
            if AppUsageInsights.isProblem(account), let error = AppUsageInsights.errorText(account, language: language) {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(LocalPalette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
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

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            LocalBrandIcon(
                letter: AppUsageInsights.brandLetter(for: account),
                color: LocalPalette.brand(for: account.provider),
                size: 28
            )
            VStack(alignment: .leading, spacing: 1) {
                Text(AppUsageInsights.displayName(account))
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                if let subtitle = AppUsageInsights.subtitle(for: account.provider) {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if AppUsageInsights.isNearFull(account) {
                // One pill for the account, in the colour of its worst limit.
                LocalNearFullPill(tier: UsageFormat.tier(AppUsageInsights.highestPercent(account)))
            }
            if let plan = AppUsageInsights.planTag(account) {
                PlanTag(text: plan)
            }
        }
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

/// A limit with its reset line, what is left, what is used and a bar that drains. Used for accounts with two limits or
/// fewer. The bar and the numbers take the tier colour, so they turn yellow at 80% used and red at 95%.
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(UsageFormat.windowLabel(limit, language: language))
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if let line = resetLine {
                    Text(line)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    if alert {
                        Circle()
                            .fill(tier.color(colorScheme))
                            .frame(width: 6, height: 6)
                    }
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(UsageFormat.leftText(used, language))
                            .font(.system(size: 13, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(tier.color(colorScheme))
                            .lineLimit(1)
                            .fixedSize()
                            .contentTransition(.numericText(value: Double(UsageFormat.leftWhole(used) ?? 0)))
                        Text(UsageFormat.usedText(used, language))
                            .font(.system(size: 10.5))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
            }
            LocalUsageBar(
                fraction: UsageFormat.remainingFraction(used),
                color: tier.color(colorScheme),
                height: 6
            )
        }
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
            .frame(width: 84)
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
            .frame(width: 66, alignment: .trailing)
        }
        .padding(.vertical, 7)
        .modifier(AlertPulse(isAlert: UsageFormat.isAlert(used)))
    }
}

/// The "Today" or "This month" tile: the token count, then the estimated cost in green.
struct UsageTileView: View {
    let tile: AppUsageInsights.UsageTile

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tile.title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Text(tile.tokensText)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if let cost = tile.costText {
                    Text("· \(cost)")
                        .font(.system(size: 13))
                        .foregroundStyle(LocalPalette.healthy)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
        )
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
