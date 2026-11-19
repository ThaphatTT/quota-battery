import XCTest

final class UsageFormattingTests: XCTestCase {
    // MARK: Pill, pulse and tiers

    func testPillAndPulseStartAtEightyUsedInclusive() {
        XCTAssertFalse(UsageFormat.isAlert(79.99))
        XCTAssertTrue(UsageFormat.isAlert(80))
        XCTAssertTrue(UsageFormat.isAlert(100))
        XCTAssertFalse(UsageFormat.isAlert(.infinity))
    }

    /// Tiers are on used_percent: white above 20% left, yellow for 6 to 20% left, red for 5% left or less.
    func testTierBoundariesByHand() {
        XCTAssertEqual(UsageFormat.tier(0), .plenty)
        XCTAssertEqual(UsageFormat.tier(32), .plenty)
        XCTAssertEqual(UsageFormat.tier(79.6), .plenty)
        XCTAssertEqual(UsageFormat.tier(79.99), .plenty)
        XCTAssertEqual(UsageFormat.tier(80), .low)
        XCTAssertEqual(UsageFormat.tier(85), .low)
        XCTAssertEqual(UsageFormat.tier(94.6), .low)
        XCTAssertEqual(UsageFormat.tier(94.99), .low)
        XCTAssertEqual(UsageFormat.tier(95), .critical)
        XCTAssertEqual(UsageFormat.tier(99.6), .critical)
        XCTAssertEqual(UsageFormat.tier(100), .critical)
        XCTAssertEqual(UsageFormat.tier(150), .critical)
    }

    func testUnknownUsageIsWhiteTierAndHasNoNumber() {
        XCTAssertEqual(UsageFormat.tier(nil), .plenty)
        XCTAssertEqual(UsageFormat.tier(Double.nan), .plenty)
        XCTAssertEqual(UsageFormat.tier(Double.infinity), .plenty)
        XCTAssertNil(UsageFormat.leftWhole(nil))
        XCTAssertNil(UsageFormat.leftWhole(Double.nan))
        XCTAssertNil(UsageFormat.leftWhole(Double.infinity))
    }

    func testTierColoursAreFixedExceptWhite() {
        XCTAssertNil(UsageTier.plenty.hex)
        XCTAssertEqual(UsageTier.low.hex, "#FFD60A")
        XCTAssertEqual(UsageTier.critical.hex, "#FF5F57")
        XCTAssertEqual(ProviderStyle.lowHex, "#FFD60A")
        XCTAssertEqual(ProviderStyle.alertHex, "#FF5F57")
    }

    /// Light appearance uses the darker yellow and red (the same choice as the iPhone). Dark keeps the bright ones.
    /// White stays the ink colour in both, so `plenty` has no hex.
    func testTierColoursInLightModeAreDarker() {
        XCTAssertNil(UsageTier.plenty.hex(dark: false))
        XCTAssertNil(UsageTier.plenty.hex(dark: true))
        XCTAssertEqual(UsageTier.low.hex(dark: false), "#B58900")
        XCTAssertEqual(UsageTier.critical.hex(dark: false), "#D93025")
        XCTAssertEqual(UsageTier.low.hex(dark: true), "#FFD60A")
        XCTAssertEqual(UsageTier.critical.hex(dark: true), "#FF5F57")
        XCTAssertEqual(ProviderStyle.lowLightHex, "#B58900")
        XCTAssertEqual(ProviderStyle.alertLightHex, "#D93025")
    }

    // MARK: Left, used and rounding

