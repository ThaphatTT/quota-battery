"""Unit tests for ai_usage_collect, and the fixtures that the other test modules share.

No network, no real subprocess and no real Keychain. urlopen, subprocess.run, subprocess.Popen and os.killpg
are patched to raise ForbiddenCall, so a call that escapes the fakes fails the test. The provider CLIs are
scripted with FakeCLIs (see Base.use_clis). Every path points into a temporary home folder.
"""
import base64
import contextlib
import fcntl
import io
import json
import os
import subprocess
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest import mock
from zoneinfo import ZoneInfo

import ai_usage_collect as m

NOW = datetime(2026, 11, 19, 4, 30, tzinfo=timezone.utc)  # 05:30 in Berlin, the day zone the tests inject
ICLOUD_REL = Path("Library/Mobile Documents/iCloud~dk~simonbs~Scriptable/Documents")
MAC_REL = Path("Library/Application Support/AIUsage")

# Invented values that must never reach the output, a log line or a file.
FAKE_CODEX_ACCESS = "eyJFAKECODEX0123456789abcdef"
FAKE_ACCOUNT_ID = "acct-FAKE-0123456789"
FAKE_AGY_ACCESS = "ya29.FAKEAGYACCESS0123456789"
FAKE_PROJECT = "fake-project-123"
FAKE_EMAIL = "user@example.com"
FAKE_SESSION = "session-FAKE-0123456789"
SENTINELS = (FAKE_CODEX_ACCESS, FAKE_ACCOUNT_ID, FAKE_AGY_ACCESS, FAKE_PROJECT, FAKE_EMAIL, FAKE_SESSION)


class FrozenDatetime(datetime):
    """datetime as ai_usage_collect sees it during a run: now() is the fixture clock NOW."""

    @classmethod
    def now(cls, tz=None):
        return NOW if tz is None else NOW.astimezone(tz)


class ForbiddenCall(BaseException):
    """Raised when code under test reaches for the network, a subprocess or the real Keychain."""


def ms(moment: datetime) -> int:
    return int(moment.timestamp() * 1000)


def ts(text: str) -> int:
    return int(datetime.fromisoformat(text.replace("Z", "+00:00")).timestamp())


def resp(obj, status=200):
    return status, json.dumps(obj).encode("utf-8")


