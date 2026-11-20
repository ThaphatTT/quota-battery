import Foundation

/// Model mix test data, given inline. The numbers are chosen so the expected results can be worked out by hand (see
/// ModelMixTests). Nothing here reads a real file.
enum ModelMixFixtures {
    /// Two Claude accounts with the month's `by_family` each, one codex account with no `by_model` (so it has no mix), and
    /// `model_prices`. Each Claude account has its own mix.
    ///
    /// claude-main, month, the four families plus `other`:
    /// - input: opus 1.0M, sonnet 0.5M, haiku 2.0M, other 0.1M
    /// - output: opus 0.1M, sonnet 0.05M
    /// - cache write 5m: opus 0.2M. cache write 1h: sonnet 0.1M. cache read: opus 2.0M, sonnet 1.0M
    /// claude-claude-2, month: sonnet input 1.0M only, so its mix is Sonnet 100%.
    /// claude-main, today: opus input 50K and haiku input 50K, so today's real shares are Opus 50, Haiku 50.
    static let json = """
    {
      "schema": 1,
      "generated_at": "2026-11-19T04:30:00Z",
      "model_prices": {
        "claude-opus-5-5": {"family": "opus", "label": "Opus 5.5", "input": 4.0, "cache_write_5m": 5.0,
                            "cache_write_1h": 8.0, "cache_read": 0.2, "output": 20.0},
        "claude-sonnet-5-5": {"family": "sonnet", "label": "Sonnet 5.5", "input": 2.0, "cache_write_5m": 2.5,
                              "cache_write_1h": 4.0, "cache_read": 0.1, "output": 10.0},
        "claude-haiku-5-5": {"family": "haiku", "label": "Haiku 5.5", "input": 0.1, "cache_write_5m": 0.125,
                             "cache_write_1h": 0.2, "cache_read": 0.01, "output": 0.5},
        "claude-fable-5-2": {"family": "fable", "label": "Fable 5.2", "input": 8.0, "cache_write_5m": 10.0,
                             "cache_write_1h": 16.0, "cache_read": 0.2, "output": 40.0}
      },
      "accounts": [
        {"id": "claude-main", "provider": "claude", "label": "Claude", "plan": "Max", "status": "ok",
         "usage": {
           "today": {"tokens": 100000, "cost_usd": 1.0,
             "by_family": {
               "opus": {"input": 50000, "output": 0, "cache_write_5m": 0, "cache_write_1h": 0, "cache_read": 0},
               "haiku": {"input": 50000, "output": 0, "cache_write_5m": 0, "cache_write_1h": 0, "cache_read": 0}
             }},
           "month": {"tokens": 3000000, "cost_usd": 6.0,
             "by_family": {
               "opus": {"input": 1000000, "output": 100000, "cache_write_5m": 200000, "cache_write_1h": 0, "cache_read": 2000000},
               "sonnet": {"input": 500000, "output": 50000, "cache_write_5m": 0, "cache_write_1h": 100000, "cache_read": 1000000},
               "haiku": {"input": 2000000, "output": 0, "cache_write_5m": 0, "cache_write_1h": 0, "cache_read": 0},
               "fable": {"input": 0, "output": 0, "cache_write_5m": 0, "cache_write_1h": 0, "cache_read": 0},
               "other": {"input": 100000, "output": 0, "cache_write_5m": 0, "cache_write_1h": 0, "cache_read": 0}
             }}}},
        {"id": "claude-claude-2", "provider": "claude", "label": "Claude 2", "plan": "Pro", "status": "ok",
         "usage": {
           "today": {"tokens": 0, "cost_usd": 0},
           "month": {"tokens": 1000000, "cost_usd": 2.0,
             "by_family": {
               "sonnet": {"input": 1000000, "output": 0, "cache_write_5m": 0, "cache_write_1h": 0, "cache_read": 0}
             }}}},
        {"id": "codex-main", "provider": "codex", "label": "ChatGPT", "plan": "Pro Lite", "status": "ok",
         "usage": {"month": {"tokens": 999999999, "cost_usd": 1}}}
      ]
    }
    """

    /// The same file without the two new fields: an old usage.json.
    static let oldJSON = """
    {
      "schema": 1,
      "generated_at": "2026-11-19T04:30:00Z",
      "accounts": [
        {"id": "claude-main", "provider": "claude", "label": "Claude", "plan": "Max", "status": "ok",
         "usage": {"today": {"tokens": 100000, "cost_usd": 1.0}, "month": {"tokens": 3000000, "cost_usd": 6.0}}}
      ]
    }
    """

    static func document() throws -> UsageDocument {
        try Fixtures.document(json)
    }

