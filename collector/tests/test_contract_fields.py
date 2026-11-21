"""Tests for the language-neutral contract fields.

Every limit carries window_seconds: an integer, or null where the window has no length (agy buckets and groups).
Every account carries error_code: null when it is ok, otherwise one of the seven documented codes.
The Thai `label` and `error` texts stay as they are. Default mode runs the scripted CLIs; the direct-mode
checks use mock HTTP. No network, no real Keychain, no provider program is started.
"""
import json
import unittest

import ai_usage_collect as m
from tests.test_collector import (AGY_LOAD_BODY, AGY_MODELS_BODY, CODEX_RATE_RESULT, CODEX_USAGE_BODY, NOW,
                                  Base, FakeHTTP, FakeKeychain, agy_pw, agy_usage_lines, claude_program,
                                  claude_stream_error_lines, claude_stream_lines, claude_text_lines,
                                  codex_rpc_lines, control_response, json_line, make_env, resp,
                                  single_program)

DOCUMENTED_CODES = {"login_expired", "relogin_needed", "not_set_up", "network", "rate_limited",
                    "server_error", "unknown"}


class WindowSecondsTests(Base):
    def test_claude_limits_from_get_usage_carry_18000_and_604800_seconds(self):
        self.use_clis({"claude": claude_program((claude_stream_lines(), claude_text_lines()))})
        acc = self.collect_real(make_env(self.home), "claude")
        by_key = {limit["key"]: limit for limit in acc["limits"]}
        self.assertEqual(by_key["five_hour"]["window_seconds"], 18000)
        self.assertEqual(by_key["seven_day"]["window_seconds"], 604800)

    def test_claude_usage_text_limits_carry_the_same_lengths(self):
        self.use_clis({"claude": claude_program(("hang", claude_text_lines()))})
        acc = self.collect_real(make_env(self.home), "claude")
        by_key = {limit["key"]: limit for limit in acc["limits"]}
        self.assertEqual((by_key["five_hour"]["window_seconds"], by_key["seven_day"]["window_seconds"]),
                         (18000, 604800))

    def test_codex_limit_carries_the_window_length_the_cli_reports_in_minutes(self):
        self.write_codex_auth()
        self.use_clis({"codex": single_program(codex_rpc_lines())})
        acc = self.collect_real(make_env(self.home), "codex")
        self.assertEqual(acc["limits"][0]["window_seconds"], 604800)

    def test_codex_limit_is_null_when_the_cli_gives_no_length(self):
        result = dict(CODEX_RATE_RESULT, rateLimits=dict(CODEX_RATE_RESULT["rateLimits"], primary={
            "usedPercent": 5, "windowDurationMins": None, "resetsAt": None}))
        self.write_codex_auth()
        self.use_clis({"codex": single_program(codex_rpc_lines(result))})
        acc = self.collect_real(make_env(self.home), "codex")
        self.assertIsNone(acc["limits"][0]["window_seconds"])
        self.assertEqual(acc["limits"][0]["label"], "ช่วงเวลา")  # the Thai label is still written

    def test_agy_bucket_limits_have_null_window_seconds(self):
        self.use_clis({"agy": single_program(agy_usage_lines())})
        keychain = FakeKeychain({m.AGY_KEYCHAIN_SERVICE: agy_pw()})
        acc = self.collect_real(make_env(self.home, keychain), "agy")
        self.assertTrue(acc["limits"])
        self.assertTrue(all(limit["window_seconds"] is None for limit in acc["limits"]))

    def test_agy_direct_mode_group_limits_have_null_window_seconds(self):
        limits = m.group_agy_models(AGY_MODELS_BODY["models"])
        self.assertTrue(limits)
        self.assertTrue(all(limit["window_seconds"] is None for limit in limits))

    def test_codex_direct_mode_limit_carries_the_window_length_the_api_reports(self):
        self.write_codex_auth()
        http = FakeHTTP({m.CODEX_USAGE_URL: resp(CODEX_USAGE_BODY)})
        acc = self.collect_real(make_env(self.home, http=http, direct={"codex": True}), "codex")
        self.assertEqual(acc["limits"][0]["window_seconds"], 604800)

    def test_a_stale_limit_from_an_old_file_gets_its_length_filled_in(self):
        previous = {"plan": "Max", "status": "ok", "updated_at": "2026-11-19T04:00:00Z",
                    "limits": [{"key": "seven_day", "label": "สัปดาห์", "used_percent": 60.0,
                                "resets_at": None}],
                    "usage": None, "credits": None}
        self.use_clis({"claude": claude_program(("hang", "hang"))})
        acc = self.collect_real(make_env(self.home), "claude", previous)
        self.assertEqual(acc["status"], "stale")
        self.assertEqual(acc["limits"][0]["window_seconds"], 604800)