    /// What is left is 100 minus the used whole number. So 94.6 used reads "6" left (rounded UP), and "94" used
    /// (rounded DOWN), and the two add up to 100.
    func testLeftRoundsUpAndUsedRoundsDown() {
        XCTAssertEqual(UsageFormat.leftWhole(79.6), 21)
        XCTAssertEqual(UsageFormat.usedWhole(79.6), 79)
        XCTAssertEqual(UsageFormat.leftWhole(79.99), 21)
        XCTAssertEqual(UsageFormat.leftWhole(80), 20)
        XCTAssertEqual(UsageFormat.leftWhole(94.6), 6)
        XCTAssertEqual(UsageFormat.usedWhole(94.6), 94)
        XCTAssertEqual(UsageFormat.leftWhole(94.99), 6)
        XCTAssertEqual(UsageFormat.leftWhole(95), 5)
        XCTAssertEqual(UsageFormat.leftWhole(99.6), 1)
        XCTAssertEqual(UsageFormat.leftWhole(99.99), 1)
        XCTAssertEqual(UsageFormat.leftWhole(100), 0)
        XCTAssertEqual(UsageFormat.leftWhole(0), 100)
        XCTAssertEqual(UsageFormat.leftWhole(32), 68)
        XCTAssertEqual(UsageFormat.leftWhole(150), 0)
        XCTAssertEqual(UsageFormat.leftWhole(-5), 100)
    }

    func testLeftAndUsedTextsInBothLanguages() {
        XCTAssertEqual(UsageFormat.leftText(94.6, .th), "เหลือ 6%")
        XCTAssertEqual(UsageFormat.leftText(94.6, .en), "6% left")
        XCTAssertEqual(UsageFormat.usedText(94.6, .th), "ใช้ไป 94%")
        XCTAssertEqual(UsageFormat.usedText(94.6, .en), "94% used")
        XCTAssertEqual(UsageFormat.leftText(32, .th), "เหลือ 68%")
        XCTAssertEqual(UsageFormat.usedText(32, .en), "32% used")
        XCTAssertEqual(UsageFormat.leftText(95, .th), "เหลือ 5%")
        XCTAssertEqual(UsageFormat.leftText(100, .en), "0% left")
        XCTAssertEqual(UsageFormat.leftText(nil, .th), "—")
        XCTAssertEqual(UsageFormat.usedText(Double.nan, .en), "—")
    }

    // MARK: Gauge and ring fill

    func testRemainingFractionIsTheShareLeftAndClamped() {
        XCTAssertEqual(UsageFormat.remainingFraction(25), 0.75, accuracy: 0.0001)
        XCTAssertEqual(UsageFormat.remainingFraction(0), 1)
        XCTAssertEqual(UsageFormat.remainingFraction(94.6), 0.054, accuracy: 0.0001)
        XCTAssertEqual(UsageFormat.remainingFraction(100), 0)
        XCTAssertEqual(UsageFormat.remainingFraction(150), 0)
        XCTAssertEqual(UsageFormat.remainingFraction(-3), 1)
    }

    /// Unknown usage is an empty gauge, never a full one.
    func testUnknownUsageDrawsAnEmptyGauge() {
        XCTAssertEqual(UsageFormat.remainingFraction(nil), 0)
        XCTAssertEqual(UsageFormat.remainingFraction(Double.nan), 0)
        XCTAssertNil(UsageFormat.remainingPercent(nil))
    }

    /// Anything left draws at least 2 points, so a gauge with a little left is never invisible. Nothing left draws nothing.
    func testFillWidthHasATwoPointSliverWhenAnyIsLeft() {
        XCTAssertEqual(UsageFormat.fillWidth(fraction: 0, available: 20), 0)
        XCTAssertEqual(UsageFormat.fillWidth(fraction: 0.001, available: 20), 2)
        XCTAssertEqual(UsageFormat.fillWidth(fraction: 0.05, available: 20), 2)
        XCTAssertEqual(UsageFormat.fillWidth(fraction: 0.5, available: 20), 10)
        XCTAssertEqual(UsageFormat.fillWidth(fraction: 1, available: 20), 20)
        XCTAssertEqual(UsageFormat.fillWidth(fraction: 0.2, available: 1), 1)
        XCTAssertEqual(UsageFormat.fillWidth(fraction: 0.5, available: 0), 0)
    }

