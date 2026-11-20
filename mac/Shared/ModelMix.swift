import Foundation

// The model mix: how much of an account's traffic each model would take, and what it would cost at API list prices.
// Pure rules only. No SwiftUI here, so the tests can check every number. The real mix comes from the logs: Claude
// accounts use their own `by_family`, ChatGPT (Codex) accounts use their own `by_model`. The user can move the sliders
// to try a what-if, per account. Subscription plans do not pay these amounts.

// MARK: - Prices and token counts in usage.json

/// Rates per 1M tokens: the standard rates of a model, or its long-context rates.
struct PriceRates: Equatable, Decodable {
    var input: Double
    var cacheWrite5m: Double
    var cacheWrite1h: Double
    var cacheRead: Double
    var output: Double

    init(input: Double, cacheWrite5m: Double, cacheWrite1h: Double, cacheRead: Double, output: Double) {
        self.input = input
        self.cacheWrite5m = cacheWrite5m
        self.cacheWrite1h = cacheWrite1h
        self.cacheRead = cacheRead
        self.output = output
    }

    /// The keys the collector writes. Claude prices use `cache_write_5m`, `cache_write_1h` and `cache_read`. ChatGPT prices
    /// use `cache_write` (the 30-minute rate) and `cached_input` (the cached-input rate). Both spellings are read. A
    /// missing or mistyped rate counts as 0.
    private enum CodingKeys: String, CodingKey {
        case input, output
        case cacheWrite5m = "cache_write_5m"
        case cacheWrite = "cache_write"
        case cacheWrite1h = "cache_write_1h"
        case cacheRead = "cache_read"
        case cachedInput = "cached_input"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        input = (try? c.decodeIfPresent(Double.self, forKey: .input)) ?? 0
        output = (try? c.decodeIfPresent(Double.self, forKey: .output)) ?? 0
        cacheWrite5m = Self.rate(c, .cacheWrite5m, or: .cacheWrite)
        cacheWrite1h = (try? c.decodeIfPresent(Double.self, forKey: .cacheWrite1h)) ?? 0
        cacheRead = Self.rate(c, .cachedInput, or: .cacheRead)
    }

    /// The first of two keys that holds a number, else 0.
    private static func rate(_ c: KeyedDecodingContainer<CodingKeys>, _ first: CodingKeys, or second: CodingKeys) -> Double {
        if let value = try? c.decodeIfPresent(Double.self, forKey: first) { return value }
        return (try? c.decodeIfPresent(Double.self, forKey: second)) ?? 0
    }


}

/// One model's list prices, per 1M tokens, from usage.json `model_prices`.
struct ModelPrice: Equatable, Decodable {
    /// The family the model belongs to: `opus`, `sonnet`, `haiku` or `fable` for Claude. Empty when the file has none.
    var family: String
    /// The name shown in the app, for example `Opus 5.5`.
    var label: String
    /// `openai` for ChatGPT models. Nil for Claude, because older files have no provider field.
    var provider: String?
    var input: Double
    var cacheWrite5m: Double
    var cacheWrite1h: Double
    var cacheRead: Double
    var output: Double
    /// The rates for requests above the long-context limit (272K input tokens). Nil when the model has none.
    var longContext: PriceRates?

    init(
        family: String, label: String, input: Double, cacheWrite5m: Double, cacheWrite1h: Double, cacheRead: Double,
        output: Double, provider: String? = nil, longContext: PriceRates? = nil
    ) {
        self.family = family
        self.label = label
        self.provider = provider
        self.input = input
        self.cacheWrite5m = cacheWrite5m
        self.cacheWrite1h = cacheWrite1h
        self.cacheRead = cacheRead
        self.output = output
        self.longContext = longContext
    }

    private enum CodingKeys: String, CodingKey {
        case family, label, provider
        case longContext = "long_context"
    }

    /// The providers the collector writes. Claude is `anthropic` in the file (and `claude` in some older writers). ChatGPT
    /// is `openai`. A missing provider is Claude, as in the files written before the field existed.
    static let claudeProviders: Set<String> = ["anthropic", "claude"]
    static let openAIProvider = "openai"

