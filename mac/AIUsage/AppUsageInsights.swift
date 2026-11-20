import Foundation

/// The values the views draw. Plain data, so a snapshot can be built without the model.
struct AppUsageState: Equatable {
    var result: UsageLoadResult
    var now: Date
    var isRefreshing: Bool
    /// What the app says about its last refresh once it has finished. Drawn in the chosen language.
    var notice: RefreshNotice?
    /// The Model mix of each account that has one, by account id. An account without one has no Model mix tab.
    var accountMixes: [String: AccountModelMix] = [:]

    var document: UsageDocument? { result.document }
    var accounts: [UsageAccount] { result.document?.accounts ?? [] }

    /// The popover's total line over the shown accounts that have a mix. Nil when none has one.
    var popoverTotal: PopoverTotal? {
        AppUsageInsights.popoverTotal(accounts: accounts, mixes: accountMixes)
    }
}

/// The popover's money line: this month's estimated cost over every shown account with a mix, split by provider. The
/// parts are whole cents, so they always add up to the total. A part is a trial when one of its accounts is a trial.
struct PopoverTotal: Equatable {
    struct Part: Equatable {
        /// `claude` or `codex`.
        let provider: String
        let cents: Int
        let isTrial: Bool
    }

    /// Claude first, then GPT, each only when it has an account with a mix.
    let parts: [Part]

    var totalCents: Int { parts.reduce(0) { $0 + $1.cents } }
}

/// Rules for the menu bar, the popover and the app window. No SwiftUI here. Every time comes in as `now`, and every
/// text comes in with the language it must be drawn in.
enum AppUsageInsights {
    struct SublineText: Equatable {
        let text: String
        let isError: Bool
    }

    struct UsageTile: Equatable {
        let title: String
        let tokensText: String
        /// The real cost, as the Quota tab shows it: "~$12.40". Nil when the file has none.
        let costText: String?
        /// The shares of the period by model, for the colour bar under the tile. Empty when there is no mix.
        var bar: [TileBarSegment] = []
        /// The what-if cost, shown big in the Model mix tab while the mix is a trial. Nil otherwise.
        var trialCostText: String? = nil
    }

    /// One model's part of a tile's colour bar.
    struct TileBarSegment: Equatable {
        let family: String
        let label: String
        let percent: Int
    }

    struct StatusLine: Equatable {
        enum Tone: Equatable { case healthy, warning, neutral }
        let text: String
        let tone: Tone
    }

    // MARK: Percentages

    /// Highest used_percent among the account's limits. Nil when it has no limits.
    static func highestPercent(_ account: UsageAccount) -> Double? {
        account.limits.map { $0.usedPercent }.max()
    }

    /// Highest used_percent across all accounts. The menu bar shows what is left of this limit, which is the least left
    /// of all. Nil means show "--".
    static func overallPercent(_ document: UsageDocument?) -> Double? {
        document?.accounts.compactMap { highestPercent($0) }.max()
    }

    /// The menu bar text: what is left, as a whole number with no % sign, since the bar has no room for one. "--" when unknown.
    static func statusTitle(_ percent: Double?) -> String {
        UsageFormat.leftWhole(percent).map { String($0) } ?? "--"
    }

    /// The limit with the highest used_percent. On a tie the earlier limit in the file wins.
    static func topLimit(_ account: UsageAccount) -> UsageLimit? {
        account.limits.reduce(nil as UsageLimit?) { best, limit in
            guard let best else { return limit }
            return limit.usedPercent > best.usedPercent ? limit : best
        }
    }

    /// True when any limit is at 80% or more (yellow or red). Drives the "ใกล้หมด" pill.
    static func isNearFull(_ account: UsageAccount) -> Bool {
        account.limits.contains { UsageFormat.isAlert($0.usedPercent) }
    }

    /// True only on the move from below 80 to 80 or more. A missing earlier value (the first load) never counts.
    static func crossedAlert(previous: Double?, current: Double?) -> Bool {
        guard let previous, let current else { return false }
        return previous < UsageFormat.alertThreshold && current >= UsageFormat.alertThreshold
    }

    // MARK: Text

    /// Stale and error accounts. Their error text is shown.
    static func isProblem(_ account: UsageAccount) -> Bool {
        account.status == "stale" || account.status == "error"
    }

    /// The text of an account's error, in the chosen language (see `L10n.errorMessage`). Nil when there is none.
    static func errorText(_ account: UsageAccount, language: UILanguage) -> String? {
        L10n.errorMessage(code: account.errorCode, fallback: account.error, language)
    }

