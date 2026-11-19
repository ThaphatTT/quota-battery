import SwiftUI

// MARK: - Language choice and resolution

/// The language the user chose. `system` follows the first preferred language of the device.
enum AppLanguage: String, CaseIterable {
    case system, th, en
}

/// The language a text is drawn in. Only Thai and English exist.
enum UILanguage: String, CaseIterable, Equatable {
    case th, en

    /// `system` is Thai when the preferred language starts with "th", and English for every other language.
    /// An explicit choice ignores the system language. Nothing here reads the device: pass the language in.
    static func resolve(_ choice: AppLanguage, preferred: String?) -> UILanguage {
        switch choice {
        case .th:
            return .th
        case .en:
            return .en
        case .system:
            return (preferred ?? "").lowercased().hasPrefix("th") ? .th : .en
        }
    }

    /// The language in use on this device right now. Only the app and widget roots call this.
    static func current(for choice: AppLanguage) -> UILanguage {
        resolve(choice, preferred: Locale.preferredLanguages.first)
    }
}

private struct UILanguageKey: EnvironmentKey {
    static let defaultValue = UILanguage.current(for: .system)
}

extension EnvironmentValues {
    /// The language for all text in a view tree. Only four roots set it: the app window, the popover, the widget
    /// entry view and the test renders. Every view below them reads it.
    var uiLanguage: UILanguage {
        get { self[UILanguageKey.self] }
        set { self[UILanguageKey.self] = newValue }
    }
}

// MARK: - Refresh notices

/// Why the last refresh did not finish cleanly. The text is made when it is drawn, so it follows the language.
enum RefreshFailure: Equatable {
    case launchFailed
    case exitStatus(Int32)
}

/// What the app says about its last refresh once it has finished. While it runs, `isRefreshing` says so instead.
enum RefreshNotice: Equatable {
    case noNewData
    case failed(RefreshFailure)
}

// MARK: - The texts

/// Every fixed user-facing text on the Mac. The Thai and English wording of the widget texts is the same as the
/// iPhone widget's (scriptable/AI Usage.js, TEXT), wherever the meaning is the same.
enum L10nKey: CaseIterable {
    case usageTitle
    case appName
    case refresh
    case openApp
    case quit
    case openLogFolder
    case showMenuBarIcon
    case notifyAt80And95
    case languageLabel
    case languageSystem
    case languageThai
    case languageEnglish
    case almostOut
    case noData
    case noLimitData
    case allSystemsNormal
    case refreshing
    case noNewData
    case updatedLabel
    case limitsHeader
    case today
    case thisMonth
    case week
    case widgetName
    case widgetDescription
    case refreshFailedLaunch
    case accountsTitle
    case rescan
    case addAccount
    case addClaudeAccount
    case addCodexAccount
    case agyOneAccount
    case sortLabel
    case sortManual
    case sortLowest
    case sortProvider
    case newTag
    case dragToReorder
    case showAccount
    case renameAccount
    case renameHint
    case noAccounts
    case accountOpenedClaude
    case accountOpenedCodex
    case accountTerminalFailed
    case directModeTurnOnAction
    case directModeOn
    case directModeTurnOff
    case directConsentReads
    case directConsentReadsValue
    case directConsentSends
    case directConsentSendsValue
    case directConsentCopy
    case directConsentCopyValue
    case directConsentWarning
    case directConsentCheckbox
    case directConsentCancel
    case directConsentTurnOn
}

