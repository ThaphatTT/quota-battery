import ApplicationServices
import SwiftUI

/// The Settings window: four panes (General, Accounts, Notifications, Direct mode). It opens with ⌘, and from the gear
/// in the app window. Each pane reads and writes what the app window used to hold, with the same settings.json keys
/// and the same behaviour. Only the place has changed.
struct AppSettingsView: View {
    @ObservedObject var model: UsageViewModel
    /// The tab on screen: 0 General, 1 Accounts, 2 Notifications, 3 Direct mode.
    @State private var tab = 0
    @ObservedObject var openAtLogin: OpenAtLoginModel
    @AppStorage(AppSettingKey.showMenuBarIcon) private var showMenuBarIcon = true
    @AppStorage(AppSettingKey.notifyAt80And95) private var notifyAt80And95 = true

    var body: some View {
        let language = model.uiLanguage
        TabView(selection: $tab) {
            ScrollView {
                GeneralSettingsPane(
                    choice: model.languageChoice,
                    onSetLanguage: { model.setLanguage($0) },
                    showMenuBarIcon: $showMenuBarIcon,
                    openAtLogin: openAtLogin
                )
                .padding(20)
            }
            .tabItem { Label(L10n.text(.tabGeneral, language), systemImage: "gearshape") }
            .tag(0)

            ScrollView {
                AppAccountsSection(
                    state: model.accountsPanel,
                    actions: AccountActions(
                        rescan: { model.refresh() },
                        add: { model.addAccount(provider: $0) },
                        rename: { model.renameAccount($0, to: $1) },
                        setEnabled: { model.setAccountEnabled($0, $1) },
                        move: { model.moveAccount($0, onto: $1) },
                        setSort: { model.setAccountSort($0) },
                        setDirectMode: { model.setDirectMode($0, enabled: $1) }
                    ),
                    isShowing: tab == 1
                )
                .padding(20)
            }
            .tabItem { Label(L10n.text(.tabAccounts, language), systemImage: "person.2") }
            .tag(1)

            ScrollView {
                NotificationsSettingsPane(notify: $notifyAt80And95)
                    .padding(20)
            }
            .tabItem { Label(L10n.text(.tabNotifications, language), systemImage: "bell") }
            .tag(2)

            ScrollView {
                DirectModeSettingsPane(
                    state: model.accountsPanel.directMode,
                    onSetDirectMode: { model.setDirectMode($0, enabled: $1) }
                )
                .padding(20)
            }
            .tabItem { Label(L10n.text(.tabDirectMode, language), systemImage: "bolt.horizontal") }
            .tag(3)
        }
        .environment(\.uiLanguage, language)
        .frame(width: 580, height: 520)
        .onAppear { openAtLogin.refresh() }
    }
}

// MARK: - Panes

