import XCTest

final class UsageModelTests: XCTestCase {
    func testSampleDecodesAllThreeAccounts() throws {
        let document = try Fixtures.sample()
        XCTAssertEqual(document.schema, 1)
        XCTAssertEqual(document.generatedAt, Fixtures.now)
        XCTAssertEqual(document.accounts.map(\.provider), ["claude", "codex", "agy"])
        XCTAssertEqual(document.accounts.map(\.label), ["Claude", "ChatGPT", "agy"])
        XCTAssertEqual(document.accounts.map(\.plan), ["Max", "Pro Lite", "free-tier"])
        XCTAssertEqual(document.accounts.map(\.status), ["ok", "ok", "ok"])
        XCTAssertEqual(document.accounts.map { $0.limits.count }, [2, 1, 3])
        XCTAssertEqual(document.accounts[0].credits?.extraUsageEnabled, true)
        XCTAssertEqual(document.accounts[0].credits?.limitUsd, 50)
        XCTAssertEqual(document.accounts[0].limits[0].resetsAt, UsageDate.parse("2026-11-19T06:40:00Z"))
        XCTAssertNil(document.accounts[1].usage?.today?.costUsd)
        XCTAssertNil(document.accounts[2].usage)
        XCTAssertNil(document.accounts[2].credits)
        XCTAssertEqual(document.accounts[1].credits?.balanceUsd, 0)
        XCTAssertNil(document.accounts[0].credits?.balanceUsd)
    }

    func testUnknownFieldsAreIgnored() throws {
        let document = try Fixtures.document("""
        {"schema": 1, "future": {"x": [1, 2]}, "generated_at": "2026-11-19T04:30:00Z",
         "accounts": [{"id": "claude-main", "provider": "claude", "label": "Claude", "plan": "Max",
           "status": "ok", "error": null, "updated_at": "2026-11-19T04:30:00Z", "new_flag": true,
           "limits": [{"key": "five_hour", "label": "5 ชม.", "used_percent": 42, "resets_at": null, "extra": "x"}],
           "usage": {"today": {"tokens": 1200000.0, "cost_usd": 1, "unknown": 3}}, "credits": null}]}
        """)
        XCTAssertEqual(document.accounts.count, 1)
        XCTAssertEqual(document.accounts[0].limits[0].usedPercent, 42)
        XCTAssertNil(document.accounts[0].limits[0].resetsAt)
        XCTAssertEqual(document.accounts[0].usage?.today?.tokens, 1_200_000)
    }

    func testMalformedAccountsAreDroppedAndTheRestKept() throws {
        let document = try Fixtures.document("""
        {"accounts": ["junk", {"provider": "codex", "label": "ChatGPT", "status": "ok", "limits": []}, 42, null]}
        """)
        XCTAssertEqual(document.accounts.map(\.provider), ["codex"])
    }

    func testLimitWithoutNumberIsDroppedAndAccountKept() throws {
        let document = try Fixtures.document("""
        {"accounts": [{"provider": "agy", "label": "agy", "status": "ok",
          "limits": [{"key": "claude", "label": "Claude"}, {"key": "gemini_pro", "label": "Gemini Pro", "used_percent": 10}]}]}
        """)
        XCTAssertEqual(document.accounts.count, 1)
        XCTAssertEqual(document.accounts[0].limits.map(\.key), ["gemini_pro"])
    }

    func testMistypedUsageAndCreditsDoNotDropTheAccount() throws {
        let document = try Fixtures.document("""
        {"accounts": [{"provider": "claude", "label": "Claude", "status": "ok", "usage": "oops", "credits": 7,
          "limits": [{"key": "five_hour", "label": "5 ชม.", "used_percent": 12}]}]}
        """)
        XCTAssertEqual(document.accounts.count, 1)
        XCTAssertNil(document.accounts[0].usage)
        XCTAssertNil(document.accounts[0].credits)
        XCTAssertEqual(document.accounts[0].limits.count, 1)
    }

