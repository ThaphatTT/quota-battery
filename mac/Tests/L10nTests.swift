import XCTest

/// The fixed texts, the window labels built from window_seconds, the error texts and their fallbacks. Every
/// expectation is written out by hand, in both languages.
final class L10nTests: XCTestCase {
    // MARK: Every text has both languages

    func testEveryFixedTextHasAThaiAndAnEnglishWording() {
        for key in L10nKey.allCases {
            XCTAssertFalse(L10n.text(key, .th).isEmpty, "Thai text missing for \(key)")
            XCTAssertFalse(L10n.text(key, .en).isEmpty, "English text missing for \(key)")
        }
    }

    /// These wordings are the iPhone widget's (scriptable/AI Usage.js), so both devices read the same.
    func testSharedWordingMatchesTheIPhoneWidget() {
        XCTAssertEqual(L10n.text(.almostOut, .th), "ใกล้หมด")
        XCTAssertEqual(L10n.text(.almostOut, .en), "Almost out")
        XCTAssertEqual(L10n.text(.noData, .th), "ยังไม่มีข้อมูล เปิด Mac ไว้")
        XCTAssertEqual(L10n.text(.noData, .en), "No data yet. Keep your Mac on.")
        XCTAssertEqual(L10n.text(.week, .th), "สัปดาห์")
        XCTAssertEqual(L10n.text(.week, .en), "Week")
        XCTAssertEqual(L10n.text(.noLimitData, .th), "ไม่มีข้อมูล")
        XCTAssertEqual(L10n.text(.noLimitData, .en), "No data")
    }

    func testMoreAccountsWordingsForTheBadge() {
        XCTAssertEqual(L10n.moreAccounts(2, .th), "อีก 2 บัญชี")
        XCTAssertEqual(L10n.moreAccounts(2, .en), "2 more accounts")
        XCTAssertEqual(L10n.moreAccounts(1, .th), "อีก 1 บัญชี")
        XCTAssertEqual(L10n.moreAccounts(1, .en), "1 more account")
    }

    func testAgeResetCreditAndTokenWordings() {
        XCTAssertEqual(L10n.updated("2 นาทีก่อน", .th), "อัปเดต 2 นาทีก่อน")
        XCTAssertEqual(L10n.updated("2 min ago", .en), "Updated 2 min ago")
        XCTAssertEqual(L10n.ago(3, .hour, .th), "3 ชม.ก่อน")
        XCTAssertEqual(L10n.ago(3, .hour, .en), "3 h ago")
        XCTAssertEqual(L10n.ago(1, .day, .th), "1 วันก่อน")
        XCTAssertEqual(L10n.ago(1, .day, .en), "1 d ago")
        XCTAssertEqual(L10n.resetsIn(5, .hour, .th), "รีเซ็ตใน 5 ชม.")
        XCTAssertEqual(L10n.resetsIn(5, .hour, .en), "Resets in 5 h")
        XCTAssertEqual(L10n.credits("0", .th), "เครดิต 0")
        XCTAssertEqual(L10n.credits("0", .en), "Credits 0")
        XCTAssertEqual(L10n.tokens("1.2M", .th), "1.2M token")
        XCTAssertEqual(L10n.tokens("1.2M", .en), "1.2M tokens")
        XCTAssertEqual(L10n.todayTokens("640K", .th), "วันนี้ 640K token")
        XCTAssertEqual(L10n.todayTokens("640K", .en), "Today 640K tokens")
    }

    /// "เหลือ 58%" / "58% left", "ใช้ไป 42%" / "42% used". The iPhone widget uses the same two wordings.
    func testLeftAndUsedWordings() {
        XCTAssertEqual(L10n.percentLeft(58, .th), "เหลือ 58%")
        XCTAssertEqual(L10n.percentLeft(58, .en), "58% left")
        XCTAssertEqual(L10n.percentUsed(42, .th), "ใช้ไป 42%")
        XCTAssertEqual(L10n.percentUsed(42, .en), "42% used")
    }

    /// The VoiceOver form: "<service> <window>, เหลือ N เปอร์เซ็นต์" / "<service> <window>, N percent left".
    func testLimitSpokenReadsServiceWindowAndWhatIsLeft() {
        XCTAssertEqual(L10n.limitSpoken(service: "Claude", window: "5 ชม.", left: 58, .th), "Claude 5 ชม., เหลือ 58 เปอร์เซ็นต์")
        XCTAssertEqual(L10n.limitSpoken(service: "Claude", window: "5h", left: 58, .en), "Claude 5h, 58 percent left")
        XCTAssertEqual(L10n.limitSpoken(service: "agy", window: "", left: 100, .en), "agy, 100 percent left")
        XCTAssertEqual(L10n.limitSpoken(service: "agy", window: "", left: nil, .th), "agy, ไม่มีข้อมูล")
        XCTAssertEqual(L10n.limitSpoken(service: "Claude", window: "5h", left: nil, .en), "Claude 5h, No data")
    }

