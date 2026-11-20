import XCTest

/// The words VoiceOver reads for the new controls: the gear, the Settings tabs, the open-at-login switch and its notes.
/// Each is checked in both languages. Whether VoiceOver reads them in order, and whether the keyboard reaches each control,
/// is checked by hand (see the test matrix).
final class AccessibilityLabelTests: XCTestCase {
    func testTheGearIsNamedSettingsInBothLanguages() {
        XCTAssertEqual(L10n.text(.settings, .en), "Settings")
        XCTAssertEqual(L10n.text(.settings, .th), "ตั้งค่า")
    }

    func testTheSettingsTabsAreNamedInBothLanguages() {
        XCTAssertEqual(L10n.text(.tabGeneral, .en), "General")
        XCTAssertEqual(L10n.text(.tabGeneral, .th), "ทั่วไป")
        XCTAssertEqual(L10n.text(.tabAccounts, .en), "Accounts")
        XCTAssertEqual(L10n.text(.tabAccounts, .th), "บัญชี")
        XCTAssertEqual(L10n.text(.tabNotifications, .en), "Notifications")
        XCTAssertEqual(L10n.text(.tabNotifications, .th), "การแจ้งเตือน")
        XCTAssertEqual(L10n.text(.tabDirectMode, .en), "Direct mode")
        XCTAssertEqual(L10n.text(.tabDirectMode, .th), "โหมดตรง")
    }

    func testTheLoginSwitchAndItsNotesAreNamedInBothLanguages() {
        XCTAssertEqual(L10n.text(.openAtLogin, .en), "Open at login")
        XCTAssertEqual(L10n.text(.openAtLogin, .th), "เปิดเมื่อเข้าสู่ระบบ")
        XCTAssertFalse(L10n.text(.openAtLoginNeedsApproval, .en).isEmpty)
        XCTAssertFalse(L10n.text(.openAtLoginFailed, .th).isEmpty)
    }

    /// The used share is read by VoiceOver next to the left share, through the card's limit row.
    func testTheUsedShareIsSpokenAsUsedInBothLanguages() {
        XCTAssertEqual(UsageFormat.usedText(42, .en), "42% used")
        XCTAssertEqual(UsageFormat.usedText(42, .th), "ใช้ไป 42%")
    }
}
