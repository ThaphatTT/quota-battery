import XCTest

/// The guard behind the "show menu bar icon" switch. The rule is pure, so these tests need no AppKit. They pin the
/// crash: setting `isVisible` made AppKit write its defaults, which called the same code again, without end.
final class MenuBarIconSwitchTests: XCTestCase {
    func testLaunchWithTheSwitchOnLeavesAVisibleItemAlone() {
        XCTAssertEqual(
            MenuBarIconSwitchRule.step(wanted: true, lastApplied: nil, isVisibleNow: true, isApplying: false),
            .rememberOnly
        )
    }

    func testLaunchWithTheSwitchOffHidesTheItem() {
        XCTAssertEqual(
            MenuBarIconSwitchRule.step(wanted: false, lastApplied: nil, isVisibleNow: true, isApplying: false),
            .setVisible(false)
        )
    }

    func testTurningTheSwitchOffHidesTheItem() {
        XCTAssertEqual(
            MenuBarIconSwitchRule.step(wanted: false, lastApplied: true, isVisibleNow: true, isApplying: false),
            .setVisible(false)
        )
    }

    func testTurningTheSwitchBackOnShowsTheItem() {
        XCTAssertEqual(
            MenuBarIconSwitchRule.step(wanted: true, lastApplied: false, isVisibleNow: false, isApplying: false),
            .setVisible(true)
        )
    }

    func testAnItemAlreadyShowingTheNewValueOnlyRemembersIt() {
        XCTAssertEqual(
            MenuBarIconSwitchRule.step(wanted: true, lastApplied: false, isVisibleNow: true, isApplying: false),
            .rememberOnly
        )
    }

    func testAnUnchangedSwitchNeverTouchesVisibility() {
        // The defaults changed for another reason, and the system removed the item. Nothing is set.
        XCTAssertEqual(
            MenuBarIconSwitchRule.step(wanted: true, lastApplied: true, isVisibleNow: false, isApplying: false),
            .nothing
        )
    }

    func testAChangeWhileSettingIsIgnored() {
        // The change that AppKit posts during a set arrives while the set is still running.
        XCTAssertEqual(
            MenuBarIconSwitchRule.step(wanted: false, lastApplied: true, isVisibleNow: true, isApplying: true),
            .nothing
        )
    }

    /// Models the controller's set path: the applied value is recorded first, the flag is raised, and the set makes
    /// AppKit post a change that reaches the same code while AppKit still reports the old `isVisible`. The flag comes
    /// down after the set. Exactly one set must happen, and a later call with the new state must set nothing.
    func testTheCrashSequenceSetsOnceAndStops() {
        var lastApplied: Bool? = true
        var isVisible = true
        var isApplying = false
        var sets = 0

        func applySwitch(_ wanted: Bool) {
            let step = MenuBarIconSwitchRule.step(
                wanted: wanted,
                lastApplied: lastApplied,
                isVisibleNow: isVisible,
                isApplying: isApplying
            )
            switch step {
            case .nothing:
                return
            case .rememberOnly:
                lastApplied = wanted
            case .setVisible(let value):
                lastApplied = value
                isApplying = true
                defer { isApplying = false }
                sets += 1
                applySwitch(wanted)
            }
        }

        applySwitch(false)
        XCTAssertEqual(sets, 1)
        XCTAssertEqual(lastApplied, false)

        isVisible = false
        applySwitch(false)
        XCTAssertEqual(sets, 1)
    }
}
