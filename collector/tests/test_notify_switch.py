"""Tests for settings.json (the Mac app's notification switch and language) and for the alert texts.

Mocks only: nothing is sent, no Keychain is read, no provider CLI or endpoint is started.
"""
import json
import os
import plistlib
import unittest
from pathlib import Path
from unittest import mock

import ai_usage_collect as m
from tests.test_collector import (CODEX_RATE_RESULT, CLAUDE_RATE_LIMITS, NOW, Base, FakeHTTP, FakeKeychain,
                                  FrozenDatetime, agy_pw, agy_usage_lines, claude_program, claude_stream_lines,
                                  claude_text_lines, codex_rpc_lines, make_env, single_program, ts)

APP_REL = Path("Library") / "Application Support" / "AIUsage"
CODEX_LOW_RESULT = dict(CODEX_RATE_RESULT, rateLimits=dict(
    CODEX_RATE_RESULT["rateLimits"],
    primary={"usedPercent": 10, "windowDurationMins": 10080, "resetsAt": ts("2026-11-20T02:15:51Z")}))
AGY_LOW_DOC = {"status": "SUCCESS", "command": {"name": "usage", "data": {"groups": [
    {"name": "Gemini Pro", "buckets": [
        {"id": "gemini-5h", "window": "5h", "remaining_fraction": 1, "reset_time": "2026-11-19T09:21:41Z"}]}]}}}
CLAUDE_KEY = "claude-main|five_hour|2026-11-19T06:40:00Z"


def account(used, resets="2026-11-19T06:40:00Z"):
    return {"id": "claude-main", "label": "Claude", "status": "ok",
            "limits": [{"key": "five_hour", "label": "5 ชม.", "used_percent": used,
                        "resets_at": resets, "window_seconds": 18000}]}


class SettingsFileTests(Base):
    def test_settings_file_lives_in_the_app_folder(self):
        self.assertEqual(m.Paths(self.home).settings_file, self.home / APP_REL / "settings.json")

    def test_missing_settings_file_reads_as_defaults(self):
        self.assertEqual(m.read_settings(self.home / "missing.json"), {})

    def test_broken_settings_json_reads_as_defaults(self):
        path = self.home / "settings.json"
        path.write_text('{"notify": fal', encoding="utf-8")
        self.assertEqual(m.read_settings(path), {})

    def test_settings_that_is_not_an_object_reads_as_defaults(self):
        path = self.home / "settings.json"
        path.write_text("[true]", encoding="utf-8")
        self.assertEqual(m.read_settings(path), {})


class NotifyPassBase(Base):
    def run_pass(self, used, language="en", send=True, accounts=None, now=NOW):
        sent = []

        def notify(title, text):
            sent.append((title, text))
            return True

        env = make_env(self.home, notify=notify, now=now)
        accounts = [account(used)] if accounts is None else accounts
        m.notify_pass(env, accounts, self.home / "state" / "notify-state.json", language, send)
        return sent

    def state(self):
        return json.loads((self.home / "state" / "notify-state.json").read_text(encoding="utf-8"))


class NotifySwitchTests(NotifyPassBase):
    def test_missing_notify_key_means_on(self):
        self.assertTrue(m.notify_enabled({}))

    def test_notify_true_means_on(self):
        self.assertTrue(m.notify_enabled({"notify": True}))

    def test_notify_false_means_off(self):
        self.assertFalse(m.notify_enabled({"notify": False}))

    def test_a_non_boolean_notify_value_counts_as_on(self):
        self.assertTrue(m.notify_enabled({"notify": "false"}))
        self.assertTrue(m.notify_enabled({"notify": None}))
        self.assertTrue(m.notify_enabled({"notify": 0}))

    def test_switch_off_sends_nothing_but_records_the_crossing(self):
        self.assertEqual(self.run_pass(85.0, send=False), [])
        self.assertEqual(self.state()[CLAUDE_KEY]["sent"], [80])

    def test_switch_back_on_does_not_burst_alerts_crossed_while_off(self):
        self.run_pass(85.0, send=False)
        self.assertEqual(self.run_pass(85.0, send=True), [])

    def test_a_higher_threshold_after_the_switch_is_back_on_still_alerts(self):
        self.run_pass(85.0, send=False)
        self.assertEqual(self.run_pass(96.0, send=True),
                         [("Quota Battery", "Claude · 5h near limit, 96% used")])

    def test_switch_off_still_prunes_old_state(self):
        old = {CLAUDE_KEY: {"sent": [80], "seen": "2026-10-01T00:00:00Z"}}
        path = self.home / "state" / "notify-state.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(old), encoding="utf-8")
        self.run_pass(0.0, send=False, accounts=[])
        self.assertEqual(self.state(), {})


