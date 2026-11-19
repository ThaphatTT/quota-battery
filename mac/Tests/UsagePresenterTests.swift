import XCTest

final class UsagePresenterTests: XCTestCase {
    func testSampleTitlesAndTrailingText() throws {
        let cards = UsagePresenter.cards(for: try Fixtures.sample(), now: Fixtures.now, language: .th)
        XCTAssertEqual(cards.map(\.title), ["Claude · Max", "ChatGPT · Pro Lite", "agy · free-tier"])
        XCTAssertEqual(cards.map(\.trailing), ["อัปเดต 1 นาทีก่อน", "อัปเดต 1 นาทีก่อน", "อัปเดต 1 นาทีก่อน"])
        XCTAssertEqual(cards.map(\.trailingIsTag), [false, false, false])
    }

    func testSampleMetaLinesOmitMissingParts() throws {
        let cards = UsagePresenter.cards(for: try Fixtures.sample(), now: Fixtures.now, language: .th)
        XCTAssertEqual(cards[0].meta, "รีเซ็ตใน 2 ชม. · วันนี้ 1.2M token · ~$18.40 · Extra usage $0.00 / $50.00")
        XCTAssertEqual(cards[1].meta, "รีเซ็ตใน 22 ชม. · เครดิต 0 · วันนี้ 640K token")
        XCTAssertEqual(cards[2].meta, "รีเซ็ตใน 5 ชม.")
    }

    func testSampleRowsKeepFileOrderLeftUsedAndTier() throws {
        let cards = UsagePresenter.cards(for: try Fixtures.sample(), now: Fixtures.now, language: .th)
        XCTAssertEqual(cards[0].rows.map(\.label), ["5 ชม.", "สัปดาห์"])
        XCTAssertEqual(cards[0].rows.map(\.leftText), ["เหลือ 58%", "เหลือ 33%"])
        XCTAssertEqual(cards[0].rows.map(\.usedText), ["ใช้ไป 42%", "ใช้ไป 67%"])
        XCTAssertEqual(cards[0].rows.map(\.tier), [.plenty, .plenty])
        XCTAssertEqual(cards[1].rows[0].leftText, "เหลือ 7%")
        XCTAssertTrue(cards[1].rows[0].isAlert)
        XCTAssertEqual(cards[1].rows[0].tier, .low)
        XCTAssertEqual(cards[2].rows.map(\.label), ["Claude", "Gemini Pro", "Gemini Flash"])
    }

    func testRowsReadTheServiceWindowAndWhatIsLeft() throws {
        let sample = try Fixtures.sample()
        let thai = UsagePresenter.cards(for: sample, now: Fixtures.now, language: .th)
        XCTAssertEqual(thai[0].rows.map(\.accessibilityText), ["Claude 5 ชม., เหลือ 58 เปอร์เซ็นต์", "Claude สัปดาห์, เหลือ 33 เปอร์เซ็นต์"])
        let english = UsagePresenter.cards(for: sample, now: Fixtures.now, language: .en)
        XCTAssertEqual(english[0].rows.map(\.accessibilityText), ["Claude 5h, 58 percent left", "Claude Week, 33 percent left"])
    }

    /// A stale account reads its error text as well, on its first row and in the popover row.
    func testStaleAccountSpeaksItsErrorText() throws {
        let document = try Fixtures.document("""
        {"accounts": [{"provider": "agy", "label": "agy", "status": "stale", "error": "ล็อกอิน agy หมดอายุ",
          "updated_at": "2026-11-19T04:00:00Z",
          "limits": [{"key": "claude", "label": "Claude", "used_percent": 85, "resets_at": "2026-11-19T09:21:41Z"}]}]}
        """)
        let rows = UsagePresenter.largeRows(for: UsagePresenter.cards(for: document, now: Fixtures.now, language: .th), language: .th)
        XCTAssertEqual(rows.map(\.spokenText), ["agy Claude, เหลือ 15 เปอร์เซ็นต์, ล็อกอิน agy หมดอายุ"])
        let account = try XCTUnwrap(document.accounts.first)
        XCTAssertEqual(
            AppUsageInsights.popoverSpokenText(account, now: Fixtures.now, language: .th),
            "agy Claude, เหลือ 15 เปอร์เซ็นต์, ล็อกอิน agy หมดอายุ"
        )
    }

