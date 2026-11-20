import Foundation

/// Decodes one array element on its own. A malformed element becomes nil
/// instead of failing the whole document, so one bad account or limit never
/// hides the others (docs/usage-json.md: readers must tolerate bad data).
struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

/// Root of usage.json (schema 1). Unknown fields are ignored. Missing or
/// mistyped fields fall back to defaults.
struct UsageDocument: Equatable, Decodable {
    var schema: Int?
    var generatedAt: Date?
    var accounts: [UsageAccount]
    /// The Claude model prices from `model_prices` (one copy for the file, keyed by model id). Nil in files written
    /// before the field existed, which hides the model mix section.
    var modelPrices: [String: ModelPrice]?

    private enum CodingKeys: String, CodingKey {
        case schema, accounts
        case generatedAt = "generated_at"
        case modelPrices = "model_prices"
    }

    init(schema: Int?, generatedAt: Date?, accounts: [UsageAccount], modelPrices: [String: ModelPrice]? = nil) {
        self.schema = schema
        self.generatedAt = generatedAt
        self.accounts = accounts
        self.modelPrices = modelPrices
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try? c.decodeIfPresent(Int.self, forKey: .schema)
        generatedAt = UsageDate.parse(try? c.decodeIfPresent(String.self, forKey: .generatedAt))
        accounts = (try? c.decodeIfPresent([Lossy<UsageAccount>].self, forKey: .accounts))?
            .compactMap { $0.value } ?? []
        // One entry at a time: an entry in a shape this version does not know drops only itself.
        modelPrices = (try? c.decodeIfPresent([String: Lossy<ModelPrice>].self, forKey: .modelPrices))?
            .compactMapValues { $0.value }
    }
}

struct UsageAccount: Equatable, Decodable {
    /// The stable account id, for example `claude-main` or `claude-claude-2`. Empty when the file has none. It matches
    /// the account in known-accounts.json and in settings.json.
    var id: String
    var provider: String
    var label: String
    var plan: String?
    var status: String
    var error: String?
    /// Language-neutral reason for the error (`login_expired`, `network`, ...). Nil for an ok account, and for
    /// files written before the field existed.
    var errorCode: String?
    var updatedAt: Date?
    var limits: [UsageLimit]
    var usage: UsageSummary?
    var credits: UsageCredits?

    private enum CodingKeys: String, CodingKey {
        case id, provider, label, plan, status, error, limits, usage, credits
        case updatedAt = "updated_at"
        case errorCode = "error_code"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? ""
        provider = (try? c.decodeIfPresent(String.self, forKey: .provider)) ?? ""
        label = (try? c.decodeIfPresent(String.self, forKey: .label)) ?? ""
        plan = try? c.decodeIfPresent(String.self, forKey: .plan)
        status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? ""
        error = try? c.decodeIfPresent(String.self, forKey: .error)
        errorCode = try? c.decodeIfPresent(String.self, forKey: .errorCode)
        updatedAt = UsageDate.parse(try? c.decodeIfPresent(String.self, forKey: .updatedAt))
        limits = (try? c.decodeIfPresent([Lossy<UsageLimit>].self, forKey: .limits))?
            .compactMap { $0.value } ?? []
        usage = try? c.decodeIfPresent(UsageSummary.self, forKey: .usage)
        credits = try? c.decodeIfPresent(UsageCredits.self, forKey: .credits)
    }
}

struct UsageLimit: Equatable, Decodable {
    var key: String
    /// The Thai label that the collector writes. Readers build their own label from `windowSeconds` and `key`.
    var label: String
    /// The window length in seconds (18000 for five hours, 604800 for a week), or nil for a model group.
    var windowSeconds: Int?
    /// Required. A limit without a number is dropped by `Lossy`.
    var usedPercent: Double
    var resetsAt: Date?

    private enum CodingKeys: String, CodingKey {
        case key, label
        case windowSeconds = "window_seconds"
        case usedPercent = "used_percent"
        case resetsAt = "resets_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = (try? c.decodeIfPresent(String.self, forKey: .key)) ?? ""
        label = (try? c.decodeIfPresent(String.self, forKey: .label)) ?? key
        windowSeconds = try? c.decodeIfPresent(Int.self, forKey: .windowSeconds)
        usedPercent = try c.decode(Double.self, forKey: .usedPercent)
        resetsAt = UsageDate.parse(try? c.decodeIfPresent(String.self, forKey: .resetsAt))
    }
}

struct UsageSummary: Equatable, Decodable {
    var today: UsageBucket?
    var month: UsageBucket?
}

struct UsageBucket: Equatable, Decodable {
    var tokens: Double?
    var costUsd: Double?
    /// Claude tokens per model family (`opus`, `sonnet`, `haiku`, `fable`, `other`). Nil in files written before the
    /// field existed, and when a family entry is malformed the field is nil.
    var byFamily: [String: FamilyTokens]?
    /// ChatGPT (Codex) tokens per model id. Nil when the account has none. See `OpenAIModelTokens`.
    var byModel: [String: OpenAIModelTokens]?

    private enum CodingKeys: String, CodingKey {
        case tokens
        case costUsd = "cost_usd"
        case byFamily = "by_family"
        case byModel = "by_model"
    }

    init(tokens: Double?, costUsd: Double?, byFamily: [String: FamilyTokens]? = nil, byModel: [String: OpenAIModelTokens]? = nil) {
        self.tokens = tokens
        self.costUsd = costUsd
        self.byFamily = byFamily
        self.byModel = byModel
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tokens = try c.decodeIfPresent(Double.self, forKey: .tokens)
        costUsd = try c.decodeIfPresent(Double.self, forKey: .costUsd)
        byFamily = try? c.decodeIfPresent([String: FamilyTokens].self, forKey: .byFamily)
        byModel = (try? c.decodeIfPresent([String: Lossy<OpenAIModelTokens>].self, forKey: .byModel))?
            .compactMapValues { $0.value }
    }
}

struct UsageCredits: Equatable, Decodable {
    var extraUsageEnabled: Bool?
    var usedUsd: Double?
    var limitUsd: Double?
    var balanceUsd: Double?

    private enum CodingKeys: String, CodingKey {
        case extraUsageEnabled = "extra_usage_enabled"
        case usedUsd = "used_usd"
        case limitUsd = "limit_usd"
        case balanceUsd = "balance_usd"
    }
}

enum UsageDate {
    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// Accepts ISO-8601 with or without fractional seconds. Anything else is nil.
    static func parse(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        return plain.date(from: text) ?? fractional.date(from: text)
    }
}
