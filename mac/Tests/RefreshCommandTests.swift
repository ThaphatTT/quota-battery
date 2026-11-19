import XCTest

final class RefreshCommandTests: XCTestCase {
    func testKickstartTargetsTheCollectorJobInTheUserGuiDomain() {
        XCTAssertEqual(RefreshCommand.kickstartArguments(uid: 501), ["kickstart", "-k", "gui/501/com.user.aiusage"])
    }

    func testRunsLaunchctlFromBinWithTheCollectorLabel() {
        XCTAssertEqual(RefreshCommand.executable.path, "/bin/launchctl")
        XCTAssertEqual(RefreshCommand.jobLabel, "com.user.aiusage")
    }

    /// Exit status 0 is success. Any other status is kept as the failure, and the view makes its text.
    func testOnlyExitStatusZeroIsNotAFailure() {
        XCTAssertNil(RefreshCommand.failure(forExitStatus: 0))
        XCTAssertEqual(RefreshCommand.failure(forExitStatus: 3), .exitStatus(3))
        XCTAssertEqual(RefreshCommand.failure(forExitStatus: 113), .exitStatus(113))
    }
}
