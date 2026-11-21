import SwiftUI

struct CodexSidebarQuota {
    static let accountKey = "codexSidebarQuotaAccountID"

    let accounts: [UsageAccount]

    init(_ accounts: [UsageAccount]) {
        var seen: Set<String> = []
        self.accounts = accounts.filter { $0.provider == "codex" && !$0.id.isEmpty && seen.insert($0.id).inserted }
    }

    func account(preferredID: String) -> UsageAccount? {
        if let selected = accounts.first(where: { $0.id == preferredID }) { return selected }
        let primary = accounts.first { $0.id == "codex-main" }
        if !Self.periods(for: primary).isEmpty { return primary }
        return accounts.first { !Self.periods(for: $0).isEmpty } ?? primary ?? accounts.first
    }

    static func periods(for account: UsageAccount?) -> [UsageLimit] {
        account?.limits.filter { $0.usedPercent.isFinite } ?? []
    }

    static func name(_ account: UsageAccount) -> String {
        account.label.isEmpty ? ProviderStyle.fallbackLabel(for: account.provider) : account.label
    }

    static func marker(for limit: UsageLimit) -> String {
        switch limit.windowSeconds {
        case 18_000: return "5"
        case 604_800: return "W"
        case let seconds? where seconds > 0:
            if seconds.isMultiple(of: 86_400) { return "\(seconds / 86_400)d" }
            if seconds.isMultiple(of: 3_600) { return "\(seconds / 3_600)h" }
            if seconds.isMultiple(of: 60) { return "\(seconds / 60)m" }
            return "\(seconds)s"
        default:
            switch limit.key {
            case "five_hour": return "5"
            case "seven_day": return "W"
            case "primary": return "P"
            case "secondary": return "S"
            default: return "—"
            }
        }
    }

    static func windowName(_ limit: UsageLimit, language: UILanguage) -> String {
        if let seconds = limit.windowSeconds, seconds > 0 {
            if !seconds.isMultiple(of: 60) {
                return language == .th ? "\(seconds) วินาที" : "\(seconds) seconds"
            }
            if seconds >= 3_600, !seconds.isMultiple(of: 3_600) {
                return language == .th ? "\(seconds / 60) นาที" : "\(seconds / 60) minutes"
            }
            return UsageFormat.windowLabel(limit, language: language)
        }
        switch marker(for: limit) {
        case "5": return language == .th ? "5 ชั่วโมง" : "5 hours"
        case "W": return L10n.text(.week, language)
        case "P": return language == .th ? "โควตาหลัก" : "Primary limit"
        case "S": return language == .th ? "โควตารอง" : "Secondary limit"
        default: return UsageFormat.windowLabel(limit, language: language)
        }
    }
}

struct CodexQuotaDetails: View {
    @ObservedObject var model: UsageViewModel
    @AppStorage(CodexSidebarQuota.accountKey) private var preferredID = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false
    let onOpenApp: () -> Void

    var body: some View {
        let accounts = model.result.document?.accounts ?? []
        let quota = CodexSidebarQuota(accounts)
        let account = quota.account(preferredID: preferredID)
        let others = accounts.filter { $0.id != account?.id }
        let language = model.uiLanguage
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text(.usageTitle, language)).font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let account {
                        let accountLabel = language == .th ? "บัญชี GPT ที่เลือก" : "Selected GPT account"
                        if quota.accounts.count > 1 {
                            Picker(accountLabel, selection: Binding(get: { account.id }, set: { preferredID = $0 })) {
                                ForEach(quota.accounts, id: \.id) { option in
                                    Text(CodexSidebarQuota.name(option)).tag(option.id)
                                }
                            }
                        }
                        accountRows(account, language: language)
                    }
                    ForEach(others.indices, id: \.self) { index in
                        if account != nil || index > 0 { Divider() }
                        accountRows(others[index], language: language)
                    }
                    if account == nil, others.isEmpty {
                        Text(L10n.text(.noData, language)).foregroundStyle(.secondary)
                    }
                }
                .padding(.trailing, 3)
            }
            .frame(minHeight: 70, maxHeight: 330)
            .opacity(revealed ? 1 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2).delay(0.06), value: revealed)

            Divider()
            Button(L10n.text(.openApp, language), action: onOpenApp)
                .buttonStyle(.link)
                .opacity(revealed ? 1 : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2).delay(0.14), value: revealed)
        }
        .padding(14)
        .frame(width: 294, alignment: .leading)
        .onAppear { revealed = true }
    }

    private func accountRows(_ account: UsageAccount, language: UILanguage) -> some View {
        let periods = CodexSidebarQuota.periods(for: account)
        return VStack(alignment: .leading, spacing: 6) {
            Label(CodexSidebarQuota.name(account), systemImage: "circle.fill")
                .foregroundStyle(Color(hex: ProviderStyle.accentHex(for: account.provider)))
                .font(.subheadline.weight(.semibold))
            if periods.isEmpty {
                Text(L10n.text(.noLimitData, language)).foregroundStyle(.secondary)
            }
            ForEach(periods.indices, id: \.self) { index in
                periodRow(periods[index], language: language)
            }
            if let balance = account.credits?.balanceUsd {
                Text(L10n.credits(UsageFormat.creditText(balance), language))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func periodRow(_ limit: UsageLimit, language: UILanguage) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(CodexSidebarQuota.windowName(limit, language: language))
                Spacer()
                Text(UsageFormat.leftText(limit.usedPercent, language)).monospacedDigit()
            }
            if let reset = limit.resetsAt {
                let time = reset.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened)
                    .locale(Locale(identifier: language == .th ? "th_TH" : "en_US")))
                Text(language == .th ? "รีเซ็ต \(time)" : "Resets \(time)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