enum L10n {
    static func text(_ key: L10nKey, _ language: UILanguage) -> String {
        switch key {
        case .usageTitle:
            return pick("การใช้งาน AI", "AI Usage", language)
        case .appName:
            return "Quota Battery"
        case .refresh:
            return pick("รีเฟรช", "Refresh", language)
        case .openApp:
            return pick("เปิดแอป", "Open app", language)
        case .quit:
            return pick("ออก (Quit)", "Quit", language)
        case .openLogFolder:
            return pick("เปิดโฟลเดอร์ log", "Open log folder", language)
        case .showMenuBarIcon:
            return pick("แสดงไอคอนบนแถบเมนู", "Show menu bar icon", language)
        case .notifyAt80And95:
            return pick("แจ้งเตือนที่ 80% และ 95%", "Notify at 80% and 95%", language)
        case .languageLabel:
            return pick("ภาษา", "Language", language)
        case .languageSystem:
            return pick("ตามระบบ", "System", language)
        case .languageThai:
            return "ไทย"
        case .languageEnglish:
            return "English"
        case .almostOut:
            return pick("ใกล้หมด", "Almost out", language)
        case .noData:
            return pick("ยังไม่มีข้อมูล เปิด Mac ไว้", "No data yet. Keep your Mac on.", language)
        case .noLimitData:
            return pick("ไม่มีข้อมูล", "No data", language)
        case .allSystemsNormal:
            return pick("ระบบออนไลน์ปกติ", "All systems normal", language)
        case .refreshing:
            return pick("กำลังรีเฟรช…", "Refreshing…", language)
        case .noNewData:
            return pick("ยังไม่มีข้อมูลใหม่", "No new data yet", language)
        case .updatedLabel:
            return pick("อัปเดต", "Updated", language)
        case .limitsHeader:
            return pick("ขีดจำกัดปัจจุบัน", "Current limits", language)
        case .today:
            return pick("วันนี้", "Today", language)
        case .thisMonth:
            return pick("เดือนนี้", "This month", language)
        case .week:
            return pick("สัปดาห์", "Week", language)
        case .widgetName:
            return "Quota Battery"
        case .widgetDescription:
            return pick(
                "โควตาการใช้งาน Claude, ChatGPT และ agy",
                "AI usage quotas for Claude, ChatGPT and agy",
                language
            )
        case .refreshFailedLaunch:
            return pick("รีเฟรชไม่สำเร็จ: เรียก launchctl ไม่ได้", "Refresh failed: could not run launchctl", language)
        case .accountsTitle:
            return pick("บัญชี", "Accounts", language)
        case .rescan:
            return pick("สแกนใหม่", "Rescan", language)
        case .addAccount:
            return pick("เพิ่มบัญชี", "Add account", language)
        case .addClaudeAccount:
            return "Claude Code"
        case .addCodexAccount:
            return "Codex (ChatGPT)"
        case .agyOneAccount:
            return pick("agy มีบัญชีเดียว (ตามโควตาของ agy)", "agy has one account (its own limit)", language)
        case .sortLabel:
            return pick("เรียงลำดับ", "Sort order", language)
        case .sortManual:
            return pick("เรียงเอง", "Manual", language)
        case .sortLowest:
            return pick("ใกล้หมดก่อน", "Lowest left first", language)
        case .sortProvider:
            return pick("ตามบริการ", "By service", language)
        case .newTag:
            return pick("ใหม่", "New", language)
        case .dragToReorder:
            return pick("ลากเพื่อเรียงลำดับ", "Drag to reorder", language)
        case .showAccount:
            return pick("แสดงบัญชีนี้", "Show this account", language)
        case .renameAccount:
            return pick("ชื่อที่แสดง", "Display name", language)
        case .renameHint:
            return pick("กดเพื่อเปลี่ยนชื่อ", "Tap to rename", language)
        case .noAccounts:
            return pick(
                "ยังไม่พบบัญชี กดสแกนใหม่หลังล็อกอินแล้ว",
                "No accounts found yet. Press Rescan after you sign in.",
                language
            )
        case .accountOpenedClaude:
            return pick(
                "เปิด Terminal แล้ว พิมพ์ /login ใน Claude Code แล้วกดสแกนใหม่",
                "Terminal is open. Type /login in Claude Code, then press Rescan.",
                language
            )
        case .accountOpenedCodex:
            return pick(
                "เปิด Terminal แล้ว ล็อกอินให้เสร็จ แล้วกดสแกนใหม่",
                "Terminal is open. Finish signing in, then press Rescan.",
                language
            )
        case .accountTerminalFailed:
            return pick(
                "เปิด Terminal ไม่ได้ อนุญาตให้ Quota Battery ควบคุม Terminal ในการตั้งค่าระบบ",
                "Could not open Terminal. Allow Quota Battery to control Terminal in System Settings.",
                language
            )
        case .directModeTurnOnAction:
            return pick("เปิดโหมดโดยตรง…", "Turn on direct mode…", language)
        case .directModeOn:
            return pick("โหมดโดยตรง: เปิดอยู่", "Direct mode: on", language)
        case .directModeTurnOff:
            return pick("ปิด", "Turn off", language)
        case .directConsentReads:
            return pick("อ่าน", "Reads", language)
        case .directConsentReadsValue:
            return pick("การล็อกอินของ CLI บน Mac เครื่องนี้", "The CLI's own login on this Mac", language)
        case .directConsentSends:
            return pick("ส่งไปที่", "Sends to", language)
        case .directConsentSendsValue:
            return pick("ผู้ให้บริการเท่านั้น", "The provider only", language)
        case .directConsentCopy:
            return pick("สำเนา", "Copy", language)
        case .directConsentCopyValue:
            return pick("ไม่เก็บสำเนาข้อมูลล็อกอินไว้", "No copy of the login is kept", language)
        case .directConsentWarning:
            return pick(
                "นี่เป็นช่องทางที่ไม่เป็นทางการ อาจใช้งานไม่ได้ หรือขัดกับข้อกำหนดของผู้ให้บริการ คุณใช้บัญชีด้วยความเสี่ยงของตนเอง",
                "This is an unofficial channel. It may stop working or conflict with the provider's terms. You use your account at your own risk.",
                language
            )
        case .directConsentCheckbox:
            return pick("ฉันเข้าใจและยินยอมตามข้อความด้านบน", "I understand and consent to the above", language)
        case .directConsentCancel:
            return pick("ยกเลิก", "Cancel", language)
        case .directConsentTurnOn:
            return pick("เปิดใช้งาน", "Turn on", language)
        }
    }

