import Foundation

/// One account the collector has found on this Mac, from `known-accounts.json` next to usage.json. The collector writes
/// it on every run. It holds display text and dates only: no tokens, no emails.
struct KnownAccount: Equatable, Identifiable {
    /// The stable id, for example `claude-main`, `claude-claude-2`, `codex-main` or `agy-main`.
    let id: String
    /// `claude`, `codex` or `agy`.
    let provider: String
    /// Where the account was found, as display text, for example "Claude Code (~/.claude-2)". Empty when unknown.
    let source: String
    /// When the collector first found the account. Nil when the file has no date.
    let firstSeen: Date?
}

extension KnownAccount: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, provider, source
        case firstSeen = "first_seen"
    }

    /// An entry without an `id` or a `provider` is dropped by `KnownAccounts.decode`, so it throws here.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        provider = try c.decode(String.self, forKey: .provider)
        source = (try? c.decodeIfPresent(String.self, forKey: .source)) ?? ""
        firstSeen = UsageDate.parse(try? c.decodeIfPresent(String.self, forKey: .firstSeen))
    }
}

/// Reads known-accounts.json. The file is `{"schema": 1, "accounts": [...]}`; a bare array is read the same way. A
/// missing or broken file means no known accounts, and one broken entry never hides the others.
enum KnownAccounts {
    /// `~/Library/Application Support/AIUsage/known-accounts.json`, the real home folder's copy.
    static func defaultFileURL(home: URL = UsageLoader.realHomeDirectory()) -> URL {
        home.appendingPathComponent("Library/Application Support/AIUsage/known-accounts.json")
    }

    static func load(from url: URL) -> [KnownAccount] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return decode(data)
    }

    static func decode(_ data: Data) -> [KnownAccount] {
        let decoder = JSONDecoder()
        if let list = try? decoder.decode([Lossy<KnownAccount>].self, from: data) {
            return list.compactMap { $0.value }
        }
        if let file = try? decoder.decode(KnownAccountsFile.self, from: data) {
            return file.accounts.compactMap { $0.value }
        }
        return []
    }
}

private struct KnownAccountsFile: Decodable {
    let accounts: [Lossy<KnownAccount>]
}
