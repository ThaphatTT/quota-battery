import Foundation

/// UserDefaults keys for the switches in the app window. The window writes them with @AppStorage and the
/// scene reads the same keys. The notify switch is also written to settings.json as `notify`, so the collector can read it.
enum AppSettingKey {
    static let showMenuBarIcon = "showMenuBarIcon"
    static let showClaudeHeaderRing = "showClaudeHeaderRing"
    static let showCodexUsageRing = "showCodexUsageRing"
    static let notifyAt80And95 = "notifyAt80And95"
}

/// The notify switch as a key-value observable property. The name is the stored key, so KVO fires when the switch
/// writes it. A missing value means on, as in the switch's @AppStorage.
extension UserDefaults {
    @objc dynamic var showClaudeHeaderRing: Bool {
        bool(forKey: AppSettingKey.showClaudeHeaderRing)
    }

    @objc dynamic var showCodexUsageRing: Bool {
        object(forKey: AppSettingKey.showCodexUsageRing) as? Bool ?? true
    }

    @objc dynamic var notifyAt80And95: Bool {
        object(forKey: AppSettingKey.notifyAt80And95) as? Bool ?? true
    }
}