    func testThePickerWordingsAreShownInEachLanguage() {
        XCTAssertEqual(L10n.text(.languageLabel, .th), "ภาษา")
        XCTAssertEqual(L10n.text(.languageLabel, .en), "Language")
        XCTAssertEqual(L10n.text(.languageSystem, .th), "ตามระบบ")
        XCTAssertEqual(L10n.text(.languageSystem, .en), "System")
        XCTAssertEqual(L10n.text(.languageThai, .en), "ไทย")
        XCTAssertEqual(L10n.text(.languageEnglish, .th), "English")
    }

    func testRefreshingTextAndNoticeTexts() {
        XCTAssertEqual(L10n.text(.refreshing, .th), "กำลังรีเฟรช…")
        XCTAssertEqual(L10n.text(.refreshing, .en), "Refreshing…")
        XCTAssertEqual(L10n.notice(.noNewData, .th), "ยังไม่มีข้อมูลใหม่")
        XCTAssertEqual(L10n.notice(.noNewData, .en), "No new data yet")
        XCTAssertEqual(L10n.notice(.failed(.launchFailed), .th), "รีเฟรชไม่สำเร็จ: เรียก launchctl ไม่ได้")
        XCTAssertEqual(L10n.notice(.failed(.launchFailed), .en), "Refresh failed: could not run launchctl")
        XCTAssertEqual(L10n.notice(.failed(.exitStatus(3)), .th), "รีเฟรชไม่สำเร็จ (launchctl 3)")
        XCTAssertEqual(L10n.notice(.failed(.exitStatus(3)), .en), "Refresh failed (launchctl 3)")
    }

    // MARK: Window labels come from window_seconds and the key