    /// The mix of claude-main, the account the fixture's real numbers belong to. Its real shares are Opus 33, Sonnet 16,
    /// Haiku 51, Fable 0.
    static func actualPanel(settings: ModelMixSettings = .standard) throws -> ModelMixPanel {
        try unwrapPanel(accountMix(id: "claude-main", json: json, settings: settings)?.shown)
    }

    /// A what-if mix for the snapshots: Opus 50, Sonnet 30, Haiku 20, Fable 0.
    static func whatIfPanel() throws -> ModelMixPanel {
        try unwrapPanel(accountMix(
            id: "claude-main",
            json: json,
            settings: ModelMixSettings(
                order: ModelMix.defaultOrder,
                percent: ["claude-opus-5-5": 50, "claude-sonnet-5-5": 30, "claude-haiku-5-5": 20, "claude-fable-5-2": 0]
            )
        )?.shown)
    }

    /// The mix of every account of the fixture that has one, by account id, with the standard settings.
    static func allMixes() throws -> [String: AccountModelMix] {
        let document = try Fixtures.document(json)
        var mixes: [String: AccountModelMix] = [:]
        for account in document.accounts {
            mixes[account.id] = ModelMix.accountMix(for: account, prices: document.modelPrices ?? [:], settings: .standard)
        }
        return mixes
    }

    /// The mix of one account of a document, or nil when it has none.
    static func accountMix(id: String, json: String, settings: ModelMixSettings) throws -> AccountModelMix? {
        let document = try Fixtures.document(json)
        guard let account = document.accounts.first(where: { $0.id == id }) else { return nil }
        return ModelMix.accountMix(for: account, prices: document.modelPrices ?? [:], settings: settings)
    }

    private static func unwrapPanel(_ panel: ModelMixPanel?) throws -> ModelMixPanel {
        guard let panel else { throw FixtureError.jsonNotLoaded }
        return panel
    }

    /// ChatGPT (Codex) prices and usage, in the collector's shape (docs/usage-json.md). Two models this month:
    /// gpt-6.2-sol, with a long-context part, and gpt-6-luna. gpt-6.1-sol has prices but no tokens, so it is not a row.
    /// `long_context` is a subset of each model's total: gpt-6.2-sol has total input 2.0M, of which 1.0M is long, so its
    /// short part is 1.0M. The month's tokens are the share tokens of both models (2.15M + 2.0M) and its cost is 6.37.
    ///
    /// Prices (per 1M): sol input 2.00, cached 0.10, cache write 2.50, output 10.00; long context: input 4.00, cached 0.20,
    /// output 15.00, and the cache write rate 2.50 applies there too. luna input 0.10, cached 0.01, cache write 0.125,
    /// output 0.50 (no long context). The Claude price in this file has provider `anthropic`, as the collector writes it.
    static let gptJSON = """
    {
      "schema": 1,
      "generated_at": "2026-11-20T04:30:00Z",
      "model_prices": {
        "gpt-6.2-sol": {"provider": "openai", "family": "sol", "label": "GPT-6.2 Sol", "input": 2.0,
                        "cached_input": 0.1, "cache_write": 2.5, "output": 10.0,
                        "long_context": {"threshold": 272000, "input": 4.0, "cached_input": 0.2, "output": 15.0}},
        "gpt-6.1-sol": {"provider": "openai", "family": "sol", "label": "GPT-6.1 Sol", "input": 2.0,
                        "cached_input": 0.1, "cache_write": 2.5, "output": 10.0,
                        "long_context": {"threshold": 272000, "input": 4.0, "cached_input": 0.2, "output": 15.0}},
        "gpt-6-luna": {"provider": "openai", "family": "luna", "label": "GPT-6 Luna", "input": 0.1,
                       "cached_input": 0.01, "cache_write": 0.125, "output": 0.5},
        "claude-haiku-5-5": {"provider": "anthropic", "family": "haiku", "label": "Haiku 5.5", "input": 0.1,
                             "cache_write_5m": 0.125, "cache_write_1h": 0.2, "cache_read": 0.01, "output": 0.5}
      },
      "accounts": [
        {"id": "codex-main", "provider": "codex", "label": "ChatGPT", "plan": "Pro Lite", "status": "ok",
         "usage": {
           "today": {"tokens": 0, "cost_usd": null},
           "month": {"tokens": 4150000, "cost_usd": 6.37,
             "by_model": {
               "gpt-6.2-sol": {"input": 2000000, "cached_input": 500000, "cache_write": 0, "output": 150000,
                 "reasoning": 0,
                 "long_context": {"input": 1000000, "cached_input": 0, "cache_write": 0, "output": 50000}},
               "gpt-6-luna": {"input": 2000000, "cached_input": 0, "cache_write": 0, "output": 0, "reasoning": 0},
               "gpt-6.1-sol": {"input": 0, "cached_input": 0, "cache_write": 0, "output": 0, "reasoning": 0}
             }}}}
      ]
    }
    """
}