class ErrorCodeTests(Base):
    """Each failure of each provider, in default mode, names one documented code and its Thai text."""

    def claude(self, stream, text=None, previous=None):
        self.use_clis({"claude": claude_program((stream, text if text is not None else claude_text_lines()))})
        return self.collect_real(make_env(self.home), "claude", previous)

    def test_an_ok_account_has_a_null_error_code(self):
        acc = self.claude(claude_stream_lines())
        self.assertEqual((acc["status"], acc["error_code"]), ("ok", None))

    def test_a_claude_that_does_not_answer_in_time_is_network(self):
        acc = self.claude("hang", "hang")
        self.assertEqual((acc["error_code"], acc["error"]), ("network", m.MSG_CLAUDE_TIMEOUT))

    def test_a_claude_that_cannot_be_read_at_all_is_unknown(self):
        acc = self.claude([b"not json\n"], text=[b"still not json\n"])
        self.assertEqual((acc["error_code"], acc["error"]), ("unknown", m.MSG_CLAUDE_FORMAT))

    def test_a_claude_that_is_not_logged_in_is_left_out_not_an_error(self):
        self.assertIsNone(self.claude(claude_stream_error_lines()))

    def test_a_claude_that_rejects_the_request_is_unknown(self):
        reply = [json_line(control_response("init-1", {})), json_line(control_response(
            "usage-1", error="rate window opened elsewhere"))]
        acc = self.claude(reply, text=claude_text_lines(text="no usage here", is_error=True))
        self.assertEqual((acc["error_code"], acc["error"]), ("unknown", m.MSG_CLAUDE_REJECTED))

    def test_a_missing_claude_is_unknown(self):
        self.use_clis({})
        acc = self.collect_real(make_env(self.home), "claude")
        self.assertEqual((acc["error_code"], acc["error"]), ("unknown", m.MSG_CLI_MISSING.format(name="claude")))

    def test_a_codex_login_error_from_the_server_is_login_expired(self):
        self.write_codex_auth()
        self.use_clis({"codex": single_program([json_line({"id": 1, "result": {}}),
                                                json_line({"id": 2, "error": {"message": "login required"}})])})
        acc = self.collect_real(make_env(self.home), "codex")
        self.assertEqual((acc["error_code"], acc["error"]), ("login_expired", m.MSG_CODEX_EXPIRED))

    def test_a_codex_that_does_not_answer_in_time_is_network(self):
        self.write_codex_auth()
        self.use_clis({"codex": single_program("hang")})
        acc = self.collect_real(make_env(self.home), "codex")
        self.assertEqual((acc["error_code"], acc["error"]), ("network", m.MSG_CODEX_TIMEOUT))

    def test_a_codex_server_error_is_unknown(self):
        self.write_codex_auth()
        self.use_clis({"codex": single_program([json_line({"id": 1, "result": {}}),
                                                json_line({"id": 2, "error": {"message": "boom"}})])})
        acc = self.collect_real(make_env(self.home), "codex")
        self.assertEqual((acc["error_code"], acc["error"]), ("unknown", m.MSG_CODEX_REJECTED))

    def test_an_agy_login_rejected_by_the_cli_is_login_expired(self):
        doc = {"status": "ERROR", "response": "You are not logged in"}
        self.use_clis({"agy": single_program(agy_usage_lines(doc))})
        keychain = FakeKeychain({m.AGY_KEYCHAIN_SERVICE: agy_pw()})
        acc = self.collect_real(make_env(self.home, keychain), "agy")
        self.assertEqual((acc["error_code"], acc["error"]), ("login_expired", m.MSG_AGY_EXPIRED))

    def test_an_agy_that_does_not_answer_in_time_is_network(self):
        self.use_clis({"agy": single_program("hang")})
        keychain = FakeKeychain({m.AGY_KEYCHAIN_SERVICE: agy_pw()})
        acc = self.collect_real(make_env(self.home, keychain), "agy")
        self.assertEqual((acc["error_code"], acc["error"]), ("network", m.MSG_AGY_TIMEOUT))

    def test_an_agy_answer_in_another_shape_is_unknown(self):
        self.use_clis({"agy": single_program([b'{"status": "SUCCESS", "command": {"data": {}}}\n'])})
        keychain = FakeKeychain({m.AGY_KEYCHAIN_SERVICE: agy_pw()})
        acc = self.collect_real(make_env(self.home, keychain), "agy")
        self.assertEqual((acc["error_code"], acc["error"]), ("unknown", m.MSG_AGY_FORMAT))

    def test_a_codex_login_without_a_token_asks_for_relogin_in_direct_mode(self):
        path = self.home / ".codex" / "auth.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps({"auth_mode": "apikey", "OPENAI_API_KEY": None}), encoding="utf-8")
        acc = self.collect_real(make_env(self.home, direct={"codex": True}), "codex")
        self.assertEqual((acc["error_code"], acc["error"]), ("relogin_needed", m.MSG_CODEX_EXPIRED))

    def test_direct_mode_codex_401_is_login_expired_and_500_is_server_error(self):
        self.write_codex_auth()
        acc = self.collect_real(make_env(self.home, http=FakeHTTP({m.CODEX_USAGE_URL: (401, b"{}")}),
                                         direct={"codex": True}), "codex")
        self.assertEqual((acc["error_code"], acc["error"]), ("login_expired", m.MSG_CODEX_EXPIRED))
        acc = self.collect_real(make_env(self.home, http=FakeHTTP({m.CODEX_USAGE_URL: (500, b"{}")}),
                                         direct={"codex": True}), "codex")
        self.assertEqual(acc["error_code"], "server_error")

    def test_direct_mode_codex_429_is_rate_limited_and_403_is_unknown_and_no_answer_is_network(self):
        self.write_codex_auth()
        cases = ((429, "rate_limited"), (403, "unknown"), (None, "network"))
        for status, code in cases:
            with self.subTest(status=status):
                acc = self.collect_real(make_env(self.home, http=FakeHTTP({m.CODEX_USAGE_URL: (status, b"{}")}),
                                                 direct={"codex": True}), "codex")
                self.assertEqual(acc["error_code"], code)

    def test_direct_mode_agy_load_401_is_login_expired_and_no_project_is_not_set_up(self):
        keychain = FakeKeychain({m.AGY_KEYCHAIN_SERVICE: agy_pw()})
        acc = self.collect_real(make_env(self.home, keychain, FakeHTTP({m.AGY_LOAD_URL: (401, b"{}")}),
                                         direct={"agy": True}), "agy")
        self.assertEqual((acc["error_code"], acc["error"]), ("login_expired", m.MSG_AGY_EXPIRED))
        http = FakeHTTP({m.AGY_LOAD_URL: resp({"allowedTiers": [{"id": "standard-tier"}]})})
        acc = self.collect_real(make_env(self.home, keychain, http, direct={"agy": True}), "agy")
        self.assertEqual((acc["error_code"], acc["error"]), ("not_set_up", m.MSG_AGY_NO_PROJECT))

    def test_direct_mode_agy_models_500_is_server_error_and_a_broken_login_asks_for_relogin(self):
        keychain = FakeKeychain({m.AGY_KEYCHAIN_SERVICE: agy_pw()})
        http = FakeHTTP({m.AGY_LOAD_URL: resp(AGY_LOAD_BODY), m.AGY_MODELS_URL: (500, b"{}")})
        acc = self.collect_real(make_env(self.home, keychain, http, direct={"agy": True}), "agy")
        self.assertEqual(acc["error_code"], "server_error")
        broken = FakeKeychain({m.AGY_KEYCHAIN_SERVICE: "not a login"})
        acc = self.collect_real(make_env(self.home, broken, direct={"agy": True}), "agy")
        self.assertEqual((acc["error_code"], acc["error"]), ("relogin_needed", m.MSG_AGY_MISSING))

    def test_an_unexpected_exception_is_unknown(self):
        def boom(env):
            raise ValueError("unexpected")

        acc = self.collect(make_env(self.home), boom, None)
        self.assertEqual((acc["error_code"], acc["error"]), ("unknown", m.MSG_GENERIC))

    def test_a_stale_account_reports_the_code_of_the_current_failure(self):
        previous = {"plan": "Max", "status": "ok", "updated_at": "2026-11-19T04:00:00Z",
                    "limits": [{"key": "five_hour", "label": "5 ชม.", "used_percent": 42.0,
                                "resets_at": None}],
                    "usage": None, "credits": None}
        acc = self.claude("hang", "hang", previous)
        self.assertEqual((acc["status"], acc["error_code"]), ("stale", "network"))
        self.assertEqual(acc["updated_at"], "2026-11-19T04:00:00Z")


