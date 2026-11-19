import Foundation

/// Opens a new Terminal window and types one command into it, with `/usr/bin/osascript`. Terminal runs the command, so
/// the app never sees what the user types there. Only the argument list and the exit status are used here. Tests use
/// `AccountLogin.osascriptArguments` and never start osascript.
enum TerminalLauncher {
    static let executable = URL(fileURLWithPath: "/usr/bin/osascript")

    /// True when osascript exits with 0. False when it cannot start, or when the user has not allowed AIUsage to
    /// control Terminal (the system asks the first time).
    static func open(command: String) async -> Bool {
        await Task.detached(priority: .utility) { () -> Bool in
            let process = Process()
            process.executableURL = executable
            process.arguments = AccountLogin.osascriptArguments(for: command)
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                return false
            }
            return process.terminationStatus == 0
        }.value
    }
}
