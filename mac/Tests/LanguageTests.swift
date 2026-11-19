import XCTest

/// Language resolution and the settings file. The tests pass fixed locale strings and a temporary folder. Nothing
/// here reads this Mac's language, and nothing writes the real settings.json.
final class LanguageTests: XCTestCase {
    func testSystemIsThaiWhenThePreferredLanguageStartsWithTh() {
        XCTAssertEqual(UILanguage.resolve(.system, preferred: "th-TH"), .th)
        XCTAssertEqual(UILanguage.resolve(.system, preferred: "th"), .th)
        XCTAssertEqual(UILanguage.resolve(.system, preferred: "TH-th"), .th)
    }

    func testSystemIsEnglishForEveryOtherLanguage() {
        XCTAssertEqual(UILanguage.resolve(.system, preferred: "en-US"), .en)
        XCTAssertEqual(UILanguage.resolve(.system, preferred: "ja-JP"), .en)
        XCTAssertEqual(UILanguage.resolve(.system, preferred: "fr-FR"), .en)
        XCTAssertEqual(UILanguage.resolve(.system, preferred: ""), .en)
        XCTAssertEqual(UILanguage.resolve(.system, preferred: nil), .en)
    }

    func testAnExplicitChoiceIgnoresTheSystemLanguage() {
        XCTAssertEqual(UILanguage.resolve(.th, preferred: "en-US"), .th)
        XCTAssertEqual(UILanguage.resolve(.en, preferred: "th-TH"), .en)
        XCTAssertEqual(UILanguage.resolve(.th, preferred: nil), .th)
        XCTAssertEqual(UILanguage.resolve(.en, preferred: nil), .en)
    }

    /// A temporary folder for each test. The settings file sits in a nested folder, so saving creates it.
    private func temporarySettingsURL() -> (url: URL, folder: URL) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("AIUsageTests-\(UUID().uuidString)", isDirectory: true)
        return (folder.appendingPathComponent("Application Support/AIUsage/settings.json"), folder)
    }

    func testTheSettingsFileRoundTripsAndIsWrittenAsTheContractSays() throws {
        let (url, folder) = temporarySettingsURL()
        defer { try? FileManager.default.removeItem(at: folder) }

        XCTAssertEqual(AppSettingsStore.load(from: url), .system, "a missing file means system")
        try AppSettingsStore.save(.th, to: url)
        XCTAssertEqual(AppSettingsStore.load(from: url), .th)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), #"{"language":"th"}"#)
        try AppSettingsStore.save(.en, to: url)
        XCTAssertEqual(AppSettingsStore.load(from: url), .en)
        try AppSettingsStore.save(.system, to: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), #"{"language":"system"}"#)
        XCTAssertEqual(AppSettingsStore.load(from: url), .system)
    }

    func testABrokenOrUnknownSettingsFileMeansSystem() throws {
        let (url, folder) = temporarySettingsURL()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        try Data("not json".utf8).write(to: url)
        XCTAssertEqual(AppSettingsStore.load(from: url), .system)
        try Data(#"{"language":"fr"}"#.utf8).write(to: url)
        XCTAssertEqual(AppSettingsStore.load(from: url), .system)
        try Data(#"{"other":"th"}"#.utf8).write(to: url)
        XCTAssertEqual(AppSettingsStore.load(from: url), .system)
    }

    func testTheDefaultSettingsPathIsNextToUsageJSON() {
        let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
        XCTAssertEqual(
            AppSettingsStore.defaultFileURL(home: home).path,
            "/Users/example/Library/Application Support/AIUsage/settings.json"
        )
    }

    /// The settings file as a JSON object, for checks on keys.
    private func settingsObject(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }

    /// The notify key is a JSON boolean, written next to the language with compact, sorted bytes.
    func testTheNotifyValueIsWrittenNextToTheLanguageAsAJSONBoolean() throws {
        let (url, folder) = temporarySettingsURL()
        defer { try? FileManager.default.removeItem(at: folder) }

        try AppSettingsStore.saveNotify(false, to: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), #"{"notify":false}"#)
        try AppSettingsStore.save(.th, to: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), #"{"language":"th","notify":false}"#)
        try AppSettingsStore.saveNotify(true, to: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), #"{"language":"th","notify":true}"#)
        XCTAssertEqual(AppSettingsStore.load(from: url), .th, "the language still loads with notify present")
    }

    /// The language write keeps the notify value, whichever key was written first.
    func testSavingTheLanguageKeepsTheNotifyValue() throws {
        let (url, folder) = temporarySettingsURL()
        defer { try? FileManager.default.removeItem(at: folder) }

        try AppSettingsStore.save(.en, to: url)
        try AppSettingsStore.saveNotify(true, to: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), #"{"language":"en","notify":true}"#)
        try AppSettingsStore.save(.system, to: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), #"{"language":"system","notify":true}"#)
    }

    /// Keys this version does not know survive both writes.
    func testUnknownKeysSurviveEveryWrite() throws {
        let (url, folder) = temporarySettingsURL()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"future":{"a":[1,2]},"language":"th"}"#.utf8).write(to: url)

        try AppSettingsStore.saveNotify(false, to: url)
        var object = try settingsObject(at: url)
        XCTAssertEqual(object["language"] as? String, "th")
        XCTAssertEqual(object["notify"] as? Bool, false)
        XCTAssertEqual((object["future"] as? [String: Any])?["a"] as? [Int], [1, 2])

        try AppSettingsStore.save(.en, to: url)
        object = try settingsObject(at: url)
        XCTAssertEqual(object["language"] as? String, "en")
        XCTAssertEqual((object["future"] as? [String: Any])?["a"] as? [Int], [1, 2])
    }

    /// A broken file is replaced by the write, and a write leaves no temporary file next to the settings file.
    func testABrokenFileIsReplacedAndNoTemporaryFileIsLeft() throws {
        let (url, folder) = temporarySettingsURL()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)

        try AppSettingsStore.saveNotify(true, to: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), #"{"notify":true}"#)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path),
            ["settings.json"]
        )
    }
}
