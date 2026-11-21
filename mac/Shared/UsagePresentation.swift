import Foundation

/// Provider names, colours and tags. Colours are hex strings so tests can check them without SwiftUI.
enum ProviderStyle {
    /// Red for a limit with 5% or less left (95% used or more), in dark appearance.
    static let alertHex = "#FF5F57"
    /// The same red in light appearance. It is darker, so it reads on a white background.
    static let alertLightHex = "#D93025"

    /// Yellow for a limit with 6 to 20% left (80 to 94% used), in dark appearance.
    static let lowHex = "#FFD60A"
    /// The same yellow in light appearance. It is darker, so it reads on a white background.
    static let lowLightHex = "#B58900"

    /// Brand colours: Claude coral, ChatGPT green, agy blue. Grey for any other provider.
    static func accentHex(for provider: String) -> String {
        switch provider {
        case "claude": return "#D97757"
        case "codex": return "#10A37F"
        case "agy": return "#4285F4"
        default: return "#888780"
        }
    }

    /// The white letter on the brand icon: C, G or A. Other providers use their first letter.
    static func iconLetter(for provider: String) -> String {
        switch provider {
        case "claude": return "C"
        case "codex": return "G"
        case "agy": return "A"
        default: return provider.first.map { String($0).uppercased() } ?? "?"
        }
    }

    /// Account name, used when the file has no label.
    static func fallbackLabel(for provider: String) -> String {
        switch provider {
        case "claude": return "Claude"
        case "codex": return "ChatGPT"
        case "agy": return "agy"
        default: return provider.isEmpty ? "AI" : provider
        }
    }

    /// Short name on the small widget lines (Claude / GPT / agy).
    static func shortName(for provider: String) -> String {
        switch provider {
        case "claude": return "Claude"
        case "codex": return "GPT"
        case "agy": return "agy"
        default: return fallbackLabel(for: provider)
        }
    }

    /// Tag on the account header, used when there is no update time yet.
    static func tag(for provider: String) -> String {
        switch provider {
        case "claude": return "Claude Code"
        case "codex": return "Codex CLI"
        case "agy": return "Antigravity"
        default: return fallbackLabel(for: provider)
        }
    }
}

/// The unit used by the relative-time texts.
enum TimeSpanUnit: Equatable {
    case minute, hour, day
}

/// The colour tier of a limit, from what is left. The thresholds are on used_percent, and the number rounds the same
/// way, so the colour and the number always agree: 79.6 used shows "21" left and is white, 94.6 used shows "6" and is yellow.
enum UsageTier: Equatable {
    /// More than 20% left (below 80% used). White on dark, the primary ink in light mode.
    case plenty
    /// 6 to 20% left (80 to 94% used). Yellow.
    case low
    /// 5% or less left (95% used or more). Red.
    case critical

    /// The fixed colour in dark appearance, or nil for `plenty`, which takes the ink colour.
    var hex: String? {
        hex(dark: true)
    }

    /// The fixed colour for the appearance: yellow `#FFD60A` and red `#FF5F57` in dark, `#B58900` and `#D93025` in light.
    /// Nil for `plenty`, which takes the ink colour (white on dark, the primary ink on light).
    func hex(dark: Bool) -> String? {
        switch self {
        case .plenty: return nil
        case .low: return dark ? ProviderStyle.lowHex : ProviderStyle.lowLightHex
        case .critical: return dark ? ProviderStyle.alertHex : ProviderStyle.alertLightHex
        }
    }
}

/// Number and text formatting. Every relative time takes `now`, and every text takes the language, so the output
/// is deterministic and the caller always says which language it wants.
enum UsageFormat {
    /// Used share from which a limit is yellow or red (20% left or less). The pill, the pulse and the notifications use it.
    static let alertThreshold = 80.0
    /// Used share from which a limit is red (5% left or less).
    static let criticalThreshold = 95.0

    /// True at 80 or more used, on the raw value: yellow or red. Drives the pill and the pulse.
    static func isAlert(_ usedPercent: Double) -> Bool {
        usedPercent.isFinite && usedPercent >= alertThreshold
    }

    /// The colour tier of a used percent. Unknown (nil or non-finite) is `plenty`, and its text is "—".
    static func tier(_ usedPercent: Double?) -> UsageTier {
        guard let usedPercent, usedPercent.isFinite else { return .plenty }
        if usedPercent >= criticalThreshold { return .critical }
        if usedPercent >= alertThreshold { return .low }
        return .plenty
    }

