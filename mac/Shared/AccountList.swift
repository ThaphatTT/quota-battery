import Foundation

/// One row of the Accounts section in the app window: an account the collector found, shown or hidden. Plain data, so
/// the rules are tested without SwiftUI.
struct AccountListRow: Equatable, Identifiable {
    let id: String
    let provider: String
    /// The name on the row: the user's nickname, or else the default name ("Claude", "Claude 1", "ChatGPT", "agy").
    let name: String
    /// The user's nickname, or nil when none is set. The rename field starts from it.
    let nickname: String?
    /// Where the account was found, for example "Claude Code (~/.claude-2)".
    let source: String
    /// The plan from usage.json. Nil for a hidden account, and when the plan is unknown.
    let plan: String?
    /// The show and hide switch. False keeps the account out of usage.json and out of the widgets.
    let enabled: Bool
    /// True for an account found less than `AccountList.newWindow` ago. Shows the green "ใหม่ / New" tag.
    let isNew: Bool
    /// The place in the drag order from settings.json, or nil when the account has none yet.
    let order: Int?
    /// What is left of the account's most used limit, from 0 to 100. Nil when the account is hidden or has no limits.
    let smallestRemaining: Double?
}

/// The rules of the Accounts section: which accounts it lists, what they are called, which are new, and the order they
/// are shown in. The order follows the collector's rules for usage.json, so the list and the widgets agree.
enum AccountList {
    /// An account found less than this long ago gets the "New" tag.
    static let newWindow: TimeInterval = 24 * 60 * 60

    /// One row per known account, in discovery order, then any account in usage.json that the known list does not have.
    /// The rows are not sorted yet: call `sorted`. An account in usage.json with no id is left out, because it cannot be
    /// changed from here.
    static func rows(
        known: [KnownAccount],
        usage: [UsageAccount],
        settings: AccountSettings,
        now: Date
    ) -> [AccountListRow] {
        var found: [FoundAccount] = []
        var seen = Set<String>()
        for account in known where seen.insert(account.id).inserted {
            found.append(FoundAccount(
                id: account.id,
                provider: account.provider,
                source: account.source,
                firstSeen: account.firstSeen
            ))
        }
        var usageByID: [String: UsageAccount] = [:]
        for account in usage where !account.id.isEmpty && seen.insert(account.id).inserted {
            found.append(FoundAccount(
                id: account.id,
                provider: account.provider,
                source: ProviderStyle.tag(for: account.provider),
                firstSeen: nil
            ))
        }
        for account in usage where !account.id.isEmpty {
            usageByID[account.id] = usageByID[account.id] ?? account
        }

        var countByProvider: [String: Int] = [:]
        for entry in found {
            countByProvider[entry.provider, default: 0] += 1
        }
        var indexByProvider: [String: Int] = [:]
        return found.map { entry in
            let index = indexByProvider[entry.provider, default: 0]
            indexByProvider[entry.provider] = index + 1
            let preference = settings.preference(for: entry.id)
            let nickname = nonEmpty(preference.label)
            let usageAccount = usageByID[entry.id]
            return AccountListRow(
                id: entry.id,
                provider: entry.provider,
                name: nickname ?? defaultName(
                    provider: entry.provider,
                    index: index,
                    count: countByProvider[entry.provider] ?? 1
                ),
                nickname: nickname,
                source: entry.source.isEmpty ? ProviderStyle.tag(for: entry.provider) : entry.source,
                plan: usageAccount.flatMap { nonEmpty($0.plan) },
                enabled: preference.enabled,
                isNew: isNew(firstSeen: entry.firstSeen, now: now),
                order: preference.order,
                smallestRemaining: usageAccount.flatMap { smallestRemaining(of: $0) }
            )
        }
    }

    /// The default name, the same rule as the collector's label: the provider's name alone when it has one account, and
    /// a number from 1 in discovery order when it has two or more ("Claude 1", "Claude 2"). Hidden accounts count too,
    /// so a name does not change when the account is shown again.
    static func defaultName(provider: String, index: Int, count: Int) -> String {
        let base = ProviderStyle.fallbackLabel(for: provider)
        return count > 1 ? "\(base) \(index + 1)" : base
    }

    /// True for an account first found less than `newWindow` ago. An account with no date is never new.
    static func isNew(firstSeen: Date?, now: Date) -> Bool {
        guard let firstSeen else { return false }
        return now.timeIntervalSince(firstSeen) < newWindow
    }

    /// The rows in the chosen order.
    /// - manual: `order` ascending. Rows with no order go last, in discovery order.
    /// - lowest: ascending by what is left of the most used limit. Ties keep the manual order, and rows with no limits go last.
    /// - provider: Claude, then ChatGPT (codex), then agy, and any other provider last. Each group in the manual order.
    static func sorted(_ rows: [AccountListRow], by sort: AccountSort) -> [AccountListRow] {
        let manual = manualOrder(rows)
        let positioned = manual.enumerated().map { (position: $0.offset, row: $0.element) }
        switch sort {
        case .manual:
            return manual
        case .lowest:
            return positioned.sorted { lhs, rhs in
                let left = lhs.row.smallestRemaining ?? .infinity
                let right = rhs.row.smallestRemaining ?? .infinity
                if left != right { return left < right }
                return lhs.position < rhs.position
            }.map(\.row)
        case .provider:
            return positioned.sorted { lhs, rhs in
                let left = providerRank(lhs.row.provider)
                let right = providerRank(rhs.row.provider)
                if left != right { return left < right }
                return lhs.position < rhs.position
            }.map(\.row)
        }
    }

    /// The rows in the manual order: `order` ascending, rows with no order last in their given (discovery) order.
    static func manualOrder(_ rows: [AccountListRow]) -> [AccountListRow] {
        rows.enumerated().sorted { lhs, rhs in
            switch (lhs.element.order, rhs.element.order) {
            case let (left?, right?):
                return left == right ? lhs.offset < rhs.offset : left < right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.offset < rhs.offset
            }
        }.map(\.element)
    }

    /// The ids in the new drag order after the dragged id is moved onto the place of `target`. It is removed from
    /// where it was and put at the target's index, so the target moves over by one. An unknown id or the same id leaves
    /// the list as it is.
    static func moved(_ ids: [String], id: String, onto target: String) -> [String] {
        guard id != target, let from = ids.firstIndex(of: id), let to = ids.firstIndex(of: target) else {
            return ids
        }
        var result = ids
        result.remove(at: from)
        result.insert(id, at: to)
        return result
    }

    /// Claude first, then ChatGPT (codex), then agy. Any other provider comes after them.
    static func providerRank(_ provider: String) -> Int {
        switch provider {
        case "claude": return 0
        case "codex": return 1
        case "agy": return 2
        default: return 3
        }
    }

    /// What is left of the account's most used limit, from 0 to 100, or nil when it has no limits.
    static func smallestRemaining(of account: UsageAccount) -> Double? {
        UsageFormat.remainingPercent(account.limits.map(\.usedPercent).max())
    }

    private struct FoundAccount {
        let id: String
        let provider: String
        let source: String
        let firstSeen: Date?
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
