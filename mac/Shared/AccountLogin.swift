import Foundation

/// The login for a second account. The app only types a command into Terminal. The sign-in happens in Terminal, so the
/// app never sees a password. Claude and Codex each get their own folder; agy has one account only (its own limit).
enum AccountLogin {
    /// The providers that can get another account from the app.
    static let addableProviders = ["claude", "codex"]

    /// The folder name in the home folder, for example `.claude-2` or `.codex-2`. Nil for a provider that cannot add one.
    static func folderName(provider: String, number: Int) -> String? {
        switch provider {
        case "claude": return ".claude-\(number)"
        case "codex": return ".codex-\(number)"
        default: return nil
        }
    }

    /// The first free number, starting at 2: the first `.claude-N` (or `.codex-N`) folder that `isTaken` says is not
    /// there. Nil when no provider folder can be used, or after 99 numbers.
    static func firstFreeNumber(provider: String, isTaken: (String) -> Bool) -> Int? {
        for number in 2...99 {
            guard let name = folderName(provider: provider, number: number) else { return nil }
            if !isTaken(name) {
                return number
            }
        }
        return nil
    }

    /// The command typed into Terminal, with the folder written as `~/`, for example
    /// `CLAUDE_CONFIG_DIR=~/.claude-2 claude` or `CODEX_HOME=~/.codex-2 codex login`. Nil for agy.
    static func command(provider: String, number: Int) -> String? {
        guard let name = folderName(provider: provider, number: number) else { return nil }
        switch provider {
        case "claude": return "CLAUDE_CONFIG_DIR=~/\(name) claude"
        case "codex": return "CODEX_HOME=~/\(name) codex login"
        default: return nil
        }
    }

    /// The AppleScript that opens a new Terminal window and types `command` into it.
    static func terminalScript(for command: String) -> String {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return """
        tell application "Terminal"
        activate
        do script "\(escaped)"
        end tell
        """
    }

    /// The arguments for `/usr/bin/osascript`: one `-e` per line of the script.
    static func osascriptArguments(for command: String) -> [String] {
        terminalScript(for: command)
            .components(separatedBy: "\n")
            .flatMap { ["-e", $0] }
    }
}