    /// "อัปเดต 2 นาทีก่อน" / "Updated 2 min ago".
    static func updated(_ ago: String, _ language: UILanguage) -> String {
        text(.updatedLabel, language) + " " + ago
    }

    /// "2 นาทีก่อน", "1 ชม.ก่อน", "1 วันก่อน" / "2 min ago", "1 h ago", "1 d ago".
    static func ago(_ value: Int, _ unit: TimeSpanUnit, _ language: UILanguage) -> String {
        switch language {
        case .th:
            return "\(value) " + thaiAgoUnit(unit)
        case .en:
            return "\(value) " + englishUnit(unit) + " ago"
        }
    }

    /// "รีเซ็ตใน 5 ชม." / "Resets in 5 h".
    static func resetsIn(_ value: Int, _ unit: TimeSpanUnit, _ language: UILanguage) -> String {
        switch language {
        case .th:
            return "รีเซ็ตใน \(value) " + thaiUnit(unit)
        case .en:
            return "Resets in \(value) " + englishUnit(unit)
        }
    }

    /// A length as a window label: "5 ชม." / "5h", "3 วัน" / "3d", "30 นาที" / "30min".
    static func windowDuration(_ value: Int, _ unit: TimeSpanUnit, _ language: UILanguage) -> String {
        switch language {
        case .th:
            return "\(value) " + thaiUnit(unit)
        case .en:
            return "\(value)" + englishUnit(unit)
        }
    }

    /// "เปิดโหมดอ่านรหัสโดยตรง · ChatGPT" / "Turn on direct mode · ChatGPT". The service is the provider's name.
    static func directConsentTitle(service: String, _ language: UILanguage) -> String {
        pick("เปิดโหมดอ่านรหัสโดยตรง · \(service)", "Turn on direct mode · \(service)", language)
    }

    /// "อีก 2 บัญชี" / "2 more accounts", and "1 more account". The spoken text of the "+N" badge.
    static func moreAccounts(_ count: Int, _ language: UILanguage) -> String {
        switch language {
        case .th:
            return "อีก \(count) บัญชี"
        case .en:
            return count == 1 ? "1 more account" : "\(count) more accounts"
        }
    }

    /// "เครดิต 0" / "Credits 0".
    static func credits(_ number: String, _ language: UILanguage) -> String {
        switch language {
        case .th:
            return "เครดิต \(number)"
        case .en:
            return "Credits \(number)"
        }
    }

    /// "1.2M token" / "1.2M tokens".
    static func tokens(_ number: String, _ language: UILanguage) -> String {
        switch language {
        case .th:
            return "\(number) token"
        case .en:
            return "\(number) tokens"
        }
    }