class LanguageTests(NotifyPassBase):
    def set_preferred(self, languages):
        path = self.home / "Library" / "Preferences" / ".GlobalPreferences.plist"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(plistlib.dumps({"AppleLanguages": languages}))

    def test_language_th_is_thai_whatever_the_system_says(self):
        self.set_preferred(["en-US"])
        self.assertEqual(m.notification_language({"language": "th"}, self.home), "th")

    def test_language_en_is_english_whatever_the_system_says(self):
        self.set_preferred(["th-TH"])
        self.assertEqual(m.notification_language({"language": "en"}, self.home), "en")

    def test_system_follows_the_first_preferred_language_when_it_is_thai(self):
        self.set_preferred(["th-TH", "en-US"])
        self.assertEqual(m.notification_language({"language": "system"}, self.home), "th")

    def test_system_with_english_first_is_english_even_if_thai_is_second(self):
        self.set_preferred(["en-US", "th-TH"])
        self.assertEqual(m.notification_language({"language": "system"}, self.home), "en")

    def test_system_without_a_preferences_file_is_english(self):
        self.assertEqual(m.notification_language({"language": "system"}, self.home), "en")

    def test_an_unknown_language_value_follows_the_system(self):
        self.set_preferred(["th-TH"])
        self.assertEqual(m.notification_language({"language": "fr"}, self.home), "th")

    def test_a_missing_language_key_follows_the_system(self):
        self.set_preferred(["th-TH"])
        self.assertEqual(m.notification_language({}, self.home), "th")

    def test_a_broken_preferences_file_is_english(self):
        path = self.home / "Library" / "Preferences" / ".GlobalPreferences.plist"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b"not a plist at all")
        self.assertEqual(m.notification_language({"language": "system"}, self.home), "en")

    def test_thai_alert_text_for_both_thresholds(self):
        acc = account(85.0)
        limit = acc["limits"][0]
        self.assertEqual(m.notification_text("th", acc, limit, 80, 85.0),
                         ("Quota Battery", "Claude · 5 ชม. ใช้ไปแล้ว 85%"))
        self.assertEqual(m.notification_text("th", acc, limit, 95, 96.0),
                         ("Quota Battery", "Claude · 5 ชม. ใกล้เต็มแล้ว 96%"))

    def test_english_alert_text_for_both_thresholds(self):
        acc = account(85.0)
        limit = acc["limits"][0]
        self.assertEqual(m.notification_text("en", acc, limit, 80, 85.0),
                         ("Quota Battery", "Claude · 5h used 85%"))
        self.assertEqual(m.notification_text("en", acc, limit, 95, 96.0),
                         ("Quota Battery", "Claude · 5h near limit, 96% used"))

    def test_notification_title_is_quota_battery_in_both_languages_at_both_thresholds(self):
        acc = account(85.0)
        limit = acc["limits"][0]
        for language in ("en", "th"):
            for threshold, used in ((80, 85.0), (95, 96.0)):
                with self.subTest(language=language, threshold=threshold):
                    title, _ = m.notification_text(language, acc, limit, threshold, used)
                    self.assertEqual(title, "Quota Battery")

    def test_english_limit_labels_follow_window_seconds_and_key(self):
        cases = [
            ({"key": "five_hour", "label": "5 ชม.", "window_seconds": 18000}, "5h"),
            ({"key": "seven_day", "label": "สัปดาห์", "window_seconds": 604800}, "Week"),
            ({"key": "seven_day_opus", "label": "Opus สัปดาห์", "window_seconds": 604800}, "Week (Opus)"),
            ({"key": "seven_day_sonnet", "label": "Sonnet สัปดาห์", "window_seconds": 604800},
             "Week (Sonnet)"),
            ({"key": "primary", "label": "สัปดาห์", "window_seconds": 604800}, "Week"),
        ]
        for limit, expected in cases:
            with self.subTest(key=limit["key"]):
                self.assertEqual(m.english_limit_label(limit), expected)

    def test_window_english_for_other_lengths(self):
        self.assertEqual(m.window_english(2592000), "30d")
        self.assertEqual(m.window_english(3600), "1h")
        self.assertEqual(m.window_english(180), "3m")

    def test_a_limit_without_a_length_keeps_its_own_name(self):
        self.assertEqual(m.english_limit_label({"key": "gemini_pro", "label": "Gemini Pro",
                                                "window_seconds": None}), "Gemini Pro")

    def test_notify_pass_sends_the_thai_title_and_text_when_language_is_th(self):
        self.assertEqual(self.run_pass(85.0, language="th"),
                         [("Quota Battery", "Claude · 5 ชม. ใช้ไปแล้ว 85%")])


