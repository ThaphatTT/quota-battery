"""Default mode: each provider's own CLI reports its usage. Every CLI here is scripted (FakeCLIs), except the
last group, which runs the real subprocess runner against small stub programs written into a temporary folder.

The fixtures are the redacted shapes of the provider CLIs' output, with invented values. No provider CLI and
no provider endpoint is ever started.
"""
import contextlib
import io
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

import ai_usage_collect as m
from tests.test_collector import (AGY_USAGE_DOC, CLAUDE_RATE_LIMITS, CODEX_RATE_RESULT, CODEX_USAGE_BODY,
                                  FAKE_ACCOUNT_ID, FAKE_AGY_ACCESS, FAKE_EMAIL, FAKE_SESSION,
                                  ForbiddenCall, FakeHTTP, FakeKeychain, FrozenDatetime, NOW, Base,
                                  agy_pw, agy_usage_lines, claude_program, claude_stream_error_lines,
                                  claude_stream_lines, claude_text_lines, codex_rpc_lines, json_line,
                                  make_env, resp, single_program, ts)

# The real primitives, captured before any test patches them (Base patches Popen and killpg for every test).
REAL_POPEN = subprocess.Popen
REAL_KILLPG = os.killpg
CODEX_METHODS_ALLOWED = ("initialize", "initialized", "account/rateLimits/read")
CODEX_METHODS_FORBIDDEN = ("consume", "nudge", "login", "logout", "bedrock", "gatewayOAuth", "sendAddCreditsNudge")


def written_methods(proc):
    """The JSON-RPC method names that the collector wrote to a protocol server's stdin."""
    return [json.loads(line).get("method") for line in proc.stdin.written]