    private func limit(_ json: String) throws -> UsageLimit {
        let document = try Fixtures.document(#"{"accounts": [{"provider": "claude", "status": "ok", "limits": [\#(json)]}]}"#)
        return try XCTUnwrap(document.accounts.first?.limits.first)
    }

    func testFiveHourAndWeekLabels() throws {
        let fiveHour = try limit(#"{"key": "five_hour", "label": "5 ชม.", "window_seconds": 18000, "used_percent": 1}"#)
        XCTAssertEqual(UsageFormat.windowLabel(fiveHour, language: .th), "5 ชม.")
        XCTAssertEqual(UsageFormat.windowLabel(fiveHour, language: .en), "5h")
        let week = try limit(#"{"key": "seven_day", "label": "สัปดาห์", "window_seconds": 604800, "used_percent": 1}"#)
        XCTAssertEqual(UsageFormat.windowLabel(week, language: .th), "สัปดาห์")
        XCTAssertEqual(UsageFormat.windowLabel(week, language: .en), "Week")
    }

    func testOpusAndSonnetVariantsAddTheirNameInBothLanguages() throws {
        let opus = try limit(#"{"key": "seven_day_opus", "label": "Opus สัปดาห์", "window_seconds": 604800, "used_percent": 1}"#)
        XCTAssertEqual(UsageFormat.windowLabel(opus, language: .th), "สัปดาห์ (Opus)")
        XCTAssertEqual(UsageFormat.windowLabel(opus, language: .en), "Week (Opus)")
        let sonnet = try limit(#"{"key": "seven_day_sonnet", "label": "Sonnet สัปดาห์", "window_seconds": 604800, "used_percent": 1}"#)
        XCTAssertEqual(UsageFormat.windowLabel(sonnet, language: .th), "สัปดาห์ (Sonnet)")
        XCTAssertEqual(UsageFormat.windowLabel(sonnet, language: .en), "Week (Sonnet)")
    }

    func testOtherLengthsBecomeMinutesHoursOrDays() throws {
        let fiveMinutes = try limit(#"{"key": "x", "label": "x", "window_seconds": 300, "used_percent": 1}"#)
        XCTAssertEqual(UsageFormat.windowLabel(fiveMinutes, language: .th), "5 นาที")
        XCTAssertEqual(UsageFormat.windowLabel(fiveMinutes, language: .en), "5min")
        let hour = try limit(#"{"key": "x", "label": "x", "window_seconds": 3600, "used_percent": 1}"#)
        XCTAssertEqual(UsageFormat.windowLabel(hour, language: .th), "1 ชม.")
        XCTAssertEqual(UsageFormat.windowLabel(hour, language: .en), "1h")
        let day = try limit(#"{"key": "x", "label": "x", "window_seconds": 86400, "used_percent": 1}"#)
        XCTAssertEqual(UsageFormat.windowLabel(day, language: .th), "1 วัน")
        XCTAssertEqual(UsageFormat.windowLabel(day, language: .en), "1d")
        let twoWeeks = try limit(#"{"key": "x", "label": "x", "window_seconds": 1209600, "used_percent": 1}"#)
        XCTAssertEqual(UsageFormat.windowLabel(twoWeeks, language: .th), "14 วัน")
        XCTAssertEqual(UsageFormat.windowLabel(twoWeeks, language: .en), "14d")
    }

    /// Model groups have no window length (null), so the file's own label is shown in both languages.
    func testModelGroupKeepsItsOwnLabel() throws {
        let group = try limit(#"{"key": "gemini_pro", "label": "Gemini Pro", "window_seconds": null, "used_percent": 0}"#)
        XCTAssertEqual(UsageFormat.windowLabel(group, language: .th), "Gemini Pro")
        XCTAssertEqual(UsageFormat.windowLabel(group, language: .en), "Gemini Pro")
    }

    /// A file written before window_seconds existed: its own label is the fallback.
    func testTheFileLabelIsTheFallbackWhenTheLengthIsMissing() throws {
        let old = try limit(#"{"key": "seven_day", "label": "สัปดาห์", "used_percent": 1}"#)
        XCTAssertEqual(UsageFormat.windowLabel(old, language: .en), "สัปดาห์")
        let noLabel = try limit(#"{"key": "seven_day_opus", "used_percent": 1}"#)
        XCTAssertEqual(UsageFormat.windowLabel(noLabel, language: .en), "seven_day_opus")
    }

    // MARK: Error texts

    /// The wording of every error_code is the iPhone widget's.
    func testEveryErrorCodeHasTheIPhoneWording() {
        let expected: [(code: String, th: String, en: String)] = [
            ("login_expired", "ล็อกอินหมดอายุ", "Sign-in expired"),
            ("relogin_needed", "ต้องล็อกอินใหม่", "Sign in again"),
            ("not_set_up", "ยังไม่มีโปรเจกต์", "No project yet"),
            ("network", "เชื่อมต่อเครือข่ายไม่ได้", "No network connection"),
            ("rate_limited", "ถูกจำกัดการเรียกชั่วคราว", "Rate limited for now"),
            ("server_error", "เซิร์ฟเวอร์มีปัญหา", "Server error"),
            ("unknown", "เกิดข้อผิดพลาดที่ไม่ทราบสาเหตุ", "Unknown error"),
        ]
        for item in expected {
            XCTAssertEqual(L10n.errorWording(item.code, .th), item.th, item.code)
            XCTAssertEqual(L10n.errorWording(item.code, .en), item.en, item.code)
        }
        XCTAssertNil(L10n.errorWording("something_new", .th))
    }

    func testAKnownCodeShowsItsWordingNotTheFileText() {
        let file = "ล็อกอิน Codex หมดอายุ เปิด codex สักครั้ง"
        XCTAssertEqual(L10n.errorMessage(code: "login_expired", fallback: file, .th), "ล็อกอินหมดอายุ")
        XCTAssertEqual(L10n.errorMessage(code: "login_expired", fallback: file, .en), "Sign-in expired")
    }

    /// A code that is not in the table shows the Thai `error` text, in either language.
    func testAnUnrecognisedCodeFallsBackToTheThaiErrorText() {
        for language in [UILanguage.th, .en] {
            XCTAssertEqual(
                L10n.errorMessage(code: "something_new", fallback: "ล็อกอิน agy หมดอายุ", language),
                "ล็อกอิน agy หมดอายุ"
            )
        }
    }

    /// `unknown` is in the table, so it shows the table wording as the iPhone does, even when the file has text.
    func testUnknownCodeShowsItsWordingEvenWhenTheFileHasText() {
        let file = "รีเฟรชโทเคนไม่สำเร็จ"
        XCTAssertEqual(L10n.errorMessage(code: "unknown", fallback: file, .th), "เกิดข้อผิดพลาดที่ไม่ทราบสาเหตุ")
        XCTAssertEqual(L10n.errorMessage(code: "unknown", fallback: file, .en), "Unknown error")
    }

    func testUnknownCodeWithoutFileTextShowsItsWording() {
        XCTAssertEqual(L10n.errorMessage(code: "unknown", fallback: nil, .th), "เกิดข้อผิดพลาดที่ไม่ทราบสาเหตุ")
        XCTAssertEqual(L10n.errorMessage(code: "unknown", fallback: "", .en), "Unknown error")
    }

    func testMissingCodeKeepsTheFileTextAndNoTextMeansNil() {
        XCTAssertEqual(L10n.errorMessage(code: nil, fallback: "ล็อกอิน agy หมดอายุ", .en), "ล็อกอิน agy หมดอายุ")
        XCTAssertNil(L10n.errorMessage(code: nil, fallback: nil, .th))
        XCTAssertNil(L10n.errorMessage(code: nil, fallback: "", .th))
    }

    /// The code from the file reaches the account card in each language.
    func testTheErrorCodeReachesTheCardInEachLanguage() throws {
        let document = try Fixtures.document(#"{"accounts": [{"provider": "codex", "label": "ChatGPT", "status": "error", "error": "ล็อกอิน Codex หมดอายุ เปิด codex สักครั้ง", "error_code": "login_expired", "limits": []}]}"#)
        XCTAssertEqual(UsagePresenter.cards(for: document, now: Fixtures.now, language: .th).first?.errorText, "ล็อกอินหมดอายุ")
        XCTAssertEqual(UsagePresenter.cards(for: document, now: Fixtures.now, language: .en).first?.errorText, "Sign-in expired")
    }
}