    /// "วันนี้ 1.2M token" / "Today 1.2M tokens".
    static func todayTokens(_ number: String, _ language: UILanguage) -> String {
        text(.today, language) + " " + tokens(number, language)
    }

    /// "เหลือ 58%" / "58% left": what is left, as a whole percent.
    static func percentLeft(_ value: Int, _ language: UILanguage) -> String {
        switch language {
        case .th:
            return "เหลือ \(value)%"
        case .en:
            return "\(value)% left"
        }
    }

    /// "ใช้ไป 42%" / "42% used": what is used, as a whole percent.
    static func percentUsed(_ value: Int, _ language: UILanguage) -> String {
        switch language {
        case .th:
            return "ใช้ไป \(value)%"
        case .en:
            return "\(value)% used"
        }
    }

    /// The VoiceOver text of a limit: "Claude 5 ชม., เหลือ 58 เปอร์เซ็นต์" / "Claude 5h, 58 percent left". An empty window
    /// leaves the window out. Without a number it reads "Claude, ไม่มีข้อมูล" / "Claude, No data".
    static func limitSpoken(service: String, window: String, left: Int?, _ language: UILanguage) -> String {
        let head = window.isEmpty ? service : "\(service) \(window)"
        guard let left else {
            return "\(head), " + text(.noLimitData, language)
        }
        switch language {
        case .th:
            return "\(head), เหลือ \(left) เปอร์เซ็นต์"
        case .en:
            return "\(head), \(left) percent left"
        }
    }

    /// The text of a refresh notice.
    static func notice(_ notice: RefreshNotice, _ language: UILanguage) -> String {
        switch notice {
        case .noNewData:
            return text(.noNewData, language)
        case .failed(.launchFailed):
            return text(.refreshFailedLaunch, language)
        case .failed(.exitStatus(let status)):
            switch language {
            case .th:
                return "รีเฟรชไม่สำเร็จ (launchctl \(status))"
            case .en:
                return "Refresh failed (launchctl \(status))"
            }
        }
    }

    /// The wording of an error_code. Nil for a code that is not in the table.
    static func errorWording(_ code: String, _ language: UILanguage) -> String? {
        switch code {
        case "login_expired":
            return pick("ล็อกอินหมดอายุ", "Sign-in expired", language)
        case "relogin_needed":
            return pick("ต้องล็อกอินใหม่", "Sign in again", language)
        case "not_set_up":
            return pick("ยังไม่มีโปรเจกต์", "No project yet", language)
        case "network":
            return pick("เชื่อมต่อเครือข่ายไม่ได้", "No network connection", language)
        case "rate_limited":
            return pick("ถูกจำกัดการเรียกชั่วคราว", "Rate limited for now", language)
        case "server_error":
            return pick("เซิร์ฟเวอร์มีปัญหา", "Server error", language)
        case "unknown":
            return pick("เกิดข้อผิดพลาดที่ไม่ทราบสาเหตุ", "Unknown error", language)
        default:
            return nil
        }
    }

    /// The text for an account's error, the same rule as the iPhone widget. A code in the table shows its wording,
    /// `unknown` included. Any other or missing code shows the Thai `error`, and nil when the file has none.
    static func errorMessage(code: String?, fallback: String?, _ language: UILanguage) -> String? {
        let file = fallback.flatMap { $0.isEmpty ? nil : $0 }
        guard let code else { return file }
        if let wording = errorWording(code, language) {
            return wording
        }
        return file
    }

    private static func pick(_ th: String, _ en: String, _ language: UILanguage) -> String {
        language == .th ? th : en
    }

    private static func thaiAgoUnit(_ unit: TimeSpanUnit) -> String {
        switch unit {
        case .minute: return "นาทีก่อน"
        case .hour: return "ชม.ก่อน"
        case .day: return "วันก่อน"
        }
    }

    private static func thaiUnit(_ unit: TimeSpanUnit) -> String {
        switch unit {
        case .minute: return "นาที"
        case .hour: return "ชม."
        case .day: return "วัน"
        }
    }

    private static func englishUnit(_ unit: TimeSpanUnit) -> String {
        switch unit {
        case .minute: return "min"
        case .hour: return "h"
        case .day: return "d"
        }
    }
}