    func testMissingFieldsGetDefaults() throws {
        let document = try Fixtures.document(#"{"accounts": [{"provider": "codex"}]}"#)
        let account = try XCTUnwrap(document.accounts.first)
        XCTAssertEqual(account.provider, "codex")
        XCTAssertEqual(account.label, "")
        XCTAssertNil(account.plan)
        XCTAssertEqual(account.status, "")
        XCTAssertNil(account.error)
        XCTAssertNil(account.updatedAt)
        XCTAssertTrue(account.limits.isEmpty)
        XCTAssertNil(account.usage)
        XCTAssertNil(account.credits)
    }

    func testMissingAccountsArrayGivesEmptyDocument() throws {
        let document = try Fixtures.document(#"{"schema": 1}"#)
        XCTAssertTrue(document.accounts.isEmpty)
        XCTAssertNil(document.generatedAt)
    }

    func testNullOptionalFieldsAreNil() throws {
        let document = try Fixtures.document("""
        {"accounts": [{"provider": "agy", "label": "agy", "plan": null, "status": "ok", "error": null,
          "updated_at": null, "usage": null, "credits": null,
          "limits": [{"key": "claude", "label": "Claude", "used_percent": 0.0, "resets_at": null}]}]}
        """)
        let account = try XCTUnwrap(document.accounts.first)
        XCTAssertNil(account.plan)
        XCTAssertNil(account.error)
        XCTAssertNil(account.updatedAt)
        XCTAssertNil(account.usage)
        XCTAssertNil(account.credits)
        XCTAssertNil(account.limits[0].resetsAt)
    }

    func testDatesWithAndWithoutFractionalSecondsParse() throws {
        let plain = try XCTUnwrap(UsageDate.parse("2026-11-19T06:40:00Z"))
        let fractional = try XCTUnwrap(UsageDate.parse("2026-11-19T06:40:00.250Z"))
        XCTAssertEqual(fractional.timeIntervalSince(plain), 0.25, accuracy: 0.0001)
        XCTAssertNil(UsageDate.parse("not a date"))
        XCTAssertNil(UsageDate.parse(""))
        XCTAssertNil(UsageDate.parse(nil))
    }

    func testWindowSecondsAndErrorCodeAreReadWhenPresent() throws {
        let document = try Fixtures.document("""
        {"accounts": [{"provider": "claude", "label": "Claude", "status": "stale", "error": "เชื่อมต่อไม่ได้",
          "error_code": "network",
          "limits": [{"key": "five_hour", "label": "5 ชม.", "window_seconds": 18000, "used_percent": 12},
                     {"key": "gemini_pro", "label": "Gemini Pro", "window_seconds": null, "used_percent": 0}]}]}
        """)
        let account = try XCTUnwrap(document.accounts.first)
        XCTAssertEqual(account.errorCode, "network")
        XCTAssertEqual(account.limits.map(\.windowSeconds), [18_000, nil])
        XCTAssertEqual(account.limits.map(\.label), ["5 ชม.", "Gemini Pro"])
    }

    /// A file written before the two fields existed still reads, and the new fields are nil.
    func testOldFilesWithoutTheNewFieldsReadWithNil() throws {
        let document = try Fixtures.document(#"{"accounts": [{"provider": "codex", "label": "ChatGPT", "status": "error", "error": "เชื่อมต่อไม่ได้", "limits": [{"key": "primary", "label": "สัปดาห์", "used_percent": 1}]}]}"#)
        XCTAssertEqual(document.accounts.count, 1)
        XCTAssertNil(document.accounts[0].errorCode)
        XCTAssertNil(document.accounts[0].limits[0].windowSeconds)
    }

    /// A field of the wrong type is ignored, and the account and its limit are kept.
    func testWrongTypeForTheNewFieldsIsIgnoredAndTheRowIsKept() throws {
        let document = try Fixtures.document(#"{"accounts": [{"provider": "codex", "status": "ok", "error_code": 7, "limits": [{"key": "primary", "label": "x", "window_seconds": "week", "used_percent": 1}]}]}"#)
        XCTAssertEqual(document.accounts.count, 1)
        XCTAssertNil(document.accounts[0].errorCode)
        XCTAssertEqual(document.accounts[0].limits.count, 1)
        XCTAssertNil(document.accounts[0].limits[0].windowSeconds)
    }
}
