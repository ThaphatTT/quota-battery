import Foundation
import XCTest

/// The Accounts rules: known-accounts.json, the sort and per-account settings in settings.json, the names, the New tag,
/// the three sort orders, the drag placement and the login command. Files are written to a temporary folder, never to
/// the real home folder.
final class AccountsTests: XCTestCase {
    private let now = Fixtures.now

    // MARK: known-accounts.json

    func testKnownAccountsReadTheObjectShapeAndDropEntriesWithoutAnIdOrProvider() {
        let data = Data(#"""
        {"schema": 1, "accounts": [
          {"id": "claude-main", "provider": "claude", "source": "Claude Code (main)", "first_seen": "2026-11-19T04:00:00Z"},
          {"provider": "codex", "source": "no id, so dropped"},
          {"id": "codex-main", "provider": "codex", "source": "Codex (~/.codex)"},
          {"id": "agy-main", "provider": "agy", "source": "Antigravity", "first_seen": "not a date"}
        ]}
        """#.utf8)
        let known = KnownAccounts.decode(data)
        XCTAssertEqual(known.map(\.id), ["claude-main", "codex-main", "agy-main"])
        XCTAssertEqual(known[0].source, "Claude Code (main)")
        XCTAssertEqual(known[0].firstSeen, date("2026-11-19T04:00:00Z"))
        XCTAssertEqual(known[1].source, "Codex (~/.codex)")
        XCTAssertNil(known[1].firstSeen)
        XCTAssertNil(known[2].firstSeen)
    }

    func testKnownAccountsAlsoReadABareArray() {
        let data = Data(#"[{"id": "codex-2", "provider": "codex", "source": "Codex (~/.codex-2)"}]"#.utf8)
        XCTAssertEqual(KnownAccounts.decode(data).map(\.id), ["codex-2"])
    }

    func testABrokenOrMissingKnownAccountsFileMeansNone() {
        XCTAssertEqual(KnownAccounts.decode(Data("{ not json".utf8)), [])
        XCTAssertEqual(KnownAccounts.decode(Data(#"{"accounts": "nope"}"#.utf8)), [])
        XCTAssertEqual(KnownAccounts.load(from: temporaryURL(named: "known-accounts.json")), [])
    }

    /// The id is what links an account in usage.json to the known list and to settings.json.
    func testUsageAccountKeepsItsIdAndAnAccountWithoutOneHasAnEmptyId() throws {
        let document = try Fixtures.document(#"""
        {"accounts": [
          {"id": "claude-claude-2", "provider": "claude", "status": "ok", "limits": []},
          {"provider": "agy", "status": "ok", "limits": []}
        ]}
        """#)
        XCTAssertEqual(document.accounts.map(\.id), ["claude-claude-2", ""])
    }

    // MARK: settings.json

    func testMissingSettingsMeanManualOrderAndNoAccountEntries() {
        let settings = AppSettingsStore.loadAccountSettings(from: temporaryURL(named: "settings.json"))
        XCTAssertEqual(settings, AccountSettings())
        XCTAssertEqual(settings.preference(for: "claude-main"), AccountPreference.standard)
    }

    func testAnUnknownSortAndBrokenEntriesCountAsDefaults() throws {
        let url = temporaryURL(named: "settings.json")
        try write(#"{"sort": "random", "accounts": {"claude-main": "oops", "codex-main": {"label": "  ", "enabled": false, "order": 2}}}"#, to: url)
        let settings = AppSettingsStore.loadAccountSettings(from: url)
        XCTAssertEqual(settings.sort, .manual)
        XCTAssertNil(settings.accounts["claude-main"])
        XCTAssertEqual(settings.accounts["codex-main"], AccountPreference(label: nil, enabled: false, order: 2))
    }

    /// Saving the accounts changes only `sort` and each account's own keys. The language, the notify switch and any key
    /// this version does not know stay as they are.
    func testSavingKeepsTheOtherKeysAndUnknownKeysInsideAnAccount() throws {
        let url = temporaryURL(named: "settings.json")
        try write(#"{"language": "th", "notify": false, "accounts": {"claude-main": {"enabled": true, "future": 7}}}"#, to: url)
        var settings = AppSettingsStore.loadAccountSettings(from: url)
        settings.sort = .lowest
        settings.accounts["claude-main"] = AccountPreference(label: "Claude งาน", enabled: false, order: 1)
        settings.accounts["codex-main"] = AccountPreference(label: nil, enabled: true, order: 0)
        try AppSettingsStore.saveAccountSettings(settings, at: url)

        let object = try readObject(url)
        XCTAssertEqual(object["language"] as? String, "th")
        XCTAssertEqual(object["notify"] as? Bool, false)
        XCTAssertEqual(object["sort"] as? String, "lowest")
        let accounts = try XCTUnwrap(object["accounts"] as? [String: Any])
        let claude = try XCTUnwrap(accounts["claude-main"] as? [String: Any])
        XCTAssertEqual(claude["label"] as? String, "Claude งาน")
        XCTAssertEqual(claude["enabled"] as? Bool, false)
        XCTAssertEqual(claude["order"] as? Int, 1)
        XCTAssertEqual(claude["future"] as? Int, 7)
        let codex = try XCTUnwrap(accounts["codex-main"] as? [String: Any])
        XCTAssertNil(codex["label"])
        XCTAssertEqual(codex["enabled"] as? Bool, true)
        XCTAssertEqual(codex["order"] as? Int, 0)

        XCTAssertEqual(AppSettingsStore.loadAccountSettings(from: url), settings)
    }

    /// The language write and the notify write (the existing keys) keep the account keys.
    func testTheOlderSettingsWritesKeepTheAccountKeys() throws {
        let url = temporaryURL(named: "settings.json")
        try AppSettingsStore.saveAccountSettings(
            AccountSettings(sort: .provider, accounts: ["agy-main": AccountPreference(label: nil, enabled: true, order: 3)]),
            at: url
        )
        try AppSettingsStore.save(.en, to: url)
        try AppSettingsStore.saveNotify(true, to: url)
        let settings = AppSettingsStore.loadAccountSettings(from: url)
        XCTAssertEqual(settings.sort, .provider)
        XCTAssertEqual(settings.accounts["agy-main"]?.order, 3)
        XCTAssertEqual(AppSettingsStore.load(from: url), .en)
    }

    // MARK: Names

    /// The nickname wins. Without one, the default name is the provider's name, and a second account of the same
    /// provider gets a number in discovery order.
    func testNamesUseTheNicknameOrTheDefaultNumberedInDiscoveryOrder() {
        let known = [
            knownAccount("claude-main", "claude", "Claude Code (main)"),
            knownAccount("codex-main", "codex", "Codex (~/.codex)"),
            knownAccount("claude-claude-2", "claude", "Claude Code (~/.claude-2)"),
        ]
        var settings = AccountSettings()
        settings.accounts["claude-claude-2"] = AccountPreference(label: "Claude งาน", enabled: true, order: nil)
        let rows = AccountList.rows(known: known, usage: [], settings: settings, now: now)
        XCTAssertEqual(rows.map(\.name), ["Claude 1", "ChatGPT", "Claude งาน"])
        XCTAssertNil(rows[0].nickname)
        XCTAssertEqual(rows[2].nickname, "Claude งาน")
    }

    /// The collector's rule: one account keeps the plain name, and two or more are numbered from 1 in discovery order.
    func testDefaultNamesAreNumberedFromOneWhenAProviderHasTwoOrMoreAccounts() {
        XCTAssertEqual(AccountList.defaultName(provider: "claude", index: 0, count: 1), "Claude")
        XCTAssertEqual(AccountList.defaultName(provider: "claude", index: 0, count: 2), "Claude 1")
        XCTAssertEqual(AccountList.defaultName(provider: "claude", index: 1, count: 2), "Claude 2")
        XCTAssertEqual(AccountList.defaultName(provider: "claude", index: 2, count: 3), "Claude 3")
        XCTAssertEqual(AccountList.defaultName(provider: "agy", index: 0, count: 1), "agy")
    }

    // MARK: New tag

    func testTheNewTagIsOnlyForAccountsFoundInTheLastDay() {
        let rows = AccountList.rows(
            known: [
                knownAccount("claude-claude-2", "claude", "Claude Code (~/.claude-2)", firstSeen: "2026-11-19T03:00:00Z"),
                knownAccount("codex-main", "codex", "Codex (~/.codex)", firstSeen: "2026-11-17T04:30:00Z"),
                knownAccount("agy-main", "agy", "Antigravity"),
            ],
            usage: [],
            settings: AccountSettings(),
            now: now
        )
        XCTAssertEqual(rows.map(\.isNew), [true, false, false])
        XCTAssertFalse(AccountList.isNew(firstSeen: now.addingTimeInterval(-AccountList.newWindow), now: now))
        XCTAssertTrue(AccountList.isNew(firstSeen: now.addingTimeInterval(-AccountList.newWindow + 1), now: now))
    }

    // MARK: Plan, switch and the smallest remaining

    /// The plan and the smallest remaining come from usage.json. A hidden account is not in usage.json, so it has
    /// neither, and an account with no limits has no remaining.
    func testRowsTakeThePlanAndTheSmallestRemainingFromUsageJson() throws {
        let usage = try Fixtures.document(#"""
        {"accounts": [
          {"id": "claude-main", "provider": "claude", "label": "Claude", "plan": "Max", "status": "ok",
           "limits": [{"key": "five_hour", "window_seconds": 18000, "used_percent": 42},
                      {"key": "seven_day", "window_seconds": 604800, "used_percent": 67}]},
          {"id": "agy-main", "provider": "agy", "label": "agy", "plan": "free-tier", "status": "ok", "limits": []}
        ]}
        """#).accounts
        var settings = AccountSettings()
        settings.accounts["codex-main"] = AccountPreference(label: nil, enabled: false, order: nil)
        let rows = AccountList.rows(
            known: [
                knownAccount("claude-main", "claude", "Claude Code (main)"),
                knownAccount("codex-main", "codex", "Codex (~/.codex)"),
                knownAccount("agy-main", "agy", "Antigravity"),
            ],
            usage: usage,
            settings: settings,
            now: now
        )
        XCTAssertEqual(rows.map(\.plan), ["Max", nil, "free-tier"])
        XCTAssertEqual(rows.map(\.smallestRemaining), [33, nil, nil])
        XCTAssertEqual(rows.map(\.enabled), [true, false, true])
    }

    /// An account that only usage.json has is still listed, with the provider's tag as its source.
    func testAnAccountOnlyInUsageJsonIsListedWithTheProviderTag() throws {
        let usage = try Fixtures.document(#"{"accounts": [{"id": "codex-2", "provider": "codex", "label": "ChatGPT 2", "status": "ok", "limits": []}]}"#).accounts
        let rows = AccountList.rows(known: [], usage: usage, settings: AccountSettings(), now: now)
        XCTAssertEqual(rows.map(\.id), ["codex-2"])
        XCTAssertEqual(rows.map(\.source), ["Codex CLI"])
        XCTAssertEqual(rows.map(\.name), ["ChatGPT"])
    }

    // MARK: Order

    func testManualOrderPutsAccountsWithoutAnOrderLastInDiscoveryOrder() {
        let rows = [
            listRow("a", order: nil),
            listRow("b", order: 2),
            listRow("c", order: 0),
            listRow("d", order: nil),
        ]
        XCTAssertEqual(AccountList.sorted(rows, by: .manual).map(\.id), ["c", "b", "a", "d"])
    }

    /// Lowest left first: the smallest remaining first. Ties keep the manual order. An account with no limits goes last.
    func testLowestLeftFirstUsesTheSmallestRemainingAndKeepsTheManualOrderOnTies() {
        let rows = [
            listRow("a", order: 0, remaining: 50),
            listRow("b", order: 1, remaining: 10),
            listRow("c", order: 2, remaining: nil),
            listRow("d", order: 3, remaining: 10),
            listRow("e", order: 4, remaining: 0),
        ]
        XCTAssertEqual(AccountList.sorted(rows, by: .lowest).map(\.id), ["e", "b", "d", "a", "c"])
    }

    /// By service: Claude, then ChatGPT (codex), then agy, then any other provider. Each group keeps the manual order.
    func testByServiceGroupsClaudeChatGPTAgyThenOthersInManualOrder() {
        let rows = [
            listRow("agy-main", provider: "agy", order: 0),
            listRow("codex-main", provider: "codex", order: 1),
            listRow("claude-claude-2", provider: "claude", order: 2),
            listRow("claude-main", provider: "claude", order: 3),
            listRow("other-1", provider: "other", order: 4),
            listRow("codex-2", provider: "codex", order: 5),
        ]
        XCTAssertEqual(
            AccountList.sorted(rows, by: .provider).map(\.id),
            ["claude-claude-2", "claude-main", "codex-main", "codex-2", "agy-main", "other-1"]
        )
    }

    /// Drag and drop: the dragged account is taken out and put at the target's place.
    func testMovingDropsTheDraggedAccountAtTheTargetsPlace() {
        XCTAssertEqual(AccountList.moved(["a", "b", "c", "d"], id: "a", onto: "c"), ["b", "c", "a", "d"])
        XCTAssertEqual(AccountList.moved(["a", "b", "c", "d"], id: "d", onto: "b"), ["a", "d", "b", "c"])
        XCTAssertEqual(AccountList.moved(["a", "b"], id: "a", onto: "a"), ["a", "b"])
        XCTAssertEqual(AccountList.moved(["a", "b"], id: "z", onto: "a"), ["a", "b"])
    }

    // MARK: Login

    func testTheFirstFreeFolderStartsAtTwoAndSkipsFoldersThatExist() {
        XCTAssertEqual(AccountLogin.firstFreeNumber(provider: "claude", isTaken: { _ in false }), 2)
        XCTAssertEqual(AccountLogin.firstFreeNumber(provider: "claude", isTaken: { $0 == ".claude-2" }), 3)
        XCTAssertEqual(
            AccountLogin.firstFreeNumber(provider: "codex", isTaken: { $0 == ".codex-2" || $0 == ".codex-3" }),
            4
        )
        XCTAssertNil(AccountLogin.firstFreeNumber(provider: "agy", isTaken: { _ in false }))
        XCTAssertNil(AccountLogin.firstFreeNumber(provider: "claude", isTaken: { _ in true }))
    }

    func testTheLoginCommandsUseATildeFolder() {
        XCTAssertEqual(AccountLogin.command(provider: "claude", number: 2), "CLAUDE_CONFIG_DIR=~/.claude-2 claude")
        XCTAssertEqual(AccountLogin.command(provider: "codex", number: 2), "CODEX_HOME=~/.codex-2 codex login")
        XCTAssertNil(AccountLogin.command(provider: "agy", number: 2))
        XCTAssertEqual(AccountLogin.addableProviders, ["claude", "codex"])
    }

    func testTheTerminalScriptEscapesQuotesAndBackslashesAndOpensANewWindow() {
        let script = AccountLogin.terminalScript(for: #"echo "a\b""#)
        XCTAssertTrue(script.hasPrefix(#"tell application "Terminal""#))
        XCTAssertTrue(script.contains(#"do script "echo \"a\\b\"""#))
        XCTAssertTrue(script.hasSuffix("end tell"))
    }

    func testOsascriptGetsOneDashEForEachLineOfTheScript() {
        let args = AccountLogin.osascriptArguments(for: "CODEX_HOME=~/.codex-2 codex login")
        XCTAssertEqual(args.count, 8)
        XCTAssertEqual(args.filter { $0 == "-e" }.count, 4)
        XCTAssertEqual(args[1], #"tell application "Terminal""#)
        XCTAssertEqual(args[5], #"do script "CODEX_HOME=~/.codex-2 codex login""#)
    }

    // MARK: Helpers

    private func knownAccount(_ id: String, _ provider: String, _ source: String, firstSeen: String? = nil) -> KnownAccount {
        KnownAccount(id: id, provider: provider, source: source, firstSeen: firstSeen.flatMap(date))
    }

    private func listRow(
        _ id: String,
        provider: String = "claude",
        order: Int? = nil,
        remaining: Double? = nil
    ) -> AccountListRow {
        AccountListRow(
            id: id,
            provider: provider,
            name: id,
            nickname: nil,
            source: "",
            plan: nil,
            enabled: true,
            isNew: false,
            order: order,
            smallestRemaining: remaining
        )
    }

    private func date(_ text: String) -> Date? {
        ISO8601DateFormatter().date(from: text)
    }

    private func temporaryURL(named name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("aiusage-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(name)
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func readObject(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
