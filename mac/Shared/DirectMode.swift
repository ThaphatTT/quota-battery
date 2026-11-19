import Foundation

/// Direct mode: the app reads the CLI's own login on this Mac and asks the provider for the usage itself. Only ChatGPT
/// (`codex`) and agy can have it. Claude never does, so every rule that offers, switches or saves it starts from here.
enum DirectMode {
    /// The only providers that can have direct mode. Claude is not one of them.
    static let providers = ["codex", "agy"]

    static func isAvailable(_ provider: String) -> Bool {
        providers.contains(provider)
    }
}

/// The direct mode switches, as settings.json holds them under `direct_mode`: `{"codex": true|false, "agy": true|false}`.
/// A missing key, or a value that is not a JSON boolean, means off. The switch is per provider, so every ChatGPT account
/// shares it.
struct DirectModeSettings: Equatable {
    var codex = false
    var agy = false

    static let off = DirectModeSettings()

    func isOn(_ provider: String) -> Bool {
        switch provider {
        case "codex": return codex
        case "agy": return agy
        default: return false
        }
    }

    /// The settings with one provider switched. Nil for a provider that cannot have direct mode, such as Claude, so
    /// nothing changes for it.
    func setting(_ provider: String, to enabled: Bool) -> DirectModeSettings? {
        guard DirectMode.isAvailable(provider) else { return nil }
        var result = self
        switch provider {
        case "codex": result.codex = enabled
        case "agy": result.agy = enabled
        default: return nil
        }
        return result
    }
}

/// The consent screen's state, without SwiftUI. The box starts unticked. "Turn on" is enabled only when the box is ticked
/// and the provider can have direct mode, and `confirm()` gives the provider only then. The view reads `canTurnOn` for
/// the button and calls `confirm()` for its action, so the two cannot disagree.
struct DirectModeConsent: Equatable {
    let provider: String
    var consented = false

    init(provider: String) {
        self.provider = provider
    }

    var canTurnOn: Bool {
        consented && DirectMode.isAvailable(provider)
    }

    /// The provider to switch on, or nil while the button is disabled.
    func confirm() -> String? {
        canTurnOn ? provider : nil
    }
}
