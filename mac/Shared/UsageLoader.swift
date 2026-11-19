import Foundation
import os

/// What a reader got from usage.json. Anything other than `.loaded` is shown as "no data".
enum UsageLoadResult: Equatable {
    case loaded(UsageDocument)
    /// The file does not exist yet, for example because the collector has not run.
    case missing
    /// The file exists but could not be read. A sandbox denial shows up here, with its error code.
    case unreadable(code: Int)
    /// The file is not valid usage JSON.
    case broken

    var document: UsageDocument? {
        if case .loaded(let document) = self { return document }
        return nil
    }
}

enum UsageLoader {
    private static let logger = Logger(subsystem: "local.aiusage", category: "usage-loader")

    /// The real home folder. NSHomeDirectory() points inside the app container in a sandboxed
    /// process, so the passwd entry is used instead.
    static func realHomeDirectory() -> URL {
        if let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: directory), isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    /// `~/Library/Application Support/AIUsage/usage.json`, the Mac copy written by the collector.
    static func defaultFileURL() -> URL {
        realHomeDirectory().appendingPathComponent("Library/Application Support/AIUsage/usage.json")
    }

    static func load(from url: URL) -> UsageLoadResult {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            if let cocoa = error as? CocoaError, cocoa.code == .fileReadNoSuchFile || cocoa.code == .fileNoSuchFile {
                return .missing
            }
            let nsError = error as NSError
            logger.error("usage.json read failed: domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)")
            return .unreadable(code: nsError.code)
        }
        return decode(data)
    }

    static func decode(_ data: Data) -> UsageLoadResult {
        do {
            return .loaded(try JSONDecoder().decode(UsageDocument.self, from: data))
        } catch {
            logger.error("usage.json is not valid usage JSON")
            return .broken
        }
    }
}