    /// Decodes tolerantly: a missing name or rate never fails the entry. `model_prices` decodes one entry at a time, so one
    /// odd entry cannot hide the others (see `UsageDocument`).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        family = (try? c.decodeIfPresent(String.self, forKey: .family)) ?? ""
        label = (try? c.decodeIfPresent(String.self, forKey: .label)) ?? ""
        provider = try? c.decodeIfPresent(String.self, forKey: .provider)
        let rates = try PriceRates(from: decoder)
        input = rates.input
        cacheWrite5m = rates.cacheWrite5m
        cacheWrite1h = rates.cacheWrite1h
        cacheRead = rates.cacheRead
        output = rates.output
        longContext = Self.longRates(c, standardCacheWrite: cacheWrite5m)
    }

    /// The long-context block, read leniently. Its cache write rate is always the standard one, whatever the block says:
    /// the long-context table has no cache write rate (docs/usage-json.md), so `cache_write` tokens are priced at the
    /// normal `cache_write` rate in long context too.
    private static func longRates(_ c: KeyedDecodingContainer<CodingKeys>, standardCacheWrite: Double) -> PriceRates? {
        guard let block = try? c.decodeIfPresent(LongBlock.self, forKey: .longContext) else { return nil }
        return PriceRates(
            input: block.input ?? 0,
            cacheWrite5m: standardCacheWrite,
            cacheWrite1h: 0,
            cacheRead: block.cachedInput ?? block.cacheRead ?? 0,
            output: block.output ?? 0
        )
    }

    /// The rates of a long-context block. Each is optional, so a missing one takes its default. A cache write key is not
    /// read here (see `longRates`).
    private struct LongBlock: Decodable {
        let input: Double?
        let output: Double?
        let cachedInput: Double?
        let cacheRead: Double?

        private enum CodingKeys: String, CodingKey {
            case input, output
            case cachedInput = "cached_input"
            case cacheRead = "cache_read"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            input = try? c.decodeIfPresent(Double.self, forKey: .input)
            output = try? c.decodeIfPresent(Double.self, forKey: .output)
            cachedInput = try? c.decodeIfPresent(Double.self, forKey: .cachedInput)
            cacheRead = try? c.decodeIfPresent(Double.self, forKey: .cacheRead)
        }
    }

    /// The standard rates as a `PriceRates`.
    var standard: PriceRates {
        PriceRates(input: input, cacheWrite5m: cacheWrite5m, cacheWrite1h: cacheWrite1h, cacheRead: cacheRead, output: output)
    }

    /// True for Claude models: a missing provider or one of the Claude providers.
    var isClaude: Bool { provider == nil || ModelPrice.claudeProviders.contains(provider ?? "") }
}

/// Tokens of one family (or of all families together) in one kind each. A missing or mistyped number counts as 0.
struct FamilyTokens: Equatable, Decodable {
    var input: Double
    var output: Double
    var cacheWrite5m: Double
    var cacheWrite1h: Double
    var cacheRead: Double

    static let zero = FamilyTokens(input: 0, output: 0, cacheWrite5m: 0, cacheWrite1h: 0, cacheRead: 0)

    init(input: Double, output: Double, cacheWrite5m: Double, cacheWrite1h: Double, cacheRead: Double) {
        self.input = input
        self.output = output
        self.cacheWrite5m = cacheWrite5m
        self.cacheWrite1h = cacheWrite1h
        self.cacheRead = cacheRead
    }

    private enum CodingKeys: String, CodingKey {
        case input, output
        case cacheWrite5m = "cache_write_5m"
        case cacheWrite1h = "cache_write_1h"
        case cacheRead = "cache_read"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        input = (try? c.decodeIfPresent(Double.self, forKey: .input)) ?? 0
        output = (try? c.decodeIfPresent(Double.self, forKey: .output)) ?? 0
        cacheWrite5m = (try? c.decodeIfPresent(Double.self, forKey: .cacheWrite5m)) ?? 0
        cacheWrite1h = (try? c.decodeIfPresent(Double.self, forKey: .cacheWrite1h)) ?? 0
        cacheRead = (try? c.decodeIfPresent(Double.self, forKey: .cacheRead)) ?? 0
    }

    /// Adds two counts kind by kind.
    func adding(_ other: FamilyTokens) -> FamilyTokens {
        FamilyTokens(
            input: input + other.input,
            output: output + other.output,
            cacheWrite5m: cacheWrite5m + other.cacheWrite5m,
            cacheWrite1h: cacheWrite1h + other.cacheWrite1h,
            cacheRead: cacheRead + other.cacheRead
        )
    }

