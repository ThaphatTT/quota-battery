import Foundation

/// Runs `launchctl kickstart -k` for the collector job. Only the argument list and the exit-status mapping are unit
/// tested, so the tests never start launchctl.
enum RefreshCommand {
    static let executable = URL(fileURLWithPath: "/bin/launchctl")
    static let jobLabel = "com.user.aiusage"

    static func kickstartArguments(uid: uid_t) -> [String] {
        ["kickstart", "-k", "gui/\(uid)/\(jobLabel)"]
    }

    /// nil for exit status 0. Otherwise the failure, whose text the view makes in the chosen language.
    static func failure(forExitStatus status: Int32) -> RefreshFailure? {
        status == 0 ? nil : .exitStatus(status)
    }

    /// Returns nil when launchctl exits with 0. Otherwise returns why it failed.
    static func run(uid: uid_t) async -> RefreshFailure? {
        await Task.detached(priority: .utility) { () -> RefreshFailure? in
            let process = Process()
            process.executableURL = executable
            process.arguments = kickstartArguments(uid: uid)
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                return .launchFailed
            }
            return failure(forExitStatus: process.terminationStatus)
        }.value
    }
}
