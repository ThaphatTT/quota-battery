import AppKit
import SwiftUI

/// The app window: a title row, one card per account, the Accounts section, then the two
/// switches, the language picker and the status line.
struct ContentView: View {
    let state: AppUsageState
    let accounts: AccountsPanelState
    let accountActions: AccountActions
    let languageChoice: AppLanguage
    let onSetLanguage: (AppLanguage) -> Void
    let onRefresh: () -> Void
    let onOpenLogs: () -> Void

    @AppStorage(AppSettingKey.showMenuBarIcon) private var showMenuBarIcon = true
    @AppStorage(AppSettingKey.notifyAt80And95) private var notifyAt80And95 = true
    @Environment(\.uiLanguage) private var language

    var body: some View {
        VStack(spacing: 0) {
            titleRow
            Divider()
            ScrollView {
                VStack(spacing: 16) {
                    cards
                    AppAccountsSection(state: accounts, actions: accountActions)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            Divider()
            footer
        }
        .frame(width: 530)
    }

    /// The window has a hidden title bar, so this row takes the place of the title bar. The traffic lights stay at the left.
    private var titleRow: some View {
        ZStack {
            Text(L10n.text(.appName, language))
                .font(.system(size: 13, weight: .semibold))
            HStack(spacing: 10) {
                Spacer()
                if let updated = AppUsageInsights.updatedText(state.document, now: state.now, language: language) {
                    Text(updated)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                RefreshButton(isRefreshing: state.isRefreshing, action: onRefresh)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var cards: some View {
        if state.accounts.isEmpty {
            AppNoDataView()
                .frame(maxWidth: .infinity, minHeight: 300)
        } else {
            VStack(spacing: 12) {
                ForEach(Array(state.accounts.enumerated()), id: \.offset) { _, account in
                    AppAccountCardView(account: account, now: state.now)
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 28) {
                SwitchRow(title: L10n.text(.showMenuBarIcon, language), isOn: $showMenuBarIcon)
                SwitchRow(title: L10n.text(.notifyAt80And95, language), isOn: $notifyAt80And95)
            }
            LanguagePicker(choice: languageChoice, onChange: onSetLanguage)
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
            Text(line.text)
                .font(.system(size: 12))
                .foregroundStyle(line.tone == .warning ? LocalPalette.warning : Color.secondary)
                .lineLimit(1)
        }
    }
}

/// A native switch on the left and its label on the right.
private struct SwitchRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 8) {
            Toggle(isOn: $isOn) {
                Text(title)
            }
            .toggleStyle(.switch)
            .labelsHidden()
            Text(title)
                .font(.system(size: 12))
                .accessibilityHidden(true)
        }
    }
}

/// The language choice: a segmented control under the two switches. Choosing a language changes the window, the
/// popover, the menu bar and the widgets at once.
private struct LanguagePicker: View {
    let choice: AppLanguage
    let onChange: (AppLanguage) -> Void
    @Environment(\.uiLanguage) private var language

    var body: some View {
        HStack(spacing: 12) {
            Text(L10n.text(.languageLabel, language))
                .font(.system(size: 12))
            Picker(L10n.text(.languageLabel, language), selection: Binding(get: { choice }, set: onChange)) {
                Text(L10n.text(.languageSystem, language)).tag(AppLanguage.system)
                Text(L10n.text(.languageThai, language)).tag(AppLanguage.th)
                Text(L10n.text(.languageEnglish, language)).tag(AppLanguage.en)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
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