    /// Takes `other` away kind by kind. A kind never goes below 0, so a `long_context` block larger than its total
    /// (a broken file) cannot make a negative count.
    func subtracting(_ other: FamilyTokens) -> FamilyTokens {
        FamilyTokens(
            input: max(input - other.input, 0),
            output: max(output - other.output, 0),
            cacheWrite5m: max(cacheWrite5m - other.cacheWrite5m, 0),
            cacheWrite1h: max(cacheWrite1h - other.cacheWrite1h, 0),
            cacheRead: max(cacheRead - other.cacheRead, 0)
        )
    }

    /// The tokens that make up the share: input, output and both cache writes. Cache reads are left out, as the
    /// existing token count leaves them out.
    var shareTokens: Double {
        input + output + cacheWrite5m + cacheWrite1h
    }
}

/// The ChatGPT (Codex) tokens of one model in one period, from a bucket's `by_model`. `total` is every request of the
/// model: `input` (uncached input), `cached_input`, `cache_write` and `output` (reasoning already included, so it is not
/// counted twice). `long` is the part of `total` from requests above 272K input tokens, written under `long_context`. It
/// is a subset of `total`, not an extra count, so `short` (the traffic up to 272K) is `total` minus `long`.
struct OpenAIModelTokens: Equatable, Decodable {
    var total: FamilyTokens
    var long: FamilyTokens

    /// The traffic of requests up to 272K input tokens, priced at the standard rates.
    var short: FamilyTokens { total.subtracting(long) }

    /// The four counts of one traffic group.
    private struct Kinds: Decodable {
        let input: Double
        let output: Double
        let cachedInput: Double
        let cacheWrite: Double

        private enum CodingKeys: String, CodingKey {
            case input, output
            case cachedInput = "cached_input"
            case cacheWrite = "cache_write"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            input = (try? c.decodeIfPresent(Double.self, forKey: .input)) ?? 0
            output = (try? c.decodeIfPresent(Double.self, forKey: .output)) ?? 0
            cachedInput = (try? c.decodeIfPresent(Double.self, forKey: .cachedInput)) ?? 0
            cacheWrite = (try? c.decodeIfPresent(Double.self, forKey: .cacheWrite)) ?? 0
        }

        /// The counts in the same slots the Claude rows use: cache writes take the 5-minute slot, cached input the read slot.
        var tokens: FamilyTokens {
            FamilyTokens(input: input, output: output, cacheWrite5m: cacheWrite, cacheWrite1h: 0, cacheRead: cachedInput)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case longContext = "long_context"
    }

    init(total: FamilyTokens, long: FamilyTokens) {
        self.total = total
        self.long = long
    }

    /// A missing or broken `long_context` means no long-context traffic: everything is priced at the standard rates.
    init(from decoder: Decoder) throws {
        total = try Kinds(from: decoder).tokens
        let c = try decoder.container(keyedBy: CodingKeys.self)
        long = (try? c.decodeIfPresent(Kinds.self, forKey: .longContext))?.tokens ?? .zero
    }

    /// Every token of the model in the period, in the share (`total` already holds the long part).
    var shareTokens: Double {
        total.shareTokens
    }
}

// MARK: - Settings

/// One account's entry in settings.json `model_mix`: `{"order": [model ids], "percent": {model id: whole %} | null}`.
/// `percent` nil means the real mix from the logs. An empty `order` means the default order for that account.
struct ModelMixSettings: Equatable {
    /// The drag order of the model ids. Unknown ids are ignored, and models missing from it come last, sorted by id.
    var order: [String] = []
    /// The what-if percentages by model id. Nil means the real mix.
    var percent: [String: Int]?

    static let standard = ModelMixSettings()
}

extension AppSettingsStore {
    static let modelMixKey = "model_mix"
    /// The account that an old single `model_mix` value (before the mix was per account) belongs to.
    static let legacyModelMixAccount = "claude-main"

    /// Reads `model_mix` as one entry per account id. A missing file or key, or a broken value, gives no entries, which
    /// means the default order and the real mix. An entry that holds only defaults is left out.
    ///
    /// The old shape (one `order` and `percent` at the top of `model_mix`) is read as the entry of `claude-main`, in memory
    /// only. Nothing is written until the user changes a mix, so reading never changes the file.
    static func loadModelMix(from url: URL) -> [String: ModelMixSettings] {
        modelMixEntries(object: readObject(at: url))
    }