    /// Sorting uses the used share, so the most used limit still comes first in the large widget.
    func testUsedShareIsClampedForSorting() {
        XCTAssertEqual(UsageFormat.fraction(25), 0.25, accuracy: 0.0001)
        XCTAssertEqual(UsageFormat.fraction(150), 1)
        XCTAssertEqual(UsageFormat.fraction(-3), 0)
        XCTAssertEqual(UsageFormat.fraction(.nan), 0)
    }

    func testUnitFractionAndUsedWholeClamp() {
        XCTAssertEqual(UsageFormat.unitFraction(0.4), 0.4, accuracy: 0.0001)
        XCTAssertEqual(UsageFormat.unitFraction(1.7), 1)
        XCTAssertEqual(UsageFormat.unitFraction(-0.2), 0)
        XCTAssertEqual(UsageFormat.unitFraction(.nan), 0)
        XCTAssertEqual(UsageFormat.usedWhole(150), 100)
        XCTAssertEqual(UsageFormat.usedWhole(-5), 0)
    }

    func testBrandIconLettersAndColours() {
        XCTAssertEqual(["claude", "codex", "agy", "zed", ""].map(ProviderStyle.iconLetter(for:)), ["C", "G", "A", "Z", "?"])
        XCTAssertEqual(ProviderStyle.accentHex(for: "claude"), "#D97757")
        XCTAssertEqual(ProviderStyle.accentHex(for: "codex"), "#10A37F")
        XCTAssertEqual(ProviderStyle.accentHex(for: "agy"), "#4285F4")
    }

    /// The unit switches by size: minutes under 60, hours under 24, then days. The unit is picked from the
    /// rounded value, so 59.5 minutes shows "1 ชม." instead of "60 นาที".
    func testUpdatedTextUsesTheUnitThatReadsRight() {
        func ago(_ seconds: TimeInterval) -> String? {
            UsageFormat.updatedText(updatedAt: Fixtures.now.addingTimeInterval(-seconds), now: Fixtures.now, language: .th)
        }
        XCTAssertEqual(ago(0), "อัปเดต 1 นาทีก่อน")
        XCTAssertEqual(ago(12 * 60), "อัปเดต 12 นาทีก่อน")
        XCTAssertEqual(ago(12 * 60 + 30), "อัปเดต 13 นาทีก่อน")
        XCTAssertEqual(ago(59 * 60), "อัปเดต 59 นาทีก่อน")
        XCTAssertEqual(ago(59.5 * 60), "อัปเดต 1 ชม.ก่อน")
        XCTAssertEqual(ago(60 * 60), "อัปเดต 1 ชม.ก่อน")
        XCTAssertEqual(ago(3.5 * 3600), "อัปเดต 4 ชม.ก่อน")
        XCTAssertEqual(ago(23 * 3600), "อัปเดต 23 ชม.ก่อน")
        XCTAssertEqual(ago(23.5 * 3600), "อัปเดต 1 วันก่อน")
        XCTAssertEqual(ago(36 * 3600), "อัปเดต 2 วันก่อน")
        XCTAssertEqual(
            UsageFormat.updatedText(updatedAt: Fixtures.now.addingTimeInterval(60), now: Fixtures.now, language: .th),
            "อัปเดต 1 นาทีก่อน"
        )
        XCTAssertNil(UsageFormat.updatedText(updatedAt: nil, now: Fixtures.now, language: .th))
    }

