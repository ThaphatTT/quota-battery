import Foundation
import os
import WidgetKit

@MainActor
final class UsageViewModel: ObservableObject {
    private static let logger = Logger(subsystem: "local.aiusage", category: "usage-model")

    @Published private(set) var result: UsageLoadResult
    @Published private(set) var now = Date()
    @Published private(set) var isRefreshing = false
    /// What the app says about its last refresh once it has finished. Its text is made when it is drawn.
    @Published private(set) var notice: RefreshNotice?
    /// The user's language choice. Saved to settings.json; the widgets are reloaded when it changes.
    @Published private(set) var languageChoice: AppLanguage
    /// Every account the collector has found (known-accounts.json), in discovery order. Shown or hidden alike.
    @Published private(set) var knownAccounts: [KnownAccount]
    /// The sort and each account's settings, as settings.json holds them.
    @Published private(set) var accountSettings: AccountSettings
    /// What the last "Add account" did. It stays under the list until the next action.
    @Published private(set) var accountNotice: AccountNotice?
    /// The direct mode switches for ChatGPT and agy, as settings.json holds them. Claude has none.
    @Published private(set) var directMode: DirectModeSettings
    /// The model mix order and what-if percentages of each account, as settings.json `model_mix` holds them. An account
    /// with no entry uses the defaults.
    @Published private(set) var modelMixSettings: [String: ModelMixSettings]

    /// The menu bar label. It is updated on every reload.
    let statusItem = MenuBarStatusItem()

    private let fileURL: URL
    private let settingsURL: URL
    private let knownAccountsURL: URL
    private let uid: uid_t
    private var pollTimer: Timer?
    private var folderWatch: DispatchSourceFileSystemObject?
    /// Watches the notify switch, so settings.json is written again when it changes.
    private var notifySwitch: NSKeyValueObservation?
    /// An account change asked for a collector run while one was already running. That run starts again when it ends.
    private var runAgainAfterRefresh = false
    /// How the three files looked when they were last read (usage.json, known-accounts.json, settings.json).
    private var fileStamps: [FileStamp] = []
    /// The minute of the last reload. The relative times in the window change once a minute, so a reload runs then too.
    private var reloadedMinute = 0
    /// Writes one account's `model_mix` entry to settings.json. The app uses the real writer; a test passes one that counts.
    private let writeModelMix: (String, ModelMixSettings, URL) throws -> Void

    /// The modification time and size of a file. A poll compares these before it reads anything.
    private struct FileStamp: Equatable {
        let modified: Date?
        let size: Int?

        init(_ url: URL) {
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            modified = attributes?[.modificationDate] as? Date
            size = (attributes?[.size] as? NSNumber)?.intValue
        }
    }