    /// The entries of a settings object, with the old single value migrated. Entries that equal the defaults are left out.
    static func modelMixEntries(object: [String: Any]) -> [String: ModelMixSettings] {
        guard let raw = object[modelMixKey] as? [String: Any] else { return [:] }
        var entries: [String: ModelMixSettings] = [:]
        if raw["order"] != nil || raw["percent"] != nil {
            entries[legacyModelMixAccount] = parseModelMix(raw)
        } else {
            for (id, value) in raw {
                if let entry = value as? [String: Any] {
                    entries[id] = parseModelMix(entry)
                }
            }
        }
        return entries.filter { $0.value != .standard }
    }

    /// Saves one account's entry. The other accounts' entries stay as they are, and so does every other key in the file.
    /// A legacy value is written in the new shape, as `claude-main`, the first time any account is saved.
    static func saveModelMix(_ settings: ModelMixSettings, accountID: String, at url: URL) throws {
        var entries = modelMixEntries(object: readObject(at: url))
        entries[accountID] = settings
        var raw: [String: Any] = [:]
        for (id, entry) in entries {
            let percentValue: Any = entry.percent.map { $0.mapValues { $0 as Any } as Any } ?? NSNull()
            raw[id] = ["order": entry.order, "percent": percentValue]
        }
        try update(modelMixKey, to: raw, at: url)
    }

    private static func parseModelMix(_ entry: [String: Any]) -> ModelMixSettings {
        let order = (entry["order"] as? [Any])?.compactMap { $0 as? String } ?? []
        var percent: [String: Int]?
        if let raw = entry["percent"] as? [String: Any] {
            var values: [String: Int] = [:]
            for (id, value) in raw {
                if let number = value as? NSNumber, number.doubleValue == number.doubleValue.rounded() {
                    values[id] = number.intValue
                }
            }
            percent = values
        }
        return ModelMixSettings(order: order, percent: percent)
    }
}

// MARK: - Maths

/// The rounding and rescaling rules. Every result is a whole number of percent, never negative, and sums to the total.
enum ModelMixMath {
    /// Largest-remainder rounding: each value is scaled to `total`, rounded down, then the leftover units go to the
    /// largest fractions. A tie goes to the earlier position. When the values sum to 0 or less, every result is 0.
    static func largestRemainder(_ values: [Double], total: Int) -> [Int] {
        let clean = values.map { $0.isFinite && $0 > 0 ? $0 : 0 }
        let sum = clean.reduce(0, +)
        guard sum > 0, total > 0, !clean.isEmpty else {
            return Array(repeating: 0, count: clean.count)
        }
        let scaled = clean.map { $0 / sum * Double(total) }
        var result = scaled.map { Int($0.rounded(.down)) }
        let missing = min(max(total - result.reduce(0, +), 0), clean.count)
        let byFraction = scaled.indices.sorted { a, b in
            let fa = scaled[a] - Double(result[a])
            let fb = scaled[b] - Double(result[b])
            if fa != fb { return fa > fb }
            return a < b
        }
        for index in byFraction.prefix(missing) {
            result[index] += 1
        }
        return result
    }

    /// The cents shown for each row and for the total. The total is the exact sum rounded to the cent. Each row starts at
    /// its own cents, rounded down, then the missing cents go to the rows with the largest fractions (a tie goes to the
    /// earlier row). A row at 0 never gets a cent, so the shown rows always add up to the shown total.
    static func centsSplit(_ costs: [Double]) -> (rows: [Int], total: Int) {
        // Snapped to a millionth of a cent, so floating-point noise cannot decide a tie.
        func snap(_ value: Double) -> Double { (value * 1_000_000).rounded() / 1_000_000 }
        let clean = costs.map { $0.isFinite && $0 > 0 ? $0 : 0 }
        let total = Int(snap(clean.reduce(0, +) * 100).rounded())
        let exact = clean.map { snap($0 * 100) }
        var result = exact.map { Int($0.rounded(.down)) }
        let missing = min(max(total - result.reduce(0, +), 0), clean.count)
        let candidates = clean.indices.filter { clean[$0] > 0 }
        let byFraction = candidates.sorted { a, b in
            let fa = snap(exact[a] - Double(result[a]))
            let fb = snap(exact[b] - Double(result[b]))
            if fa != fb { return fa > fb }
            return a < b
        }
        for index in byFraction.prefix(missing) {
            result[index] += 1
        }
        return (result, total)
    }

