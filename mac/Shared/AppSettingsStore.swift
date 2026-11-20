import Foundation

/// The settings kept in `~/Library/Application Support/AIUsage/settings.json`, next to usage.json. The file is one JSON
/// object. The app writes `"language"` (`"system" | "th" | "en"`), `"notify"` (a JSON boolean), `"sort"` (`"manual" |
/// "lowest" | "provider"`), `"accounts"` (per account: `label`, `enabled`, `order`) and `"direct_mode"` (`{"codex": bool,
/// "agy": bool}`). The widget reads the language and the collector reads the notify value, the sort, the accounts and
/// direct_mode. Each write changes only its own keys and keeps the others.
/// A missing or broken file means "system" when it is read, and an empty object when it is written.
enum AppSettingsStore {
    /// The keys the app writes. Other keys in the file are kept as they are.
    static let languageKey = "language"
    static let notifyKey = "notify"

    private struct Stored: Codable {
        let language: String
    }

    /// The real home folder's copy, next to usage.json.
    static func defaultFileURL(home: URL = UsageLoader.realHomeDirectory()) -> URL {
        home.appendingPathComponent("Library/Application Support/AIUsage/settings.json")
    }

    static func load(from url: URL) -> AppLanguage {
        guard
            let data = try? Data(contentsOf: url),
            let stored = try? JSONDecoder().decode(Stored.self, from: data),
            let language = AppLanguage(rawValue: stored.language)
        else {
            return .system
        }
        return language
    }

    static func save(_ language: AppLanguage, to url: URL) throws {
        try update(languageKey, to: language.rawValue, at: url)
    }

    static func saveNotify(_ notify: Bool, to url: URL) throws {
        try update(notifyKey, to: notify, at: url)
    }

    /// Sets one key and keeps every other key. The whole file is read as a JSON object, so keys this version does not
    /// know stay. A missing or broken file starts from an empty object. The bytes are compact with sorted keys, for
    /// example `{"language":"th","notify":true}`, and the write is atomic.
    static func update(_ key: String, to value: Any, at url: URL) throws {
        var object = readObject(at: url)
        object[key] = value
        try write(object, to: url)
    }

    /// Writes the whole object with sorted keys, as compact bytes, and replaces the file atomically. The folder is
    /// created first.
    fileprivate static func write(_ object: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    /// The settings object as a dictionary. A missing or broken file reads as an empty object.
    static func readObject(at url: URL) -> [String: Any] {
        guard
            let data = try? Data(contentsOf: url),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        return object
    }
}

// MARK: - Accounts in settings.json

/// The order the account list and the widgets show the accounts in. The app writes it, and the collector applies it.
enum AccountSort: String, CaseIterable, Equatable {
    /// The drag order, from `order`. Accounts with no order go last, in discovery order.
    case manual
    /// The account with the least left first. Ties keep the drag order, and accounts with no limits go last.
    case lowest
    /// Claude, then ChatGPT, then agy, each group in the drag order.
    case provider
}

/// One account's entry in settings.json `accounts`. A missing key means the default: no nickname, shown, no order yet.
struct AccountPreference: Equatable {
    /// The nickname the user typed. Nil when none is set, which means the default name.
    var label: String?
    /// False hides the account from usage.json and from the widgets.
    var enabled: Bool
    /// The place in the drag order, from 0. Nil when the account has none yet.
    var order: Int?

    static let standard = AccountPreference(label: nil, enabled: true, order: nil)
}

/// The sort and each account's preference, as settings.json holds them under the keys `sort` and `accounts`.
struct AccountSettings: Equatable {
    var sort: AccountSort = .manual
    /// Keyed by account id. An account with no entry uses `AccountPreference.standard`.
    var accounts: [String: AccountPreference] = [:]

    func preference(for id: String) -> AccountPreference {
        accounts[id] ?? .standard
    }
}

extension AppSettingsStore {
    static let sortKey = "sort"
    static let accountsKey = "accounts"

    /// A missing or broken file, a missing key, or an unknown sort value counts as the default.
    static func loadAccountSettings(from url: URL) -> AccountSettings {
        let object = readObject(at: url)
        let sort = (object[sortKey] as? String).flatMap(AccountSort.init(rawValue:)) ?? .manual
        var accounts: [String: AccountPreference] = [:]
        for (id, value) in (object[accountsKey] as? [String: Any]) ?? [:] {
            guard let entry = value as? [String: Any] else { continue }
            accounts[id] = AccountPreference(
                label: nonEmptyText(entry["label"] as? String),
                enabled: (entry["enabled"] as? Bool) ?? true,
                order: entry["order"] as? Int
            )
        }
        return AccountSettings(sort: sort, accounts: accounts)
    }

    /// Writes `sort`. For each account in `settings.accounts` it writes `enabled`, and `label` and `order`, where a nil
    /// value removes the key. Any other key in an account's entry, and every other key in the file, stays as it is.
    static func saveAccountSettings(_ settings: AccountSettings, at url: URL) throws {
        var object = readObject(at: url)
        object[sortKey] = settings.sort.rawValue
        var accounts = (object[accountsKey] as? [String: Any]) ?? [:]
        for (id, preference) in settings.accounts {
            var entry = (accounts[id] as? [String: Any]) ?? [:]
            entry["enabled"] = preference.enabled
            if let label = preference.label {
                entry["label"] = label
            } else {
                entry.removeValue(forKey: "label")
            }
            if let order = preference.order {
                entry["order"] = order
            } else {
                entry.removeValue(forKey: "order")
            }
            accounts[id] = entry
        }
        object[accountsKey] = accounts
        try write(object, to: url)
    }

    private static func nonEmptyText(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

// MARK: - Direct mode in settings.json

extension AppSettingsStore {
    static let directModeKey = "direct_mode"

    /// Reads `direct_mode`. A missing file, a missing key or a value that is not a JSON boolean means off. A `claude`
    /// entry is never read, because Claude has no direct mode.
    static func loadDirectMode(from url: URL) -> DirectModeSettings {
        let direct = (readObject(at: url)[directModeKey] as? [String: Any]) ?? [:]
        return DirectModeSettings(
            codex: (direct["codex"] as? Bool) ?? false,
            agy: (direct["agy"] as? Bool) ?? false
        )
    }

    /// Writes both switches as JSON booleans, so the file always has both keys. Any other key inside `direct_mode` and
    /// every other key in the file stay as they are, except a `claude` entry, which is removed: Claude never has direct mode.
    static func saveDirectMode(_ settings: DirectModeSettings, at url: URL) throws {
        var object = readObject(at: url)
        var direct = (object[directModeKey] as? [String: Any]) ?? [:]
        direct.removeValue(forKey: "claude")
        direct["codex"] = settings.codex
        direct["agy"] = settings.agy
        object[directModeKey] = direct
        try write(object, to: url)
    }
}