    /// What is left, from 0 to 100, clamped: `100 - used_percent`. Nil when the used value is unknown.
    static func remainingPercent(_ usedPercent: Double?) -> Double? {
        guard let usedPercent, usedPercent.isFinite else { return nil }
        return min(max(100 - usedPercent, 0), 100)
    }

    /// What is left as a share from 0 to 1, for the gauge and the ring. Unknown is 0: an empty gauge, never a full one.
    static func remainingFraction(_ usedPercent: Double?) -> Double {
        (remainingPercent(usedPercent) ?? 0) / 100
    }

    /// The used percent rounded DOWN to a whole number (79.6 is 79). Nil when unknown.
    static func usedWhole(_ usedPercent: Double?) -> Int? {
        guard let usedPercent, usedPercent.isFinite else { return nil }
        return Int(min(max(usedPercent, 0), 100).rounded(.down))
    }

    /// What is left, rounded UP: 100 minus `usedWhole`. So 94.6 used is 6 left and 79.6 used is 21 left. Nil when unknown.
    static func leftWhole(_ usedPercent: Double?) -> Int? {
        usedWhole(usedPercent).map { 100 - $0 }
    }

    /// "เหลือ 58%" / "58% left", or "—" when unknown.
    static func leftText(_ usedPercent: Double?, _ language: UILanguage) -> String {
        leftWhole(usedPercent).map { L10n.percentLeft($0, language) } ?? "—"
    }

    /// "ใช้ไป 42%" / "42% used", or "—" when unknown.
    static func usedText(_ usedPercent: Double?, _ language: UILanguage) -> String {
        usedWhole(usedPercent).map { L10n.percentUsed($0, language) } ?? "—"
    }

    /// The width of a battery fill inside `available` points. Anything left draws at least 2 points, so the gauge is
    /// never invisible. Nothing left draws nothing.
    static func fillWidth(fraction: Double, available: CGFloat) -> CGFloat {
        guard fraction > 0, available > 0 else { return 0 }
        return min(available, max(2, available * CGFloat(fraction)))
    }

    /// Used share as 0...1, clamped, for sorting. Non-finite values count as 0.
    static func fraction(_ usedPercent: Double) -> Double {
        guard usedPercent.isFinite else { return 0 }
        return min(max(usedPercent, 0), 100) / 100
    }

