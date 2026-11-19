import XCTest

final class UsageLoaderTests: XCTestCase {
    func testSampleFileLoads() {
        guard case .loaded(let document) = UsageLoader.load(from: Fixtures.sampleURL) else {
            return XCTFail("the sample file did not load")
        }
        XCTAssertEqual(document.accounts.count, 3)
    }

    func testMissingFileIsNoDataNotAnError() {
        let url = Fixtures.macFolder.appendingPathComponent("build/no-such-usage-file.json")
        XCTAssertEqual(UsageLoader.load(from: url), .missing)
    }

    func testBrokenOrEmptyJSONIsNoData() {
        XCTAssertEqual(UsageLoader.decode(Data("{".utf8)), .broken)
        XCTAssertEqual(UsageLoader.decode(Data()), .broken)
        XCTAssertEqual(UsageLoader.decode(Data("[1, 2]".utf8)), .broken)
    }

    func testDefaultFileIsInTheRealHomeNotTheAppContainer() {
        let path = UsageLoader.defaultFileURL().path
        XCTAssertTrue(path.hasSuffix("/Library/Application Support/AIUsage/usage.json"), path)
        XCTAssertFalse(path.contains("/Library/Containers/"), path)
    }

    func testRealHomeComesFromThePasswdEntry() throws {
        let entry = try XCTUnwrap(getpwuid(getuid()))
        let directory = try XCTUnwrap(entry.pointee.pw_dir)
        XCTAssertEqual(UsageLoader.realHomeDirectory().path, String(cString: directory))
    }

    func testWidgetEntitlementsSandboxTheExtensionAndAllowOnlyTheUsageFolder() throws {
        let plist = try propertyList(at: "AIUsageWidget/AIUsageWidget.entitlements")
        XCTAssertEqual(plist["com.apple.security.app-sandbox"] as? Bool, true)
        XCTAssertEqual(
            plist["com.apple.security.temporary-exception.files.home-relative-path.read-only"] as? [String],
            ["/Library/Application Support/AIUsage/"]
        )
    }

    func testWidgetIsAWidgetKitExtension() throws {
        let plist = try propertyList(at: "AIUsageWidget/Info.plist")
        let extensionInfo = plist["NSExtension"] as? [String: Any]
        XCTAssertEqual(extensionInfo?["NSExtensionPointIdentifier"] as? String, "com.apple.widgetkit-extension")
    }

    private func propertyList(at relativePath: String) throws -> [String: Any] {
        let data = try Data(contentsOf: Fixtures.macFolder.appendingPathComponent(relativePath))
        let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return try XCTUnwrap(object as? [String: Any])
    }
}