    /// The real share of each row, in whole percent, summing to 100. Nil when no row has any tokens.
    static func realShares(_ tokens: [Double]) -> [Int]? {
        guard tokens.reduce(0, +) > 0 else { return nil }
        return largestRemainder(tokens, total: 100)
    }

    /// Moves one slider to `value` (clamped to 0...100). The other rows share the rest in proportion to what they had.
    /// When they had nothing, they share it evenly. The result sums to 100 and has no negative value.
    static func rescale(_ percents: [Int], index: Int, to value: Int) -> [Int] {
        guard percents.indices.contains(index) else { return percents }
        let kept = min(max(value, 0), 100)
        let others = percents.indices.filter { $0 != index }
        var result = Array(repeating: 0, count: percents.count)
        result[index] = kept
        guard !others.isEmpty else {
            result[index] = 100
            return result
        }
        let remaining = 100 - kept
        let current = others.map { Double(max(percents[$0], 0)) }
        let weights = current.reduce(0, +) > 0 ? current : others.map { _ in 1.0 }
        let shares = largestRemainder(weights, total: remaining)
        for (position, rowIndex) in others.enumerated() {
            result[rowIndex] = shares[position]
        }
        return result
    }

    /// Makes a stored set of percentages sum to 100. Values that already do are kept. Otherwise they are scaled. Nil
    /// when nothing is left to scale.
    static func normalized(_ values: [Int]) -> [Int]? {
        let clean = values.map { max($0, 0) }
        let sum = clean.reduce(0, +)
        if sum == 100 { return clean }
        guard sum > 0 else { return nil }
        return largestRemainder(clean.map(Double.init), total: 100)
    }

    /// The cost in USD of `percent` of the tokens, at one model's prices. `totals` are the tokens at the standard rates,
    /// and `longTotals` (ChatGPT only) the tokens above the long-context limit, priced at the model's long-context rates
    /// when it has them, and at the standard rates when it has none.
    static func cost(percent: Int, price: ModelPrice, totals: FamilyTokens, longTotals: FamilyTokens? = nil) -> Double {
        var perMillion = perKind(totals, price.standard)
        if let longTotals {
            perMillion += perKind(longTotals, price.longContext ?? price.standard)
        }
        return Double(percent) / 100 * perMillion / 1_000_000
    }

    /// The cost of the tokens at one set of rates, in dollars per 1M tokens of each kind.
    private static func perKind(_ tokens: FamilyTokens, _ rates: PriceRates) -> Double {
        tokens.input * rates.input
            + tokens.output * rates.output
            + tokens.cacheWrite5m * rates.cacheWrite5m
            + tokens.cacheWrite1h * rates.cacheWrite1h
            + tokens.cacheRead * rates.cacheRead
    }
}

// MARK: - The panel the views draw

/// One model row: its share in whole percent, and its estimated monthly cost at that share.
struct ModelMixRow: Equatable, Identifiable {
    /// The model id, for example `claude-opus-5-5`.
    let id: String
    let label: String
    let family: String
    let inputPrice: Double
    let outputPrice: Double
    let percent: Int
    /// The exact cost in USD, kept for anything that is not shown as money.
    let cost: Double
    /// The cost as shown, in cents. The rows' cents add up to the panel's `totalCents`.
    let cents: Int
}

/// What the Model mix tab shows for one account. Nil when the data is missing.
struct ModelMixPanel: Equatable {
    /// The rows in the chosen order. The first row is the main model.
    let rows: [ModelMixRow]
    /// True when the shown mix is the real one from the logs. False when the user moved a slider (a trial).
    let isActual: Bool
    /// The exact sum of the row costs.
    let totalCost: Double
    /// The total as shown, in cents: `totalCost` rounded to the cent. Equal to the sum of the rows' `cents`.
    let totalCents: Int
    /// What is needed to price other shares without the logs. Nil for a panel built by hand.
    var basis: ModelMixBasis? = nil