    func testResetTextUsesMinutesHoursOrDays() {
        func resetIn(_ seconds: TimeInterval) -> String? {
            UsageFormat.resetText(resetsAt: Fixtures.now.addingTimeInterval(seconds), now: Fixtures.now, language: .th)
        }
        XCTAssertEqual(resetIn(30), "รีเซ็ตใน 1 นาที")
        XCTAssertEqual(resetIn(10 * 60), "รีเซ็ตใน 10 นาที")
        XCTAssertEqual(resetIn(59 * 60), "รีเซ็ตใน 59 นาที")
        XCTAssertEqual(resetIn(59.5 * 60), "รีเซ็ตใน 1 ชม.")
        XCTAssertEqual(resetIn(2 * 3600 + 600), "รีเซ็ตใน 2 ชม.")
        XCTAssertEqual(resetIn(2 * 3600 + 3000), "รีเซ็ตใน 3 ชม.")
        XCTAssertEqual(resetIn(23 * 3600), "รีเซ็ตใน 23 ชม.")
        XCTAssertEqual(resetIn(23.5 * 3600), "รีเซ็ตใน 1 วัน")
        XCTAssertEqual(resetIn(150 * 3600), "รีเซ็ตใน 6 วัน")
        XCTAssertEqual(resetIn(156 * 3600), "รีเซ็ตใน 7 วัน")
        XCTAssertNil(resetIn(-1))
        XCTAssertNil(resetIn(0))
        XCTAssertNil(UsageFormat.resetText(resetsAt: nil, now: Fixtures.now, language: .th))
    }

    /// The same rules in English: "Updated 2 min ago", "Resets in 5 h". The units keep the iPhone's wording.
    func testEnglishUpdatedAndResetTexts() {
        func updated(_ seconds: TimeInterval) -> String? {
            UsageFormat.updatedText(updatedAt: Fixtures.now.addingTimeInterval(-seconds), now: Fixtures.now, language: .en)
        }
        XCTAssertEqual(updated(0), "Updated 1 min ago")
        XCTAssertEqual(updated(12 * 60), "Updated 12 min ago")
        XCTAssertEqual(updated(59.5 * 60), "Updated 1 h ago")
        XCTAssertEqual(updated(23 * 3600), "Updated 23 h ago")
        XCTAssertEqual(updated(36 * 3600), "Updated 2 d ago")
        XCTAssertNil(UsageFormat.updatedText(updatedAt: nil, now: Fixtures.now, language: .en))

        func resetIn(_ seconds: TimeInterval) -> String? {
            UsageFormat.resetText(resetsAt: Fixtures.now.addingTimeInterval(seconds), now: Fixtures.now, language: .en)
        }
        XCTAssertEqual(resetIn(30), "Resets in 1 min")
        XCTAssertEqual(resetIn(59 * 60), "Resets in 59 min")
        XCTAssertEqual(resetIn(2 * 3600 + 600), "Resets in 2 h")
        XCTAssertEqual(resetIn(23.5 * 3600), "Resets in 1 d")
        XCTAssertNil(resetIn(-1))
    }

    func testCreditTextDropsZerosAndHasNoDollarSign() {
        XCTAssertEqual(UsageFormat.creditText(0), "0")
        XCTAssertEqual(UsageFormat.creditText(-0.0), "0")
        XCTAssertEqual(UsageFormat.creditText(12), "12")
        XCTAssertEqual(UsageFormat.creditText(12.5), "12.5")
        XCTAssertEqual(UsageFormat.creditText(12.25), "12.25")
        XCTAssertEqual(UsageFormat.creditText(12.1), "12.1")
        XCTAssertEqual(UsageFormat.creditText(12.004), "12")
        XCTAssertEqual(UsageFormat.creditText(-3), "-3")
        XCTAssertEqual(UsageFormat.creditText(-0.5), "-0.5")
        XCTAssertEqual(UsageFormat.creditText(.nan), "—")
    }

    func testTokensText() {
        XCTAssertEqual(UsageFormat.tokensText(1_200_000), "1.2M")
        XCTAssertEqual(UsageFormat.tokensText(640_000), "640K")
        XCTAssertEqual(UsageFormat.tokensText(850), "850")
        XCTAssertEqual(UsageFormat.tokensText(0), "0")
        XCTAssertEqual(UsageFormat.tokensText(.nan), "—")
    }

    func testMoneyText() {
        XCTAssertEqual(UsageFormat.moneyText(18.4), "$18.40")
        XCTAssertEqual(UsageFormat.moneyText(0), "$0.00")
        XCTAssertEqual(UsageFormat.moneyText(50), "$50.00")
        XCTAssertEqual(UsageFormat.moneyText(.nan), "—")
    }
}