    /// Name on the card and in the popover. Falls back to the provider's name when the label is empty.
    static func displayName(_ account: UsageAccount) -> String {
        nonEmpty(account.label) ?? ProviderStyle.fallbackLabel(for: account.provider)
    }

    /// Line under the name in the app window. Nil for a provider the app does not know. Company names stay as they are.
    static func subtitle(for provider: String) -> String? {
        switch provider {
        case "claude": return "Anthropic"
        case "codex": return "OpenAI"
        case "agy": return "Antigravity"
        default: return nil
        }
    }

    /// Letter on the brand square: C, G and A for the three providers, otherwise the first letter of the name.
    static func brandLetter(for account: UsageAccount) -> String {
        switch account.provider {
        case "claude": return "C"
        case "codex": return "G"
        case "agy": return "A"
        default: return String(displayName(account).prefix(1)).uppercased()
        }
    }

    /// Plan under the name in the popover. Only Claude shows it.
    static func popoverCaption(_ account: UsageAccount) -> String? {
        account.provider == "claude" ? nonEmpty(account.plan) : nil
    }

    /// Plan tag on the app-window card, for every account.
    static func planTag(_ account: UsageAccount) -> String? {
        nonEmpty(account.plan)
    }

    /// The popover's subline, which may wrap to two lines and is never cut off. Two limits take one line each, in file
    /// order: "label เหลือ NN%" on the first line and the same on the second. One limit, or three and more, read the top
    /// limit as "label เหลือ NN%" and its reset text, which wraps when it is long. A stale or error account shows its
    /// error text instead.
    static func popoverSubline(_ account: UsageAccount, now: Date, language: UILanguage) -> SublineText? {
        if isProblem(account), let error = errorText(account, language: language) {
            return SublineText(text: error, isError: true)
        }
        if account.limits.count == 2 {
            let lines = account.limits
                .map { "\(UsageFormat.windowLabel($0, language: language)) \(UsageFormat.leftText($0.usedPercent, language))" }
            return SublineText(text: lines.joined(separator: "\n"), isError: false)
        }
        guard let top = topLimit(account) else { return nil }
        var text = "\(UsageFormat.windowLabel(top, language: language)) \(UsageFormat.leftText(top.usedPercent, language))"
        if let reset = UsageFormat.resetText(resetsAt: top.resetsAt, now: now, language: language) {
            text += " · \(reset)"
        }
        return SublineText(text: text, isError: false)
    }

    /// What VoiceOver reads for a popover row: "Claude 5 ชม., เหลือ 58 เปอร์เซ็นต์", the account, its most used limit and
    /// what is left of it. A stale or error account also reads its error text.
    static func popoverSpokenText(_ account: UsageAccount, now: Date, language: UILanguage) -> String {
        let top = topLimit(account).map { UsageFormat.windowLabel($0, language: language) } ?? ""
        let base = L10n.limitSpoken(
            service: displayName(account),
            window: top,
            left: UsageFormat.leftWhole(highestPercent(account)),
            language
        )
        guard let subline = popoverSubline(account, now: now, language: language), subline.isError else { return base }
        return base + ", " + subline.text
    }

    /// "เครดิต N" / "Credits N" when the balance is known, 0 included.
    static func creditText(_ account: UsageAccount, language: UILanguage) -> String? {
        account.credits?.balanceUsd.map { L10n.credits(UsageFormat.creditText($0), language) }
    }

    // MARK: Layout

    /// Accounts with more than two limits use the compact list in the app window.
    static func usesCompactLimits(_ account: UsageAccount) -> Bool {
        account.limits.count > 2
    }

    /// The "Today" and "This month" tiles, for Claude and ChatGPT accounts (the cost is USD at API rates for both).
    ///
    /// The Quota tab passes `shownPercents` nil: the tiles show the real values and the real colour bar. The Model mix tab
    /// passes the shares it shows: the bar takes them, and while they differ from the real mix the tile's big value is the
    /// what-if cost and `costText` stays the real one (the "actual" figure).
    static func usageTiles(_ account: UsageAccount, mix: AccountModelMix?, shownPercents: [Int]?, language: UILanguage) -> [UsageTile] {
        guard account.provider == "claude" || account.provider == "codex", let usage = account.usage else { return [] }
        let trial = shownPercents != nil && mix?.isTrial == true
        let todayTrial = trial ? mix?.today?.panel(percents: mix?.shown.percents ?? []).totalCost : nil
        let monthTrial = trial ? mix?.shown.totalCost : nil
        return [
            tile(title: L10n.text(.today, language), bucket: usage.today, basis: mix?.today, shown: shownPercents, trialCost: todayTrial, language: language),
            tile(title: L10n.text(.thisMonth, language), bucket: usage.month, basis: mix?.month, shown: shownPercents, trialCost: monthTrial, language: language),
        ]
    }