    var mainModelLabel: String? { rows.first?.label }
    var percents: [Int] { rows.map(\.percent) }

    /// The same models priced at other shares. Nil when there is no basis or the count does not match.
    func previewing(percents: [Int]) -> ModelMixPanel? {
        guard let basis, percents.count == rows.count else { return nil }
        return basis.panel(percents: percents)
    }
}

/// The part of the panel that does not change while a slider moves: the models in order with their prices, the
/// period's totals and the real shares. Built once from the account's bucket and the model order.
struct ModelMixBasis: Equatable {
    struct Model: Equatable {
        let id: String
        let price: ModelPrice
    }

    let models: [Model]
    /// The tokens at the standard rates. For ChatGPT, the short-context traffic.
    let totals: FamilyTokens
    /// The tokens above the long-context limit (ChatGPT only). Nil when there are none.
    let longTotals: FamilyTokens?
    let realPercents: [Int]

    /// The panel for these shares. Costs are the period's tokens at each model's prices. The panel is a trial when the
    /// shares differ from the real ones.
    func panel(percents: [Int]) -> ModelMixPanel {
        let priced = models.enumerated().map { position, model in
            (model: model, percent: percents[position], cost: ModelMixMath.cost(
                percent: percents[position], price: model.price, totals: totals, longTotals: longTotals
            ))
        }
        let split = ModelMixMath.centsSplit(priced.map(\.cost))
        let rows = priced.enumerated().map { position, item in
            ModelMixRow(
                id: item.model.id,
                label: item.model.price.label,
                family: item.model.price.family,
                inputPrice: item.model.price.input,
                outputPrice: item.model.price.output,
                percent: item.percent,
                cost: item.cost,
                cents: split.rows[position]
            )
        }
        return ModelMixPanel(
            rows: rows,
            isActual: percents == realPercents,
            totalCost: priced.reduce(0) { $0 + $1.cost },
            totalCents: split.total,
            basis: self
        )
    }
}

/// One slider drag. Each move recomputes only this panel, so a drag of any length does no saving and changes no
/// other state. The view saves `savedPercent` once, when the drag ends.
struct ModelMixDrag: Equatable {
    /// The panel as the drag leaves it. The view shows this one.
    private(set) var panel: ModelMixPanel
    private let start: [Int]

    init(panel: ModelMixPanel) {
        self.panel = panel
        start = panel.percents
    }

    /// Moves row `index` to `value`; the other rows follow. Returns false when the move cannot be shown.
    @discardableResult
    mutating func move(row index: Int, to value: Int) -> Bool {
        let percents = ModelMixMath.rescale(panel.percents, index: index, to: value)
        guard let next = panel.previewing(percents: percents) else { return false }
        panel = next
        return true
    }

    /// The shares to save, by model id, at the end of the drag. Nil when the drag left them where they started.
    var savedPercent: [String: Int]? {
        guard panel.percents != start else { return nil }
        return Dictionary(uniqueKeysWithValues: zip(panel.rows.map(\.id), panel.percents))
    }
}

/// One account's mix, as the card shows it: the month's basis and panel for the shown shares, and today's basis over
/// the same models (for the Today tile). Nil when the account has no mix data.
struct AccountModelMix: Equatable {
    let accountID: String
    /// `claude` or `codex`. Decides the colours and the source of the rows.
    let provider: String
    /// The month's basis. Its models are the rows, in order.
    let month: ModelMixBasis
    /// The month's panel for the shown shares: the real shares, or the what-if the user chose.
    let shown: ModelMixPanel
    /// Today's basis over the same models. Nil when today has no tokens.
    let today: ModelMixBasis?

    /// True when the shown shares differ from the real ones: the tiles then show a trial value.
    var isTrial: Bool { !shown.isActual }
}

// MARK: - Building the panels

/// Builds the mix for each account from usage.json and that account's settings. Rules:
/// - Claude: the account's own month `by_family`. Only the four model families take part in the share. The cost totals
///   include every family, `other` too. A family belongs to one model id: a second model of the same family gets 0 tokens.
/// - ChatGPT (Codex): the account's own `by_model`, for the models with `provider` `openai` and tokens this month. Rows
///   are ordered by tokens, most first, unless the user has moved them. Long-context tokens use the long-context rates.
/// - A period with no tokens gives no basis. An account with no basis has no Model mix tab.
enum ModelMix {
    /// The default drag order for Claude: Opus 5.5, Sonnet 5.5, Haiku 5.5, Fable 5.2.
    static let defaultOrder = ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5", "claude-fable-5-2"]
    static let shareFamilies = ["opus", "sonnet", "haiku", "fable"]