    /// An error account with no limits reads "no data" and its error text. A healthy row reads only its label.
    func testErrorAccountWithoutLimitsSpeaksNoDataAndItsError() throws {
        let document = try Fixtures.document(#"{"accounts": [{"provider": "codex", "label": "ChatGPT", "status": "error", "error": "ล็อกอิน Codex หมดอายุ", "limits": []}]}"#)
        let account = try XCTUnwrap(document.accounts.first)
        XCTAssertEqual(
            AppUsageInsights.popoverSpokenText(account, now: Fixtures.now, language: .th),
            "ChatGPT, ไม่มีข้อมูล, ล็อกอิน Codex หมดอายุ"
        )
        let healthy = try Fixtures.sample()
        // The popover row names the most used limit (the week, 67% used), so it reads 33% left.
        XCTAssertEqual(
            AppUsageInsights.popoverSpokenText(healthy.accounts[0], now: Fixtures.now, language: .th),
            "Claude สัปดาห์, เหลือ 33 เปอร์เซ็นต์"
        )
        XCTAssertEqual(
            UsagePresenter.cards(for: healthy, now: Fixtures.now, language: .th)[0].rows.map(\.spokenText),
            ["Claude 5 ชม., เหลือ 58 เปอร์เซ็นต์", "Claude สัปดาห์, เหลือ 33 เปอร์เซ็นต์"]
        )
    }

    func testSmallLinesUseTheMostImportantLimitAndShowWhatIsLeft() throws {
        let lines = UsagePresenter.smallLines(for: try Fixtures.sample(), language: .th)
        XCTAssertEqual(lines.map(\.name), ["Claude", "ChatGPT", "agy"])
        XCTAssertEqual(lines.map(\.windowLabel), ["5 ชม.", "สัปดาห์", "Claude"])
        XCTAssertEqual(lines.map(\.numberText), ["58", "7", "100"])
        XCTAssertEqual(lines.map(\.tier), [.plenty, .low, .plenty])
        XCTAssertEqual(lines.map(\.accessibilityText), [
            "Claude 5 ชม., เหลือ 58 เปอร์เซ็นต์",
            "ChatGPT สัปดาห์, เหลือ 7 เปอร์เซ็นต์",
            "agy Claude, เหลือ 100 เปอร์เซ็นต์",
        ])
    }

    func testErrorAccountShowsTagAndErrorAndNoRows() throws {
        let document = try Fixtures.document("""
        {"accounts": [{"provider": "codex", "label": "ChatGPT", "plan": null, "status": "error",
          "error": "ล็อกอิน Codex หมดอายุ เปิด codex สักครั้ง", "updated_at": null,
          "limits": [], "usage": null, "credits": null}]}
        """)
        let card = try XCTUnwrap(UsagePresenter.cards(for: document, now: Fixtures.now, language: .th).first)
        XCTAssertEqual(card.title, "ChatGPT")
        XCTAssertEqual(card.trailing, "Codex CLI")
        XCTAssertTrue(card.trailingIsTag)
        XCTAssertTrue(card.rows.isEmpty)
        XCTAssertNil(card.meta)
        XCTAssertEqual(card.errorText, "ล็อกอิน Codex หมดอายุ เปิด codex สักครั้ง")
        let ring = try XCTUnwrap(UsagePresenter.smallLines(for: document, language: .th).first)
        XCTAssertEqual(ring.numberText, "—")
        XCTAssertNil(ring.usedPercent)
        XCTAssertEqual(ring.tier, .plenty)
        XCTAssertEqual(ring.accessibilityText, "ChatGPT, ไม่มีข้อมูล")
    }

    func testStaleAccountKeepsRowsAndShowsItsError() throws {
        let document = try Fixtures.document("""
        {"accounts": [{"provider": "agy", "label": "agy", "plan": "free-tier", "status": "stale",
          "error": "ล็อกอิน agy หมดอายุ", "updated_at": "2026-11-19T04:00:00Z", "usage": null, "credits": null,
          "limits": [{"key": "claude", "label": "Claude", "used_percent": 85, "resets_at": "2026-11-19T09:21:41Z"}]}]}
        """)
        let card = try XCTUnwrap(UsagePresenter.cards(for: document, now: Fixtures.now, language: .th).first)
        XCTAssertEqual(card.trailing, "อัปเดต 30 นาทีก่อน")
        XCTAssertFalse(card.trailingIsTag)
        XCTAssertEqual(card.rows.map(\.leftText), ["เหลือ 15%"])
        XCTAssertTrue(card.rows[0].isAlert)
        XCTAssertEqual(card.rows[0].tier, .low)
        XCTAssertEqual(card.errorText, "ล็อกอิน agy หมดอายุ")
        XCTAssertEqual(card.meta, "รีเซ็ตใน 5 ชม.")
    }

    func testOkAccountWithoutUpdateTimeShowsTheProviderTag() throws {
        let document = try Fixtures.document(#"{"accounts": [{"provider": "claude", "label": "Claude", "status": "ok", "limits": []}]}"#)
        let card = try XCTUnwrap(UsagePresenter.cards(for: document, now: Fixtures.now, language: .th).first)
        XCTAssertEqual(card.trailing, "Claude Code")
        XCTAssertTrue(card.trailingIsTag)
    }

    func testMissingLabelAndBlankPlanFallBack() throws {
        let document = try Fixtures.document(#"{"accounts": [{"provider": "codex", "status": "ok", "plan": "  "}]}"#)
        let card = try XCTUnwrap(UsagePresenter.cards(for: document, now: Fixtures.now, language: .th).first)
        XCTAssertEqual(card.title, "ChatGPT")
    }

    func testMetaLineShowsOnlyThePartsThatExist() throws {
        let document = try Fixtures.document("""
        {"accounts": [
          {"provider": "codex", "label": "ChatGPT", "status": "ok", "updated_at": "2026-11-19T04:30:00Z",
           "limits": [], "usage": {"today": {"tokens": 850, "cost_usd": null}},
           "credits": {"extra_usage_enabled": false, "used_usd": 0, "limit_usd": 50}},
          {"provider": "claude", "label": "Claude", "status": "ok", "updated_at": "2026-11-19T04:30:00Z",
           "limits": [], "usage": {"today": {"tokens": null, "cost_usd": 2.5}},
           "credits": {"extra_usage_enabled": true, "used_usd": 3, "limit_usd": null}}
        ]}
        """)
        let cards = UsagePresenter.cards(for: document, now: Fixtures.now, language: .th)
        XCTAssertEqual(cards[0].meta, "วันนี้ 850 token")
        XCTAssertEqual(cards[1].meta, "~$2.50 · Extra usage $3.00")
    }

    func testResetPartUsesTheFirstLimitWithAFutureReset() throws {
        let document = try Fixtures.document("""
        {"accounts": [{"provider": "claude", "label": "Claude", "status": "ok", "updated_at": "2026-11-19T04:30:00Z",
          "limits": [
            {"key": "old", "label": "old", "used_percent": 1, "resets_at": "2026-11-19T01:00:00Z"},
            {"key": "five_hour", "label": "5 ชม.", "used_percent": 2, "resets_at": "2026-11-19T06:40:00Z"}]}]}
        """)
        let card = try XCTUnwrap(UsagePresenter.cards(for: document, now: Fixtures.now, language: .th).first)
        XCTAssertEqual(card.meta, "รีเซ็ตใน 2 ชม.")
    }

    func testCreditsSitRightAfterTheResetPart() throws {
        let document = try Fixtures.document("""
        {"accounts": [{"provider": "codex", "label": "ChatGPT", "status": "ok", "updated_at": "2026-11-19T04:30:00Z",
          "limits": [{"key": "five_hour", "label": "5 ชม.", "used_percent": 2, "resets_at": "2026-11-19T06:40:00Z"}],
          "usage": {"today": {"tokens": 850, "cost_usd": null}},
          "credits": {"extra_usage_enabled": false, "used_usd": null, "limit_usd": null, "balance_usd": 12.5}}]}
        """)
        let card = try XCTUnwrap(UsagePresenter.cards(for: document, now: Fixtures.now, language: .th).first)
        XCTAssertEqual(card.meta, "รีเซ็ตใน 2 ชม. · เครดิต 12.5 · วันนี้ 850 token")
    }

    func testZeroCreditsAreShownEvenWithoutAReset() throws {
        let document = try Fixtures.document(#"{"accounts": [{"provider": "codex", "label": "ChatGPT", "status": "ok", "limits": [], "credits": {"balance_usd": 0}}]}"#)
        let card = try XCTUnwrap(UsagePresenter.cards(for: document, now: Fixtures.now, language: .th).first)
        XCTAssertEqual(card.meta, "เครดิต 0")
    }

    func testNullCreditBalanceIsOmitted() throws {
        let document = try Fixtures.document(#"{"accounts": [{"provider": "claude", "label": "Claude", "status": "ok", "limits": [], "credits": {"balance_usd": null}}]}"#)
        let card = try XCTUnwrap(UsagePresenter.cards(for: document, now: Fixtures.now, language: .th).first)
        XCTAssertNil(card.meta)
    }

    func testNoMetaLineWhenNothingExists() throws {
        let document = try Fixtures.document(#"{"accounts": [{"provider": "agy", "label": "agy", "status": "ok", "limits": []}]}"#)
        let card = try XCTUnwrap(UsagePresenter.cards(for: document, now: Fixtures.now, language: .th).first)
        XCTAssertNil(card.meta)
    }

    // MARK: English

    /// The same sample in English: the labels come from window_seconds, and the times and tokens use the iPhone's words.
    func testEnglishSampleLabelsTrailingAndMeta() throws {
        let cards = UsagePresenter.cards(for: try Fixtures.sample(), now: Fixtures.now, language: .en)
        XCTAssertEqual(cards.map(\.trailing), ["Updated 1 min ago", "Updated 1 min ago", "Updated 1 min ago"])
        XCTAssertEqual(cards[0].rows.map(\.label), ["5h", "Week"])
        XCTAssertEqual(cards[2].rows.map(\.label), ["Claude", "Gemini Pro", "Gemini Flash"])
        XCTAssertEqual(cards[0].meta, "Resets in 2 h · Today 1.2M tokens · ~$18.40 · Extra usage $0.00 / $50.00")
        XCTAssertEqual(cards[1].meta, "Resets in 22 h · Credits 0 · Today 640K tokens")
        XCTAssertEqual(cards[2].meta, "Resets in 5 h")
        XCTAssertEqual(UsagePresenter.smallLines(for: try Fixtures.sample(), language: .en).map(\.windowLabel),
                       ["5h", "Week", "Claude"])
    }

    func testEnglishMediumRowsNameTheHighestWindow() throws {
        let rows = UsagePresenter.mediumRows(
            for: UsagePresenter.cards(for: try Fixtures.sample(), now: Fixtures.now, language: .en),
            language: .en
        )
        XCTAssertEqual(rows.map(\.subtitle), ["Week (Resets in 5 d)", "Week (Resets in 22 h)", "Claude (Resets in 5 h)"])
    }

    func testEnglishPlaceholderRowSaysNoData() throws {
        let document = try Fixtures.document(#"{"accounts": [{"provider": "claude", "label": "Claude", "status": "ok", "limits": []}]}"#)
        let rows = UsagePresenter.largeRows(for: UsagePresenter.cards(for: document, now: Fixtures.now, language: .en), language: .en)
        XCTAssertEqual(rows.map(\.subtitle), ["No data"])
        let thai = UsagePresenter.largeRows(for: UsagePresenter.cards(for: document, now: Fixtures.now, language: .th), language: .th)
        XCTAssertEqual(thai.map(\.subtitle), ["ไม่มีข้อมูล"])
    }

    // MARK: Large widget rows

    func testLargeRowsShowTheFiveHighestAndKeepFileOrder() throws {
        let rows = UsagePresenter.largeRows(
            for: UsagePresenter.cards(for: try Fixtures.sample(), now: Fixtures.now, language: .th),
            language: .th
        )
        XCTAssertEqual(rows.map(\.title), ["Claude · 5 ชม.", "Claude · สัปดาห์", "ChatGPT · สัปดาห์", "agy · Claude", "agy · Gemini Pro"])
        XCTAssertEqual(Set(rows.map(\.id)).count, 5)
    }

    func testLargeRowSubtitleIsTheResetTextPlusCredit() throws {
        let rows = UsagePresenter.largeRows(
            for: UsagePresenter.cards(for: try Fixtures.sample(), now: Fixtures.now, language: .th),
            language: .th
        )
        XCTAssertEqual(rows.map(\.subtitle), ["รีเซ็ตใน 2 ชม.", "รีเซ็ตใน 5 วัน", "รีเซ็ตใน 22 ชม. · เครดิต 0", "รีเซ็ตใน 5 ชม.", "รีเซ็ตใน 5 ชม."])
        XCTAssertEqual(rows.map(\.subtitleIsError), [false, false, false, false, false])
    }

    /// The pill is on each row that is yellow or red, and its colour is that row's tier.
    func testPillGoesOnEveryYellowOrRedRow() throws {
        let document = try Fixtures.document("""
        {"accounts": [
          {"provider": "codex", "label": "ChatGPT", "status": "ok", "updated_at": "2026-11-19T04:30:00Z",
           "limits": [{"key": "a", "label": "5 ชม.", "used_percent": 85, "resets_at": null},
                      {"key": "b", "label": "สัปดาห์", "used_percent": 90, "resets_at": null}]},
          {"provider": "claude", "label": "Claude", "status": "ok", "updated_at": "2026-11-19T04:30:00Z",
           "limits": [{"key": "c", "label": "5 ชม.", "used_percent": 79.9, "resets_at": null}]}
        ]}
        """)
        let cards = UsagePresenter.cards(for: document, now: Fixtures.now, language: .th)
        XCTAssertEqual(UsagePresenter.largeRows(for: cards, language: .th).map(\.isAlert), [true, true, false])
        XCTAssertEqual(UsagePresenter.largeRows(for: cards, language: .th).map(\.showsNearFull), [true, true, false])
        XCTAssertEqual(UsagePresenter.largeRows(for: cards, language: .th).map(\.tier), [.low, .low, .plenty])
        XCTAssertEqual(UsagePresenter.mediumRows(for: cards, language: .th).map(\.showsNearFull), [true, false])
    }

    func testAccountWithNoLimitsKeepsItsRowWhenTheWidgetIsFull() throws {
        let document = try Fixtures.document("""
        {"accounts": [
          {"provider": "claude", "label": "Claude", "status": "ok", "updated_at": "2026-11-19T04:30:00Z",
           "limits": [
             {"key": "a", "label": "1", "used_percent": 10}, {"key": "b", "label": "2", "used_percent": 20},
             {"key": "c", "label": "3", "used_percent": 30}, {"key": "d", "label": "4", "used_percent": 40},
             {"key": "e", "label": "5", "used_percent": 50}, {"key": "f", "label": "6", "used_percent": 60}]},
          {"provider": "agy", "label": "agy", "status": "error", "error": "ล็อกอิน agy หมดอายุ", "limits": []}
        ]}
        """)
        let rows = UsagePresenter.largeRows(for: UsagePresenter.cards(for: document, now: Fixtures.now, language: .th), language: .th)
        XCTAssertEqual(rows.map(\.title), ["Claude · 3", "Claude · 4", "Claude · 5", "Claude · 6", "agy"])
        XCTAssertEqual(rows.last?.subtitle, "ล็อกอิน agy หมดอายุ")
        XCTAssertEqual(rows.last?.subtitleIsError, true)
        XCTAssertEqual(rows.last?.hasUsage, false)
    }

    func testStaleErrorReplacesTheResetTextOnItsFirstShownRow() throws {
        let document = try Fixtures.document("""
        {"accounts": [{"provider": "agy", "label": "agy", "status": "stale", "error": "ล็อกอิน agy หมดอายุ",
          "updated_at": "2026-11-19T04:00:00Z",
          "limits": [{"key": "claude", "label": "Claude", "used_percent": 85, "resets_at": "2026-11-19T09:21:41Z"},
                     {"key": "gemini", "label": "Gemini Pro", "used_percent": 10, "resets_at": "2026-11-19T09:21:41Z"}]}]}
        """)
        let rows = UsagePresenter.largeRows(for: UsagePresenter.cards(for: document, now: Fixtures.now, language: .th), language: .th)
        XCTAssertEqual(rows.map(\.subtitle), ["ล็อกอิน agy หมดอายุ", "รีเซ็ตใน 5 ชม."])
        XCTAssertEqual(rows.map(\.subtitleIsError), [true, false])
        XCTAssertEqual(rows.map(\.showsNearFull), [true, false])
    }

    // MARK: Medium widget rows and small rings

    func testMediumRowsShowTheHighestLimitOfEachAccount() throws {
        let rows = UsagePresenter.mediumRows(
            for: UsagePresenter.cards(for: try Fixtures.sample(), now: Fixtures.now, language: .th),
            language: .th
        )
        XCTAssertEqual(rows.map(\.title), ["Claude", "ChatGPT", "agy"])
        XCTAssertEqual(rows.map(\.subtitle), ["สัปดาห์ (รีเซ็ตใน 5 วัน)", "สัปดาห์ (รีเซ็ตใน 22 ชม.)", "Claude (รีเซ็ตใน 5 ชม.)"])
        XCTAssertEqual(rows.map(\.leftText), ["เหลือ 33%", "เหลือ 7%", "เหลือ 100%"])
        XCTAssertEqual(rows.map(\.showsNearFull), [false, true, false])
    }

    func testMediumShowsTheErrorTextForAnAccountWithoutLimits() throws {
        let document = try Fixtures.document(#"{"accounts": [{"provider": "codex", "label": "ChatGPT", "status": "error", "error": "ล็อกอิน Codex หมดอายุ", "limits": []}]}"#)
        let rows = UsagePresenter.mediumRows(for: UsagePresenter.cards(for: document, now: Fixtures.now, language: .th), language: .th)
        XCTAssertEqual(rows.map(\.title), ["ChatGPT"])
        XCTAssertEqual(rows.map(\.subtitle), ["ล็อกอิน Codex หมดอายุ"])
        XCTAssertEqual(rows.map(\.hasUsage), [false])
    }

    func testSmallRingsShowWhatIsLeftAndTheUpdateAge() throws {
        let document = try Fixtures.sample()
        let lines = UsagePresenter.smallLines(for: document, language: .th)
        XCTAssertEqual(lines.map(\.numberText), ["58", "7", "100"])
        XCTAssertEqual(lines.map(\.usedPercent), [42, 93, 0])
        XCTAssertEqual(
            UsagePresenter.updatedValue(for: document, now: Fixtures.now.addingTimeInterval(120), language: .th),
            "2 นาทีก่อน"
        )
    }

    /// The small widget shows the label of the first three accounts, in file order. The collector has already left out
    /// the hidden accounts and put the rest in the chosen order, so a fourth account is not drawn.
    func testSmallRingsShowTheLabelsOfTheFirstThreeAccountsInFileOrder() throws {
        let document = try Fixtures.document("""
        {"accounts": [
          {"id": "claude-claude-2", "provider": "claude", "label": "Claude งาน", "status": "ok",
           "limits": [{"key": "five_hour", "window_seconds": 18000, "used_percent": 10}]},
          {"id": "codex-main", "provider": "codex", "label": "ChatGPT", "status": "ok",
           "limits": [{"key": "primary", "window_seconds": 604800, "used_percent": 20}]},
          {"id": "agy-main", "provider": "agy", "label": "agy", "status": "ok",
           "limits": [{"key": "claude", "used_percent": 30}]},
          {"id": "claude-main", "provider": "claude", "label": "Claude", "status": "ok",
           "limits": [{"key": "five_hour", "window_seconds": 18000, "used_percent": 40}]}
        ]}
        """)
        let lines = UsagePresenter.smallLines(for: document, language: .th)
        XCTAssertEqual(lines.map(\.name), ["Claude งาน", "ChatGPT", "agy"])
        XCTAssertEqual(lines.map(\.numberText), ["90", "80", "70"])
    }

    /// Without a label the small ring falls back to the short provider name, as before.
    func testSmallRingFallsBackToTheShortNameWithoutALabel() throws {
        let document = try Fixtures.document(#"{"accounts": [{"id": "codex-main", "provider": "codex", "label": "", "status": "ok", "limits": [{"key": "primary", "window_seconds": 604800, "used_percent": 20}]}]}"#)
        XCTAssertEqual(UsagePresenter.smallLines(for: document, language: .th).map(\.name), ["GPT"])
    }

    func testUpdatedValueCountsFromTheOldestAccountUpdate() throws {
        let document = try Fixtures.document(#"{"generated_at": "2026-11-19T04:30:00Z", "accounts": [{"provider": "claude", "label": "Claude", "status": "ok", "updated_at": "2026-11-19T04:20:00Z", "limits": []}, {"provider": "agy", "label": "agy", "status": "stale", "updated_at": "2026-11-19T01:00:00Z", "limits": []}]}"#)
        XCTAssertEqual(UsagePresenter.updatedValue(for: document, now: Fixtures.now, language: .th), "4 ชม.ก่อน")
        XCTAssertEqual(UsagePresenter.updatedValue(for: document, now: Fixtures.now, language: .en), "4 h ago")
    }

    func testUpdatedValueFallsBackToGeneratedAtThenToNothing() throws {
        let noUpdates = try Fixtures.document(#"{"generated_at": "2026-11-19T04:25:00Z", "accounts": [{"provider": "agy", "label": "agy", "status": "error", "error": "ล็อกอิน agy หมดอายุ", "updated_at": null, "limits": []}]}"#)
        XCTAssertEqual(UsagePresenter.updatedValue(for: noUpdates, now: Fixtures.now, language: .th), "5 นาทีก่อน")
        XCTAssertNil(UsagePresenter.updatedValue(for: try Fixtures.document(#"{"accounts": []}"#), now: Fixtures.now, language: .th))
    }

    /// The "+N" badge counts the accounts past the first three. Three or fewer accounts draw no badge.
    func testTheMoreBadgeCountsTheAccountsPastTheFirstThree() throws {
        let counts = try [0, 1, 3, 4, 5, 12].map { n -> Int in
            let accounts = (0..<n).map { _ in #"{"provider": "claude", "label": "Claude", "limits": []}"# }
            let document = try Fixtures.document(#"{"accounts": ["# + accounts.joined(separator: ",") + "]}")
            return UsagePresenter.hiddenAccountCount(for: document, shown: UsagePresenter.smallRingLimit)
        }
        XCTAssertEqual(counts, [0, 0, 0, 1, 2, 9])
        XCTAssertEqual(UsagePresenter.hiddenAccountCount(for: try Fixtures.sample(), shown: UsagePresenter.mediumRowLimit), 0)
    }

    /// With five accounts, the small rings and the medium rows are the first three, in file order.
    func testSmallAndMediumShowTheFirstThreeOfFiveAccounts() throws {
        let document = try Fixtures.document("""
        {"accounts": [
          {"id": "claude-main", "provider": "claude", "label": "Claude", "status": "ok", "limits": [{"key": "five_hour", "window_seconds": 18000, "used_percent": 42}]},
          {"id": "claude-claude-2", "provider": "claude", "label": "Claude งาน", "status": "ok", "limits": [{"key": "five_hour", "window_seconds": 18000, "used_percent": 12}]},
          {"id": "codex-main", "provider": "codex", "label": "ChatGPT", "status": "ok", "limits": [{"key": "primary", "window_seconds": 604800, "used_percent": 85}]},
          {"id": "codex-codex-2", "provider": "codex", "label": "ChatGPT 2", "status": "ok", "limits": [{"key": "primary", "window_seconds": 604800, "used_percent": 100}]},
          {"id": "agy-main", "provider": "agy", "label": "agy", "status": "ok", "limits": [{"key": "claude", "used_percent": 0}]}
        ]}
        """)
        XCTAssertEqual(UsagePresenter.smallLines(for: document, language: .th).map(\.name), ["Claude", "Claude งาน", "ChatGPT"])
        let cards = UsagePresenter.cards(for: document, now: Fixtures.now, language: .th)
        XCTAssertEqual(UsagePresenter.mediumRows(for: cards, language: .th).map(\.title), ["Claude", "Claude งาน", "ChatGPT"])
    }

    /// Two limits take one line each, in file order, so the popover subline wraps to two lines and is not cut off.
    func testPopoverSublineOfTwoLimitsHasOneLimitPerLine() throws {
        let claude = try XCTUnwrap(Fixtures.sample().accounts.first)
        let subline = try XCTUnwrap(AppUsageInsights.popoverSubline(claude, now: Fixtures.now, language: .th))
        XCTAssertEqual(subline.text, "5 ชม. เหลือ 58%\nสัปดาห์ เหลือ 33%")
        XCTAssertFalse(subline.isError)
        XCTAssertEqual(subline.text.components(separatedBy: "\n").count, 2)

        let english = try XCTUnwrap(AppUsageInsights.popoverSubline(claude, now: Fixtures.now, language: .en))
        XCTAssertEqual(english.text, "5h 58% left\nWeek 33% left")
    }

    /// One limit keeps the top limit and its reset on one text, which wraps when it is long. It has no line break.
    func testPopoverSublineOfOneLimitKeepsItsResetAndHasNoLineBreak() throws {
        let codex = try XCTUnwrap(Fixtures.sample().accounts.dropFirst().first)
        let subline = try XCTUnwrap(AppUsageInsights.popoverSubline(codex, now: Fixtures.now, language: .th))
        XCTAssertEqual(subline.text, "สัปดาห์ เหลือ 7% · รีเซ็ตใน 22 ชม.")
        XCTAssertFalse(subline.text.contains("\n"))
    }
}
