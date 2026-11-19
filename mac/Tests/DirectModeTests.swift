import Foundation
import XCTest

/// The direct mode rules: who can have it, the settings.json shape and its writes, the consent button, and the refusals
/// for Claude. Files are written to a temporary folder, which is removed afterwards. The real home folder is never used.
final class DirectModeTests: XCTestCase {
    private var folders: [URL] = []

    override func tearDown() {
        for folder in folders {
            try? FileManager.default.removeItem(at: folder)
        }
        folders = []
        super.tearDown()
    }

    // MARK: Who can have it

    func testOnlyChatGPTAndAgyCanHaveDirectMode() {
        XCTAssertEqual(DirectMode.providers, ["codex", "agy"])
        XCTAssertTrue(DirectMode.isAvailable("codex"))
        XCTAssertTrue(DirectMode.isAvailable("agy"))
    }

    /// Claude never gets the option: no switch can turn it on, and the consent screen never enables its button.
    func testClaudeNeverGetsTheOption() {
        XCTAssertFalse(DirectMode.isAvailable("claude"))
        XCTAssertFalse(DirectMode.isAvailable(""))
        XCTAssertNil(DirectModeSettings.off.setting("claude", to: true))
        XCTAssertFalse(DirectModeSettings.off.isOn("claude"))

        var consent = DirectModeConsent(provider: "claude")
        consent.consented = true
        XCTAssertFalse(consent.canTurnOn)
        XCTAssertNil(consent.confirm())
    }