/// General: the language, the menu bar icon switch, and open at login.
struct GeneralSettingsPane: View {
    let choice: AppLanguage
    let onSetLanguage: (AppLanguage) -> Void
    @Binding var showMenuBarIcon: Bool
    @ObservedObject var openAtLogin: OpenAtLoginModel
    /// Set only by the snapshot tests: draws look-alikes of the native segmented control and switches.
    var snapshot: Bool = false
    @AppStorage(AppSettingKey.showClaudeHeaderRing) private var showClaudeHeaderRing = false
    @AppStorage(AppSettingKey.showCodexUsageRing) private var showCodexUsageRing = true
    @State private var accessibilityGranted = AXIsProcessTrusted()
    @Environment(\.uiLanguage) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard {
                SettingsRow(title: L10n.text(.languageLabel, language)) {
                    languagePicker
                }
                Divider()
                SettingsRow(title: L10n.text(.showMenuBarIcon, language)) {
                    switchControl(isOn: $showMenuBarIcon, title: L10n.text(.showMenuBarIcon, language), snapshotOn: showMenuBarIcon)
                }
                Divider()
                SettingsRow(
                    title: L10n.text(.showClaudeHeaderRing, language),
                    hint: L10n.text(.claudeHeaderHint, language)
                ) {
                    switchControl(
                        isOn: $showClaudeHeaderRing,
                        title: L10n.text(.showClaudeHeaderRing, language),
                        snapshotOn: showClaudeHeaderRing
                    )
                }
                Divider()
                SettingsRow(title: L10n.text(.showCodexUsageRing, language)) {
                    switchControl(
                        isOn: $showCodexUsageRing,
                        title: L10n.text(.showCodexUsageRing, language),
                        snapshotOn: showCodexUsageRing
                    )
                }
                if !snapshot && (showClaudeHeaderRing || showCodexUsageRing) && !accessibilityGranted {
                    Button(L10n.text(.claudeHeaderAccessibility, language)) {
                        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                        accessibilityGranted = AXIsProcessTrustedWithOptions(options as CFDictionary)
                    }
                    .controlSize(.small)
                }
                Divider()
                SettingsRow(
                    title: L10n.text(.openAtLogin, language),
                    hint: L10n.text(.openAtLoginHint, language)
                ) {
                    switchControl(
                        isOn: Binding(get: { openAtLogin.isOn }, set: { openAtLogin.setEnabled($0) }),
                        title: L10n.text(.openAtLogin, language),
                        snapshotOn: openAtLogin.isOn
                    )
                }
                if openAtLogin.status == .requiresApproval {
                    Text(L10n.text(.openAtLoginNeedsApproval, language))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if openAtLogin.failed {
                    Text(L10n.text(.openAtLoginFailed, language))
                        .font(.system(size: 11))
                        .foregroundStyle(LocalPalette.warning)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessibilityGranted = AXIsProcessTrusted()
        }
    }

    @ViewBuilder
    private var languagePicker: some View {
        let options: [(AppLanguage, String)] = [
            (.system, L10n.text(.languageSystem, language)),
            (.th, L10n.text(.languageThai, language)),
            (.en, L10n.text(.languageEnglish, language)),
        ]
        if snapshot {
            SegmentedLook(selection: choice, options: options)
                .frame(width: 240)
        } else {
            Picker(L10n.text(.languageLabel, language), selection: Binding(get: { choice }, set: onSetLanguage)) {
                ForEach(options, id: \.0) { option in
                    Text(option.1).tag(option.0)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
    }

    @ViewBuilder
    private func switchControl(isOn: Binding<Bool>, title: String, snapshotOn: Bool) -> some View {
        if snapshot {
            SwitchLook(isOn: snapshotOn)
        } else {
            Toggle(isOn: isOn) {
                Text(title)
            }
            .toggleStyle(.switch)
            .labelsHidden()
        }
    }
}

/// Notifications: the 80% and 95% switch.
struct NotificationsSettingsPane: View {
    @Binding var notify: Bool
    var snapshot: Bool = false
    @Environment(\.uiLanguage) private var language

    var body: some View {
        SettingsCard {
            SettingsRow(title: L10n.text(.notifyAt80And95, language)) {
                if snapshot {
                    SwitchLook(isOn: notify)
                } else {
                    Toggle(isOn: $notify) {
                        Text(L10n.text(.notifyAt80And95, language))
                    }
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Direct mode: one control for each provider that can have it (ChatGPT and agy). Claude has none.
struct DirectModeSettingsPane: View {
    let state: DirectModeSettings
    let onSetDirectMode: (String, Bool) -> Void
    var snapshot: Bool = false
    @Environment(\.uiLanguage) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text(.directModeIntro, language))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            SettingsCard {
                ForEach(Array(DirectMode.providers.enumerated()), id: \.offset) { index, provider in
                    if index > 0 {
                        Divider()
                    }
                    DirectModeRow(
                        provider: provider,
                        name: Self.name(for: provider),
                        isOn: state.isOn(provider),
                        onSet: { onSetDirectMode(provider, $0) },
                        snapshot: snapshot
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The brand names of the two providers. They are not translated.
    static func name(for provider: String) -> String {
        provider == "codex" ? "ChatGPT" : "agy"
    }
}

/// One provider in the Direct mode pane. Off: a button that opens the consent screen. On: the state, and a button that
/// turns it off at once. Turning it off needs no consent. The switch is per provider, so every account of it shares it.
private struct DirectModeRow: View {
    let provider: String
    let name: String
    let isOn: Bool
    let onSet: (Bool) -> Void
    let snapshot: Bool
    @Environment(\.uiLanguage) private var language
    @State private var showConsent = false

    var body: some View {
        SettingsRow(title: name) {
            HStack(spacing: 8) {
                if isOn {
                    Circle()
                        .fill(LocalPalette.healthy)
                        .frame(width: 7, height: 7)
                    Text(L10n.text(.directModeOn, language))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Button(L10n.text(.directModeTurnOff, language)) {
                        onSet(false)
                    }
                    .controlSize(.small)
                } else {
                    Button(L10n.text(.directModeTurnOnAction, language)) {
                        showConsent = true
                    }
                    .controlSize(.small)
                }
            }
        }
        .sheet(isPresented: $showConsent) {
            DirectModeConsentView(provider: provider, snapshot: snapshot) { _ in onSet(true) }
                .environment(\.uiLanguage, language)
        }
    }
}

// MARK: - Building blocks

/// A rounded group of rows, the same look as the app window's sections.
struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
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
}

/// A title, an optional hint under it, and the control at the right.
struct SettingsRow<Control: View>: View {
    let title: String
    var hint: String? = nil
    @ViewBuilder let control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                if let hint {
                    Text(hint)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            control
        }
    }
}
