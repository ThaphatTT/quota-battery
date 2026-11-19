"""Several accounts per provider: discovery by folder, labels, order, hiding and known-accounts.json.

Claude is found by its config folder and never by a Keychain item. Whether its login is there is decided by the
CLI, so a folder that is not logged in is left out after the run, and only then are the labels numbered.
Every fixture folder lives in a temporary HOME. The provider CLIs are scripted, and nothing real runs.
"""
import contextlib
import io
import json
import os
import shutil
import unittest
from datetime import datetime, timedelta
from pathlib import Path
from unittest import mock

import ai_usage_collect as m
from tests.test_collector import (CLAUDE_RATE_LIMITS, NOW, SENTINELS, Base, FakeHTTP, FakeKeychain, agy_pw,
                                  agy_usage_lines, claude_line, claude_program, claude_stream_error_lines,
                                  claude_stream_lines, claude_text_lines, codex_rpc_lines, make_env,
                                  single_program)

SECOND_RATE = dict(CLAUDE_RATE_LIMITS,
                   five_hour={"utilization": 85.0, "resets_at": "2026-11-19T06:40:00.000000+00:00"},
                   seven_day={"utilization": 20.0, "resets_at": "2026-11-24T02:00:00.000000+00:00"})


def frozen_at(moment):
    """A datetime class whose now() is moment, so that main() can run at chosen times."""
    class Frozen(datetime):
        @classmethod
        def now(cls, tz=None):
            return moment if tz is None else moment.astimezone(tz)
    return Frozen


def pair(account_id, provider, label, used=None):
    """A (source, account) pair for the ordering tests. used is one percentage, or a tuple of them (one per window)."""
    source = m.Source(id=account_id, provider=provider, source=label, default_label=label)
    windows = () if used is None else (used if isinstance(used, tuple) else (used,))
    limits = [{"key": f"window{index}", "label": "x", "used_percent": float(value),
               "resets_at": None, "window_seconds": None} for index, value in enumerate(windows)]
    return source, {"id": account_id, "provider": provider, "label": label, "limits": limits}


def ids_of(accounts):
    return [account["id"] for account in accounts]


class KeychainExistsTests(unittest.TestCase):
    def test_only_not_found_means_missing_and_the_password_is_never_asked_for(self):
        keychain = m.SystemKeychain()
        for rc, expected in ((0, True), (m.KEYCHAIN_NOT_FOUND_RC, False), (1, True), (-1, True)):
            with mock.patch.object(m, "run_cmd", return_value=(rc, "")) as run:
                self.assertEqual(keychain.exists("gemini", "antigravity"), expected, rc)
            self.assertNotIn("-w", run.call_args.args[0])

    def test_an_account_name_is_passed_on_when_given(self):
        with mock.patch.object(m, "run_cmd", return_value=(0, "")) as run:
            m.SystemKeychain().exists("gemini", "antigravity")
        self.assertEqual(run.call_args.args[0][-2:], ["-a", "antigravity"])


class LabelTests(unittest.TestCase):
    def test_one_account_keeps_the_plain_label_and_several_are_numbered_in_order(self):
        def sources(*providers):
            return [m.Source(id=f"{p}-{i}", provider=p, source="") for i, p in enumerate(providers)]
        single = sources("claude", "codex")
        m.number_default_labels(single)
        self.assertEqual([s.default_label for s in single], ["Claude", "ChatGPT"])
        several = sources("claude", "claude", "codex", "codex", "agy")
        m.number_default_labels(several)
        self.assertEqual([s.default_label for s in several],
                         ["Claude 1", "Claude 2", "ChatGPT 1", "ChatGPT 2", "agy"])