    /// A `claude` entry in the file is never read as on, and the next write removes it.
    func testAClaudeEntryInTheFileIsNeverOnAndIsRemovedOnTheNextWrite() throws {
        let url = temporaryURL(named: "settings.json")
        try write(#"{"direct_mode": {"claude": true, "codex": true}}"#, to: url)
        XCTAssertEqual(AppSettingsStore.loadDirectMode(from: url), DirectModeSettings(codex: true, agy: false))

        try AppSettingsStore.saveDirectMode(DirectModeSettings(codex: true, agy: false), at: url)
        let object = try readObject(url)
        let direct = try XCTUnwrap(object["direct_mode"] as? [String: Any])
        XCTAssertEqual(Set(direct.keys), ["codex", "agy"])
    }

    // MARK: The settings file

    func testAMissingOrBrokenDirectModeMeansOff() throws {
        XCTAssertEqual(AppSettingsStore.loadDirectMode(from: temporaryURL(named: "settings.json")), .off)

        let url = temporaryURL(named: "settings.json")
        try write(#"{"direct_mode": "oops"}"#, to: url)
        XCTAssertEqual(AppSettingsStore.loadDirectMode(from: url), .off)
        try write(#"{"direct_mode": {"codex": "yes", "agy": "on"}}"#, to: url)
        XCTAssertEqual(AppSettingsStore.loadDirectMode(from: url), .off)
    }

    /// The write creates the folder when needed, writes both switches as JSON booleans, and changes only the provider
    /// that was turned on.
    func testSavingWritesBothSwitchesAndChangesOnlyTheProviderTurnedOn() throws {
        let url = temporaryURL(named: "settings.json")
        try AppSettingsStore.saveDirectMode(DirectModeSettings(codex: false, agy: true), at: url)

        let turnedOn = try XCTUnwrap(AppSettingsStore.loadDirectMode(from: url).setting("codex", to: true))
        try AppSettingsStore.saveDirectMode(turnedOn, at: url)

        XCTAssertEqual(AppSettingsStore.loadDirectMode(from: url), DirectModeSettings(codex: true, agy: true))
        let object = try readObject(url)
        let direct = try XCTUnwrap(object["direct_mode"] as? [String: Any])
        XCTAssertEqual(direct["codex"] as? Bool, true)
        XCTAssertEqual(direct["agy"] as? Bool, true)
    }

    /// A direct-mode write changes only `direct_mode`. The language, notify, sort, accounts and unknown keys stay as they
    /// were, and so does an unknown key inside `direct_mode`.
    func testTurningDirectModeOnKeepsEveryOtherKey() throws {
        let url = temporaryURL(named: "settings.json")
        try write(#"""
        {"language": "th", "notify": false, "sort": "lowest",
         "accounts": {"claude-main": {"enabled": true, "future": 7}},
         "direct_mode": {"agy": true, "future": "keep"}, "unknown_top": [1, 2]}
        """#, to: url)
        let before = try readObject(url)

        try AppSettingsStore.saveDirectMode(DirectModeSettings(codex: true, agy: true), at: url)

        let after = try readObject(url)
        for key in ["language", "notify", "sort", "accounts", "unknown_top"] {
            XCTAssertEqual(try canonical(after[key]), try canonical(before[key]), key)
        }
        let direct = try XCTUnwrap(after["direct_mode"] as? [String: Any])
        XCTAssertEqual(direct["codex"] as? Bool, true)
        XCTAssertEqual(direct["agy"] as? Bool, true)
        XCTAssertEqual(direct["future"] as? String, "keep")
    }

    /// The language, notify and account writes keep `direct_mode` as it is.
    func testTheOtherSettingsWritesKeepDirectMode() throws {
        let url = temporaryURL(named: "settings.json")
        try write(#"{"direct_mode": {"codex": true, "agy": false, "future": "keep"}}"#, to: url)

        try AppSettingsStore.save(.en, to: url)
        try AppSettingsStore.saveNotify(false, to: url)
        try AppSettingsStore.saveAccountSettings(AccountSettings(sort: .provider, accounts: [
            "codex-main": AccountPreference(label: nil, enabled: false, order: 0),
        ]), at: url)

        let object = try readObject(url)
        let direct = try XCTUnwrap(object["direct_mode"] as? [String: Any])
        XCTAssertEqual(direct["codex"] as? Bool, true)
        XCTAssertEqual(direct["agy"] as? Bool, false)
        XCTAssertEqual(direct["future"] as? String, "keep")
        XCTAssertEqual(AppSettingsStore.loadDirectMode(from: url), DirectModeSettings(codex: true, agy: false))
    }

    /// Turning one provider on or off changes only that provider.
    func testASwitchChangesOnlyItsProvider() throws {
        let start = DirectModeSettings(codex: false, agy: true)
        let on = try XCTUnwrap(start.setting("codex", to: true))
        XCTAssertEqual(on, DirectModeSettings(codex: true, agy: true))
        let off = try XCTUnwrap(on.setting("agy", to: false))
        XCTAssertEqual(off, DirectModeSettings(codex: true, agy: false))
        XCTAssertTrue(off.isOn("codex"))
        XCTAssertFalse(off.isOn("agy"))
        XCTAssertFalse(DirectModeSettings.off.isOn("codex"))
    }

    // MARK: The consent screen

    /// The button stays disabled until the box is ticked, and confirming before that gives nothing.
    func testTheTurnOnButtonStaysDisabledUntilTheBoxIsTicked() {
        var consent = DirectModeConsent(provider: "codex")
        XCTAssertFalse(consent.consented)
        XCTAssertFalse(consent.canTurnOn)
        XCTAssertNil(consent.confirm())

        consent.consented = true
        XCTAssertTrue(consent.canTurnOn)
        XCTAssertEqual(consent.confirm(), "codex")

        consent.consented = false
        XCTAssertFalse(consent.canTurnOn)
        XCTAssertNil(consent.confirm())
    }

    func testAgyUsesTheSameConsent() {
        var consent = DirectModeConsent(provider: "agy")
        XCTAssertNil(consent.confirm())
        consent.consented = true
        XCTAssertEqual(consent.confirm(), "agy")
    }

    func testTheConsentTitleNamesTheServiceInBothLanguages() {
        XCTAssertEqual(L10n.directConsentTitle(service: "ChatGPT", .th), "เปิดโหมดอ่านรหัสโดยตรง · ChatGPT")
        XCTAssertEqual(L10n.directConsentTitle(service: "ChatGPT", .en), "Turn on direct mode · ChatGPT")
        XCTAssertEqual(L10n.directConsentTitle(service: "agy", .en), "Turn on direct mode · agy")
    }

    // MARK: Helpers

    private func temporaryURL(named name: String) -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("aiusage-direct-\(UUID().uuidString)", isDirectory: true)
        folders.append(folder)
        return folder.appendingPathComponent(name)
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func readObject(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// The JSON text of one value with sorted keys, so that two values can be compared.
    private func canonical(_ value: Any?) throws -> String {
        let object: Any = value ?? NSNull()
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed])
        return String(decoding: data, as: UTF8.self)
    }
}