    /// A value already on a 0...1 scale, clamped. Non-finite values count as empty.
    static func unitFraction(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    /// Picks the unit and the number for a span of time. Rounds to the nearest whole unit, with a minimum of 1.
    /// The unit is chosen from the rounded value, so the text never reads "60 นาที" or "24 ชม.".
    /// Under 60 minutes shows minutes. Under 24 hours shows hours. Otherwise shows days.
    static func timeSpan(seconds: Double) -> (value: Int, unit: TimeSpanUnit) {
        let total = max(0, seconds)
        let minutes = (total / 60).rounded()
        if minutes < 60 {
            return (max(1, Int(minutes)), .minute)
        }
        let hours = (total / 3600).rounded()
        if hours < 24 {
            return (max(1, Int(hours)), .hour)
        }
        return (max(1, Int((total / 86400).rounded())), .day)
    }

    /// The age of the data, for example "2 นาทีก่อน" or "2 min ago", counted from `date`. Nil when there is no date.
    static func agoText(since date: Date?, now: Date, language: UILanguage) -> String? {
        guard let date else { return nil }
        let (value, unit) = timeSpan(seconds: now.timeIntervalSince(date))
        return L10n.ago(value, unit, language)
    }

    /// "อัปเดต 2 นาทีก่อน" / "Updated 2 min ago", counted from the account's last successful run.
    /// Nil when there is no update time.
    static func updatedText(updatedAt: Date?, now: Date, language: UILanguage) -> String? {
        agoText(since: updatedAt, now: now, language: language).map { L10n.updated($0, language) }
    }

    /// "รีเซ็ตใน 5 ชม." / "Resets in 5 h".
    /// Nil when the reset time is unknown or has already passed.
    static func resetText(resetsAt: Date?, now: Date, language: UILanguage) -> String? {
        guard let resetsAt else { return nil }
        let seconds = resetsAt.timeIntervalSince(now)
        guard seconds > 0 else { return nil }
        let (value, unit) = timeSpan(seconds: seconds)
        return L10n.resetsIn(value, unit, language)
    }

    /// The window label of a limit, in the chosen language. When the window length is known it is built from
    /// `window_seconds` and `key`: "5 ชม." / "5h", "สัปดาห์" / "Week", and " (Opus)" or " (Sonnet)" on those variants.
    /// Without a window length the file's own label is shown, which is a model-group name such as "Gemini Pro".
    static func windowLabel(_ limit: UsageLimit, language: UILanguage) -> String {
        guard let seconds = limit.windowSeconds, seconds > 0 else {
            return limit.label.isEmpty ? limit.key : limit.label
        }
        let name = windowName(seconds: seconds, language: language)
        if limit.key.hasSuffix("_opus") { return name + " (Opus)" }
        if limit.key.hasSuffix("_sonnet") { return name + " (Sonnet)" }
        return name
    }

    /// A window name for a length in seconds. A week is "สัปดาห์" / "Week". Other lengths are whole days when they
    /// divide evenly, else hours, or minutes under one hour.
    private static func windowName(seconds: Int, language: UILanguage) -> String {
        if seconds == 604_800 {
            return L10n.text(.week, language)
        }
        if seconds % 86_400 == 0 {
            return L10n.windowDuration(seconds / 86_400, .day, language)
        }
        if seconds < 3_600 {
            return L10n.windowDuration(max(1, Int((Double(seconds) / 60).rounded())), .minute, language)
        }
        return L10n.windowDuration(max(1, Int((Double(seconds) / 3_600).rounded())), .hour, language)
    }

    /// Credit balance without a $ sign: "0", "12", "12.5", "12.25". Whole numbers have no decimals.
    static func creditText(_ balance: Double) -> String {
        guard balance.isFinite else { return "—" }
        if balance == 0 { return "0" }
        if balance == balance.rounded() { return String(format: "%.0f", balance) }
        var text = String(format: "%.2f", balance)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// 1200000 becomes "1.2M", 640000 becomes "640K", 850 stays "850".
    static func tokensText(_ tokens: Double) -> String {
        guard tokens.isFinite else { return "—" }
        let count = max(0, tokens)
        if count >= 1_000_000 { return String(format: "%.1fM", count / 1_000_000) }
        if count >= 1_000 { return String(format: "%.0fK", count / 1_000) }
        return String(format: "%.0f", count)
    }

    static func moneyText(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        return String(format: "$%.2f", value)
    }

    /// Money from a whole number of cents, for example 838 gives "$8.38". Used where the cents must add up exactly.
    static func moneyText(cents: Int) -> String {
        let sign = cents < 0 ? "-" : ""
        let absolute = abs(cents)
        return "\(sign)$\(absolute / 100).\(String(format: "%02d", absolute % 100))"
    }
}

/// One limit row of a widget, or the single row of an account with no limits (`hasUsage` false).
/// The large and medium layouts each fill `title`, `subtitle` and the flags in their own way.
/// The agy display group of a limit: Gemini first, then add-ons (Claude and GPT on their own quota), then other.
/// A limit with an unknown group name counts as other. A limit with no group field is not grouped at all.
enum LimitGroup: Equatable, CaseIterable {
    case gemini, addon, other

    /// The order the groups are shown in.
    var rank: Int {
        switch self {
        case .gemini: return 0
        case .addon: return 1
        case .other: return 2
        }
    }

    /// Nil for a limit with no group field (an old file, or another provider).
    static func parse(_ raw: String?) -> LimitGroup? {
        switch raw {
        case nil: return nil
        case "gemini": return .gemini
        case "addon": return .addon
        default: return .other
        }
    }

    /// The header text of the group in the chosen language.
    func title(_ language: UILanguage) -> String {
        switch self {
        case .gemini: return L10n.text(.agyGroupGemini, language)
        case .addon: return L10n.text(.agyGroupAddons, language)
        case .other: return L10n.text(.agyGroupOther, language)
        }
    }
}

/// One group of agy limits on the account card: its header, its tag, and the file indices of its limits in order.
struct LimitSection: Equatable {
    let group: LimitGroup
    let title: String
    /// "Separate quota" under the add-ons header, nil for the other groups.
    let tag: String?
    /// Indices into `UsageAccount.limits`, in display order.
    let indices: [Int]
}

struct LimitRowModel: Equatable, Identifiable {
    let id: String
    let provider: String
    /// Account name, for example "Claude".
    let name: String
    /// Window label in the chosen language, for example "5 ชม." or "5h". Empty for a row with no limit.
    let label: String
    /// Used share from 0 to 1. Sorts the large widget's rows, most used first.
    let fraction: Double
    /// What is left, from 0 to 1. Drives the battery gauge.
    let remainingFraction: Double
    /// The used percent, or nil when unknown.
    let usedPercent: Double?
    /// "เหลือ 58%" / "58% left", or "—".
    let leftText: String
    /// "ใช้ไป 42%" / "42% used", or nil when unknown.
    let usedText: String?
    /// The colour tier of this limit.
    let tier: UsageTier
    /// True at 80% used or more (yellow or red). Drives the pill and the pulse.
    let isAlert: Bool
    /// The VoiceOver text: "Claude 5 ชม., เหลือ 58 เปอร์เซ็นต์". A row with no usage reads its name and its subtitle.
    let accessibilityText: String
    /// The reset text, or nil when the reset is unknown or has passed.
    let resetText: String?
    /// The credit text, or nil when the balance is null.
    let creditText: String?
    /// False for the row of an account with no limits. Such a row shows no number.
    let hasUsage: Bool
    /// Large layout: "Claude · 5 ชม.". For an account with no limits, the account name.
    var title: String
    /// The reset text with the credit (large), or the error text (where it replaces the reset text).
    var subtitle: String?
    /// True when `subtitle` holds an error text.
    var subtitleIsError: Bool
    /// The pill ("ใกล้หมด" / "Almost out"). Set on every row that is yellow or red.
    var showsNearFull: Bool
    /// The agy group of the row. Nil when the account's limits are not grouped (see `LimitSection`).
    var group: LimitGroup? = nil

    /// What VoiceOver reads for the row: `accessibilityText`, plus the error text when the row carries one (the first row
    /// of a stale or error account). A row with no usage already reads its subtitle inside `accessibilityText`.
    var spokenText: String {
        guard hasUsage, subtitleIsError, let subtitle else { return accessibilityText }
        return accessibilityText + ", " + subtitle
    }
}

struct AccountCardModel: Equatable {
    /// The account's position in usage.json. Keeps row ids unique.
    let id: String
    /// Account name, for example "Claude".
    let name: String
    let provider: String
    /// "Claude · Max" (name, then plan when there is one).
    let title: String
    /// The age of the data ("อัปเดต 2 นาทีก่อน"), or the provider tag when there is no update time.
    let trailing: String?
    let trailingIsTag: Bool
    /// All limit rows, in file order. Views decide how many to show.
    let rows: [LimitRowModel]
    /// The muted meta line. Nil when no part exists.
    let meta: String?
    /// The account's error text. Shown for stale and error accounts.
    let errorText: String?
    /// The agy groups in display order, when the limits carry groups. Nil for a flat list. `rows` are in the same order.
    var sections: [LimitSection]? = nil
}

struct SmallLineModel: Equatable {
    let name: String
    /// Label of the most important limit (the first one in the file), in the chosen language.
    let windowLabel: String?
    /// Used percent of the most important limit, or nil when there is none. The ring shows what is left.
    let usedPercent: Double?
    /// The colour tier of the ring and its number.
    let tier: UsageTier
    /// The number in the ring centre: what is left, whole, without the % sign. "—" when unknown.
    let numberText: String
    /// The VoiceOver text, for example "Claude 5 ชม., เหลือ 58 เปอร์เซ็นต์".
    let accessibilityText: String
}

enum UsagePresenter {
    /// The large widget shows at most this many rows.
    static let largeRowLimit = 5
    /// The medium widget shows one row for each of this many accounts.
    static let mediumRowLimit = 3
    /// The small widget has room for this many rings.
    static let smallRingLimit = 3

    /// The indices of the account's limits in display order: Gemini, add-ons, other, each group in file order. Nil when
    /// the limits are not grouped (an old file has no `group`, so the file order is kept and nothing is split).
    static func groupedOrder(_ account: UsageAccount) -> [Int]? {
        let groups = account.limits.map { LimitGroup.parse($0.group) }
        guard !groups.isEmpty, groups.allSatisfy({ $0 != nil }) else { return nil }
        return account.limits.indices.sorted { lhs, rhs in
            let (a, b) = (groups[lhs]?.rank ?? 0, groups[rhs]?.rank ?? 0)
            return a == b ? lhs < rhs : a < b
        }
    }

    /// The groups of a grouped account, in display order, with their headers. Nil when the limits are not grouped.
    static func sections(for account: UsageAccount, language: UILanguage) -> [LimitSection]? {
        guard let order = groupedOrder(account) else { return nil }
        var sections: [LimitSection] = []
        for index in order {
            guard let group = LimitGroup.parse(account.limits[index].group) else { continue }
            if let last = sections.last, last.group == group {
                sections[sections.count - 1] = LimitSection(group: group, title: last.title, tag: last.tag,
                                                            indices: last.indices + [index])
            } else {
                let tag = group == .addon ? L10n.text(.agyGroupAddonsTag, language) : nil
                sections.append(LimitSection(group: group, title: group.title(language), tag: tag, indices: [index]))
            }
        }
        return sections
    }

    /// The short label of an agy limit in a popover line, for example "Models 5h" or "Argon Weekly". Other keys keep
    /// the window label.
    static func shortAgyLabel(_ limit: UsageLimit, language: UILanguage) -> String {
        switch limit.key {
        case "gemini-5h": return L10n.text(.agyShortModels5h, language)
        case "gemini-weekly": return L10n.text(.agyShortModelsWeekly, language)
        case "gemini-argon-wtu-weekly": return L10n.text(.agyShortArgonWeekly, language)
        case "3p-5h": return L10n.text(.agyShortClaudeGpt5h, language)
        case "3p-weekly": return L10n.text(.agyShortWeekly, language)
        default: return UsageFormat.windowLabel(limit, language: language)
        }
    }

    static func cards(for document: UsageDocument, now: Date, language: UILanguage) -> [AccountCardModel] {
        document.accounts.enumerated().map { index, account in
            card(for: account, now: now, index: index, language: language)
        }
    }

    static func card(for account: UsageAccount, now: Date, index: Int = 0, language: UILanguage) -> AccountCardModel {
        let name = account.label.isEmpty ? ProviderStyle.fallbackLabel(for: account.provider) : account.label
        let plan = (account.plan ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let title = plan.isEmpty ? name : "\(name) · \(plan)"

        let trailing: String?
        let trailingIsTag: Bool
        if account.status != "error",
           let updated = UsageFormat.updatedText(updatedAt: account.updatedAt, now: now, language: language) {
            trailing = updated
            trailingIsTag = false
        } else {
            trailing = ProviderStyle.tag(for: account.provider)
            trailingIsTag = true
        }

        let credit = account.credits?.balanceUsd.map { L10n.credits(UsageFormat.creditText($0), language) }
        let grouped = sections(for: account, language: language)
        let order = grouped?.flatMap(\.indices) ?? Array(account.limits.indices)
        let rows = order.map { limitIndex -> LimitRowModel in
            let limit = account.limits[limitIndex]
            let used: Double? = limit.usedPercent.isFinite ? limit.usedPercent : nil
            let label = UsageFormat.windowLabel(limit, language: language)
            let reset = UsageFormat.resetText(resetsAt: limit.resetsAt, now: now, language: language)
            let subtitle = [reset, credit].compactMap { $0 }.joined(separator: " · ")
            return LimitRowModel(
                id: "\(index).\(limitIndex)",
                provider: account.provider,
                name: name,
                label: label,
                fraction: UsageFormat.fraction(limit.usedPercent),
                remainingFraction: UsageFormat.remainingFraction(used),
                usedPercent: used,
                leftText: UsageFormat.leftText(used, language),
                usedText: UsageFormat.usedWhole(used).map { L10n.percentUsed($0, language) },
                tier: UsageFormat.tier(used),
                isAlert: used.map { UsageFormat.isAlert($0) } ?? false,
                accessibilityText: L10n.limitSpoken(
                    service: name, window: label, left: UsageFormat.leftWhole(used), language
                ),
                resetText: reset,
                creditText: credit,
                hasUsage: true,
                title: "\(name) · \(label)",
                subtitle: subtitle.isEmpty ? nil : subtitle,
                subtitleIsError: false,
                showsNearFull: false,
                group: grouped == nil ? nil : LimitGroup.parse(limit.group)
            )
        }

        let error = L10n.errorMessage(code: account.errorCode, fallback: account.error, language)
        return AccountCardModel(
            id: "\(index)",
            name: name,
            provider: account.provider,
            title: title,
            trailing: trailing,
            trailingIsTag: trailingIsTag,
            rows: rows,
            meta: metaLine(for: account, now: now, language: language),
            errorText: error,
            sections: grouped
        )
    }

    /// "รีเซ็ตใน X ชม. · เครดิต N · วันนี้ N token · ~$cost · Extra usage $used / $limit".
    /// Each part is left out when its data is missing. The reset part comes from the first limit that has a future reset.
    /// The credit part shows whenever credits.balance_usd is not null, including 0.
    static func metaLine(for account: UsageAccount, now: Date, language: UILanguage) -> String? {
        var parts: [String] = []
        if let reset = account.limits.lazy
            .compactMap({ UsageFormat.resetText(resetsAt: $0.resetsAt, now: now, language: language) }).first {
            parts.append(reset)
        }
        if let balance = account.credits?.balanceUsd {
            parts.append(L10n.credits(UsageFormat.creditText(balance), language))
        }
        if let tokens = account.usage?.today?.tokens {
            parts.append(L10n.todayTokens(UsageFormat.tokensText(tokens), language))
        }
        if let cost = account.usage?.today?.costUsd {
            parts.append("~\(UsageFormat.moneyText(cost))")
        }
        if let credits = account.credits, credits.extraUsageEnabled == true, let used = credits.usedUsd {
            var extra = "Extra usage \(UsageFormat.moneyText(used))"
            if let limit = credits.limitUsd {
                extra += " / \(UsageFormat.moneyText(limit))"
            }
            parts.append(extra)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The large widget's rows, in file order, at most `limit` of them.
    /// - An account with no limits gets one row (its error text, or "ไม่มีข้อมูล"). Such rows always keep their place.
    /// - The other places go to limit rows with the highest used share. Ties keep file order.
    /// - An account's error text replaces the reset text on its first shown row.
    /// - The pill goes on every row that is yellow or red (80% used or more).
    static func largeRows(
        for cards: [AccountCardModel],
        limit: Int = UsagePresenter.largeRowLimit,
        language: UILanguage
    ) -> [LimitRowModel] {
        var candidates: [LimitRowModel] = []
        var accountOf: [Int] = []
        for (accountIndex, card) in cards.enumerated() {
            let rows = card.rows.isEmpty ? [placeholderRow(for: card, language: language)] : card.rows
            candidates += rows
            accountOf += rows.map { _ in accountIndex }
        }

        var keep = Set(candidates.indices.filter { !candidates[$0].hasUsage }.prefix(limit))
        let ranked = candidates.indices
            .filter { candidates[$0].hasUsage }
            .sorted { lhs, rhs in
                let (a, b) = (candidates[lhs].fraction, candidates[rhs].fraction)
                return a == b ? lhs < rhs : a > b
            }
        keep.formUnion(ranked.prefix(max(0, limit - keep.count)))

        let shown = candidates.indices.filter { keep.contains($0) }
        var rows = shown.map { candidates[$0] }
        let rowAccounts = shown.map { accountOf[$0] }

        // A grouped agy account keeps Gemini before add-ons: its shown rows are reordered inside their own slots.
        let grouped = rows.indices.filter { rows[$0].group != nil }
        let groupedSorted = grouped.sorted { lhs, rhs in
            let (a, b) = (rowAccounts[lhs], rowAccounts[rhs])
            if a != b { return a < b }
            let (x, y) = (rows[lhs].group?.rank ?? 0, rows[rhs].group?.rank ?? 0)
            return x == y ? lhs < rhs : x < y
        }
        let reordered = groupedSorted.map { rows[$0] }
        for (slot, row) in zip(grouped, reordered) { rows[slot] = row }

        for (accountIndex, card) in cards.enumerated() where !card.rows.isEmpty {
            guard let error = card.errorText, let first = rowAccounts.firstIndex(of: accountIndex) else { continue }
            rows[first].subtitle = error
            rows[first].subtitleIsError = true
        }
        for index in rows.indices {
            rows[index].showsNearFull = rows[index].isAlert
        }
        return rows
    }

    /// The medium widget's rows: one per account, the first `mediumRowLimit`. Each shows the account's highest
    /// limit (the largest used share, ties keep file order) with its window and reset on one line.
    /// An account with no limits shows its name and its error text instead.
    static func mediumRows(for cards: [AccountCardModel], language: UILanguage) -> [LimitRowModel] {
        cards.prefix(mediumRowLimit).map { card -> LimitRowModel in
            // A grouped agy account shows its Gemini row first (its rows are in display order), not the most used one.
            let shown = card.sections == nil ? highest(in: card.rows) : card.rows.first { $0.hasUsage }
            guard var row = shown else { return placeholderRow(for: card, language: language) }
            let label = row.label
            let reset = row.resetText
            row.title = card.name
            row.subtitle = reset.map { "\(label) (\($0))" } ?? label
            row.subtitleIsError = false
            row.showsNearFull = row.isAlert
            return row
        }
    }

    /// One ring per account, the first `smallRingLimit` in file order (the collector has already put them in the chosen
    /// order and left out the hidden accounts). Each uses its most important limit, the first in the file. The name is
    /// the account's `label` (the nickname, or the default name); the short provider name is used only without a label.
    static func smallLines(for document: UsageDocument, language: UILanguage) -> [SmallLineModel] {
        document.accounts.prefix(smallRingLimit).map { account in
            let label = account.label.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = label.isEmpty ? ProviderStyle.shortName(for: account.provider) : label
            let primary = groupedOrder(account).map { account.limits[$0[0]] } ?? account.limits.first
            let used: Double? = primary.flatMap { $0.usedPercent.isFinite ? $0.usedPercent : nil }
            let window = primary.map { UsageFormat.windowLabel($0, language: language) }
            return SmallLineModel(
                name: name,
                windowLabel: window,
                usedPercent: used,
                tier: UsageFormat.tier(used),
                numberText: UsageFormat.leftWhole(used).map { String($0) } ?? "—",
                accessibilityText: L10n.limitSpoken(
                    service: name, window: window ?? "", left: UsageFormat.leftWhole(used), language
                )
            )
        }
    }

    /// How many accounts the small and medium widgets leave out: the accounts past the first `shown`. Zero for three or
    /// fewer, which is when no "+N" badge is drawn. The file has only enabled accounts, in the chosen order.
    static func hiddenAccountCount(for document: UsageDocument, shown: Int) -> Int {
        max(0, document.accounts.count - shown)
    }

    /// The age of the data for the widget footers, for example "2 นาทีก่อน" or "2 min ago". It counts from the OLDEST
    /// account update, so a stale account shows its age. Without any account update it counts from the file's
    /// generated_at. Nil when neither exists. The label "Updated" / "อัปเดต" is added by the views.
    static func updatedValue(for document: UsageDocument, now: Date, language: UILanguage) -> String? {
        let date = document.accounts.compactMap(\.updatedAt).min() ?? document.generatedAt
        return UsageFormat.agoText(since: date, now: now, language: language)
    }

    /// The limit with the largest used share. Ties keep the earlier one.
    private static func highest(in rows: [LimitRowModel]) -> LimitRowModel? {
        var best: LimitRowModel?
        for row in rows {
            if let current = best, current.fraction >= row.fraction { continue }
            best = row
        }
        return best
    }

    /// The single row of an account with no limits: its name, with its error text or "ไม่มีข้อมูล".
    private static func placeholderRow(for card: AccountCardModel, language: UILanguage) -> LimitRowModel {
        let text = card.errorText ?? L10n.text(.noLimitData, language)
        return LimitRowModel(
            id: "\(card.id).none",
            provider: card.provider,
            name: card.name,
            label: "",
            fraction: 0,
            remainingFraction: 0,
            usedPercent: nil,
            leftText: "—",
            usedText: nil,
            tier: .plenty,
            isAlert: false,
            accessibilityText: "\(card.name), \(text)",
            resetText: nil,
            creditText: nil,
            hasUsage: false,
            title: card.name,
            subtitle: text,
            subtitleIsError: card.errorText != nil,
            showsNearFull: false
        )
    }
}