    private static func tile(
        title: String, bucket: UsageBucket?, basis: ModelMixBasis?, shown: [Int]?, trialCost: Double?, language: UILanguage
    ) -> UsageTile {
        let tokens = bucket?.tokens.map { L10n.tokens(UsageFormat.tokensText($0), language) } ?? "—"
        let cost = bucket?.costUsd.map { "~\(UsageFormat.moneyText($0))" }
        var result = UsageTile(title: title, tokensText: tokens, costText: cost)
        if let basis {
            let percents = shown ?? basis.realPercents
            if percents.count == basis.models.count {
                result.bar = zip(basis.models, percents).map { model, percent in
                    TileBarSegment(family: model.price.family, label: model.price.label, percent: percent)
                }
            }
        }
        if let trialCost {
            result.trialCostText = "~\(UsageFormat.moneyText(trialCost))"
        }
        return result
    }

    // MARK: Popover total

    /// The provider order of the popover line, and the names it shows.
    static let popoverProviders = ["claude", "codex"]

    /// Sums each provider's accounts that have a mix, in whole cents. Only the accounts in `accounts` count, which are
    /// the shown ones (the collector writes the enabled accounts only).
    static func popoverTotal(accounts: [UsageAccount], mixes: [String: AccountModelMix]) -> PopoverTotal? {
        var cents: [String: Int] = [:]
        var trial: [String: Bool] = [:]
        for account in accounts {
            guard let mix = mixes[account.id] else { continue }
            cents[mix.provider, default: 0] += mix.shown.totalCents
            trial[mix.provider, default: false] = trial[mix.provider, default: false] || mix.isTrial
        }
        let parts = popoverProviders.compactMap { provider -> PopoverTotal.Part? in
            guard let value = cents[provider] else { return nil }
            return PopoverTotal.Part(provider: provider, cents: value, isTrial: trial[provider] ?? false)
        }
        return parts.isEmpty ? nil : PopoverTotal(parts: parts)
    }

    /// The name of a provider in the popover line: "Claude" and "GPT".
    static func popoverName(_ provider: String) -> String {
        provider == "codex" ? "GPT" : "Claude"
    }

    /// "≈ $48.40 เดือนนี้ · Claude $31.26 · GPT $17.14" with a trial part marked "(ทดลอง)".
    static func popoverText(_ total: PopoverTotal, language: UILanguage) -> String {
        let parts = total.parts.map { part -> String in
            let text = "\(popoverName(part.provider)) \(UsageFormat.moneyText(cents: part.cents))"
            return part.isTrial ? L10n.trialMarker(text, language) : text
        }
        return L10n.popoverTotal(total: UsageFormat.moneyText(cents: total.totalCents), parts: parts, language)
    }

    // MARK: Time and status

    /// When the data was last written: the file's generated_at, or the newest account update if that is missing.
    static func lastUpdated(_ document: UsageDocument) -> Date? {
        document.generatedAt ?? document.accounts.compactMap { $0.updatedAt }.max()
    }

    /// "Updated 2 min ago" / "อัปเดต 2 นาทีก่อน" for the title row and the popover footer. Nil when there is no data.
    static func updatedText(_ document: UsageDocument?, now: Date, language: UILanguage) -> String? {
        guard let document, let date = lastUpdated(document) else { return nil }
        return UsageFormat.updatedText(updatedAt: date, now: now, language: language)
    }

    /// The status line at the bottom. Refresh progress comes first, then the last refresh notice, then the first
    /// account that is stale or in error (its error text), then "All systems normal".
    static func statusLine(_ state: AppUsageState, language: UILanguage) -> StatusLine {
        if state.isRefreshing {
            return StatusLine(text: L10n.text(.refreshing, language), tone: .neutral)
        }
        if let notice = state.notice {
            return StatusLine(text: L10n.notice(notice, language), tone: .warning)
        }
        guard let document = state.document, !document.accounts.isEmpty else {
            return StatusLine(text: L10n.text(.noData, language), tone: .neutral)
        }
        if let problem = document.accounts.first(where: { isProblem($0) }) {
            let text = errorText(problem, language: language) ?? L10n.text(.noData, language)
            return StatusLine(text: text, tone: .warning)
        }
        return StatusLine(text: L10n.text(.allSystemsNormal, language), tone: .healthy)
    }

    /// The text trimmed of spaces, or nil when nothing is left.
    static func nonEmpty(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