    init(
        fileURL: URL = UsageLoader.defaultFileURL(),
        settingsURL: URL = AppSettingsStore.defaultFileURL(),
        knownAccountsURL: URL = KnownAccounts.defaultFileURL(),
        uid: uid_t = getuid(),
        writeModelMix: @escaping (String, ModelMixSettings, URL) throws -> Void = { try AppSettingsStore.saveModelMix($1, accountID: $0, at: $2) }
    ) {
        self.fileURL = fileURL
        self.settingsURL = settingsURL
        self.knownAccountsURL = knownAccountsURL
        self.uid = uid
        self.writeModelMix = writeModelMix
        self.reloadedMinute = Self.minute(of: Date())
        self.result = UsageLoader.load(from: fileURL)
        self.languageChoice = AppSettingsStore.load(from: settingsURL)
        self.knownAccounts = KnownAccounts.load(from: knownAccountsURL)
        self.accountSettings = AppSettingsStore.loadAccountSettings(from: settingsURL)
        self.directMode = AppSettingsStore.loadDirectMode(from: settingsURL)
        self.modelMixSettings = AppSettingsStore.loadModelMix(from: settingsURL)
        statusItem.set(percent: AppUsageInsights.overallPercent(result.document))
        writeNotifySetting()
        // Taken after the notify write, so the app's own write does not look like a change at the first poll.
        fileStamps = [fileURL, knownAccountsURL, settingsURL].map { FileStamp($0) }
        notifySwitch = UserDefaults.standard.observe(\.notifyAt80And95, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.writeNotifySetting() }
        }
        startPolling()
        watchFolder()
    }

    /// The language the texts are drawn in right now: the choice, with `system` resolved on this Mac.
    var uiLanguage: UILanguage {
        UILanguage.current(for: languageChoice)
    }

    var state: AppUsageState {
        AppUsageState(
            result: result,
            now: now,
            isRefreshing: isRefreshing,
            notice: notice,
            accountMixes: accountMixes
        )
    }

    /// The mix of every account that has one, as the settings now make it.
    private var accountMixes: [String: AccountModelMix] {
        guard let document = result.document else { return [:] }
        var mixes: [String: AccountModelMix] = [:]
        for account in document.accounts where !account.id.isEmpty {
            if let mix = mix(for: account, in: document) {
                mixes[account.id] = mix
            }
        }
        return mixes
    }

    private func mix(for account: UsageAccount, in document: UsageDocument) -> AccountModelMix? {
        ModelMix.accountMix(
            for: account,
            prices: document.modelPrices ?? [:],
            settings: modelMixSettings[account.id] ?? .standard
        )
    }

    /// The mix of one account, or nil when it has none.
    private func mix(for accountID: String) -> AccountModelMix? {
        guard let document = result.document, let account = document.accounts.first(where: { $0.id == accountID }) else {
            return nil
        }
        return mix(for: account, in: document)
    }

    /// Saves the choice and reloads the widget timelines so they redraw in the new language. The window, the popover
    /// and the menu bar observe this model, so they redraw at once.
    func setLanguage(_ choice: AppLanguage) {
        guard choice != languageChoice else { return }
        languageChoice = choice
        do {
            try AppSettingsStore.save(choice, to: settingsURL)
        } catch {
            Self.logger.error("settings.json could not be written")
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Writes the notify switch to settings.json. A switch with no stored value is on. Called at launch and whenever the
    /// switch changes, so the file always has the key.
    private func writeNotifySetting() {
        let notify = UserDefaults.standard.object(forKey: AppSettingKey.notifyAt80And95) as? Bool ?? true
        do {
            try AppSettingsStore.saveNotify(notify, to: settingsURL)
        } catch {
            Self.logger.error("settings.json could not be written")
        }
    }

    private static func minute(of date: Date) -> Int {
        Int(date.timeIntervalSinceReferenceDate / 60)
    }

    /// Reads usage.json, known-accounts.json and settings.json again, but only when one of them changed or the minute
    /// has turned. Publishes only when the content changed, so a poll that finds nothing new publishes nothing.
    func reload() {
        let stamps = [fileURL, knownAccountsURL, settingsURL].map { FileStamp($0) }
        let minute = Self.minute(of: Date())
        guard stamps != fileStamps || minute != reloadedMinute else { return }
        fileStamps = stamps
        reloadedMinute = minute
        now = Date()
        let loaded = UsageLoader.load(from: fileURL)
        if loaded != result {
            result = loaded
        }
        let known = KnownAccounts.load(from: knownAccountsURL)
        if known != knownAccounts {
            knownAccounts = known
        }
        let settings = AppSettingsStore.loadAccountSettings(from: settingsURL)
        if settings != accountSettings {
            accountSettings = settings
        }
        let direct = AppSettingsStore.loadDirectMode(from: settingsURL)
        if direct != directMode {
            directMode = direct
        }
        let mix = AppSettingsStore.loadModelMix(from: settingsURL)
        if mix != modelMixSettings {
            modelMixSettings = mix
        }
        statusItem.set(percent: AppUsageInsights.overallPercent(loaded.document))
    }

    /// Starts the collector job, then reloads the widget timelines (in that order).
    /// The collector takes a few seconds, so the file is checked again for up to 60 s. When a newer
    /// usage.json arrives, the widgets are reloaded once more. A request that comes while a run is still going
    /// starts one more run when that run ends, so a change to the accounts is never left waiting for the next timer.
    func refresh() {
        guard !isRefreshing else {
            runAgainAfterRefresh = true
            return
        }
        isRefreshing = true
        notice = nil
        let previousGeneratedAt = result.document?.generatedAt
        let uid = self.uid

        Task {
            let failure = await RefreshCommand.run(uid: uid)
            WidgetCenter.shared.reloadAllTimelines()
            if let failure {
                finishRefresh(notice: .failed(failure))
                return
            }

            let deadline = Date().addingTimeInterval(60)
            while Date() < deadline {
                try? await Task.sleep(for: .seconds(2))
                reload()
                if let generatedAt = result.document?.generatedAt, generatedAt != previousGeneratedAt {
                    WidgetCenter.shared.reloadAllTimelines()
                    finishRefresh(notice: nil)
                    return
                }
            }
            finishRefresh(notice: .noNewData)
        }
    }

    private func finishRefresh(notice: RefreshNotice?) {
        self.notice = notice
        isRefreshing = false
        if runAgainAfterRefresh {
            runAgainAfterRefresh = false
            refresh()
        }
    }

    // MARK: Accounts

    /// Every account in the list, not sorted: the known accounts in discovery order, then any extra one in usage.json.
    private var accountRows: [AccountListRow] {
        AccountList.rows(
            known: knownAccounts,
            usage: result.document?.accounts ?? [],
            settings: accountSettings,
            now: now
        )
    }

    /// What the Accounts section shows: every account in the chosen order, with the sort, the notice and the refresh state.
    var accountsPanel: AccountsPanelState {
        AccountsPanelState(
            rows: AccountList.sorted(accountRows, by: accountSettings.sort),
            sort: accountSettings.sort,
            notice: accountNotice,
            isRefreshing: isRefreshing,
            directMode: directMode
        )
    }

    /// The sort of the list and of the widgets. Writes settings.json, then runs the collector and reloads the widgets.
    func setAccountSort(_ sort: AccountSort) {
        guard sort != accountSettings.sort else { return }
        var settings = accountSettings
        settings.sort = sort
        applyAccountSettings(settings)
    }

    /// Turns direct mode on or off for ChatGPT or agy. Claude is refused. Writes settings.json, then runs the collector and
    /// reloads the widgets, as the other account settings do. Turning it off needs no consent.
    func setDirectMode(_ provider: String, enabled: Bool) {
        guard let next = directMode.setting(provider, to: enabled), next != directMode else { return }
        directMode = next
        do {
            try AppSettingsStore.saveDirectMode(next, at: settingsURL)
        } catch {
            Self.logger.error("settings.json could not be written")
        }
        refresh()
    }

    /// Shows or hides an account. Writes settings.json, then runs the collector and reloads the widgets.
    func setAccountEnabled(_ id: String, _ enabled: Bool) {
        changeAccount(id) { $0.enabled = enabled }
    }

    /// Sets the nickname. An empty name removes it, so the default name comes back.
    func renameAccount(_ id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        changeAccount(id) { $0.label = trimmed.isEmpty ? nil : trimmed }
    }

    /// Drag and drop, in manual order only. The dragged account takes the place of the target, and every account gets
    /// its new position as `order`.
    func moveAccount(_ id: String, onto target: String) {
        guard accountSettings.sort == .manual else { return }
        let ids = AccountList.sorted(accountRows, by: .manual).map(\.id)
        let moved = AccountList.moved(ids, id: id, onto: target)
        guard moved != ids else { return }
        var settings = accountSettings
        for (position, accountID) in moved.enumerated() {
            var preference = settings.preference(for: accountID)
            preference.order = position
            settings.accounts[accountID] = preference
        }
        applyAccountSettings(settings)
    }

    /// Opens Terminal with the login command for a new Claude Code or Codex folder: the first free one from
    /// `~/.claude-2` or `~/.codex-2`. agy has one account only, so it is not offered here.
    func addAccount(provider: String) {
        let home = UsageLoader.realHomeDirectory()
        guard
            AccountLogin.addableProviders.contains(provider),
            let number = AccountLogin.firstFreeNumber(provider: provider, isTaken: { name in
                FileManager.default.fileExists(atPath: home.appendingPathComponent(name).path)
            }),
            let command = AccountLogin.command(provider: provider, number: number)
        else { return }
        accountNotice = nil
        Task {
            let opened = await TerminalLauncher.open(command: command)
            accountNotice = opened ? .terminalOpened(provider: provider) : .terminalFailed
        }
    }

    // MARK: Model mix

    /// Moves one model's slider to `value` in one account's mix. The other sliders move in proportion, so the total stays
    /// 100. The first change of a real mix starts a what-if from the real shares. Writes settings.json only; no collector run.
    func setModelMixPercent(_ accountID: String, _ id: String, to value: Int) {
        guard let mix = mix(for: accountID), let index = mix.shown.rows.firstIndex(where: { $0.id == id }) else { return }
        let next = ModelMixMath.rescale(mix.shown.percents, index: index, to: value)
        var settings = modelMixSettings[accountID] ?? .standard
        settings.percent = Dictionary(uniqueKeysWithValues: zip(mix.shown.rows.map(\.id), next))
        applyModelMix(accountID, settings)
    }

    /// Saves the shares of a finished slider drag: one write for the whole drag. Nothing is written when they are the same.
    func commitModelMixPercent(_ accountID: String, _ percent: [String: Int]) {
        var settings = modelMixSettings[accountID] ?? .standard
        settings.percent = percent
        guard settings != (modelMixSettings[accountID] ?? .standard) else { return }
        applyModelMix(accountID, settings)
    }

    /// Drag and drop: the dragged model takes the place of the target in that account. The order is saved, the shares stay.
    func moveModelMix(_ accountID: String, _ id: String, onto target: String) {
        guard let mix = mix(for: accountID) else { return }
        let ids = mix.shown.rows.map(\.id)
        let moved = AccountList.moved(ids, id: id, onto: target)
        guard moved != ids else { return }
        var settings = modelMixSettings[accountID] ?? .standard
        settings.order = moved
        applyModelMix(accountID, settings)
    }

    /// Keyboard and VoiceOver alternative to dragging: moves a row one place up (-1) or down (+1).
    func stepModelMix(_ accountID: String, _ id: String, by delta: Int) {
        guard let mix = mix(for: accountID) else { return }
        var ids = mix.shown.rows.map(\.id)
        guard let from = ids.firstIndex(of: id) else { return }
        let to = from + delta
        guard ids.indices.contains(to) else { return }
        ids.swapAt(from, to)
        var settings = modelMixSettings[accountID] ?? .standard
        settings.order = ids
        applyModelMix(accountID, settings)
    }

    /// "Reset to actual": the real mix from the logs comes back for that account. The order is kept.
    func resetModelMix(_ accountID: String) {
        guard modelMixSettings[accountID]?.percent != nil else { return }
        var settings = modelMixSettings[accountID] ?? .standard
        settings.percent = nil
        applyModelMix(accountID, settings)
    }

    /// Publishes the new settings of one account at once and writes settings.json. The collector is not run for a mix change.
    private func applyModelMix(_ accountID: String, _ settings: ModelMixSettings) {
        modelMixSettings[accountID] = settings
        do {
            try writeModelMix(accountID, settings, settingsURL)
        } catch {
            Self.logger.error("settings.json could not be written")
        }
    }

    /// Changes one account's settings. Nothing is written when the change leaves them as they were.
    private func changeAccount(_ id: String, _ change: (inout AccountPreference) -> Void) {
        var settings = accountSettings
        var preference = settings.preference(for: id)
        change(&preference)
        guard preference != settings.preference(for: id) else { return }
        settings.accounts[id] = preference
        applyAccountSettings(settings)
    }

    /// Publishes the new settings at once, writes settings.json, then runs the collector and reloads the widgets.
    private func applyAccountSettings(_ settings: AccountSettings) {
        accountSettings = settings
        do {
            try AppSettingsStore.saveAccountSettings(settings, at: settingsURL)
        } catch {
            Self.logger.error("settings.json could not be written")
        }
        refresh()
    }

    /// The window, the popover and the menu bar all look again every 60 s, even when the file has not changed.
    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reload()
            }
        }
    }

    /// Watches the folder, not the file. The collector replaces usage.json by renaming a new file over it,
    /// which would leave a watch on the old file pointing at nothing. Without the folder, the 60 s poll is enough.
    private func watchFolder() {
        let folder = fileURL.deletingLastPathComponent().path
        let descriptor = open(folder, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.reload()
            }
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        folderWatch = source
    }
}
