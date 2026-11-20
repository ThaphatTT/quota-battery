import XCTest

/// A login item that records what it was asked to do. No test touches the real login items.
private final class FakeLoginItem: LoginItemService {
    var status: LoginItemStatus
    /// Set to make the next register or unregister fail.
    var failure: Error?
    private(set) var registers = 0
    private(set) var unregisters = 0

    init(status: LoginItemStatus) {
        self.status = status
    }

    func register() throws {
        registers += 1
        if let failure { throw failure }
        status = .enabled
    }

    func unregister() throws {
        unregisters += 1
        if let failure { throw failure }
        status = .notRegistered
    }
}

private struct Refused: Error {}

@MainActor
final class OpenAtLoginTests: XCTestCase {
    func testTheSwitchStartsFromTheStatusTheSystemReports() {
        XCTAssertFalse(OpenAtLoginModel(service: FakeLoginItem(status: .notRegistered)).isOn)
        XCTAssertTrue(OpenAtLoginModel(service: FakeLoginItem(status: .enabled)).isOn)
    }

    /// Waiting for approval counts as on: the item starts once the user allows it.
    func testAnItemThatNeedsApprovalIsOn() {
        XCTAssertTrue(OpenAtLoginModel(service: FakeLoginItem(status: .requiresApproval)).isOn)
    }

    func testTurningItOnRegistersOnceAndShowsTheStatusReadAfterwards() {
        let item = FakeLoginItem(status: .notRegistered)
        let model = OpenAtLoginModel(service: item)
        model.setEnabled(true)
        XCTAssertEqual(item.registers, 1)
        XCTAssertEqual(item.unregisters, 0)
        XCTAssertEqual(model.status, .enabled)
        XCTAssertTrue(model.isOn)
        XCTAssertFalse(model.failed)
    }

    func testTurningItOffUnregistersOnce() {
        let item = FakeLoginItem(status: .enabled)
        let model = OpenAtLoginModel(service: item)
        model.setEnabled(false)
        XCTAssertEqual(item.unregisters, 1)
        XCTAssertEqual(item.registers, 0)
        XCTAssertFalse(model.isOn)
    }

    /// The system refused: the switch shows what the system still says, and the failure is flagged.
    func testARefusedChangeShowsTheRealStatusAndIsFlagged() {
        let item = FakeLoginItem(status: .notRegistered)
        item.failure = Refused()
        let model = OpenAtLoginModel(service: item)
        model.setEnabled(true)
        XCTAssertTrue(model.failed)
        XCTAssertEqual(model.status, .notRegistered)
        XCTAssertFalse(model.isOn)
    }

    /// The next change clears the failure, and a success leaves none behind.
    func testTheNextChangeClearsTheFailure() {
        let item = FakeLoginItem(status: .notRegistered)
        item.failure = Refused()
        let model = OpenAtLoginModel(service: item)
        model.setEnabled(true)
        XCTAssertTrue(model.failed)
        item.failure = nil
        model.setEnabled(true)
        XCTAssertFalse(model.failed)
        XCTAssertTrue(model.isOn)
    }

    /// A status changed outside the app (in System Settings) is read again by `refresh()`.
    func testRefreshReadsAStatusChangedOutsideTheApp() {
        let item = FakeLoginItem(status: .notRegistered)
        let model = OpenAtLoginModel(service: item)
        item.status = .requiresApproval
        model.refresh()
        XCTAssertEqual(model.status, .requiresApproval)
        XCTAssertTrue(model.isOn)
    }
}