class OrderTests(unittest.TestCase):
    def setUp(self):
        self.pairs = [pair("claude-main", "claude", "Claude 1", used=60),
                      pair("claude-2", "claude", "Claude 2", used=90),
                      pair("codex-main", "codex", "ChatGPT", used=60),
                      pair("agy-main", "agy", "agy")]

    def order(self, settings, pairs=None):
        return m.order_accounts(list(pairs or self.pairs), settings)

    def test_manual_order_is_the_discovery_order_when_nothing_is_set(self):
        self.assertEqual(ids_of(self.order({})), ["claude-main", "claude-2", "codex-main", "agy-main"])

    def test_manual_order_puts_the_numbered_accounts_first_and_keeps_discovery_order_for_the_rest(self):
        settings = {"accounts": {"claude-2": {"order": 0}, "agy-main": {"order": 1}}}
        self.assertEqual(ids_of(self.order(settings)), ["claude-2", "agy-main", "claude-main", "codex-main"])

    def test_lowest_left_first_with_ties_in_manual_order_and_no_limits_last(self):
        # claude-main and codex-main both have 40 left, so manual order decides; agy-main has no limits.
        settings = {"sort": "lowest"}
        self.assertEqual(ids_of(self.order(settings)), ["claude-2", "claude-main", "codex-main", "agy-main"])

    def test_lowest_uses_the_most_used_window_of_each_account(self):
        pairs = [pair("claude-main", "claude", "Claude 1", used=(20, 70)),
                 pair("claude-2", "claude", "Claude 2", used=50)]
        self.assertEqual(ids_of(self.order({"sort": "lowest"}, pairs)), ["claude-main", "claude-2"])

    def test_provider_order_is_claude_then_chatgpt_then_agy_with_manual_order_inside(self):
        settings = {"sort": "provider",
                    "accounts": {"claude-2": {"order": 0}, "claude-main": {"order": 1}, "agy-main": {"order": 0}}}
        self.assertEqual(ids_of(self.order(settings)), ["claude-2", "claude-main", "codex-main", "agy-main"])

    def test_only_a_json_false_hides_an_account(self):
        settings = {"accounts": {"claude-2": {"enabled": False}, "codex-main": {"enabled": "false"}}}
        self.assertEqual(ids_of(self.order(settings)), ["claude-main", "codex-main", "agy-main"])

    def test_a_nickname_replaces_the_label_and_a_blank_one_does_not(self):
        settings = {"accounts": {"claude-2": {"label": "  Claude งาน  "}, "claude-main": {"label": "   "}}}
        self.assertEqual([account["label"] for account in self.order(settings)[:2]], ["Claude 1", "Claude งาน"])

    def test_unknown_settings_values_count_as_the_defaults(self):
        settings = {"sort": "random", "accounts": {"claude-2": "off", "codex-main": {"order": "1"},
                                                   "agy-main": {"order": True}}}
        self.assertEqual(ids_of(self.order(settings)), ["claude-main", "claude-2", "codex-main", "agy-main"])


class DiscoveryTests(Base):
    def setUp(self):
        super().setUp()
        patch = mock.patch.dict(os.environ, {"HOME": str(self.home)})  # ~/ in accounts.json expands through HOME
        patch.start()
        self.addCleanup(patch.stop)
        self.folder(".claude", "projects")
        self.folder(".claude-2", ".claude.json", "projects")
        self.folder(".claude-10", "projects")  # sorts after .claude-2
        self.folder(".claude-3")  # no Claude Code config in it
        self.folder(".claude-4")  # not a Claude folder
        self.folder("accounts/team", "projects")  # listed in accounts.json
        self.folder("accounts/nologin")  # listed, but no Claude Code config
        self.folder(".codex-2")
        self.folder(".codex-3")  # no auth.json
        (self.home / ".codex-2" / "auth.json").write_text(json.dumps({"tokens": {}}), encoding="utf-8")
        self.write_codex_auth()
        self.keychain = FakeKeychain({m.AGY_KEYCHAIN_SERVICE: agy_pw()})
        self.write_accounts({"claude": ["~/accounts/team", "~/accounts/nologin", "~/accounts/missing"]})

    def folder(self, relative, *entries):
        path = self.home / relative
        path.mkdir(parents=True, exist_ok=True)
        for entry in entries:
            if entry.endswith(".json"):
                (path / entry).write_text("{}", encoding="utf-8")
            else:
                (path / entry).mkdir(exist_ok=True)

    def write_accounts(self, data):
        path = m.Paths(self.home).accounts_file
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data), encoding="utf-8")

    def discover(self):
        return m.discover_sources(make_env(self.home, keychain=self.keychain))

    def test_finds_each_folder_with_claude_config_in_discovery_order(self):
        sources = self.discover()
        self.assertEqual([s.id for s in sources],
                         ["claude-main", "claude-2", "claude-10", "claude-team", "codex-main", "codex-2",
                          "agy-main"])
        self.assertEqual([s.default_label for s in sources],
                         ["Claude", "Claude", "Claude", "Claude", "ChatGPT", "ChatGPT", "agy"])
        self.assertEqual([s.source for s in sources],
                         ["Claude Code (main)", "Claude Code (~/.claude-2)", "Claude Code (~/.claude-10)",
                          "Claude Code (~/accounts/team)", "Codex (~/.codex)", "Codex (~/.codex-2)",
                          "agy (Keychain)"])

    def test_no_claude_keychain_item_is_ever_asked_for(self):
        self.discover()
        self.assertEqual(self.keychain.checks, ["gemini"])
        self.assertEqual(self.keychain.reads, [])

    def test_each_claude_folder_gets_its_own_config_variable_and_projects_folder(self):
        sources = {s.id: s for s in self.discover()}
        self.assertEqual(sources["claude-main"].cli_env, {})
        self.assertEqual(sources["claude-2"].cli_env, {"CLAUDE_CONFIG_DIR": str(self.home / ".claude-2")})
        self.assertEqual(sources["claude-2"].projects_dir, self.home / ".claude-2" / "projects")
        self.assertEqual(sources["codex-2"].cli_env, {"CODEX_HOME": str(self.home / ".codex-2")})
        self.assertEqual(sources["codex-2"].auth_file, self.home / ".codex-2" / "auth.json")

    def test_the_main_claude_folder_counts_on_the_home_config_file_alone(self):
        shutil.rmtree(self.home / ".claude")
        (self.home / ".claude.json").write_text("{}", encoding="utf-8")
        ids = [s.id for s in self.discover() if s.provider == "claude"]
        self.assertEqual(ids, ["claude-main", "claude-2", "claude-10", "claude-team"])
        (self.home / ".claude.json").unlink()
        ids = [s.id for s in self.discover() if s.provider == "claude"]
        self.assertEqual(ids, ["claude-2", "claude-10", "claude-team"])

    def test_a_folder_listed_twice_is_counted_once(self):
        self.write_accounts({"claude": ["~/.claude", "~/.claude-2/", "~/.claude-2"]})
        ids = [s.id for s in self.discover() if s.provider == "claude"]
        self.assertEqual(ids, ["claude-main", "claude-2", "claude-10"])

    def test_a_listed_folder_without_claude_config_is_not_an_account(self):
        self.assertNotIn("claude-nologin", [s.id for s in self.discover()])

    def test_a_broken_accounts_file_lists_nothing_extra(self):
        m.Paths(self.home).accounts_file.write_text("{not json", encoding="utf-8")
        ids = [s.id for s in self.discover()]
        self.assertEqual(ids, ["claude-main", "claude-2", "claude-10", "codex-main", "codex-2", "agy-main"])