def json_line(obj) -> bytes:
    """One line of JSON as a CLI writes it to stdout (or reads it from stdin)."""
    return (json.dumps(obj, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8")


class FakeKeychain:
    """The Keychain as the collector sees it. Only the agy item is ever here: Claude has no Keychain read at all.
    Every read and every presence check is recorded, so a test can assert that none happened."""

    def __init__(self, passwords=None, unreadable=()):
        self.passwords = dict(passwords or {})
        self.unreadable = set(unreadable)
        self.reads = []
        self.checks = []

    def read(self, service, account=None):
        self.reads.append(service)
        if service in self.unreadable:
            raise m.FetchError(m.MSG_KEYCHAIN_READ)
        return self.passwords.get(service)

    def exists(self, service, account=None):
        self.checks.append(service)
        return service in self.passwords or service in self.unreadable


class FakeHTTP:
    """routes maps a URL to (status, body) or to a callable(method, headers, body)."""

    def __init__(self, routes):
        self.routes = routes
        self.calls = []

    def __call__(self, method, url, headers, body=None, timeout=None):
        self.calls.append({"method": method, "url": url, "headers": dict(headers), "body": body})
        route = self.routes.get(url)
        if route is None:
            raise ForbiddenCall(f"unexpected URL {url}")
        if callable(route):
            return route(method, headers, body)
        return route

    def posts(self, url):
        return [c for c in self.calls if c["method"] == "POST" and c["url"] == url]

    def gets(self, url):
        return [c for c in self.calls if c["method"] == "GET" and c["url"] == url]


def make_env(home, keychain=None, http=None, allow_refresh=True, run=None, notify=None,
             now=NOW, cache=None, direct=None):
    paths = m.Paths(home, Path(home) / "state")
    return m.Env(paths, now, allow_refresh=allow_refresh,
                 keychain=keychain or FakeKeychain(), http=http or FakeHTTP({}),
                 run=run or (lambda args, timeout=30: (0, "")),
                 notify=notify or (lambda title, text: True), cache=cache, direct=direct)


# ---------------------------------------------------------------- fixtures: direct mode (Codex and agy)

CODEX_USAGE_BODY = {
    "plan_type": "prolite",
    "rate_limit": {"primary_window": {"used_percent": 93, "limit_window_seconds": 604800,
                                      "reset_at": ts("2026-11-20T02:15:51Z")},
                   "secondary_window": None},
    "credits": {"has_credits": False, "balance": "0", "unlimited": False},
}
CODEX_AUTH = {"auth_mode": "chatgpt", "OPENAI_API_KEY": None,
              "tokens": {"access_token": FAKE_CODEX_ACCESS, "account_id": FAKE_ACCOUNT_ID,
                         "refresh_token": "FAKE-CODEX-REFRESH"}}
AGY_LOAD_BODY = {"allowedTiers": [{"id": "standard-tier", "isDefault": True}],
                 "cloudaicompanionProject": FAKE_PROJECT, "currentTier": {"id": "free-tier"}}
AGY_MODELS_BODY = {"models": {
    "claude-sonnet-5-5": {"quotaInfo": {"remainingFraction": 0.5, "resetTime": "2026-11-19T09:21:41Z"}},
    "claude-opus-5-5": {"quotaInfo": {"remainingFraction": 0.8, "resetTime": "2026-11-19T10:00:00Z"}},
    "gemini-2.5-pro": {"quotaInfo": {"remainingFraction": 1.0, "resetTime": "2026-11-19T09:00:00Z"}},
    "gemini-2.5-flash": {"quotaInfo": {"remainingFraction": 0.75, "resetTime": "2026-11-19T09:30:00Z"}},
    "gpt-oss-120b": {"quotaInfo": {"resetTime": "2026-11-19T11:00:00Z"}},
    "tab_flash_lite": {"quotaInfo": {"remainingFraction": 0.1}},
}}


def agy_pw(expiry="2026-11-19T06:16:40+01:00"):
    """The agy Keychain item as the direct mode reads it (go-keyring base64 of a JSON token document)."""
    doc = {"token": {"access_token": FAKE_AGY_ACCESS, "refresh_token": "1//FAKE-AGY-REFRESH",
                     "expiry": expiry},
           "auth_method": "oauth", "id_token_email": FAKE_EMAIL}
    return "go-keyring-base64:" + base64.b64encode(json.dumps(doc).encode("utf-8")).decode("ascii")


def claude_line(msg_id, req_id, model, stamp, inp, out, cw=0, cr=0, cw1h=None):
    usage = {"input_tokens": inp, "output_tokens": out,
             "cache_creation_input_tokens": cw, "cache_read_input_tokens": cr}
    if cw1h is not None:
        usage["cache_creation"] = {"ephemeral_1h_input_tokens": cw1h,
                                   "ephemeral_5m_input_tokens": cw - cw1h}
    line = {"type": "assistant", "timestamp": stamp, "requestId": req_id,
            "uuid": f"{msg_id}-uuid", "message": {"id": msg_id, "model": model, "usage": usage}}
    return json.dumps(line) + "\n"


def codex_line(stamp, last_total):
    payload = {"type": "token_count",
               "info": {"last_token_usage": {"input_tokens": last_total - 10, "output_tokens": 10,
                                             "total_tokens": last_total},
                        "total_token_usage": {"total_tokens": 999999}}}
    return json.dumps({"timestamp": stamp, "type": "event_msg", "payload": payload}) + "\n"


def snapshot(root: Path):
    return sorted(str(p.relative_to(root)) for p in root.rglob("*"))


# ---------------------------------------------------------------- fixtures: the CLIs (default mode)

CLAUDE_RATE_LIMITS = {
    "five_hour": {"utilization": 42, "resets_at": "2026-11-19T06:40:00.000000+00:00"},
    "seven_day": {"utilization": 67, "resets_at": "2026-11-24T02:00:00.000000+00:00"},
    "seven_day_opus": None,
    "seven_day_sonnet": None,
    "extra_usage": {"is_enabled": True, "monthly_limit": 5000, "used_credits": 1234, "currency": "USD",
                    "utilization": 24.7, "daily": None},
    "model_scoped": [{"display_name": "Fable", "utilization": 10,
                      "resets_at": "2026-11-24T02:00:00.000000+00:00"}],
    "limits": [{"kind": "session", "group": "session", "percent": 42, "severity": "normal",
                "resets_at": "2026-11-19T06:40:00.000000+00:00", "scope": None, "is_active": False}],
    "spend": {"enabled": False, "percent": 0},
}
CLAUDE_PAYLOAD = {"session": {"total_cost_usd": 0, "email": FAKE_EMAIL}, "subscription_type": "max",
                  "rate_limits_available": True, "rate_limits": CLAUDE_RATE_LIMITS, "behaviors": None}
CLAUDE_USAGE_TEXT = "\n".join([
    "You are currently using your subscription to power your Claude Code usage",
    "",
    "Current session: 40% used · resets Nov 19 at 6pm (Europe/Berlin)",
    "Current week (all models): 67% used · resets Nov 24 at 2am (Europe/Berlin)",
    "Current week (Fable): 10% used · resets Nov 24 at 2am (Europe/Berlin)",
    "",
    "What's contributing to your limits usage?",
])


def control_response(request_id, body=None, error=None):
    """A control_response as claude sends it: the reply is nested under response, and carries request_id."""
    if error is not None:
        reply = {"subtype": "error", "request_id": request_id, "error": error}
    else:
        reply = {"subtype": "success", "request_id": request_id, "response": body if body is not None else {}}
    return {"type": "control_response", "response": reply}


def claude_stream_lines(rate_limits=CLAUDE_RATE_LIMITS, payload=None):
    """stdout of `claude -p --input-format stream-json ...` after initialize and get_usage."""
    body = payload if payload is not None else dict(CLAUDE_PAYLOAD, rate_limits=rate_limits)
    return [json_line(control_response("init-1", {})), json_line(control_response("usage-1", body))]


def claude_stream_error_lines(text="Not logged in · Run /login"):
    return [json_line(control_response("init-1", {})), json_line(control_response("usage-1", error=text))]


def claude_text_lines(text=CLAUDE_USAGE_TEXT, is_error=False):
    """stdout of `claude -p "/usage" --output-format json`: one result object."""
    return [json_line({"type": "result", "subtype": "success", "is_error": is_error, "num_turns": 0,
                       "total_cost_usd": 0, "result": text})]


CODEX_RATE_RESULT = {
    "ordinaryUsageAllowed": True,
    "rateLimits": {"limitId": "codex", "limitName": None,
                   "primary": {"usedPercent": 93, "windowDurationMins": 10080,
                               "resetsAt": ts("2026-11-20T02:15:51Z")},
                   "secondary": None,
                   "credits": {"hasCredits": False, "unlimited": False, "balance": "0"},
                   "planType": "prolite", "rateLimitReachedType": None, "spendControlReached": False},
    "rateLimitResetCredits": {"availableCount": 0, "credits": None},
    "accountId": FAKE_ACCOUNT_ID,
    "rateLimitUpsell": None,
}


def codex_rpc_lines(result=CODEX_RATE_RESULT):
    """stdout of `codex app-server --listen stdio://` after initialize and account/rateLimits/read."""
    return [json_line({"id": 1, "result": {"platformFamily": "unix", "platformOs": "macos"}}),
            json_line({"id": 2, "result": result})]


def agy_bucket(bucket_id, name, window, remaining, reset):
    return {"id": bucket_id, "name": name, "description": "fixture", "window": window,
            "remaining_fraction": remaining, "reset_time": reset}


AGY_USAGE_DOC = {
    "conversation_id": "", "status": "SUCCESS", "response": "", "duration_seconds": 0, "num_turns": 0,
    "usage": {"input_tokens": 0, "output_tokens": 0, "thinking_tokens": 0, "cache_read_tokens": 0,
              "total_tokens": 0},
    "command": {"name": "usage", "data": {"description": "fixture", "groups": [
        {"name": "Gemini Models", "description": "fixture", "buckets": [
            agy_bucket("gemini-weekly", "Weekly Limit Remaining", "weekly", 0.5, "2026-11-24T02:00:00Z"),
            agy_bucket("gemini-5h", "Five Hour Limit Remaining", "5h", 1, "2026-11-19T09:00:00Z")]},
        {"name": "Claude and GPT models", "description": "fixture", "buckets": [
            agy_bucket("3p-weekly", "Weekly Limit Remaining", "weekly", 0, "2026-11-24T02:00:00Z")]}]}},
}


def agy_usage_lines(doc=AGY_USAGE_DOC):
    """stdout of `agy -p "/usage" --output-format json`: one JSON object, printed over several lines."""
    return [(json.dumps(doc, indent=2, ensure_ascii=False) + "\n").encode("utf-8")]


class FakeStdin:
    def __init__(self):
        self.written = []
        self.closed = False

    def write(self, data):
        self.written.append(data)

    def flush(self):
        pass

    def close(self):
        self.closed = True


class FakeStdout:
    """Canned stdout. When the lines run out it ends (EOF); with hang set it blocks until the process is killed."""

    def __init__(self, lines, hang):
        self.lines = list(lines)
        self.hang = hang
        self.released = threading.Event()

    def readline(self):
        if self.lines:
            return self.lines.pop(0)
        if self.hang:
            self.released.wait(timeout=10)  # bounded: a runner that never kills fails the test, it does not hang it
        return b""

    def release(self):
        self.released.set()

    def close(self):
        pass


class FakeProc:
    """Stands in for subprocess.Popen. pid is None, so the runner's group kill never touches a real process."""

    def __init__(self, lines=(), hang=False, returncode=0, pipe_stdin=False):
        self.pid = None
        self.stdin = FakeStdin() if pipe_stdin else None
        self.stdout = FakeStdout(lines, hang)
        self.exit_code = returncode
        self.returncode = None
        self.killed = False

    def kill(self):
        self.killed = True
        if self.returncode is None:
            self.returncode = -9
        self.stdout.release()

    def wait(self, timeout=None):
        if self.returncode is None:
            self.returncode = self.exit_code
        return self.returncode

    def poll(self):
        """None while the process runs. A canned program has ended once it has printed everything; a hung one
        only ends when it is killed."""
        if self.returncode is not None:
            return self.returncode
        if not self.stdout.hang and not self.stdout.lines:
            return self.exit_code
        return None


class FakeCLIs:
    """Replaces the CLI lookup and subprocess.Popen. scripts maps a program name to a function(argv, kwargs)
    that returns a FakeProc (or raises, for a missing program). A program without a script is a ForbiddenCall.
    Every launch is recorded, with the argv, the environment, the working folder and the stdin mode."""

    def __init__(self, scripts):
        self.scripts = dict(scripts)
        self.launches = []
        self.procs = []

    def find(self, name):
        return f"/fake/bin/{name}" if name in self.scripts else None

    def popen(self, argv, **kwargs):
        name = os.path.basename(argv[0])
        self.launches.append({"name": name, "argv": list(argv), "env": dict(kwargs.get("env") or {}),
                              "cwd": kwargs.get("cwd"), "stdin": kwargs.get("stdin"),
                              "start_new_session": kwargs.get("start_new_session")})
        script = self.scripts.get(name)
        if script is None:
            raise ForbiddenCall(f"unscripted program: {name}")
        proc = script(argv, kwargs)
        self.procs.append(proc)
        return proc

    def launched(self, name):
        return [launch for launch in self.launches if launch["name"] == name]


def plan_proc(plan, kwargs):
    """The FakeProc for one plan: a list of stdout lines, "hang", or an exception class raised at start."""
    if isinstance(plan, type) and issubclass(plan, BaseException):
        raise plan()
    pipe = kwargs.get("stdin") == subprocess.PIPE
    if plan == "hang":
        return FakeProc(hang=True, pipe_stdin=pipe)
    return FakeProc(lines=plan, pipe_stdin=pipe)


def claude_program(default, folders=None):
    """claude. default is a (get_usage plan, /usage plan) pair. folders maps a CLAUDE_CONFIG_DIR value to its own pair."""
    folders = folders or {}

    def script(argv, kwargs):
        config = kwargs.get("env", {}).get("CLAUDE_CONFIG_DIR", "")
        stream_plan, text_plan = folders.get(config, default)
        return plan_proc(stream_plan if "--input-format" in argv else text_plan, kwargs)

    return script


def single_program(plan):
    """A CLI that gives the same plan on every run (codex, agy)."""
    return lambda argv, kwargs: plan_proc(plan, kwargs)


# ---------------------------------------------------------------- the shared base class

class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        # Day totals use a fixed zone here, so the results do not depend on the machine's time zone.
        zone = mock.patch.object(m, "DAY_ZONE", ZoneInfo("Europe/Berlin"))
        zone.start()
        self.addCleanup(zone.stop)
        for target in ("subprocess.run", "subprocess.Popen", "urllib.request.urlopen"):
            self.forbid(target)
        self.forbid("os.killpg")
        patch = mock.patch.object(m, "CLI_TIMEOUT_S", 0.3)  # a hung CLI is cut off after 0.3 s in tests
        patch.start()
        self.addCleanup(patch.stop)
        self.stderr = io.StringIO()
        redirect = contextlib.redirect_stderr(self.stderr)
        redirect.__enter__()
        self.addCleanup(redirect.__exit__, None, None, None)

    def forbid(self, target):
        patcher = mock.patch(target, side_effect=ForbiddenCall(target))
        patcher.start()
        self.addCleanup(patcher.stop)

    def use_clis(self, scripts):
        """Routes the CLI lookup and subprocess.Popen to a FakeCLIs. A later call replaces an earlier one."""
        fake = FakeCLIs(scripts)
        for patcher in (mock.patch.object(m, "find_cli", fake.find),
                        mock.patch.object(m.subprocess, "Popen", fake.popen)):
            patcher.start()
            self.addCleanup(patcher.stop)
        return fake

    def write_codex_auth(self):
        path = self.home / ".codex" / "auth.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(CODEX_AUTH), encoding="utf-8")

    def write_claude_folder(self, relative=".claude"):
        """A Claude Code config folder as Claude Code leaves it. No Keychain item is involved."""
        folder = self.home / relative
        (folder / "projects").mkdir(parents=True, exist_ok=True)
        return folder

    def collect(self, env, fetch, previous=None, provider="claude", label="Claude"):
        """collect_account with one fetcher replaced; the other providers are not touched."""
        source = m.default_source(provider, env.paths)
        source.default_label = label
        with mock.patch.dict(m.FETCHERS, {provider: lambda env, source: fetch(env)}):
            return m.collect_account(env, source, previous)

    def collect_real(self, env, provider, previous=None, label=None):
        """collect_account with the real fetchers: the CLI in default mode, direct mode when env says so."""
        source = m.default_source(provider, env.paths)
        source.default_label = label or m.PROVIDER_LABEL[provider]
        return m.collect_account(env, source, previous)


# ---------------------------------------------------------------- parsing

class ParsingTests(Base):
    def test_claude_windows_keep_seven_day_variants_in_order(self):
        limits, _ = m.parse_claude_usage({
            "seven_day_sonnet": {"utilization": 12, "resets_at": None},
            "seven_day": {"utilization": 67, "resets_at": "2026-11-24T02:00:00Z"},
            "five_hour": {"utilization": 42, "resets_at": "2026-11-19T06:40:00Z"},
            "seven_day_cowork": {"utilization": 3, "resets_at": "2026-11-24T02:00:00+00:00"},
        })
        self.assertEqual([limit["key"] for limit in limits],
                         ["five_hour", "seven_day", "seven_day_cowork", "seven_day_sonnet"])
        self.assertEqual(limits[0]["label"], "5 ชม.")
        self.assertEqual(limits[1]["label"], "สัปดาห์")
        self.assertEqual(limits[1]["resets_at"], "2026-11-24T02:00:00Z")
        self.assertIsNone(limits[3]["resets_at"])

    def test_claude_ignores_unknown_fields_and_null_windows(self):
        limits, _ = m.parse_claude_usage({
            "five_hour": {"utilization": None},
            "seven_day": {"utilization": 10, "resets_at": "2026-11-24T02:00:00Z"},
            "iguana_necktie": {"x": 1},
            "seven_day_opus": "not-a-dict",
        })
        self.assertEqual([limit["key"] for limit in limits], ["seven_day"])

    def test_claude_without_any_window_is_an_error(self):
        with self.assertRaises(m.FetchError):
            m.parse_claude_usage({"extra_usage": None})

    def test_claude_utilization_is_clamped_to_0_100(self):
        limits, _ = m.parse_claude_usage({"five_hour": {"utilization": 130},
                                          "seven_day": {"utilization": -5}})
        self.assertEqual([limit["used_percent"] for limit in limits], [100.0, 0.0])

    def test_claude_extra_usage_minor_units_become_dollars(self):
        _, credits = m.parse_claude_usage({
            "five_hour": {"utilization": 1},
            "extra_usage": {"is_enabled": True, "monthly_limit": 5000, "used_credits": 1234}})
        self.assertEqual(credits, {"extra_usage_enabled": True, "used_usd": 12.34,
                                   "limit_usd": 50.0, "balance_usd": None})

    def test_claude_extra_usage_in_other_currency_gives_no_dollar_amounts(self):
        _, credits = m.parse_claude_usage({
            "five_hour": {"utilization": 1},
            "extra_usage": {"is_enabled": False, "currency": "EUR", "monthly_limit": 5000,
                            "used_credits": 10}})
        self.assertIsNone(credits["used_usd"])
        self.assertIsNone(credits["limit_usd"])

    def test_claude_plan_label_takes_the_tier_multiplier_only_when_a_tier_is_given(self):
        self.assertEqual(m.claude_plan("max", "default_claude_max_5x"), "Max 5x")
        self.assertEqual(m.claude_plan("max"), "Max")
        self.assertEqual(m.claude_plan("pro"), "Pro")
        self.assertIsNone(m.claude_plan(None))

    def test_codex_windows_are_labelled_by_length_and_reset_fallback(self):
        doc = {"plan_type": "prolite",
               "rate_limit": {
                   "primary_window": {"used_percent": 93, "limit_window_seconds": 604800,
                                      "reset_at": ts("2026-11-20T02:15:51Z")},
                   "secondary_window": {"used_percent": 10, "limit_window_seconds": 18000,
                                        "reset_after_seconds": 3600}},
               "credits": {"has_credits": False, "balance": "0"}}
        plan, limits, credits = m.parse_codex_usage(doc, NOW)
        self.assertEqual(plan, "Pro Lite")
        self.assertEqual([(limit["key"], limit["label"]) for limit in limits],
                         [("primary", "สัปดาห์"), ("secondary", "5 ชม.")])
        self.assertEqual(limits[0]["resets_at"], "2026-11-20T02:15:51Z")
        self.assertEqual(limits[1]["resets_at"], "2026-11-19T05:30:00Z")
        self.assertEqual(credits["balance_usd"], 0.0)

    def test_codex_window_labels_for_other_lengths(self):
        self.assertEqual(m.window_label(2592000), "30 วัน")
        self.assertEqual(m.window_label(3600), "1 ชม.")
        self.assertEqual(m.window_label(180), "3 นาที")
        self.assertEqual(m.window_label(None), "ช่วงเวลา")

    def test_codex_unknown_plan_is_title_cased(self):
        plan, _, _ = m.parse_codex_usage({"plan_type": "solo_pro",
                                          "rate_limit": {"primary_window": {"used_percent": 1}}},
                                         NOW)
        self.assertEqual(plan, "Solo Pro")

    def test_agy_groups_models_and_takes_the_worst_case(self):
        limits = m.group_agy_models(AGY_MODELS_BODY["models"])
        by_key = {limit["key"]: limit for limit in limits}
        self.assertEqual([limit["key"] for limit in limits],
                         ["gemini_pro", "gemini_flash", "claude", "gpt_oss"])  # Gemini group first
        self.assertEqual(by_key["claude"]["used_percent"], 50.0)
        self.assertEqual(by_key["claude"]["resets_at"], "2026-11-19T09:21:41Z")
        self.assertEqual(by_key["gemini_flash"]["used_percent"], 25.0)
        self.assertEqual(by_key["gemini_pro"]["used_percent"], 0.0)
        self.assertEqual(by_key["gpt_oss"]["used_percent"], 100.0)
        self.assertNotIn("tab_flash_lite", json.dumps(limits))

    def test_agy_quota_entry_without_reset_or_fraction_is_skipped(self):
        self.assertEqual(m.group_agy_models({"claude-x": {"quotaInfo": {}}}), [])

    def test_agy_expiry_with_timezone_is_compared_in_utc(self):
        self.assertTrue(m.agy_expired({"expiry": "2026-11-19T03:00:00+01:00"}, NOW))
        self.assertFalse(m.agy_expired({"expiry": "2026-11-19T06:16:40+01:00"}, NOW))
        self.assertFalse(m.agy_expired({"expiry": "not a date"}, NOW))


class LocalLogTests(Base):
    def write_claude(self, name, lines):
        path = self.home / ".claude" / "projects" / "proj" / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("".join(lines), encoding="utf-8")
        return path

    def test_repeats_are_counted_once_across_files_and_synthetic_is_skipped(self):
        stamp = "2026-11-19T03:00:00.000Z"
        line = claude_line("msg_1", "req_1", "claude-sonnet-5-5", stamp, 100, 50)
        self.write_claude("a.jsonl", [line, line])
        self.write_claude("sub/b.jsonl", [line, claude_line("msg_x", "req_x", "<synthetic>",
                                                            stamp, 9, 9)])
        usage = m.claude_local_usage(make_env(self.home))
        self.assertEqual(usage["today"]["tokens"], 150)
        self.assertEqual(usage["month"]["tokens"], 150)

    def test_day_boundary_decides_today(self):
        # Berlin midnight of Nov 19 is 23:00 UTC on Nov 18 (CET, UTC+1)
        self.write_claude("c.jsonl", [
            claude_line("m1", "r1", "claude-sonnet-5-5", "2026-11-18T23:30:00.000Z", 1, 0),
            claude_line("m2", "r2", "claude-sonnet-5-5", "2026-11-18T22:59:59.000Z", 2, 0)])
        usage = m.claude_local_usage(make_env(self.home))
        self.assertEqual(usage["today"]["tokens"], 1)
        self.assertEqual(usage["month"]["tokens"], 3)

    def test_day_boundary_follows_the_injected_local_zone(self):
        # NOW is 04:30 UTC on Nov 19: Nov 19 in Berlin, still Nov 18 in New York (UTC-5 after DST ends).
        # 03:00 UTC is Nov 19 in Berlin but Nov 18 in New York; 06:00 UTC is Nov 19 in both.
        self.write_claude("z.jsonl", [
            claude_line("m20", "r20", "claude-sonnet-5-5", "2026-11-19T03:00:00.000Z", 5, 0),
            claude_line("m21", "r21", "claude-sonnet-5-5", "2026-11-19T06:00:00.000Z", 7, 0)])
        usage = m.claude_local_usage(make_env(self.home))
        self.assertEqual((usage["today"]["tokens"], usage["month"]["tokens"]), (12, 12))
        with mock.patch.object(m, "DAY_ZONE", ZoneInfo("America/New_York")):
            usage = m.claude_local_usage(make_env(self.home, cache={}))
        self.assertEqual((usage["today"]["tokens"], usage["month"]["tokens"]), (5, 12))
        self.assertEqual(m.local_day("2026-11-19T03:00:00.000Z"), "2026-11-19")

    def test_token_counts_leave_out_cache_reads_while_the_cost_includes_them(self):
        self.assertFalse(m.TOKENS_INCLUDE_CACHE_READS)
        self.write_claude("g.jsonl", [claude_line("m11", "r11", "claude-opus-5-5",
                                                  "2026-11-19T03:00:00.000Z", 100, 0, cr=1_000_000)])
        usage = m.claude_local_usage(make_env(self.home))
        self.assertEqual((usage["today"]["tokens"], usage["today"]["cost_usd"]), (100, 0.2))

    def test_claude_cost_uses_family_prices_and_haiku_tiers(self):
        self.assertAlmostEqual(m.cost_usd("claude-opus-5-5", 1_000_000, 0, 0, 0, 0), 4.0)
        self.assertAlmostEqual(m.cost_usd("claude-opus-5-5", 0, 0, 0, 0, 1_000_000), 0.20)
        self.assertAlmostEqual(m.cost_usd("claude-sonnet-5-5", 0, 1_000_000, 0, 0, 0), 10.0)
        self.assertAlmostEqual(m.cost_usd("claude-haiku-5-5", 50_000, 0, 0, 0, 0), 0.005)
        self.assertAlmostEqual(m.cost_usd("claude-haiku-5-5", 200_000, 0, 0, 0, 0), 0.10)
        self.assertIsNone(m.cost_usd("claude-3-haiku-20240307", 1, 1, 1, 1, 1))

    def test_unknown_model_keeps_tokens_but_cost_is_null(self):
        self.write_claude("d.jsonl", [claude_line("m9", "r9", "claude-mystery-1",
                                                  "2026-11-19T03:00:00.000Z", 10, 10)])
        usage = m.claude_local_usage(make_env(self.home))
        self.assertEqual((usage["today"]["tokens"], usage["today"]["cost_usd"]), (20, None))

    def test_partial_last_line_is_skipped_and_old_month_is_not_in_month(self):
        self.write_claude("e.jsonl", [
            claude_line("m5", "r5", "claude-sonnet-5-5", "2026-10-15T03:00:00.000Z", 5, 5),
            '{"message": {"usage": {"input_tokens": 1'])
        usage = m.claude_local_usage(make_env(self.home))
        self.assertEqual(usage["today"]["tokens"], 0)
        self.assertEqual(usage["month"]["tokens"], 0)

    def test_family_split_by_model_prefix_and_kind_for_today_and_month(self):
        # Berlin day: NOW is Nov 19. opus 4-8 and opus 5-5 both land in "opus"; the unknown id lands in "other".
        self.write_claude("fam.jsonl", [
            claude_line("f1", "fr1", "claude-opus-5-5", "2026-11-19T03:00:00.000Z", 100, 10, cw=20, cr=1000,
                        cw1h=5),
            claude_line("f2", "fr2", "claude-opus-4-8", "2026-11-19T03:10:00.000Z", 50, 5),
            claude_line("f3", "fr3", "claude-sonnet-5-5", "2026-11-19T03:20:00.000Z", 200, 0),
            claude_line("f4", "fr4", "claude-haiku-5-5", "2026-11-19T03:30:00.000Z", 7, 0),
            claude_line("f5", "fr5", "claude-fable-5-2", "2026-11-19T03:40:00.000Z", 0, 3),
            claude_line("f6", "fr6", "claude-mystery-1", "2026-11-19T03:50:00.000Z", 11, 1)])
        usage = m.claude_local_usage(make_env(self.home))
        zero = {"input": 0, "output": 0, "cache_write_5m": 0, "cache_write_1h": 0, "cache_read": 0}
        month = usage["month"]["by_family"]
        self.assertEqual(set(month), {"opus", "sonnet", "haiku", "fable", "other"})
        self.assertEqual(month["opus"], {"input": 150, "output": 15, "cache_write_5m": 15,
                                         "cache_write_1h": 5, "cache_read": 1000})
        self.assertEqual(month["sonnet"], dict(zero, input=200))
        self.assertEqual(month["haiku"], dict(zero, input=7))
        self.assertEqual(month["fable"], dict(zero, output=3))
        self.assertEqual(month["other"], dict(zero, input=11, output=1))
        self.assertEqual(usage["today"]["by_family"], usage["month"]["by_family"])
        # tokens leave out cache reads: 130 + 55 + 200 + 7 + 3 + 12 = 407; the unknown model has no cost
        self.assertEqual((usage["month"]["tokens"], usage["month"]["cost_usd"]), (407, None))

    def test_tokens_and_cost_are_unchanged_by_the_family_split(self):
        self.write_claude("cost.jsonl", [
            claude_line("c1", "cr1", "claude-opus-5-5", "2026-11-19T03:00:00.000Z", 1_000_000, 0),
            claude_line("c2", "cr2", "claude-opus-4-8", "2026-11-19T03:10:00.000Z", 0, 100_000),
            claude_line("c3", "cr3", "claude-sonnet-5-5", "2026-11-19T03:20:00.000Z", 0, 0, cw=1_000_000),
            claude_line("c4", "cr4", "claude-fable-5-2", "2026-11-19T03:40:00.000Z", 0, 1_000)])
        usage = m.claude_local_usage(make_env(self.home))
        # Opus 5.5 input 4.00 + Opus 4.8 output 2.50 + Sonnet 5.5 cache write 5m 2.50 + Fable 5.2 output 0.04
        self.assertEqual((usage["month"]["tokens"], usage["month"]["cost_usd"]), (2_101_000, 9.04))
        self.assertEqual((usage["today"]["tokens"], usage["today"]["cost_usd"]), (2_101_000, 9.04))
        self.assertEqual(usage["month"]["by_family"]["opus"]["input"], 1_000_000)
        self.assertEqual(usage["month"]["by_family"]["opus"]["output"], 100_000)
        self.assertEqual(usage["month"]["by_family"]["sonnet"]["cache_write_5m"], 1_000_000)

    def test_family_totals_follow_the_today_and_month_boundaries(self):
        self.write_claude("bound.jsonl", [
            # Berlin Nov 19 (today, so also this month)
            claude_line("b1", "br1", "claude-opus-5-5", "2026-11-19T03:00:00.000Z", 1000, 0),
            # Berlin Nov 18 23:30: this month, not today
            claude_line("b2", "br2", "claude-sonnet-5-5", "2026-11-18T22:30:00.000Z", 2000, 0),
            # Berlin Nov 1 00:30: this month, not today
            claude_line("b3", "br3", "claude-haiku-5-5", "2026-10-31T23:30:00.000Z", 4000, 0),
            # Berlin Oct 31 23:30: last month, in neither bucket
            claude_line("b4", "br4", "claude-fable-5-2", "2026-10-31T22:30:00.000Z", 8000, 0)])
        usage = m.claude_local_usage(make_env(self.home))
        self.assertEqual(usage["today"]["by_family"]["opus"]["input"], 1000)
        self.assertEqual(usage["today"]["by_family"]["sonnet"]["input"], 0)
        self.assertEqual(usage["today"]["tokens"], 1000)
        self.assertEqual(usage["month"]["by_family"]["opus"]["input"], 1000)
        self.assertEqual(usage["month"]["by_family"]["sonnet"]["input"], 2000)
        self.assertEqual(usage["month"]["by_family"]["haiku"]["input"], 4000)
        self.assertEqual(usage["month"]["by_family"]["fable"]["input"], 0)
        self.assertEqual(usage["month"]["tokens"], 7000)

    def test_a_cache_write_split_into_5m_and_1h_is_kept_per_kind(self):
        self.write_claude("cw.jsonl", [claude_line("w1", "wr1", "claude-opus-5-5",
                                                   "2026-11-19T03:00:00.000Z", 0, 0, cw=300, cw1h=120)])
        usage = m.claude_local_usage(make_env(self.home))
        self.assertEqual(usage["today"]["by_family"]["opus"]["cache_write_5m"], 180)
        self.assertEqual(usage["today"]["by_family"]["opus"]["cache_write_1h"], 120)
        self.assertEqual(usage["today"]["tokens"], 300)

    def test_no_claude_logs_keep_the_family_keys_at_zero(self):
        self.write_claude("none.jsonl", [claude_line("n1", "nr1", "claude-sonnet-5-5",
                                                     "2026-10-15T03:00:00.000Z", 5, 5)])
        usage = m.claude_local_usage(make_env(self.home))
        self.assertEqual(usage["today"]["by_family"]["opus"]["input"], 0)
        self.assertEqual(set(usage["today"]["by_family"]), {"opus", "sonnet", "haiku", "fable", "other"})

    def test_model_prices_are_the_four_latest_models_from_the_price_table(self):
        prices = m.model_prices()
        self.assertEqual(list(prices), ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5",
                                        "claude-fable-5-2", "gpt-6-luna", "gpt-6.2-sol", "gpt-6.1-sol"])
        self.assertEqual(prices["claude-opus-5-5"], {"provider": "anthropic", "family": "opus", "label": "Opus 5.5", "input": 4.0,
                                                    "cache_write_5m": 5.0, "cache_write_1h": 8.0,
                                                    "cache_read": 0.2, "output": 20.0})
        self.assertEqual(prices["claude-sonnet-5-5"], {"provider": "anthropic", "family": "sonnet", "label": "Sonnet 5.5", "input": 2.0,
                                                      "cache_write_5m": 2.5, "cache_write_1h": 4.0,
                                                      "cache_read": 0.1, "output": 10.0})
        # Haiku 5.5 is the base tier (prompts up to 100k tokens)
        self.assertEqual(prices["claude-haiku-5-5"], {"provider": "anthropic", "family": "haiku", "label": "Haiku 5.5", "input": 0.1,
                                                     "cache_write_5m": 0.125, "cache_write_1h": 0.2,
                                                     "cache_read": 0.01, "output": 0.5})
        self.assertEqual(prices["claude-fable-5-2"], {"provider": "anthropic", "family": "fable", "label": "Fable 5.2", "input": 8.0,
                                                     "cache_write_5m": 10.0, "cache_write_1h": 16.0,
                                                     "cache_read": 0.2, "output": 40.0})
        # the numbers are the ones cost_usd charges, so PRICE_TABLE stays the only source
        for model, price in prices.items():
            if price["provider"] != "anthropic":
                continue
            # 100k prompt tokens: the base tier, so the cost of 100k input is a tenth of the per-million price
            self.assertAlmostEqual(m.cost_usd(model, 100_000, 0, 0, 0, 0), price["input"] / 10)
            self.assertAlmostEqual(m.cost_usd(model, 0, 1_000_000, 0, 0, 0), price["output"])

    def test_usage_document_carries_model_prices_for_both_copies(self):
        doc = m.build_document(NOW, [])
        self.assertEqual(doc["schema"], 1)
        self.assertEqual(doc["model_prices"], m.model_prices())
        self.assertIn("model_prices", json.loads(m.serialize(doc)))

    def test_unchanged_files_are_not_parsed_again(self):
        path = self.write_claude("f.jsonl", [claude_line("m7", "r7", "claude-sonnet-5-5",
                                                         "2026-11-19T03:00:00.000Z", 3, 3)])
        env = make_env(self.home, cache={})
        with mock.patch.object(m, "parse_claude_file", wraps=m.parse_claude_file) as parse:
            first = m.claude_local_usage(env)
            self.assertEqual(parse.call_count, 1)
            second = m.claude_local_usage(env)
            self.assertEqual(parse.call_count, 1)
            self.assertEqual(first, second)
            path.write_text(path.read_text(encoding="utf-8") + claude_line(
                "m8", "r8", "claude-sonnet-5-5", "2026-11-19T03:01:00.000Z", 1, 1), encoding="utf-8")
            third = m.claude_local_usage(env)
            self.assertEqual(parse.call_count, 2)
            self.assertEqual(third["today"]["tokens"], 8)

    def test_files_untouched_since_last_month_are_not_read(self):
        path = self.write_claude("old.jsonl", [claude_line("m3", "r3", "claude-sonnet-5-5",
                                                           "2026-09-03T03:00:00.000Z", 4, 4)])
        old = datetime(2026, 9, 30, tzinfo=timezone.utc).timestamp()
        os.utime(path, (old, old))
        with mock.patch.object(m, "parse_claude_file", wraps=m.parse_claude_file) as parse:
            usage = m.claude_local_usage(make_env(self.home))
        self.assertEqual(parse.call_count, 0)
        self.assertEqual(usage["month"]["tokens"], 0)

    def test_codex_uses_per_turn_usage_and_local_days(self):
        day = self.home / ".codex" / "sessions" / "2026" / "11" / "19"
        day.mkdir(parents=True)
        (day / "rollout-a.jsonl").write_text(
            codex_line("2026-11-19T03:00:00.000Z", 1000)
            + codex_line("2026-11-19T03:05:00.000Z", 500) + "not json\n", encoding="utf-8")
        usage = m.codex_local_usage(make_env(self.home))
        # no turn_context line, so the model is "unknown": tokens are counted and the cost is null
        self.assertEqual((usage["today"]["tokens"], usage["today"]["cost_usd"]), (1500, None))
        self.assertEqual((usage["month"]["tokens"], usage["month"]["cost_usd"]), (1500, None))
        self.assertEqual(usage["today"]["by_model"]["unknown"]["input"], 1480)
        self.assertEqual(usage["today"]["by_model"]["unknown"]["output"], 20)

    def test_codex_usage_is_null_without_session_logs(self):
        self.assertIsNone(m.codex_local_usage(make_env(self.home)))

    def test_dedupe_key_hides_message_ids(self):
        key = m.dedupe_key("msg_secret_123", "req_secret_456", "u", Path("/x"), 1)
        self.assertNotIn("msg_secret", key)
        self.assertEqual(len(key), 20)


class StaleTests(Base):
    def test_failure_keeps_previous_data_as_stale(self):
        previous = {"plan": "Max 5x", "status": "ok", "updated_at": "2026-11-19T04:00:00Z",
                    "limits": [{"key": "five_hour", "label": "5 ชม.", "used_percent": 42.0,
                                "resets_at": "2026-11-19T06:40:00Z"}],
                    "usage": {"today": {"tokens": 1, "cost_usd": 0.0},
                              "month": {"tokens": 2, "cost_usd": 0.0}},
                    "credits": None}

        def failing(env):
            raise m.FetchError(m.MSG_CLAUDE_FORMAT)

        acc = self.collect(make_env(self.home), failing, previous)
        self.assertEqual(acc["status"], "stale")
        self.assertEqual(acc["updated_at"], "2026-11-19T04:00:00Z")
        # the file from before this change had no window_seconds: it is filled in from the key
        self.assertEqual(acc["limits"], [dict(previous["limits"][0], window_seconds=18000)])
        self.assertIsNone(acc["usage"])  # usage comes from the local logs, not from the previous run
        self.assertEqual(acc["plan"], "Max 5x")
        self.assertEqual(acc["error"], m.MSG_CLAUDE_FORMAT)

    def test_first_failure_is_error_with_no_data(self):
        def failing(env):
            raise m.FetchError(m.MSG_CLAUDE_TIMEOUT, m.ERROR_NETWORK)

        acc = self.collect(make_env(self.home), failing, None)
        self.assertEqual((acc["status"], acc["limits"], acc["updated_at"]), ("error", [], None))

    def test_previous_error_without_timestamp_is_not_data(self):
        def failing(env):
            raise m.FetchError(m.MSG_CLAUDE_TIMEOUT, m.ERROR_NETWORK)

        acc = self.collect(make_env(self.home), failing,
                           {"status": "error", "updated_at": None, "limits": []})
        self.assertEqual(acc["status"], "error")

    def test_success_replaces_stale_and_clears_error(self):
        def ok(env):
            return {"plan": "Max", "usage": None, "credits": None,
                    "limits": [{"key": "five_hour", "label": "5 ชม.", "used_percent": 1.0,
                                "resets_at": None}]}

        acc = self.collect(make_env(self.home), ok,
                           {"status": "stale", "updated_at": "2026-11-19T01:00:00Z",
                            "limits": [], "error": "old"})
        self.assertEqual((acc["status"], acc["error"], acc["updated_at"]),
                         ("ok", None, "2026-11-19T04:30:00Z"))

    def test_unexpected_exception_is_contained_and_logged_by_class_only(self):
        def boom(env):
            raise ValueError("leaked " + FAKE_CODEX_ACCESS)

        acc = self.collect(make_env(self.home), boom, None)
        self.assertEqual(acc["status"], "error")
        self.assertEqual(acc["error"], m.MSG_GENERIC)
        self.assertNotIn(FAKE_CODEX_ACCESS, self.stderr.getvalue())
        self.assertIn("ValueError", self.stderr.getvalue())


class NotifyTests(Base):
    def account(self, used, resets="2026-11-19T06:40:00Z", status="ok"):
        return {"id": "claude-main", "label": "Claude", "status": status,
                "limits": [{"key": "five_hour", "label": "5 ชม.", "used_percent": used,
                            "resets_at": resets}]}

    def run_pass(self, accounts, notify_ok=True, now=NOW):
        sent = []

        def notify(title, text):
            sent.append(text)
            return notify_ok

        env = make_env(self.home, notify=notify, now=now)
        m.notify_pass(env, accounts, self.home / "state" / "notify-state.json")
        return sent

    def test_80_then_95_each_notify_once_per_window(self):
        self.assertEqual(len(self.run_pass([self.account(85.0)])), 1)
        self.assertEqual(self.run_pass([self.account(86.0)]), [])
        self.assertEqual(len(self.run_pass([self.account(96.0)])), 1)
        self.assertEqual(self.run_pass([self.account(97.0)]), [])

    def test_a_new_reset_time_starts_a_new_window(self):
        self.run_pass([self.account(85.0)])
        sent = self.run_pass([self.account(85.0, resets="2026-11-19T11:40:00Z")])
        self.assertEqual(len(sent), 1)

    def test_first_sighting_above_95_sends_one_notification_and_marks_both(self):
        self.assertEqual(len(self.run_pass([self.account(97.0)])), 1)
        self.assertEqual(self.run_pass([self.account(97.5)]), [])
        state = json.loads((self.home / "state" / "notify-state.json").read_text(encoding="utf-8"))
        self.assertEqual(list(state.values())[0]["sent"], [80, 95])

    def test_stale_or_error_accounts_never_notify(self):
        self.assertEqual(self.run_pass([self.account(99.0, status="stale")]), [])
        self.assertEqual(self.run_pass([self.account(99.0, status="error")]), [])

    def test_small_reset_jitter_does_not_renotify(self):
        self.run_pass([self.account(85.0, resets="2026-11-19T06:40:00Z")])
        self.assertEqual(self.run_pass([self.account(85.0, resets="2026-11-19T06:40:20Z")]), [])

    def test_failed_notification_is_retried_on_the_next_run(self):
        self.assertEqual(len(self.run_pass([self.account(85.0)], notify_ok=False)), 1)
        self.assertEqual(len(self.run_pass([self.account(85.0)], notify_ok=True)), 1)

    def test_state_older_than_14_days_is_pruned(self):
        self.run_pass([self.account(85.0)])
        self.run_pass([], now=NOW + timedelta(days=15))
        state = json.loads((self.home / "state" / "notify-state.json").read_text(encoding="utf-8"))
        self.assertEqual(state, {})

    def test_minute_key_rounds_to_the_nearest_minute(self):
        self.assertEqual(m.minute_key("2026-11-19T06:40:20Z"), "2026-11-19T06:40:00Z")
        self.assertEqual(m.minute_key("2026-11-19T06:40:40Z"), "2026-11-19T06:41:00Z")
        self.assertEqual(m.minute_key(None), "")


class KeychainReadTests(Base):
    """security exit 44 means the item does not exist. Any other failure means it could not be read.
    Only the agy item is ever read, and only in direct mode."""

    def read_with(self, returns):
        with mock.patch.object(m, "run_cmd", return_value=returns) as run:
            password = m.SystemKeychain().read(m.AGY_KEYCHAIN_SERVICE, m.AGY_KEYCHAIN_ACCOUNT)
        self.assertEqual(run.call_args[0][0][:6], ["security", "find-generic-password", "-s",
                                                   m.AGY_KEYCHAIN_SERVICE, "-a", m.AGY_KEYCHAIN_ACCOUNT])
        return password

    def test_exit_zero_returns_the_password_without_its_newline(self):
        self.assertEqual(self.read_with((0, FAKE_AGY_ACCESS + "\n")), FAKE_AGY_ACCESS)
        self.assertEqual(self.stderr.getvalue(), "")

    def test_an_empty_password_is_an_item_that_exists_not_a_missing_one(self):
        self.assertEqual(self.read_with((0, "\n")), "")

    def test_exit_44_means_the_item_does_not_exist(self):
        self.assertIsNone(self.read_with((44, "")))

    def test_any_other_failure_is_unreadable_and_is_logged_by_exit_code_only(self):
        for rc in (1, 36, 128, -1):
            with self.subTest(rc=rc):
                with self.assertRaises(m.FetchError) as caught:
                    self.read_with((rc, FAKE_AGY_ACCESS))
                self.assertEqual(str(caught.exception), m.MSG_KEYCHAIN_READ)
        log_text = self.stderr.getvalue()
        self.assertIn("rc 36", log_text)
        self.assertNotIn(FAKE_AGY_ACCESS, log_text)


class OutputAndRunTests(Base):
    """Whole runs of main(): every provider through its CLI, with the files and the output checked."""

    def setUp(self):
        super().setUp()
        self.notes = []
        self.write_claude_folder(".claude")
        (self.home / ".claude.json").write_text("{}", encoding="utf-8")
        self.write_codex_auth()
        self.keychain = FakeKeychain({m.AGY_KEYCHAIN_SERVICE: agy_pw()})
        self.clis = self.use_clis({
            "claude": claude_program((claude_stream_lines(), claude_text_lines())),
            "codex": single_program(codex_rpc_lines()),
            "agy": single_program(agy_usage_lines()),
        })
        self.http = FakeHTTP({})
        patches = [
            mock.patch.object(m, "SystemKeychain", lambda: self.keychain),
            mock.patch.object(m, "http_request", self.http),
            mock.patch.object(m, "osascript_notify",
                              lambda title, text: self.notes.append(text) or True),
            mock.patch.object(m, "datetime", FrozenDatetime),
            mock.patch.dict(os.environ, {"HOME": str(self.home)}),
        ]
        for patch in patches:
            patch.start()
            self.addCleanup(patch.stop)

    def run_main(self, argv):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = m.main(argv)
        return code, out.getvalue()

    def written_doc(self):
        return json.loads((self.home / MAC_REL / "usage.json").read_text(encoding="utf-8"))

    def written_ids(self):
        return [account["id"] for account in self.written_doc()["accounts"]]

    def test_atomic_write_replaces_content_and_leaves_no_tmp_file(self):
        target = self.home / "usage.json"
        target.write_text("old", encoding="utf-8")
        m.atomic_write(target, b"new")
        self.assertEqual(target.read_bytes(), b"new")
        self.assertFalse((self.home / "usage.json.tmp").exists())

    def test_dry_run_prints_json_and_writes_or_notifies_nothing(self):
        before = snapshot(self.home)
        code, out = self.run_main(["--dry-run"])
        self.assertEqual(code, 0)
        doc = json.loads(out)
        self.assertEqual(doc["schema"], 1)
        self.assertEqual([account["id"] for account in doc["accounts"]],
                         ["claude-main", "codex-main", "agy-main"])
        self.assertEqual(snapshot(self.home), before)
        self.assertEqual(self.notes, [])

    def test_full_run_writes_identical_mac_and_icloud_copies_without_tmp_files(self):
        (self.home / ICLOUD_REL).mkdir(parents=True)
        code, _ = self.run_main([])
        self.assertEqual(code, 0)
        mac = self.home / MAC_REL / "usage.json"
        phone = self.home / ICLOUD_REL / "ai-usage.json"
        self.assertEqual(mac.read_bytes(), phone.read_bytes())
        self.assertEqual(list((self.home / MAC_REL).glob("*.tmp")), [])
        doc = self.written_doc()
        self.assertEqual([account["status"] for account in doc["accounts"]], ["ok", "ok", "ok"])
        self.assertEqual(doc["accounts"][1]["limits"][0]["label"], "สัปดาห์")
        self.assertEqual([limit["key"] for limit in doc["accounts"][2]["limits"]],
                         ["gemini-5h", "gemini-weekly", "3p-weekly"])

    def test_missing_icloud_folder_is_skipped_and_not_created(self):
        code, _ = self.run_main([])
        self.assertEqual(code, 0)
        self.assertTrue((self.home / MAC_REL / "usage.json").exists())
        self.assertFalse((self.home / "Library" / "Mobile Documents").exists())

    def test_a_provider_without_a_login_is_left_out_of_both_copies(self):
        self.use_clis({"claude": claude_program((claude_stream_error_lines(), claude_text_lines())),
                       "codex": single_program(codex_rpc_lines()),
                       "agy": single_program(agy_usage_lines())})
        (self.home / ICLOUD_REL).mkdir(parents=True)
        code, _ = self.run_main([])
        self.assertEqual(code, 0)
        self.assertEqual(self.written_ids(), ["codex-main", "agy-main"])
        phone = json.loads((self.home / ICLOUD_REL / "ai-usage.json").read_text(encoding="utf-8"))
        self.assertEqual([account["id"] for account in phone["accounts"]], ["codex-main", "agy-main"])

    def test_missing_codex_file_and_agy_login_are_left_out_of_the_dry_run(self):
        (self.home / ".codex" / "auth.json").unlink()
        self.keychain.passwords.clear()
        code, out = self.run_main(["--dry-run"])
        self.assertEqual(code, 0)
        self.assertEqual([account["id"] for account in json.loads(out)["accounts"]], ["claude-main"])

    def test_with_no_login_at_all_the_file_is_written_with_an_empty_account_list(self):
        self.keychain.passwords.clear()
        (self.home / ".codex" / "auth.json").unlink()
        (self.home / ".claude.json").unlink()
        (self.home / ".claude" / "projects").rmdir()
        (self.home / ".claude").rmdir()
        code, _ = self.run_main([])
        self.assertEqual(code, 0)
        self.assertEqual(self.written_doc()["accounts"], [])

    def test_a_login_removed_after_an_ok_run_is_left_out_of_the_next_run(self):
        self.run_main([])
        self.assertEqual(self.written_ids(), ["claude-main", "codex-main", "agy-main"])
        del self.keychain.passwords[m.AGY_KEYCHAIN_SERVICE]
        self.run_main([])
        self.assertEqual(self.written_ids(), ["claude-main", "codex-main"])

    def test_held_run_lock_skips_the_run_and_writes_nothing(self):
        lock_path = self.home / MAC_REL / "collector.lock"
        lock_path.parent.mkdir(parents=True)
        holder = open(lock_path, "a+")
        self.addCleanup(holder.close)
        fcntl.flock(holder.fileno(), fcntl.LOCK_EX)
        code, _ = self.run_main([])
        self.assertEqual(code, 0)
        self.assertFalse((self.home / MAC_REL / "usage.json").exists())
        self.assertIn("รอบก่อนยังทำงานอยู่", self.stderr.getvalue())

    def test_usage_at_85_percent_notifies_once_and_no_notify_flag_skips_it(self):
        self.use_clis({
            "claude": claude_program((claude_stream_lines(dict(CLAUDE_RATE_LIMITS, five_hour={
                "utilization": 85.0, "resets_at": "2026-11-19T06:40:00.000000+00:00"})), claude_text_lines())),
            "codex": single_program(codex_rpc_lines()),
            "agy": single_program(agy_usage_lines()),
        })
        (self.home / MAC_REL).mkdir(parents=True, exist_ok=True)
        (self.home / MAC_REL / "settings.json").write_text('{"language": "th"}', encoding="utf-8")
        self.run_main(["--state-dir", str(self.home / "state")])
        # Claude 85%, ChatGPT 93% and the agy Claude and GPT group at 100%: one notification each.
        self.assertEqual(len(self.notes), 3)
        self.assertIn("Claude · 5 ชม. ใช้ไปแล้ว 85%", self.notes)
        self.notes.clear()
        self.run_main(["--no-notify"])
        self.assertEqual(self.notes, [])

    def test_sentinel_secrets_never_reach_output_or_logs_or_the_file(self):
        self.use_clis({
            "claude": claude_program((
                claude_stream_error_lines(text="Not logged in · " + FAKE_EMAIL + " " + FAKE_SESSION),
                claude_text_lines(text="Current session: 40% used " + FAKE_EMAIL + " " + FAKE_SESSION)),
                folders={}),
            "codex": single_program([
                json_line({"id": 1, "result": {"platformOs": "macos", "accountId": FAKE_ACCOUNT_ID}}),
                json_line({"id": 2, "error": {"code": -32603,
                                              "message": "unauthorized for " + FAKE_ACCOUNT_ID}})]),
            "agy": single_program(agy_usage_lines(dict(AGY_USAGE_DOC, response=FAKE_AGY_ACCESS, status="ERROR",
                                                       conversation_id=FAKE_PROJECT))),
        })
        code, out = self.run_main(["--dry-run"])
        self.assertEqual(code, 0)
        combined = out + self.stderr.getvalue()
        for sentinel in SENTINELS:
            self.assertNotIn(sentinel, combined)
        self.assertNotIn("@", combined)
        code, _ = self.run_main([])
        self.assertEqual(code, 0)
        written = (self.home / MAC_REL / "usage.json").read_text(encoding="utf-8")
        for sentinel in SENTINELS:
            self.assertNotIn(sentinel, written)
        self.assertNotIn("@", written)

    def test_run_main_cannot_reach_the_real_network_or_subprocess(self):
        # The Base class patches all of these to raise ForbiddenCall; a real call would escape as a BaseException.
        with self.assertRaises(ForbiddenCall):
            subprocess.run(["true"])
        with self.assertRaises(ForbiddenCall):
            subprocess.Popen(["true"])
        with self.assertRaises(ForbiddenCall):
            urllib.request.urlopen("https://example.invalid")

    def test_scrub_masks_token_shapes_and_emails(self):
        text = m.scrub("a eyJabcdefghijk1 b sk-abcdefghijk2 c ya29.abcdefgh1 d user@example.com e")
        for fragment in ("eyJabcdefghijk1", "sk-abcdefghijk2", "ya29.abcdefgh1", "user@example.com"):
            self.assertNotIn(fragment, text)


class DirectModeTests(Base):
    """Opt-in direct mode, for codex and agy only. Here the CLIs are never started and the old token path runs."""

    def test_codex_direct_request_carries_account_header_and_codex_user_agent(self):
        self.write_codex_auth()
        http = FakeHTTP({m.CODEX_USAGE_URL: resp(CODEX_USAGE_BODY)})
        clis = self.use_clis({})
        acc = self.collect_real(make_env(self.home, http=http, direct={"codex": True}), "codex")
        self.assertEqual(acc["status"], "ok")
        headers = http.calls[0]["headers"]
        self.assertEqual(headers["ChatGPT-Account-Id"], FAKE_ACCOUNT_ID)
        self.assertEqual(headers["User-Agent"], "codex_cli_rs")
        self.assertEqual(headers["Authorization"], "Bearer " + FAKE_CODEX_ACCESS)
        self.assertEqual(clis.launches, [])

    def test_codex_direct_401_asks_for_relogin(self):
        self.write_codex_auth()
        http = FakeHTTP({m.CODEX_USAGE_URL: (401, b"{}")})
        acc = self.collect_real(make_env(self.home, http=http, direct={"codex": True}), "codex")
        self.assertEqual((acc["error_code"], acc["error"]), ("login_expired", m.MSG_CODEX_EXPIRED))

    def test_codex_direct_without_login_file_is_left_out_not_an_error(self):
        acc = self.collect_real(make_env(self.home, direct={"codex": True}), "codex")
        self.assertIsNone(acc)

    def test_agy_direct_without_project_asks_the_user_to_set_up_the_account(self):
        keychain = FakeKeychain({m.AGY_KEYCHAIN_SERVICE: agy_pw()})
        http = FakeHTTP({m.AGY_LOAD_URL: resp({"allowedTiers": [{"id": "standard-tier"}]})})
        acc = self.collect_real(make_env(self.home, keychain, http, direct={"agy": True}), "agy")
        self.assertEqual(acc["error"], m.MSG_AGY_NO_PROJECT)
        self.assertEqual(len(http.calls), 1)  # no quota call without a project

    def test_agy_direct_expired_token_is_renewed_by_running_agy_models_when_allowed(self):
        keychain = FakeKeychain({m.AGY_KEYCHAIN_SERVICE: agy_pw(expiry="2026-11-19T03:00:00+01:00")})
        ran = []

        def run(args, timeout=30):
            ran.append(list(args))
            return 0, ""

        http = FakeHTTP({m.AGY_LOAD_URL: resp(AGY_LOAD_BODY), m.AGY_MODELS_URL: resp(AGY_MODELS_BODY)})
        with mock.patch.object(m, "find_agy", return_value="/fake/bin/agy"):
            acc = self.collect_real(make_env(self.home, keychain, http, run=run, direct={"agy": True}), "agy")
        self.assertEqual(ran, [["/fake/bin/agy", "models"]])
        self.assertEqual(acc["status"], "ok")

    def test_agy_direct_no_refresh_does_not_run_agy_models_and_reports_expiry(self):
        keychain = FakeKeychain({m.AGY_KEYCHAIN_SERVICE: agy_pw(expiry="2026-11-19T03:00:00+01:00")})
        ran = []
        http = FakeHTTP({m.AGY_LOAD_URL: (401, b"{}")})
        with mock.patch.object(m, "find_agy", return_value="/fake/bin/agy"):
            acc = self.collect_real(make_env(self.home, keychain, http, allow_refresh=False,
                                             run=lambda args, timeout=30: ran.append(args) or (0, ""),
                                             direct={"agy": True}), "agy")
        self.assertEqual(ran, [])
        self.assertEqual(acc["error"], m.MSG_AGY_EXPIRED)

    def test_agy_direct_without_keychain_item_is_left_out_not_an_error(self):
        acc = self.collect_real(make_env(self.home, direct={"agy": True}), "agy")
        self.assertIsNone(acc)

    def test_agy_direct_requests_send_the_antigravity_client_header_and_the_ideType_body(self):
        self.assertEqual(m.AGY_USER_AGENT, "antigravity")
        keychain = FakeKeychain({m.AGY_KEYCHAIN_SERVICE: agy_pw()})
        http = FakeHTTP({m.AGY_LOAD_URL: resp(AGY_LOAD_BODY), m.AGY_MODELS_URL: resp(AGY_MODELS_BODY)})
        env = make_env(self.home, keychain, http, direct={"agy": True})
        acc = self.collect_real(env, "agy")
        self.assertEqual(acc["status"], "ok")
        self.assertEqual([call["url"] for call in http.calls], [m.AGY_LOAD_URL, m.AGY_MODELS_URL])
        for call in http.calls:
            self.assertEqual(call["headers"]["User-Agent"], "antigravity")
        self.assertEqual(json.loads(http.calls[0]["body"]), {"metadata": {"ideType": "ANTIGRAVITY"}})


class LocalUsageOnApiErrorTests(Base):
    """The token totals come from the local logs even when the CLI fails. Stale data keeps its limits."""

    def write_claude_logs(self):
        path = self.home / ".claude" / "projects" / "proj" / "s.jsonl"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(claude_line("m21", "r21", "claude-sonnet-5-5", "2026-11-19T03:00:00.000Z", 40, 10),
                        encoding="utf-8")

    def failing_claude(self):
        return self.use_clis({"claude": claude_program(("hang", "hang"))})

    def test_successful_call_also_reports_the_local_usage(self):
        self.write_claude_logs()
        self.use_clis({"claude": claude_program((claude_stream_lines(), claude_text_lines()))})
        acc = self.collect_real(make_env(self.home), "claude")
        self.assertEqual(acc["status"], "ok")
        self.assertEqual(acc["usage"]["today"]["tokens"], 50)

    def test_claude_usage_comes_from_the_logs_when_the_cli_fails(self):
        self.write_claude_logs()
        self.failing_claude()
        acc = self.collect_real(make_env(self.home), "claude")
        self.assertEqual((acc["status"], acc["error_code"]), ("error", "network"))
        self.assertEqual(acc["limits"], [])
        self.assertEqual(acc["usage"]["today"]["tokens"], 50)

    def test_stale_claude_account_keeps_old_limits_but_takes_fresh_usage(self):
        self.write_claude_logs()
        previous = {"plan": "Max 5x", "status": "ok", "updated_at": "2026-11-19T04:00:00Z",
                    "limits": [{"key": "five_hour", "label": "5 ชม.", "used_percent": 42.0,
                                "resets_at": "2026-11-19T06:40:00Z"}],
                    "usage": {"today": {"tokens": 1, "cost_usd": 0.0},
                              "month": {"tokens": 2, "cost_usd": 0.0}},
                    "credits": None}
        self.failing_claude()
        acc = self.collect_real(make_env(self.home), "claude", previous)
        self.assertEqual(acc["status"], "stale")
        self.assertEqual(acc["limits"], [dict(previous["limits"][0], window_seconds=18000)])
        self.assertEqual(acc["updated_at"], "2026-11-19T04:00:00Z")
        self.assertEqual(acc["usage"]["today"]["tokens"], 50)

    def test_codex_usage_comes_from_the_session_logs_when_the_cli_fails(self):
        self.write_codex_auth()
        day = self.home / ".codex" / "sessions" / "2026" / "11" / "19"
        day.mkdir(parents=True)
        (day / "rollout-b.jsonl").write_text(codex_line("2026-11-19T03:00:00.000Z", 1000), encoding="utf-8")
        self.use_clis({"codex": single_program("hang")})
        acc = self.collect_real(make_env(self.home), "codex")
        self.assertEqual(acc["status"], "error")
        self.assertEqual((acc["usage"]["today"]["tokens"], acc["usage"]["today"]["cost_usd"]), (1000, None))

    def test_agy_has_no_local_logs_so_its_usage_stays_null(self):
        keychain = FakeKeychain({m.AGY_KEYCHAIN_SERVICE: agy_pw()})
        self.use_clis({"agy": single_program("hang")})
        acc = self.collect_real(make_env(self.home, keychain), "agy")
        self.assertEqual(acc["status"], "error")
        self.assertIsNone(acc["usage"])


def gpt_turn(stamp, inp, cached=0, cache_write=0, output=0, reasoning=None, flag=None, total=None):
    """One token_count event with its per-turn last_token_usage. reasoning and flag are left out when None."""
    last = {"input_tokens": inp, "cached_input_tokens": cached, "cache_write_input_tokens": cache_write,
            "output_tokens": output, "total_tokens": inp + output if total is None else total}
    if reasoning is not None:
        last["reasoning_output_tokens"] = reasoning
    info = {"last_token_usage": last, "total_token_usage": {"total_tokens": 999_999_999}}
    if flag is not None:
        info["last_usage_includes_reasoning"] = flag
    payload = {"type": "token_count", "info": info}
    return json.dumps({"timestamp": stamp, "type": "event_msg", "payload": payload}) + "\n"


def gpt_context(stamp, model):
    return json.dumps({"timestamp": stamp, "type": "turn_context", "payload": {"model": model}}) + "\n"


class GptUsageTests(Base):
    """GPT (Codex) per-model counts, per-turn costs, and the GPT rows of the price table."""

    def write_codex(self, name, lines, folder="2026/11/19"):
        day = self.home / ".codex" / "sessions" / folder
        day.mkdir(parents=True, exist_ok=True)
        path = day / name
        path.write_text("".join(lines), encoding="utf-8")
        return path

    def test_three_models_are_counted_by_kind_for_today_and_month(self):
        self.write_codex("gpt-a.jsonl", [
            gpt_context("2026-11-18T10:00:00.000Z", "gpt-6-luna"),
            gpt_turn("2026-11-18T10:00:01.000Z", 100, output=10),
            gpt_context("2026-11-19T03:00:00.000Z", "gpt-6-luna"),
            gpt_turn("2026-11-19T03:00:01.000Z", 1000, cached=400, output=100, reasoning=40, flag=True),
            gpt_context("2026-11-19T03:05:00.000Z", "gpt-6.2-sol"),
            gpt_turn("2026-11-19T03:05:01.000Z", 2000, cached=1000, output=300),
            gpt_context("2026-11-19T03:10:00.000Z", "gpt-6.1-sol"),
            gpt_turn("2026-11-19T03:10:01.000Z", 500, output=50, reasoning=10, flag=False),
        ])
        usage = m.codex_local_usage(make_env(self.home))
        today = usage["today"]["by_model"]
        self.assertEqual(today["gpt-6-luna"], {"input": 600, "cached_input": 400, "cache_write": 0,
                                               "output": 100, "reasoning": 40})
        self.assertEqual(today["gpt-6.2-sol"], {"input": 1000, "cached_input": 1000, "cache_write": 0,
                                                "output": 300, "reasoning": 0})
        self.assertEqual(today["gpt-6.1-sol"], {"input": 500, "cached_input": 0, "cache_write": 0,
                                                "output": 50, "reasoning": 10})
        self.assertEqual(usage["today"]["tokens"], 1100 + 2300 + 550)  # input + output of each turn
        self.assertEqual(usage["month"]["tokens"], 1100 + 2300 + 550 + 110)
        self.assertEqual(usage["month"]["by_model"]["gpt-6-luna"]["input"], 700)
        self.assertEqual(usage["month"]["by_model"]["gpt-6-luna"]["output"], 110)
        self.assertEqual(set(today), {"gpt-6-luna", "gpt-6.2-sol", "gpt-6.1-sol"})

    def test_cached_input_is_split_out_of_input_and_cache_write_is_its_own_kind(self):
        self.write_codex("gpt-b.jsonl", [
            gpt_context("2026-11-19T03:00:00.000Z", "gpt-6.2-sol"),
            gpt_turn("2026-11-19T03:00:01.000Z", 1000, cached=250, cache_write=70, output=5),
        ])
        row = m.codex_local_usage(make_env(self.home))["today"]["by_model"]["gpt-6.2-sol"]
        self.assertEqual((row["input"], row["cached_input"], row["cache_write"]), (750, 250, 70))

    def reasoning_cost(self, flag):
        self.write_codex("gpt-r.jsonl", [
            gpt_context("2026-11-19T03:00:00.000Z", "gpt-6-luna"),
            gpt_turn("2026-11-19T03:00:01.000Z", 0, output=1_000_000, reasoning=500_000, flag=flag),
        ])
        return m.codex_local_usage(make_env(self.home))["today"]

    def test_reasoning_is_not_added_when_the_log_flag_is_true(self):
        today = self.reasoning_cost(True)
        self.assertEqual(today["cost_usd"], 0.5)  # 1M output at 0.50 per million, reasoning already inside
        self.assertEqual(today["by_model"]["gpt-6-luna"]["reasoning"], 500_000)

    def test_reasoning_is_not_added_when_the_log_has_no_flag(self):
        today = self.reasoning_cost(None)
        self.assertEqual(today["cost_usd"], 0.5)  # output_tokens includes reasoning by default
        self.assertEqual(today["by_model"]["gpt-6-luna"]["reasoning"], 500_000)

    def test_reasoning_is_added_as_output_when_the_flag_says_output_leaves_it_out(self):
        today = self.reasoning_cost(False)
        self.assertEqual(today["cost_usd"], 0.75)  # (1M + 0.5M) output at 0.50 per million
        self.assertEqual(today["by_model"]["gpt-6-luna"]["reasoning"], 500_000)
        self.assertEqual(today["by_model"]["gpt-6-luna"]["output"], 1_000_000)

    def test_long_context_turn_uses_long_rates_for_the_whole_turn(self):
        cases = [
            # (input, cached, cache write, output, expected USD)
            (272_000, 100_000, 0, 1000,  # short: 172k plain at 2.00, 100k cached at 0.10, 1k output at 10
             (172_000 * 2.0 + 100_000 * 0.1 + 1000 * 10.0) / 1e6),
            (272_001, 100_000, 0, 1000,  # long: 172001 plain at 4.00, 100k cached at 0.20, 1k output at 15
             (172_001 * 4.0 + 100_000 * 0.2 + 1000 * 15.0) / 1e6),
            (300_000, 100_000, 1_000_000, 1000,  # long, cache write at the short rate (2.50)
             (200_000 * 4.0 + 100_000 * 0.2 + 1_000_000 * 2.5 + 1000 * 15.0) / 1e6),
        ]
        for inp, cached, cw, out, expected in cases:
            with self.subTest(input=inp, cache_write=cw):
                self.assertAlmostEqual(m.gpt_cost_usd("gpt-6.2-sol", inp, cached, cw, out, 0), expected)

    def test_long_context_threshold_and_luna_long_rates(self):
        self.assertEqual(m.GPT_LONG_CONTEXT, 272_000)
        # luna short: 100k plain at 0.10 and 1M output at 0.50
        self.assertAlmostEqual(m.gpt_cost_usd("gpt-6-luna", 100_000, 0, 0, 1_000_000, 0), 0.51)
        # luna long (input above 272k): 300k plain at 0.20 and 1M output at 0.75
        self.assertAlmostEqual(m.gpt_cost_usd("gpt-6-luna", 300_000, 0, 0, 1_000_000, 0),
                               (300_000 * 0.20 + 1_000_000 * 0.75) / 1e6)

    def test_long_context_split_keeps_totals_and_the_mac_formula_gives_the_same_cost(self):
        self.write_codex("gpt-long.jsonl", [
            gpt_context("2026-11-19T03:00:00.000Z", "gpt-6-luna"),
            gpt_turn("2026-11-19T03:00:01.000Z", 100_000, cached=20_000, output=1000, reasoning=300),   # short
            gpt_turn("2026-11-19T03:00:02.000Z", 300_000, cached=50_000, output=5000, reasoning=1000),  # long
            gpt_turn("2026-11-19T03:00:03.000Z", 1000, output=100),                                       # short
            gpt_context("2026-11-19T03:05:00.000Z", "gpt-6.2-sol"),
            gpt_turn("2026-11-19T03:05:01.000Z", 272_000, output=100),  # exactly 272,000: still short
            gpt_turn("2026-11-19T03:05:02.000Z", 280_000, cache_write=10_000, output=2000, reasoning=500),  # long
            gpt_context("2026-11-19T03:10:00.000Z", "gpt-6.1-sol"),
            gpt_turn("2026-11-19T03:10:01.000Z", 500, output=50),  # short only: no long_context key
        ])
        usage = m.codex_local_usage(make_env(self.home))
        today = usage["today"]
        by = today["by_model"]
        # Totals are the short and long turns together, the same numbers as before the split.
        self.assertEqual(by["gpt-6-luna"], {
            "input": 331_000, "cached_input": 70_000, "cache_write": 0, "output": 6100, "reasoning": 1300,
            "long_context": {"input": 250_000, "cached_input": 50_000, "cache_write": 0, "output": 5000,
                             "reasoning": 1000}})
        self.assertEqual(by["gpt-6.2-sol"], {
            "input": 552_000, "cached_input": 0, "cache_write": 10_000, "output": 2100, "reasoning": 500,
            "long_context": {"input": 280_000, "cached_input": 0, "cache_write": 10_000, "output": 2000,
                             "reasoning": 500}})
        self.assertEqual(by["gpt-6.1-sol"], {"input": 500, "cached_input": 0, "cache_write": 0, "output": 50,
                                             "reasoning": 0})
        self.assertEqual(today["tokens"], 101_000 + 305_000 + 1100 + 272_100 + 282_000 + 550)
        self.assertEqual(usage["month"]["by_model"]["gpt-6.2-sol"]["long_context"]["input"], 280_000)

        def mac_cost(by_model):
            """The Mac formula from by_model only: the short part at base rates, the long_context part at the
            long-context rates. The long cache write uses the short rate, since the long table has none."""
            total = 0.0
            for model, entry in by_model.items():
                _, _, _, _, (p_in, p_cached, p_cw, p_out), (l_in, l_cached, l_out) = m.gpt_price_row(model)
                long = entry.get("long_context", {})
                short = {kind: entry[kind] - long.get(kind, 0) for kind in m.CODEX_KINDS}
                total += (short["input"] * p_in + short["cached_input"] * p_cached
                          + short["cache_write"] * p_cw + short["output"] * p_out
                          + long.get("input", 0) * l_in + long.get("cached_input", 0) * l_cached
                          + long.get("cache_write", 0) * p_cw + long.get("output", 0) * l_out) / 1_000_000
            return total

        # luna 0.0636 + sol 6.2 1.72 + sol 6.1 0.0015
        self.assertAlmostEqual(mac_cost(by), 1.7851)
        self.assertEqual(today["cost_usd"], round(mac_cost(by), 2))
        self.assertEqual(today["cost_usd"], 1.79)

    def test_turn_costs_add_up_per_day_and_month(self):
        self.write_codex("gpt-c.jsonl", [
            gpt_context("2026-11-19T03:00:00.000Z", "gpt-6-luna"),
            gpt_turn("2026-11-19T03:00:01.000Z", 100_000, output=1_000_000),
            gpt_context("2026-11-18T03:00:00.000Z", "gpt-6.2-sol"),
            gpt_turn("2026-11-18T03:00:01.000Z", 1_000_000, output=0),
        ])
        usage = m.codex_local_usage(make_env(self.home))
        self.assertEqual(usage["today"]["cost_usd"], 0.51)
        # the Nov 18 turn has 1M input, above 272k, so it is priced at the long-context rate (4.00 per million)
        self.assertEqual(usage["month"]["cost_usd"], 4.51)

    def test_duplicate_event_in_one_file_or_in_a_resumed_copy_counts_once(self):
        turn = gpt_turn("2026-11-19T03:00:01.000Z", 100_000, output=1_000_000)
        self.write_codex("gpt-d1.jsonl", [gpt_context("2026-11-19T03:00:00.000Z", "gpt-6-luna"), turn, turn])
        self.write_codex("gpt-d2.jsonl", [gpt_context("2026-11-19T03:00:00.000Z", "gpt-6-luna"), turn])
        usage = m.codex_local_usage(make_env(self.home))
        self.assertEqual(usage["today"]["tokens"], 1_100_000)
        self.assertEqual(usage["today"]["cost_usd"], 0.51)
        self.assertEqual(usage["today"]["by_model"]["gpt-6-luna"]["output"], 1_000_000)

    def test_two_turns_with_the_same_numbers_at_different_times_both_count(self):
        self.write_codex("gpt-e.jsonl", [
            gpt_context("2026-11-19T03:00:00.000Z", "gpt-6-luna"),
            gpt_turn("2026-11-19T03:00:01.000Z", 100_000, output=1_000_000),
            gpt_turn("2026-11-19T03:00:02.000Z", 100_000, output=1_000_000),
        ])
        usage = m.codex_local_usage(make_env(self.home))
        self.assertEqual(usage["today"]["tokens"], 2_200_000)

    def test_unknown_model_counts_tokens_and_makes_the_cost_null(self):
        self.write_codex("gpt-f.jsonl", [
            gpt_context("2026-11-19T03:00:00.000Z", "gpt-7-mystery"),
            gpt_turn("2026-11-19T03:00:01.000Z", 1000, output=100),
            gpt_context("2026-11-19T03:01:00.000Z", "gpt-6-luna"),
            gpt_turn("2026-11-19T03:01:01.000Z", 1000, output=100),
        ])
        usage = m.codex_local_usage(make_env(self.home))
        self.assertEqual(usage["today"]["tokens"], 2200)
        self.assertIsNone(usage["today"]["cost_usd"])
        self.assertEqual(usage["today"]["by_model"]["gpt-7-mystery"]["input"], 1000)
        self.assertEqual(usage["today"]["by_model"]["gpt-6-luna"]["output"], 100)

    def test_turn_without_any_model_is_unknown_and_has_no_cost(self):
        self.write_codex("gpt-g.jsonl", [gpt_turn("2026-11-19T03:00:01.000Z", 1000, output=100)])
        usage = m.codex_local_usage(make_env(self.home))
        self.assertEqual(usage["today"]["by_model"]["unknown"]["input"], 1000)
        self.assertIsNone(usage["today"]["cost_usd"])

    def test_model_ids_are_matched_by_prefix_and_otherwise_kept_as_logged(self):
        self.assertEqual(m.gpt_model_id("gpt-6.2-sol-2026-11-01"), "gpt-6.2-sol")
        self.assertEqual(m.gpt_model_id("GPT-6-Luna"), "gpt-6-luna")
        self.assertEqual(m.gpt_model_id("gpt-6-sol"), "gpt-6-sol")  # not in the price table: no prefix match
        self.assertIsNone(m.gpt_cost_usd("gpt-6-sol", 1, 0, 0, 1, 0))
        self.assertEqual(m.gpt_model_id(None), "unknown")
        self.assertEqual(m.gpt_model_id("   "), "unknown")
        self.assertEqual(len(m.gpt_model_id("x" * 200)), 64)

    def test_day_and_month_boundaries_use_the_injected_zone(self):
        # Zone in the test: Europe/Berlin (UTC+1 on these dates). NOW is Nov 19 05:30 Berlin.
        self.write_codex("gpt-h.jsonl", [
            gpt_context("2026-10-31T22:30:00.000Z", "gpt-6-luna"),
            gpt_turn("2026-10-31T22:30:01.000Z", 1, output=1),   # Oct 31 23:30 Berlin: October, tokens 2
            gpt_turn("2026-10-31T23:30:01.000Z", 2, output=2),   # Nov 1 00:30 Berlin: November, tokens 4
            gpt_turn("2026-11-18T22:30:01.000Z", 4, output=4),   # Nov 18 23:30 Berlin: yesterday, tokens 8
            gpt_turn("2026-11-19T03:00:01.000Z", 8, output=8),   # Nov 19 04:00 Berlin: today, tokens 16
        ])
        usage = m.codex_local_usage(make_env(self.home))
        self.assertEqual(usage["today"]["tokens"], 16)
        self.assertEqual(usage["month"]["tokens"], 4 + 8 + 16)
        with mock.patch.object(m, "DAY_ZONE", ZoneInfo("America/New_York")):
            usage = m.codex_local_usage(make_env(self.home, cache={}))
        # In New York NOW is Nov 18 23:30, so the two Nov 18 turns are "today" and the October and
        # Nov 1 turns (Oct 31 in New York) are not in the month.
        self.assertEqual(usage["today"]["tokens"], 8 + 16)
        self.assertEqual(usage["month"]["tokens"], 8 + 16)

    def test_a_cached_file_is_not_parsed_again_and_a_changed_file_is_parsed_once_more(self):
        path = self.write_codex("gpt-k.jsonl", [gpt_context("2026-11-19T03:00:00.000Z", "gpt-6-luna"),
                                                gpt_turn("2026-11-19T03:00:01.000Z", 10, output=10)])
        cache = {}
        with mock.patch.object(m, "parse_codex_file", wraps=m.parse_codex_file) as parse:
            first = m.codex_local_usage(make_env(self.home, cache=cache))
            second = m.codex_local_usage(make_env(self.home, cache=cache))
            self.assertEqual(parse.call_count, 1)
            self.assertEqual(first, second)
            path.write_text(path.read_text(encoding="utf-8") + gpt_turn(
                "2026-11-19T03:02:00.000Z", 5, output=5), encoding="utf-8")
            third = m.codex_local_usage(make_env(self.home, cache=cache))
            self.assertEqual(parse.call_count, 2)
        self.assertEqual(third["today"]["tokens"], 30)

    def test_model_prices_list_the_gpt_rows_with_provider_and_long_context(self):
        prices = m.model_prices()
        self.assertEqual(prices["gpt-6-luna"], {
            "provider": "openai", "family": "luna", "label": "GPT-6 Luna", "input": 0.1, "cached_input": 0.01,
            "cache_write": 0.125, "output": 0.5,
            "long_context": {"threshold": 272000, "input": 0.2, "cached_input": 0.02, "output": 0.75}})
        self.assertEqual(prices["gpt-6.2-sol"]["long_context"],
                         {"threshold": 272000, "input": 4.0, "cached_input": 0.2, "output": 15.0})
        self.assertEqual(prices["gpt-6.1-sol"]["label"], "GPT-6.1 Sol")
        self.assertEqual(prices["gpt-6.1-sol"]["provider"], "openai")
        for model in ("claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5", "claude-fable-5-2"):
            self.assertEqual(prices[model]["provider"], "anthropic")


class AgyGroupTests(unittest.TestCase):
    """agy limits carry a display group (gemini, addon, other) and come in display order."""

    def bucket_groups(self, buckets):
        return [{"name": "fixture", "buckets": buckets}]

    def test_known_cli_keys_come_in_the_display_order_with_their_labels_and_groups(self):
        groups = self.bucket_groups([
            agy_bucket("3p-weekly", "x", "weekly", 0.5, "2026-11-24T02:00:00Z"),
            agy_bucket("gemini-argon-wtu-weekly", "x", "weekly", 0.5, "2026-11-24T02:00:00Z"),
            agy_bucket("3p-5h", "x", "5h", 0.5, "2026-11-19T09:00:00Z"),
            agy_bucket("gemini-weekly", "x", "weekly", 0.5, "2026-11-24T02:00:00Z"),
            agy_bucket("gemini-5h", "x", "5h", 0.5, "2026-11-19T09:00:00Z")])
        limits = m.agy_cli_limits(groups)
        self.assertEqual([limit["key"] for limit in limits],
                         ["gemini-5h", "gemini-weekly", "gemini-argon-wtu-weekly", "3p-5h", "3p-weekly"])
        self.assertEqual([limit["label"] for limit in limits],
                         ["Gemini Models · 5h", "Gemini Models · Weekly", "Gemini Argon · Weekly",
                          "Claude & GPT · 5h", "Claude & GPT · Weekly"])
        self.assertEqual([limit["group"] for limit in limits], ["gemini", "gemini", "gemini", "addon", "addon"])
        self.assertTrue(all(limit["window_seconds"] is None for limit in limits))

    def test_unknown_keys_follow_their_group_prefix_and_others_come_last(self):
        groups = self.bucket_groups([
            agy_bucket("zz-new", "Mystery", "weekly", 0.5, "2026-11-24T02:00:00Z"),
            agy_bucket("3p-new", "Claude thing", "5h", 0.5, "2026-11-19T09:00:00Z"),
            agy_bucket("gemini-new-5h", "Gemini new", "5h", 0.5, "2026-11-19T09:00:00Z"),
            agy_bucket("gemini-weekly", "x", "weekly", 0.5, "2026-11-24T02:00:00Z")])
        limits = m.agy_cli_limits(groups)
        self.assertEqual([limit["key"] for limit in limits],
                         ["gemini-weekly", "gemini-new-5h", "3p-new", "zz-new"])
        self.assertEqual([limit["group"] for limit in limits], ["gemini", "gemini", "addon", "other"])
        self.assertEqual(limits[1]["label"], "fixture · 5h")  # unknown key keeps the label the CLI gave

    def test_direct_mode_models_are_grouped_gemini_first(self):
        limits = m.group_agy_models({
            "claude-opus": {"quotaInfo": {"remainingFraction": 0.5, "resetTime": "2026-11-19T09:21:41Z"}},
            "gpt-oss-120b": {"quotaInfo": {"remainingFraction": 1, "resetTime": "2026-11-19T09:21:41Z"}},
            "gemini-3-flash": {"quotaInfo": {"remainingFraction": 0.75, "resetTime": "2026-11-19T09:21:41Z"}},
            "gemini-3-pro": {"quotaInfo": {"remainingFraction": 1, "resetTime": "2026-11-19T09:21:41Z"}}})
        self.assertEqual([limit["key"] for limit in limits],
                         ["gemini_pro", "gemini_flash", "claude", "gpt_oss"])
        self.assertEqual([limit["group"] for limit in limits], ["gemini", "gemini", "addon", "addon"])

    def test_the_group_field_is_always_one_of_three_values(self):
        groups = self.bucket_groups([agy_bucket("", "x", "5h", 0.5, "2026-11-19T09:00:00Z")])
        limits = m.agy_cli_limits(groups)
        self.assertEqual({limit["group"] for limit in limits}, {"other"})
        self.assertEqual({m.agy_limit_group(key) for key in ("tab_x", "gemini_pro", "3p-5h")},
                         {"other", "gemini", "addon"})


if __name__ == "__main__":
    unittest.main()
