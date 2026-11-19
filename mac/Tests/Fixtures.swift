import Foundation

enum FixtureError: Error {
    case sampleNotLoaded
    case jsonNotLoaded
}

/// Test helpers. Tests read only the sample file, or JSON given inline. They never touch the real home folder.
enum Fixtures {
    /// The mac/ folder, found from this file's path.
    static var macFolder: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // mac
    }

    /// mac/Shared/Sample/usage.sample.json, the contract example.
    static var sampleURL: URL {
        macFolder.appendingPathComponent("Shared/Sample/usage.sample.json")
    }

    /// The fixed "now" used everywhere in the tests (the sample's generated_at).
    static let now: Date = {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: "2026-11-19T04:30:00Z")!
    }()

    static func sample() throws -> UsageDocument {
        guard case .loaded(let document) = UsageLoader.load(from: sampleURL) else {
            throw FixtureError.sampleNotLoaded
        }
        return document
    }

    static func document(_ json: String) throws -> UsageDocument {
        guard case .loaded(let document) = UsageLoader.decode(Data(json.utf8)) else {
            throw FixtureError.jsonNotLoaded
        }
        return document
    }
}