class MainNotifyTests(Base):
    """Whole runs of main() with the Claude and Codex CLIs and the agy CLI scripted."""

    def setUp(self):
        super().setUp()
        self.app = self.home / APP_REL
        self.notes = []
        self.five_hour = 10.0
        (self.home / ".claude" / "projects").mkdir(parents=True)
        (self.home / ".claude.json").write_text("{}", encoding="utf-8")
        self.write_codex_auth()
        self.http = FakeHTTP({})
        patches = [
            mock.patch.object(m, "SystemKeychain", lambda: FakeKeychain({m.AGY_KEYCHAIN_SERVICE: agy_pw()})),
            mock.patch.object(m, "http_request", self.http),
            mock.patch.object(m, "osascript_notify",
                              lambda title, text: self.notes.append((title, text)) or True),
            mock.patch.object(m, "datetime", FrozenDatetime),
            mock.patch.dict(os.environ, {"HOME": str(self.home)}),
        ]
        for patch in patches:
            patch.start()
            self.addCleanup(patch.stop)
        self.set_five_hour(10.0)

    def write_settings(self, settings):
        self.app.mkdir(parents=True, exist_ok=True)
        (self.app / "settings.json").write_text(json.dumps(settings), encoding="utf-8")

    def set_five_hour(self, used):
        self.five_hour = used
        window = {"utilization": used, "resets_at": "2026-11-19T06:40:00.000000+00:00"}
        self.use_clis({
            "claude": claude_program((claude_stream_lines(dict(CLAUDE_RATE_LIMITS, five_hour=window)),
                                      claude_text_lines())),
            "codex": single_program(codex_rpc_lines(CODEX_LOW_RESULT)),
            "agy": single_program(agy_usage_lines(AGY_LOW_DOC)),
        })

    def state(self):
        return json.loads((self.app / "notify-state.json").read_text(encoding="utf-8"))

    def test_switch_off_writes_usage_and_state_but_sends_nothing(self):
        self.write_settings({"notify": False})
        self.set_five_hour(85.0)
        self.assertEqual(m.main(["--no-refresh"]), 0)
        self.assertEqual(self.notes, [])
        self.assertTrue((self.app / "usage.json").exists())
        self.assertEqual(self.state()[CLAUDE_KEY]["sent"], [80])

    def test_turning_the_switch_back_on_sends_nothing_for_the_crossed_window(self):
        self.write_settings({"notify": False})
        self.set_five_hour(85.0)
        m.main(["--no-refresh"])
        self.write_settings({"notify": True, "language": "en"})
        m.main(["--no-refresh"])
        self.assertEqual(self.notes, [])

    def test_no_notify_flag_records_the_crossing_without_sending(self):
        self.write_settings({"notify": True, "language": "th"})
        self.set_five_hour(85.0)
        m.main(["--no-refresh", "--no-notify"])
        self.assertEqual(self.notes, [])
        self.assertEqual(self.state()[CLAUDE_KEY]["sent"], [80])
        m.main(["--no-refresh"])
        self.assertEqual(self.notes, [])

    def test_the_app_language_setting_selects_the_english_text_end_to_end(self):
        self.write_settings({"notify": True, "language": "en"})
        self.set_five_hour(85.0)
        m.main(["--no-refresh"])
        self.assertEqual(self.notes, [("Quota Battery", "Claude · 5h used 85%")])

    def test_the_app_language_setting_selects_the_thai_text_end_to_end(self):
        self.write_settings({"notify": True, "language": "th"})
        self.set_five_hour(85.0)
        m.main(["--no-refresh"])
        self.assertEqual(self.notes, [("Quota Battery", "Claude · 5 ชม. ใช้ไปแล้ว 85%")])

    def test_a_missing_settings_file_keeps_notifications_on(self):
        self.set_five_hour(85.0)
        m.main(["--no-refresh"])
        self.assertEqual(self.notes, [("Quota Battery", "Claude · 5h used 85%")])


if __name__ == "__main__":
    unittest.main()