class CliBase(Base):
    """A home folder with a Claude folder, a Codex login and an agy login, and the usual fakes around main()."""

    def setUp(self):
        super().setUp()
        self.notes = []
        self.keychain = FakeKeychain({m.AGY_KEYCHAIN_SERVICE: agy_pw()})
        self.http = FakeHTTP({})
        self.patches = [
            mock.patch.object(m, "SystemKeychain", lambda: self.keychain),
            mock.patch.object(m, "http_request", self.http),
            mock.patch.object(m, "osascript_notify", lambda title, text: self.notes.append(text) or True),
            mock.patch.object(m, "datetime", FrozenDatetime),
            mock.patch.dict(os.environ, {"HOME": str(self.home)}),
        ]
        for patch in self.patches:
            patch.start()
            self.addCleanup(patch.stop)
        (self.home / ".claude" / "projects").mkdir(parents=True)
        (self.home / ".claude.json").write_text("{}", encoding="utf-8")
        path = self.home / ".codex" / "auth.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps({"tokens": {"access_token": "x", "account_id": "y"}}), encoding="utf-8")

    def all_clis_ok(self):
        return self.use_clis({"claude": claude_program((claude_stream_lines(), claude_text_lines())),
                              "codex": single_program(codex_rpc_lines()),
                              "agy": single_program(agy_usage_lines())})

    def main_dry_run(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = m.main(["--dry-run"])
        return code, out.getvalue()


class ClaudeGetUsageTests(CliBase):
    def test_get_usage_becomes_the_claude_limits_plan_and_credits(self):
        self.use_clis({"claude": claude_program((claude_stream_lines(), claude_text_lines()))})
        acc = self.collect_real(make_env(self.home), "claude")
        self.assertEqual((acc["status"], acc["error_code"], acc["plan"]), ("ok", None, "Max"))
        self.assertEqual([(limit["key"], limit["label"], limit["window_seconds"], limit["used_percent"],
                           limit["resets_at"]) for limit in acc["limits"]],
                         [("five_hour", "5 ชม.", 18000, 42.0, "2026-11-19T06:40:00Z"),
                          ("seven_day", "สัปดาห์", 604800, 67.0, "2026-11-24T02:00:00Z")])
        self.assertEqual(acc["credits"], {"extra_usage_enabled": True, "used_usd": 12.34,
                                          "limit_usd": 50.0, "balance_usd": None})

    def test_the_stream_protocol_sends_initialize_then_get_usage_and_nothing_else(self):
        clis = self.use_clis({"claude": claude_program((claude_stream_lines(), claude_text_lines()))})
        self.collect_real(make_env(self.home), "claude")
        launch = clis.launched("claude")[0]
        self.assertEqual(launch["argv"][1:], ["-p", "--input-format", "stream-json", "--output-format",
                                              "stream-json", "--verbose", "--no-session-persistence"])
        self.assertEqual(launch["stdin"], subprocess.PIPE)
        self.assertIs(launch["start_new_session"], True)
        sent = [json.loads(line) for line in clis.procs[0].stdin.written]
        self.assertEqual([(item["request_id"], item["request"]["subtype"]) for item in sent],
                         [("init-1", "initialize"), ("usage-1", "get_usage")])
        self.assertIs(sent[1]["request"]["skip_behaviors"], True)  # no user message is ever sent: no model turn

    def test_opus_comes_from_model_scoped_and_other_models_are_left_out(self):
        scoped = dict(CLAUDE_RATE_LIMITS, seven_day_opus=None, model_scoped=[
            {"display_name": "Opus", "utilization": 12, "resets_at": "2026-11-24T02:00:00.000000+00:00"},
            {"display_name": "Fable", "utilization": 10, "resets_at": "2026-11-24T02:00:00.000000+00:00"}])
        self.use_clis({"claude": claude_program((claude_stream_lines(scoped), claude_text_lines()))})
        acc = self.collect_real(make_env(self.home), "claude")
        self.assertEqual([limit["key"] for limit in acc["limits"]],
                         ["five_hour", "seven_day", "seven_day_opus"])
        self.assertEqual(acc["limits"][2]["label"], "Opus สัปดาห์")
        self.assertEqual(acc["limits"][2]["window_seconds"], 604800)
        self.assertNotIn("Fable", json.dumps(acc))

    def test_a_schema_change_falls_back_to_the_usage_text(self):
        broken = claude_stream_lines(payload={"subscription_type": "max", "rate_limits_available": True})
        clis = self.use_clis({"claude": claude_program((broken, claude_text_lines()))})
        acc = self.collect_real(make_env(self.home), "claude")
        self.assertEqual((acc["status"], acc["error_code"]), ("ok", None))
        self.assertEqual(len(clis.launched("claude")), 2)
        self.assertEqual([limit["key"] for limit in acc["limits"]], ["five_hour", "seven_day"])
        self.assertIn("get_usage: rate_limits missing", self.stderr.getvalue())

    def test_a_hung_get_usage_is_killed_and_the_usage_text_answers(self):
        clis = self.use_clis({"claude": claude_program(("hang", claude_text_lines()))})
        acc = self.collect_real(make_env(self.home), "claude")
        self.assertEqual(acc["status"], "ok")
        self.assertTrue(clis.procs[0].killed)
        self.assertIsNone(acc["plan"])

    def test_not_logged_in_leaves_the_account_out_and_runs_nothing_else(self):
        clis = self.use_clis({"claude": claude_program((claude_stream_error_lines(), claude_text_lines()))})
        self.assertIsNone(self.collect_real(make_env(self.home), "claude"))
        self.assertEqual(len(clis.launched("claude")), 1)

    def test_a_login_without_subscription_limits_is_an_error_that_names_its_stage(self):
        reply = claude_stream_lines(payload={"subscription_type": None, "rate_limits_available": False,
                                             "rate_limits": None})
        self.use_clis({"claude": claude_program((reply, claude_text_lines(text="Current session: no data")))})
        acc = self.collect_real(make_env(self.home), "claude")
        self.assertEqual((acc["status"], acc["error_code"], acc["error"]),
                         ("error", "quota_unavailable", m.MSG_CLAUDE_NO_QUOTA))
        self.assertIn("get_usage: rate_limits_available is false", self.stderr.getvalue())

    def test_the_usage_text_answers_when_get_usage_has_no_subscription_limits(self):
        reply = claude_stream_lines(payload={"subscription_type": None, "rate_limits_available": False,
                                             "rate_limits": None})
        self.use_clis({"claude": claude_program((reply, claude_text_lines()))})
        acc = self.collect_real(make_env(self.home), "claude")
        self.assertEqual(acc["status"], "ok")

    def test_a_logged_out_account_is_left_out_with_one_log_line_that_names_the_stage(self):
        self.use_clis({"claude": claude_program((claude_stream_error_lines(), claude_text_lines()))})
        self.assertIsNone(self.collect_real(make_env(self.home), "claude"))
        log_text = self.stderr.getvalue()
        self.assertEqual(log_text.count("ไม่มีการล็อกอิน"), 1)
        self.assertIn("get_usage: the CLI said not logged in", log_text)
        self.assertIn("claude-main", log_text)

    def test_a_missing_claude_program_is_an_unknown_error_with_its_name(self):
        self.use_clis({})
        acc = self.collect_real(make_env(self.home), "claude")
        self.assertEqual((acc["status"], acc["error_code"], acc["error"]),
                         ("error", "unknown", m.MSG_CLI_MISSING.format(name="claude")))

    def test_a_program_that_cannot_start_is_an_unknown_error(self):
        self.use_clis({"claude": claude_program((FileNotFoundError, FileNotFoundError))})
        acc = self.collect_real(make_env(self.home), "claude")
        self.assertEqual((acc["status"], acc["error_code"]), ("error", "unknown"))

    def test_no_usable_limit_in_either_run_is_quota_unavailable(self):
        empty = claude_text_lines(text="Current session: no data")
        self.use_clis({"claude": claude_program((claude_stream_lines(payload={"rate_limits": {}}), empty))})
        acc = self.collect_real(make_env(self.home), "claude")
        self.assertEqual((acc["status"], acc["error_code"], acc["error"]),
                         ("error", "quota_unavailable", m.MSG_CLAUDE_NO_QUOTA))

    def test_missing_quota_keeps_the_last_good_limits_and_timestamp(self):
        empty = claude_text_lines(text="Current session: no data")
        self.use_clis({"claude": claude_program((claude_stream_lines(payload={"rate_limits": {}}), empty))})
        env = make_env(self.home)
        source = m.default_source("claude", env.paths)
        previous = {"status": "ok", "updated_at": "2026-11-18T17:00:00Z",
                    "limits": [{"key": "five_hour", "used_percent": 40.0, "window_seconds": 18000}]}
        acc = m.collect_account(env, source, previous)
        self.assertEqual((acc["status"], acc["error_code"]), ("stale", "quota_unavailable"))
        self.assertEqual(acc["updated_at"], previous["updated_at"])
        self.assertEqual(acc["limits"], previous["limits"])

    def test_usage_rate_limit_is_classified_without_copying_the_provider_payload(self):
        result = claude_text_lines(
            text='Failed to load usage data: {"error":{"type":"rate_limit_error","message":"provider payload"}}',
            is_error=True)
        self.use_clis({"claude": claude_program((claude_stream_lines(payload={"rate_limits_available": False}), result))})
        acc = self.collect_real(make_env(self.home), "claude")
        self.assertEqual((acc["status"], acc["error_code"], acc["error"]),
                         ("error", "rate_limited", m.MSG_CLAUDE_RATE_LIMITED))
        self.assertNotIn("provider payload", self.stderr.getvalue())

    def test_a_claude_folder_is_never_read_from_the_keychain(self):
        self.all_clis_ok()
        self.collect_real(make_env(self.home), "claude")
        self.assertEqual(self.keychain.reads, [])
        self.assertNotIn("Claude", " ".join(self.keychain.checks))


class ClaudeUsageTextTests(CliBase):
    """The text fallback, `claude -p "/usage"`. The reply is for people to read, so the parsing is checked here."""

    def parse(self, text):
        return m.parse_claude_usage_text(text, NOW)

    def test_session_and_week_lines_become_five_hour_and_seven_day(self):
        limits = self.parse(
            "Current session: 40% used · resets Nov 19 at 6pm (Europe/Berlin)\n"
            "Current week (all models): 67% used · resets Nov 24 at 2am (Europe/Berlin)\n")
        self.assertEqual([(limit["key"], limit["used_percent"], limit["resets_at"], limit["window_seconds"])
                          for limit in limits],
                         [("five_hour", 40.0, "2026-11-19T17:00:00Z", 18000),
                          ("seven_day", 67.0, "2026-11-24T01:00:00Z", 604800)])

    def test_opus_and_sonnet_keep_their_keys_and_other_models_are_skipped(self):
        limits = self.parse(
            "Current week (Opus): 12% used · resets Nov 24 at 2am (Europe/Berlin)\n"
            "Current week (Sonnet): 5% used · resets Nov 24 at 2am (Europe/Berlin)\n"
            "Current week (Fable): 10% used · resets Nov 24 at 2am (Europe/Berlin)\n")
        self.assertEqual([limit["key"] for limit in limits], ["seven_day_opus", "seven_day_sonnet"])
        self.assertEqual(limits[0]["label"], "Opus สัปดาห์")

    def test_a_reset_time_that_cannot_be_read_keeps_the_percentage(self):
        limits = self.parse("Current session: 40% used · resets sometime soon\n")
        self.assertEqual((limits[0]["used_percent"], limits[0]["resets_at"]), (40.0, None))

    def test_wrapped_headers_and_reset_lines_do_not_cross_to_the_next_window(self):
        limits = self.parse(
            "Current session\r\n"
            "  40% used\r\n"
            "  Resets Nov 19 at 6pm (Europe/Berlin)\r\n"
            "Current week (all models):\r\n"
            "  67% used\r\n"
            "Current week (Sonnet): no data\r\n"
            "  Disk utilization: 10% used\r\n")
        self.assertEqual([(item["key"], item["used_percent"], item["resets_at"]) for item in limits],
                         [("five_hour", 40.0, "2026-11-19T17:00:00Z"), ("seven_day", 67.0, None)])

    def test_reset_texts_are_read_in_their_own_zone_with_the_year_worked_out(self):
        cases = {
            "resets Nov 19 at 6pm (Europe/Berlin)": "2026-11-19T17:00:00Z",
            "resets Dec 1 at 9:30am (Europe/Berlin)": "2026-12-01T08:30:00Z",
            "resets Jan 3 at 1pm (Europe/Berlin)": "2027-01-03T12:00:00Z",
            "resets 6pm (Europe/Berlin)": "2026-11-19T17:00:00Z",
            "resets 9am (Europe/Berlin)": "2026-11-19T08:00:00Z",
            "resets 4am (Europe/Berlin)": "2026-11-20T03:00:00Z",
            "resets 14:05 (Europe/Berlin)": "2026-11-19T13:05:00Z",
            "resets Feb 30 at 2pm (Europe/Berlin)": None,
            "resets Nov 19 at 13am (Europe/Berlin)": None,
            "resets soon": None,
        }
        for text, expected in cases.items():
            with self.subTest(text=text):
                self.assertEqual(m.parse_usage_reset(text, NOW), expected)

    def test_an_unknown_zone_name_falls_back_to_this_macs_zone(self):
        self.assertIsInstance(m.parse_usage_reset("resets Nov 19 at 6pm (Nowhere/Zone)", NOW), str)

    def test_a_not_logged_in_text_leaves_the_account_out(self):
        self.use_clis({"claude": claude_program(("hang", claude_text_lines(text="Not logged in · Run /login")))})
        self.assertIsNone(self.collect_real(make_env(self.home), "claude"))


class LoginWordTests(unittest.TestCase):
    def test_login_words_match_as_whole_words_only(self):
        self.assertIsNotNone(m.CODEX_LOGIN_ERROR.search("login required"))
        self.assertIsNotNone(m.CODEX_LOGIN_ERROR.search("not logged in"))
        self.assertIsNotNone(m.AGY_LOGIN_ERROR.search("Please log in to continue"))
        self.assertIsNone(m.CODEX_LOGIN_ERROR.search("designing a usage plan"))
        self.assertIsNone(m.AGY_LOGIN_ERROR.search("signing the quota report"))


class CodexAppServerTests(CliBase):
    def test_the_follow_hook_answers_initialize_once_and_sends_the_two_later_lines(self):
        follow = m.codex_follow()
        self.assertEqual(follow({"id": 1, "result": {}}), m.codex_after_init_lines())
        self.assertEqual(follow({"id": 1, "result": {}}), [])
        self.assertEqual(follow({"id": 2, "result": {}}), [])
        self.assertEqual(len(m.codex_after_init_lines()), 2)
        self.assertIn(b'"method":"initialized"', m.codex_after_init_lines()[0])

    def test_rate_limits_are_read_with_the_three_allowed_messages_and_no_other(self):
        clis = self.use_clis({"codex": single_program(codex_rpc_lines())})
        acc = self.collect_real(make_env(self.home), "codex")
        self.assertEqual(acc["status"], "ok")
        proc = clis.procs[0]
        self.assertEqual(written_methods(proc), ["initialize", "initialized", "account/rateLimits/read"])
        self.assertEqual(clis.launched("codex")[0]["argv"][1:], ["app-server", "--listen", "stdio://"])
        sent = json.loads(proc.stdin.written[2])
        self.assertEqual(sent["params"], {"excludeResetCreditDetails": True})
        for method in CODEX_METHODS_FORBIDDEN:
            self.assertFalse(any(method in (name or "") for name in written_methods(proc)), method)
        self.assertTrue(set(written_methods(proc)) <= set(CODEX_METHODS_ALLOWED) | {None})

    def test_each_window_is_labelled_by_its_own_length_and_keeps_its_slot_as_key(self):
        result = dict(CODEX_RATE_RESULT, rateLimits=dict(CODEX_RATE_RESULT["rateLimits"], primary={
            "usedPercent": 10, "windowDurationMins": 300, "resetsAt": ts("2026-11-19T09:00:00Z")},
            secondary={"usedPercent": 50, "windowDurationMins": 10080,
                       "resetsAt": ts("2026-11-20T02:15:51Z")}))
        self.use_clis({"codex": single_program(codex_rpc_lines(result))})
        acc = self.collect_real(make_env(self.home), "codex")
        self.assertEqual([(limit["key"], limit["label"], limit["window_seconds"]) for limit in acc["limits"]],
                         [("primary", "5 ชม.", 18000), ("secondary", "สัปดาห์", 604800)])
        self.assertEqual(acc["plan"], "Pro Lite")
        self.assertEqual(acc["credits"]["balance_usd"], 0.0)
        self.assertEqual(acc["limits"][1]["resets_at"], "2026-11-20T02:15:51Z")

    def test_a_login_error_from_the_server_is_login_expired(self):
        self.use_clis({"codex": single_program(codex_rpc_lines_error("not logged in"))})
        acc = self.collect_real(make_env(self.home), "codex")
        self.assertEqual((acc["error_code"], acc["error"]), ("login_expired", m.MSG_CODEX_EXPIRED))

    def test_another_server_error_is_unknown_and_its_text_is_not_shown(self):
        self.use_clis({"codex": single_program(codex_rpc_lines_error("upstream failed for " + FAKE_ACCOUNT_ID))})
        acc = self.collect_real(make_env(self.home), "codex")
        self.assertEqual((acc["error_code"], acc["error"]), ("unknown", m.MSG_CODEX_REJECTED))
        self.assertNotIn(FAKE_ACCOUNT_ID, json.dumps(acc) + self.stderr.getvalue())

    def test_a_result_without_rate_limits_is_a_format_error(self):
        self.use_clis({"codex": single_program(codex_rpc_lines({"ordinaryUsageAllowed": True}))})
        acc = self.collect_real(make_env(self.home), "codex")
        self.assertEqual((acc["error_code"], acc["error"]), ("unknown", m.MSG_CODEX_FORMAT))
        self.assertIn("rateLimits missing", self.stderr.getvalue())

    def test_a_hung_server_is_killed_and_is_a_network_error(self):
        clis = self.use_clis({"codex": single_program("hang")})
        acc = self.collect_real(make_env(self.home), "codex")
        self.assertEqual((acc["error_code"], acc["error"]), ("network", m.MSG_CODEX_TIMEOUT))
        self.assertTrue(clis.procs[0].killed)

    def test_a_missing_codex_program_is_an_unknown_error(self):
        self.use_clis({})
        acc = self.collect_real(make_env(self.home), "codex")
        self.assertEqual((acc["error_code"], acc["error"]), ("unknown", m.MSG_CLI_MISSING.format(name="codex")))

    def test_an_extra_codex_home_is_passed_as_CODEX_HOME_and_the_main_one_is_not(self):
        extra = self.home / ".codex-2"
        extra.mkdir()
        (extra / "auth.json").write_text("{}", encoding="utf-8")
        clis = self.use_clis({"codex": single_program(codex_rpc_lines())})
        self.main_dry_run()
        homes = [launch["env"].get("CODEX_HOME") for launch in clis.launched("codex")]
        self.assertEqual(homes, [None, str(extra)])


def codex_rpc_lines_error(message):
    return [json_line({"id": 1, "result": {"platformOs": "macos"}}),
            json_line({"id": 2, "error": {"code": -32600, "message": message}})]


class AgyUsageTests(CliBase):
    def test_bucket_lines_become_labelled_limits_without_a_window_length(self):
        self.use_clis({"agy": single_program(agy_usage_lines())})
        acc = self.collect_real(make_env(self.home, self.keychain), "agy")
        self.assertEqual(acc["status"], "ok")
        self.assertEqual([(limit["key"], limit["label"], limit["used_percent"], limit["resets_at"],
                           limit["window_seconds"]) for limit in acc["limits"]],
                         [("gemini-5h", "Gemini Models · 5h", 0.0, "2026-11-19T09:00:00Z", None),
                          ("gemini-weekly", "Gemini Models · Weekly", 50.0, "2026-11-24T02:00:00Z", None),
                          ("3p-weekly", "Claude & GPT · Weekly", 100.0, "2026-11-24T02:00:00Z", None)])

    def test_agy_is_not_started_without_a_keychain_login(self):
        self.keychain.passwords.clear()
        clis = self.use_clis({"agy": single_program(agy_usage_lines())})
        self.assertEqual(self.main_dry_run()[0], 0)
        self.assertEqual(clis.launches, [])

    def test_a_status_that_is_not_success_with_login_text_is_login_expired(self):
        doc = dict(AGY_USAGE_DOC, status="ERROR", response="Please log in to continue")
        self.use_clis({"agy": single_program(agy_usage_lines(doc))})
        acc = self.collect_real(make_env(self.home, self.keychain), "agy")
        self.assertEqual((acc["error_code"], acc["error"]), ("login_expired", m.MSG_AGY_EXPIRED))

    def test_output_that_is_not_json_is_a_format_error(self):
        self.use_clis({"agy": single_program([b"agy is updating, try again\n"])})
        acc = self.collect_real(make_env(self.home, self.keychain), "agy")
        self.assertEqual((acc["error_code"], acc["error"]), ("unknown", m.MSG_AGY_FORMAT))

    def test_output_without_groups_is_a_format_error(self):
        doc = {"status": "SUCCESS", "command": {"name": "usage", "data": {}}}
        self.use_clis({"agy": single_program(agy_usage_lines(doc))})
        acc = self.collect_real(make_env(self.home, self.keychain), "agy")
        self.assertEqual(acc["error"], m.MSG_AGY_FORMAT)

    def test_group_names_are_scrubbed_and_capped_before_they_are_shown(self):
        long_name = "Team " + FAKE_EMAIL + " " + "x" * 80
        doc = dict(AGY_USAGE_DOC)
        doc["command"] = {"name": "usage", "data": {"groups": [dict(AGY_USAGE_DOC["command"]["data"]["groups"][1],
                                                                    name=long_name)]}}
        self.use_clis({"agy": single_program(agy_usage_lines(doc))})
        acc = self.collect_real(make_env(self.home, self.keychain), "agy")
        label = acc["limits"][0]["label"]
        self.assertNotIn(FAKE_EMAIL, label)
        self.assertLessEqual(len(label.split(" · ")[0]), 40)
        self.assertTrue(label.endswith(" · Weekly"))

    def test_a_bucket_without_a_fraction_is_used_up_when_it_has_a_reset_and_skipped_without_either(self):
        groups = [{"name": "Gemini Models", "buckets": [
            {"id": "gemini-5h", "window": "5h", "reset_time": "2026-11-19T09:00:00Z"},
            {"id": "gemini-weekly", "window": "weekly"}]}]
        self.use_clis({"agy": single_program(agy_usage_lines(dict(AGY_USAGE_DOC,
                                                                  command={"data": {"groups": groups}})))})
        acc = self.collect_real(make_env(self.home, self.keychain), "agy")
        self.assertEqual([(limit["key"], limit["used_percent"]) for limit in acc["limits"]], [("gemini-5h", 100.0)])

    def test_a_hung_agy_is_killed_and_is_a_network_error(self):
        clis = self.use_clis({"agy": single_program("hang")})
        acc = self.collect_real(make_env(self.home, self.keychain), "agy")
        self.assertEqual((acc["error_code"], acc["error"]), ("network", m.MSG_AGY_TIMEOUT))
        self.assertTrue(clis.procs[0].killed)

    def test_a_missing_agy_program_is_an_unknown_error(self):
        self.use_clis({})
        acc = self.collect_real(make_env(self.home, self.keychain), "agy")
        self.assertEqual((acc["error_code"], acc["error"]), ("unknown", m.MSG_CLI_MISSING.format(name="agy")))


class DefaultModeInvariantTests(CliBase):
    def test_default_mode_reads_no_keychain_password_opens_no_login_file_and_calls_no_endpoint(self):
        (self.home / ".codex" / "auth.json").write_text("{garbage", encoding="utf-8")
        self.all_clis_ok()
        real_read = m.read_json_file

        def guarded(path, *args, **kwargs):
            if Path(path).name == "auth.json":
                raise ForbiddenCall("a login file was opened")
            return real_read(path, *args, **kwargs)

        with mock.patch.object(m, "read_json_file", guarded):
            code, out = self.main_dry_run()
        self.assertEqual(code, 0)
        self.assertEqual(self.keychain.reads, [])
        self.assertEqual(self.http.calls, [])
        self.assertEqual([account["id"] for account in json.loads(out)["accounts"]],
                         ["claude-main", "codex-main", "agy-main"])

    def test_direct_mode_needs_json_true_and_only_for_codex_and_agy(self):
        self.assertEqual(m.direct_modes({"direct_mode": {"codex": True, "agy": True}}),
                         {"codex": True, "agy": True})
        self.assertEqual(m.direct_modes({"direct_mode": {"codex": True, "agy": "true", "claude": True}}),
                         {"codex": True})
        self.assertEqual(m.direct_modes({"direct_mode": {"codex": 1}}), {})
        self.assertEqual(m.direct_modes({"direct_mode": "codex"}), {})
        self.assertEqual(m.direct_modes({}), {})

    def test_claude_has_no_direct_mode_so_its_setting_changes_nothing(self):
        (self.home / "Library" / "Application Support" / "AIUsage").mkdir(parents=True)
        (self.home / "Library" / "Application Support" / "AIUsage" / "settings.json").write_text(
            json.dumps({"direct_mode": {"claude": True}}), encoding="utf-8")
        clis = self.all_clis_ok()
        self.main_dry_run()
        self.assertEqual(len(clis.launched("claude")), 1)  # get_usage answered, so /usage is not run
        self.assertEqual(self.http.calls, [])

    def test_codex_direct_mode_uses_the_token_path_and_starts_no_codex_program(self):
        (self.home / "Library" / "Application Support" / "AIUsage").mkdir(parents=True)
        (self.home / "Library" / "Application Support" / "AIUsage" / "settings.json").write_text(
            json.dumps({"direct_mode": {"codex": True}}), encoding="utf-8")
        self.http.routes[m.CODEX_USAGE_URL] = resp(CODEX_USAGE_BODY)
        clis = self.all_clis_ok()
        code, out = self.main_dry_run()
        self.assertEqual(code, 0)
        self.assertEqual(clis.launched("codex"), [])
        self.assertEqual([call["url"] for call in self.http.calls], [m.CODEX_USAGE_URL])
        codex = [a for a in json.loads(out)["accounts"] if a["id"] == "codex-main"][0]
        self.assertEqual(codex["limits"][0]["window_seconds"], 604800)


class ChildEnvironmentTests(CliBase):
    def test_the_child_gets_a_whitelist_and_none_of_the_secrets_or_config_variables(self):
        leaking = {"ANTHROPIC_API_KEY": "sk-FIXTURE-API-KEY-1", "ANTHROPIC_BASE_URL": "http://fixture-base-url",
                   "CLAUDECODE": "fixture-claudecode-marker", "CLAUDE_CODE_OAUTH_TOKEN": FAKE_SESSION,
                   "CLAUDE_CONFIG_DIR": "/fixture-elsewhere", "CODEX_HOME": "/fixture-codex-elsewhere",
                   "OPENAI_API_KEY": "sk-FIXTURE-API-KEY-2", "SOME_SECRET": FAKE_AGY_ACCESS,
                   "LANG": "en_US.UTF-8", "TMPDIR": "/tmp/fixture/"}
        with mock.patch.dict(os.environ, leaking):
            clis = self.all_clis_ok()
            self.collect_real(make_env(self.home), "claude")
        env = clis.launched("claude")[0]["env"]
        for name, value in leaking.items():
            if name not in ("LANG", "TMPDIR"):
                self.assertNotIn(name, env, name)
                self.assertNotIn(value, json.dumps(env), name)
        self.assertEqual(env["LANG"], "en_US.UTF-8")
        self.assertEqual(env["TMPDIR"], "/tmp/fixture/")
        self.assertEqual(env["HOME"], str(self.home))
        self.assertTrue(set(env) <= set(m.CLI_ENV_KEYS) | {"PATH"})

    def test_the_search_path_has_homebrew_and_local_bin_for_every_run(self):
        with mock.patch.dict(os.environ, {"PATH": "/usr/bin:/bin"}):
            clis = self.all_clis_ok()
            self.main_dry_run()
        for launch in clis.launches:
            folders = launch["env"]["PATH"].split(os.pathsep)
            self.assertIn("/opt/homebrew/bin", folders)
            self.assertIn(os.path.expanduser("~/.local/bin"), folders)
            self.assertEqual(len(folders), len(set(folders)))

    def test_each_claude_folder_is_set_by_its_own_variable_and_the_main_one_by_none(self):
        extra = self.home / ".claude-2"
        extra.mkdir()
        (extra / ".claude.json").write_text("{}", encoding="utf-8")
        second = str(extra)
        clis = self.use_clis({"claude": claude_program(
            (claude_stream_lines(), claude_text_lines()),
            folders={second: (claude_stream_lines(dict(CLAUDE_RATE_LIMITS, five_hour={
                "utilization": 85, "resets_at": "2026-11-19T06:40:00.000000+00:00"})), claude_text_lines())}),
            "codex": single_program(codex_rpc_lines()), "agy": single_program(agy_usage_lines())})
        code, out = self.main_dry_run()
        self.assertEqual(code, 0)
        claude = [launch for launch in clis.launched("claude") if "--input-format" in launch["argv"]]
        self.assertEqual([launch["env"].get("CLAUDE_CONFIG_DIR") for launch in claude], [None, second])
        ids = [account["id"] for account in json.loads(out)["accounts"]]
        self.assertEqual(ids, ["claude-main", "claude-2", "codex-main", "agy-main"])

    def test_the_working_folder_is_the_app_folder_when_it_exists_and_the_home_otherwise(self):
        clis = self.all_clis_ok()
        self.main_dry_run()
        self.assertEqual(clis.launched("codex")[0]["cwd"], str(self.home))
        (self.home / "Library" / "Application Support" / "AIUsage").mkdir(parents=True)
        self.main_dry_run()
        self.assertEqual(clis.launched("codex")[-1]["cwd"],
                         str(self.home / "Library" / "Application Support" / "AIUsage"))

    def test_a_stdin_that_is_a_protocol_pipe_is_only_for_the_two_servers(self):
        clis = self.all_clis_ok()
        self.main_dry_run()
        by_name = {}
        for launch in clis.launches:
            by_name.setdefault(launch["name"], []).append(launch["stdin"])
        self.assertEqual(by_name["codex"], [subprocess.PIPE])
        self.assertEqual(by_name["claude"][0], subprocess.PIPE)
        self.assertEqual(by_name["agy"], [subprocess.DEVNULL])


# ---------------------------------------------------------------- the real runner, with stub programs

STUB_PROTOCOL = """
import json, sys
for raw in sys.stdin:
    message = json.loads(raw)
    if message.get("request_id") == "init-1":
        reply = {"subtype": "success", "request_id": "init-1", "response": {}}
    elif message.get("request_id") == "usage-1":
        reply = {"subtype": "success", "request_id": "usage-1", "response": {
            "subscription_type": "pro", "rate_limits": {"five_hour": {
                "utilization": 3, "resets_at": "2026-11-19T06:40:00.000000+00:00"}}}}
    else:
        continue
    print(json.dumps({"type": "control_response", "response": reply}), flush=True)
"""
STUB_CODEX = """
import json, sys
lines = iter(sys.stdin)
json.loads(next(lines))  # initialize
print(json.dumps({"id": 1, "result": {"platformOs": "macos"}}), flush=True)
for raw in lines:  # initialized, then the read; the read is answered only after the reply to initialize
    message = json.loads(raw)
    if message.get("id") == 2:
        print(json.dumps({"id": 2, "result": {"rateLimits": {"primary": {
            "usedPercent": 7, "windowDurationMins": 10080, "resetsAt": 1795000000}}}}), flush=True)
"""
STUB_HANG = "import time\ntime.sleep(60)\n"
STUB_ONE_SHOT = """
import json, sys
print(json.dumps({"type": "result", "result": "Current session: 4% used"}, indent=2))
print("user@example.com", file=sys.stderr)
"""
STUB_BIG = "print('x' * 10000)\n"
STUB_LEAVES_CHILD = """
import json, subprocess, sys
child = subprocess.Popen([sys.executable, "-I", "-c", "import time; time.sleep(60)"])
open(sys.argv[1], "w", encoding="utf-8").write(str(child.pid))
print(json.dumps({"type": "result", "result": "Current session: 4% used"}), flush=True)
"""


class RealRunnerTests(unittest.TestCase):
    """Runs the real subprocess code against stub programs in a temporary folder. No provider program is started."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)
        for name, source in (("protocol.py", STUB_PROTOCOL), ("codex_like.py", STUB_CODEX),
                             ("hang.py", STUB_HANG), ("one_shot.py", STUB_ONE_SHOT), ("big.py", STUB_BIG),
                             ("leaves_child.py", STUB_LEAVES_CHILD)):
            (self.dir / name).write_text(source, encoding="utf-8")
        for target in ("subprocess.Popen", "os.killpg"):
            patcher = mock.patch(target, REAL_POPEN if target == "subprocess.Popen" else REAL_KILLPG)
            patcher.start()
            self.addCleanup(patcher.stop)
        self.env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin")}

    def stub(self, name):
        return [sys.executable, "-I", str(self.dir / name)]

    def test_the_protocol_answers_and_the_stub_ends_when_stdin_closes(self):
        run = m.run_cli(self.stub("protocol.py"), cwd=str(self.dir), env=self.env,
                        feed=m.claude_requests(),
                        until=lambda message: m.control_reply(message, "usage-1") is not None, timeout=20)
        self.assertFalse(run.timed_out)
        self.assertIsNotNone(m.control_reply(run.found, "usage-1"))
        self.assertEqual(run.returncode, 0)

    def test_the_codex_read_is_sent_only_after_the_reply_to_initialize(self):
        run = m.run_cli(self.stub("codex_like.py"), cwd=str(self.dir), env=self.env,
                        feed=m.codex_init_lines(), follow=m.codex_follow(),
                        until=lambda message: message.get("id") == 2 and "result" in message, timeout=20)
        self.assertFalse(run.timed_out)
        self.assertEqual(run.found["result"]["rateLimits"]["primary"]["usedPercent"], 7)

    def test_a_child_the_cli_leaves_running_does_not_hold_the_run_and_is_stopped(self):
        pid_file = self.dir / "child.pid"
        started = time.monotonic()
        run = m.run_cli([sys.executable, "-I", str(self.dir / "leaves_child.py"), str(pid_file)],
                        cwd=str(self.dir), env=self.env, timeout=20)
        self.assertFalse(run.timed_out)
        self.assertLess(time.monotonic() - started, 10)
        self.assertEqual(m.read_json_bytes(b"".join(run.lines))["result"], "Current session: 4% used")
        child = int(pid_file.read_text(encoding="utf-8"))
        deadline = time.monotonic() + 10
        while True:
            try:
                os.kill(child, 0)
            except ProcessLookupError:
                break
            self.assertLess(time.monotonic(), deadline, "the child was not stopped")
            time.sleep(0.1)

    def test_a_program_that_never_answers_is_killed_at_the_timeout(self):
        started = time.monotonic()
        run = m.run_cli(self.stub("hang.py"), cwd=str(self.dir), env=self.env,
                        feed=m.claude_requests(), until=lambda message: False, timeout=1)
        self.assertTrue(run.timed_out)
        self.assertLess(time.monotonic() - started, 15)
        self.assertLess(run.returncode, 0)  # killed, not exited

    def test_a_one_shot_run_reads_the_whole_output_and_never_keeps_stderr(self):
        run = m.run_cli(self.stub("one_shot.py"), cwd=str(self.dir), env=self.env, timeout=20)
        doc = m.read_json_bytes(b"".join(run.lines))
        self.assertEqual(doc["result"], "Current session: 4% used")
        self.assertNotIn(FAKE_EMAIL, repr(run))

    def test_a_missing_program_is_reported_as_missing(self):
        run = m.run_cli(["/nonexistent/fixture-cli/claude"], cwd=str(self.dir), env=self.env, timeout=5)
        self.assertEqual(run.spawn_error, "missing")

    def test_output_over_the_limit_stops_the_run(self):
        with mock.patch.object(m, "CLI_OUTPUT_LIMIT", 200):
            run = m.run_cli(self.stub("big.py"), cwd=str(self.dir), env=self.env, timeout=20)
        self.assertTrue(run.too_large)


if __name__ == "__main__":
    unittest.main()