    /// The mix of one account. Nil for a provider that has no mix, or when the data is missing.
    static func accountMix(for account: UsageAccount, prices: [String: ModelPrice], settings: ModelMixSettings) -> AccountModelMix? {
        guard let month = account.usage?.month else { return nil }
        let ids: [String]
        let kind: Kind
        switch account.provider {
        case "claude":
            kind = .claude
            let claudeIDs = prices.filter { $0.value.isClaude }.map(\.key)
            ids = orderedIDs(claudeIDs, order: settings.order.isEmpty ? defaultOrder : settings.order)
        case "codex":
            kind = .openai
            let byModel = month.byModel ?? [:]
            let present = byModel.filter { id, tokens in
                prices[id]?.provider == ModelPrice.openAIProvider && tokens.shareTokens > 0
            }
            let byTokens = present.keys.sorted { a, b in
                let ta = present[a]?.shareTokens ?? 0
                let tb = present[b]?.shareTokens ?? 0
                return ta != tb ? ta > tb : a < b
            }
            ids = orderedIDs(byTokens, order: settings.order.isEmpty ? byTokens : settings.order)
        default:
            return nil
        }
        guard !ids.isEmpty, let monthBasis = basis(for: month, kind: kind, ids: ids, prices: prices) else { return nil }
        let todayBasis = account.usage?.today.flatMap { basis(for: $0, kind: kind, ids: ids, prices: prices) }
        var shown = monthBasis.realPercents
        if let stored = settings.percent, let normalized = ModelMixMath.normalized(ids.map { stored[$0] ?? 0 }) {
            shown = normalized
        }
        return AccountModelMix(
            accountID: account.id,
            provider: account.provider,
            month: monthBasis,
            shown: monthBasis.panel(percents: shown),
            today: todayBasis
        )
    }

    /// The kinds of usage that feed the share.
    enum Kind: Equatable {
        case claude
        case openai
    }

    /// The basis of one period for the given model ids, in order. Nil when the period has no tokens to share.
    static func basis(for bucket: UsageBucket, kind: Kind, ids: [String], prices: [String: ModelPrice]) -> ModelMixBasis? {
        let models = ids.compactMap { id -> ModelMixBasis.Model? in
            guard let price = prices[id] else { return nil }
            return ModelMixBasis.Model(id: id, price: price)
        }
        switch kind {
        case .claude:
            let families = bucket.byFamily ?? [:]
            let totals = families.values.reduce(FamilyTokens.zero) { $0.adding($1) }
            var seenFamilies = Set<String>()
            let realTokens: [Double] = models.map { model in
                let family = model.price.family
                guard shareFamilies.contains(family), !seenFamilies.contains(family) else { return 0 }
                seenFamilies.insert(family)
                return families[family]?.shareTokens ?? 0
            }
            guard let real = ModelMixMath.realShares(realTokens) else { return nil }
            return ModelMixBasis(models: models, totals: totals, longTotals: nil, realPercents: real)
        case .openai:
            let byModel = bucket.byModel ?? [:]
            let real = ModelMixMath.realShares(ids.map { byModel[$0]?.shareTokens ?? 0 })
            guard let real else { return nil }
            let short = ids.reduce(FamilyTokens.zero) { $0.adding(byModel[$1]?.short ?? .zero) }
            let long = ids.reduce(FamilyTokens.zero) { $0.adding(byModel[$1]?.long ?? .zero) }
            // Without any `long_context` the long part is zero and every token is priced at the standard rates.
            let hasLong = long.shareTokens > 0
            return ModelMixBasis(models: models, totals: short, longTotals: hasLong ? long : nil, realPercents: real)
        }
    }

    /// The model ids in display order: the ids the order names first, in that order, then the other ids sorted by id.
    static func orderedIDs(_ ids: [String], order: [String]) -> [String] {
        var result: [String] = []
        for id in order where ids.contains(id) && !result.contains(id) {
            result.append(id)
        }
        for id in ids.sorted() where !result.contains(id) {
            result.append(id)
        }
        return result
    }
}