class RunTests(Base):
    def setUp(self):
        super().setUp()
        self.notes = []
        self.write_claude_folder(".claude")
        self.write_claude_folder(".claude-2")
        (self.home / ".claude-2" / ".claude.json").write_text("{}", encoding="utf-8")
        self.write_codex_auth()
        self.keychain = FakeKeychain({m.AGY_KEYCHAIN_SERVICE: agy_pw()})
        self.use_claude(claude_stream_lines(), claude_stream_lines(SECOND_RATE))
        patches = [
            mock.patch.object(m, "SystemKeychain", lambda: self.keychain),
            mock.patch.object(m, "http_request", FakeHTTP({})),  # default mode calls no endpoint
            mock.patch.object(m, "osascript_notify", lambda title, text: self.notes.append(text) or True),
            mock.patch.dict(os.environ, {"HOME": str(self.home)}),
        ]
        for patch in patches:
            patch.start()
            self.addCleanup(patch.stop)
        self.paths = m.Paths(self.home)

    def use_claude(self, main_stream, second_stream, second_text=None):
        """Scripts the three CLIs. The second Claude folder answers with its own plan, chosen by CLAUDE_CONFIG_DIR."""
        second_folder = str(self.home / ".claude-2")
        self.clis = self.use_clis({
            "claude": claude_program(
                (main_stream, claude_text_lines()),
                folders={second_folder: (second_stream, second_text or claude_text_lines())}),
            "codex": single_program(codex_rpc_lines()),
            "agy": single_program(agy_usage_lines()),
        })

    def run_main(self, *argv, moment=None):
        out = io.StringIO()
        patch = mock.patch.object(m, "datetime", frozen_at(moment or NOW))
        with patch, contextlib.redirect_stdout(out):
            code = m.main(list(argv))
        return code, out.getvalue()

    def usage(self):
        return json.loads(self.paths.usage_mac.read_text(encoding="utf-8"))

    def known(self):
        return json.loads(self.paths.known_file.read_text(encoding="utf-8"))

    def test_the_file_lists_accounts_in_the_chosen_order_with_their_labels(self):
        self.paths.settings_file.parent.mkdir(parents=True, exist_ok=True)
        self.paths.settings_file.write_text(json.dumps({"sort": "lowest"}), encoding="utf-8")
        code, _ = self.run_main("--no-notify")
        self.assertEqual(code, 0)
        accounts = self.usage()["accounts"]
        # agy-main has 0 left (its Claude and GPT group is used up), codex-main 7, claude-2 15, claude-main 33
        self.assertEqual([a["id"] for a in accounts], ["agy-main", "codex-main", "claude-2", "claude-main"])
        self.assertEqual([a["label"] for a in accounts], ["agy", "ChatGPT", "Claude 2", "Claude 1"])

    def test_the_known_accounts_file_lists_every_found_account_with_its_source_and_first_seen(self):
        self.run_main("--no-notify")
        known = self.known()
        self.assertEqual([a["id"] for a in known["accounts"]],
                         ["claude-main", "claude-2", "codex-main", "agy-main"])
        self.assertEqual([a["source"] for a in known["accounts"]],
                         ["Claude Code (main)", "Claude Code (~/.claude-2)", "Codex (~/.codex)", "agy (Keychain)"])
        self.assertEqual({a["first_seen"] for a in known["accounts"]}, {"2026-11-19T04:30:00Z"})

    def test_a_logged_out_folder_is_left_out_and_does_not_make_the_other_account_numbered(self):
        self.use_claude(claude_stream_lines(), claude_stream_error_lines())
        code, _ = self.run_main("--no-notify")
        self.assertEqual(code, 0)
        self.assertEqual([(a["id"], a["label"]) for a in self.usage()["accounts"]],
                         [("claude-main", "Claude"), ("codex-main", "ChatGPT"), ("agy-main", "agy")])
        self.assertNotIn("claude-2", [a["id"] for a in self.known()["accounts"]])

    def test_first_seen_is_kept_while_an_account_stays_and_restarts_after_it_was_gone(self):
        self.run_main("--no-notify")
        shutil.rmtree(self.home / ".claude-2")
        self.run_main("--no-notify", moment=NOW + timedelta(days=1))
        self.assertNotIn("claude-2", [a["id"] for a in self.known()["accounts"]])
        self.write_claude_folder(".claude-2")
        (self.home / ".claude-2" / ".claude.json").write_text("{}", encoding="utf-8")
        self.run_main("--no-notify", moment=NOW + timedelta(days=2))
        seen = {a["id"]: a["first_seen"] for a in self.known()["accounts"]}
        self.assertEqual(seen["claude-main"], "2026-11-19T04:30:00Z")
        self.assertEqual(seen["claude-2"], "2026-11-21T04:30:00Z")

    def test_a_hidden_account_is_collected_but_not_written_and_does_not_alert(self):
        self.paths.settings_file.parent.mkdir(parents=True, exist_ok=True)
        self.paths.settings_file.write_text(json.dumps({"accounts": {"claude-2": {"enabled": False}}}),
                                            encoding="utf-8")
        self.run_main()
        self.assertNotIn("claude-2", [a["id"] for a in self.usage()["accounts"]])
        second = [launch for launch in self.clis.launched("claude")
                  if launch["env"].get("CLAUDE_CONFIG_DIR") == str(self.home / ".claude-2")]
        self.assertTrue(second)  # its login stays fresh: the CLI is still run for it
        self.assertFalse(any("Claude 2" in note for note in self.notes), self.notes)

    def test_token_logs_are_read_for_each_account_on_its_own(self):
        logs = self.home / ".claude-2" / "projects" / "p"
        logs.mkdir(parents=True)
        (logs / "s.jsonl").write_text(
            claude_line("msg-1", "req-1", "claude-haiku-4-5", "2026-11-19T03:00:00Z", 1000, 500),
            encoding="utf-8")
        self.run_main("--no-notify")
        accounts = {a["id"]: a for a in self.usage()["accounts"]}
        self.assertEqual(accounts["claude-2"]["usage"]["today"]["tokens"], 1500)
        self.assertIsNone(accounts["claude-main"]["usage"])

    def test_the_token_cache_of_a_gone_account_is_dropped(self):
        logs = self.home / ".claude-2" / "projects" / "p"
        logs.mkdir(parents=True)
        (logs / "s.jsonl").write_text(
            claude_line("msg-1", "req-1", "claude-haiku-4-5", "2026-11-19T03:00:00Z", 10, 10), encoding="utf-8")
        self.run_main("--no-notify")
        cache = json.loads((self.paths.state_dir / "cache.json").read_text(encoding="utf-8"))
        self.assertIn("claude-2", cache["claude"])
        shutil.rmtree(self.home / ".claude-2")
        self.run_main("--no-notify")
        cache = json.loads((self.paths.state_dir / "cache.json").read_text(encoding="utf-8"))
        self.assertNotIn("claude-2", cache["claude"])

    def test_a_dry_run_writes_no_files_and_leaks_no_secrets(self):
        code, out = self.run_main("--dry-run")
        self.assertEqual(code, 0)
        self.assertFalse(self.paths.usage_mac.exists())
        self.assertFalse(self.paths.known_file.exists())
        self.assertIn("claude-2", out)
        for secret in SENTINELS:
            self.assertNotIn(secret, out)


if __name__ == "__main__":
    unittest.main()