class ContractTests(Base):
    def test_the_documented_error_codes_are_exactly_seven(self):
        codes = {m.ERROR_LOGIN_EXPIRED, m.ERROR_RELOGIN_NEEDED, m.ERROR_NOT_SET_UP, m.ERROR_NETWORK,
                 m.ERROR_RATE_LIMITED, m.ERROR_SERVER, m.ERROR_UNKNOWN}
        self.assertEqual(codes, DOCUMENTED_CODES)

    def test_the_document_carries_both_fields_next_to_the_thai_text(self):
        self.use_clis({"claude": claude_program((claude_stream_lines(), claude_text_lines()))})
        ok = self.collect_real(make_env(self.home), "claude")
        self.use_clis({"claude": claude_program(("hang", "hang"))})
        failed = self.collect_real(make_env(self.home), "claude")
        doc = json.loads(m.serialize(m.build_document(NOW, [ok, failed])))
        first, second = doc["accounts"]
        self.assertIsNone(first["error_code"])
        self.assertEqual(first["limits"][0]["window_seconds"], 18000)
        self.assertEqual(first["limits"][0]["label"], "5 ชม.")
        self.assertEqual(second["error_code"], "network")
        self.assertEqual(second["error"], m.MSG_CLAUDE_TIMEOUT)


if __name__ == "__main__":
    unittest.main()
