#!/usr/bin/env python3
"""Collects usage limits and local token totals for Claude, Codex (ChatGPT) and agy.

Default mode: each provider's own CLI reports its usage (Claude: `claude`, Codex: `codex app-server`,
agy: `agy -p "/usage"`). In this mode the collector never reads, refreshes or stores a provider token.
Opt-in direct mode (settings.json "direct_mode": {"codex": true, "agy": true}) reads the Codex or agy
login itself. Claude has no direct mode.

Reads the logins already on this Mac (one or more accounts per provider) and writes usage.json (format:
docs/usage-json.md) to the Mac app folder and, when present, to the iCloud copy that the Scriptable widget reads.

Standard library only. Run as: python3 -I ai_usage_collect.py [--dry-run] [--no-refresh] [--no-notify]
Secrets never leave this process: they are not printed or logged, and every message that reaches the log
or the output is scrubbed first. A CLI's stderr is never read, and its stdout is never logged.
"""
from __future__ import annotations

import argparse
import base64
import contextlib
import fcntl
import hashlib
import json
import math
import os
import plistlib
import queue
import re
import shutil
import signal
import subprocess
import sys
import threading
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

SCHEMA = 1
CACHE_VERSION = 3  # 2: the token-log cache is kept per account. 3: Codex keeps one record per turn
DAY_ZONE = None  # zone for the day and month totals; None = this Mac's own zone, looked up per moment (DST-aware)
HTTP_TIMEOUT = 20
NOTIFY_THRESHOLDS = (80, 95)
NOTIFY_KEEP_DAYS = 14
EXPIRY_MARGIN_S = 60  # direct mode: renew an agy token this long before it expires
SCRIPTABLE_FILE = "ai-usage.json"
# Token counts leave out cache reads (input + output + cache writes); the cost still includes them.
# Set True to count cache reads as tokens too.
TOKENS_INCLUDE_CACHE_READS = False
# security exits with 44 when the item does not exist. Any other failure means it could not be read.
KEYCHAIN_NOT_FOUND_RC = 44

# Default mode: one CLI run is killed after CLI_TIMEOUT_S seconds, and its stdout is capped.
CLI_TIMEOUT_S = 30
CLI_STOP_GRACE_S = 5
# Once the program has ended, its output is read for this long after the last line. A child that the program
# left running can keep the pipe open; the run then ends here instead of waiting for the whole timeout.
CLI_QUIET_AFTER_EXIT_S = 0.5
CLI_OUTPUT_LIMIT = 8 * 1024 * 1024
# Searched after PATH. launchd gives a job only /usr/bin:/bin:/usr/sbin:/sbin.
CLI_STANDARD_DIRS = ("/opt/homebrew/bin", "/usr/local/bin", "~/.local/bin",
                     "/usr/bin", "/bin", "/usr/sbin", "/sbin")
# The only variables a CLI run gets. Nothing else is passed on: no ANTHROPIC_*, CLAUDE_*, CODEX_* or tokens.
CLI_ENV_KEYS = ("HOME", "USER", "LOGNAME", "SHELL", "TMPDIR", "LANG", "LC_ALL", "LC_CTYPE",
                "__CF_USER_TEXT_ENCODING")
CLAUDE_STREAM_ARGS = ("-p", "--input-format", "stream-json", "--output-format", "stream-json",
                      "--verbose", "--no-session-persistence")
CLAUDE_USAGE_ARGS = ("-p", "/usage", "--output-format", "json", "--no-session-persistence")
CODEX_APP_ARGS = ("app-server", "--listen", "stdio://")
AGY_USAGE_ARGS = ("-p", "/usage", "--output-format", "json")

# Direct mode only: the Codex endpoint, and the agy login and endpoints.
DIRECT_PROVIDERS = ("codex", "agy")
CODEX_USAGE_URL = "https://chatgpt.com/backend-api/wham/usage"
AGY_KEYCHAIN_SERVICE = "gemini"
AGY_KEYCHAIN_ACCOUNT = "antigravity"
AGY_LOAD_URL = "https://daily-cloudcode-pa.googleapis.com/v1internal:loadCodeAssist"
AGY_MODELS_URL = "https://daily-cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels"
AGY_CANDIDATES = ("/opt/homebrew/bin/agy", "/usr/local/bin/agy", "~/.local/bin/agy")
# agy answers only the Antigravity client, so its requests send this User-Agent.
AGY_USER_AGENT = "antigravity"

MSG_CLAUDE_TIMEOUT = "Claude ตอบช้าเกินเวลา ลองใหม่รอบถัดไป"
MSG_CLAUDE_FORMAT = "ข้อมูลจาก Claude ผิดรูปแบบ อาจเป็นเพราะ Claude Code เปลี่ยนรุ่น"
MSG_CLAUDE_REJECTED = "Claude ไม่ยอมส่งข้อมูลโควตา ลองใหม่รอบถัดไป"
MSG_CLAUDE_NO_QUOTA = "ไม่พบข้อมูลโควตา Claude"
MSG_CLAUDE_RATE_LIMITED = "Claude จำกัดการอ่านโควตาชั่วคราว ลองใหม่รอบถัดไป"
MSG_CODEX_EXPIRED = "ล็อกอิน Codex หมดอายุ เปิด codex สักครั้ง"
MSG_CODEX_RETRY = "เชื่อมต่อ ChatGPT ไม่ได้ ลองใหม่รอบถัดไป"
MSG_CODEX_TIMEOUT = "Codex ตอบช้าเกินเวลา ลองใหม่รอบถัดไป"
MSG_CODEX_FORMAT = "ข้อมูลจาก Codex ผิดรูปแบบ อาจเป็นเพราะ Codex เปลี่ยนรุ่น"
MSG_CODEX_REJECTED = "Codex ไม่ยอมส่งข้อมูลโควตา ลองใหม่รอบถัดไป"
MSG_CODEX_NO_QUOTA = "ไม่พบข้อมูลโควตา ChatGPT"
MSG_AGY_RETRY = "เชื่อมต่อ agy ไม่ได้ ลองใหม่รอบถัดไป"
MSG_AGY_TIMEOUT = "agy ตอบช้าเกินเวลา ลองใหม่รอบถัดไป"
MSG_AGY_FORMAT = "ข้อมูลจาก agy ผิดรูปแบบ อาจเป็นเพราะ agy เปลี่ยนรุ่น"
MSG_AGY_NO_QUOTA = "ไม่พบข้อมูลโควตา agy"
MSG_AGY_NO_PROJECT = "ยังไม่มีโปรเจกต์ agy ให้เปิด agy ตั้งค่าบัญชีก่อน"
MSG_AGY_MISSING = "ยังไม่พบการล็อกอิน agy"
MSG_AGY_EXPIRED = "ล็อกอิน agy หมดอายุ"
MSG_CLI_MISSING = "ไม่พบคำสั่ง {name} บน Mac นี้"
MSG_CLI_FAILED = "เรียกคำสั่ง {name} ไม่สำเร็จ"
MSG_KEYCHAIN_READ = "อ่าน Keychain ไม่ได้ ลองใหม่รอบถัดไป"
MSG_GENERIC = "เก็บข้อมูลไม่สำเร็จ ลองใหม่รอบถัดไป"


# error_code values written to usage.json. They are language-neutral: readers translate each one and fall
# back to the Thai `error` text when they meet a code they do not know.
ERROR_LOGIN_EXPIRED = "login_expired"  # the login ran out; the provider's own app or CLI renews it when opened
ERROR_RELOGIN_NEEDED = "relogin_needed"  # the login is gone or revoked; the user must sign in again
ERROR_NOT_SET_UP = "not_set_up"  # agy has a login but no project yet
ERROR_NETWORK = "network"  # the provider could not be reached (or its CLI did not answer in time)
ERROR_RATE_LIMITED = "rate_limited"  # HTTP 429
ERROR_SERVER = "server_error"  # HTTP 5xx
ERROR_QUOTA_UNAVAILABLE = "quota_unavailable"  # the CLI replied without usage limits
ERROR_UNKNOWN = "unknown"  # anything else


class FetchError(Exception):
    """A failure whose message is a short Thai string, safe to show and to log. `code` is the error_code that
    usage.json carries next to the message. `detail` is a fixed technical note for the log only (a stage name
    or a missing key, never a value)."""

    def __init__(self, message: str, code: str = ERROR_UNKNOWN, detail: str = ""):
        super().__init__(message)
        self.code = code
        self.detail = detail


class NotLoggedIn(Exception):
    """The provider has no login on this Mac at all. Its account is left out of usage.json. The message is a
    fixed note naming the stage that decided it; it is logged, never shown."""


def http_error_code(status: int) -> str:
    """The error_code for an HTTP status that a provider call did not accept."""
    if status == 429:
        return ERROR_RATE_LIMITED
    if status >= 500:
        return ERROR_SERVER
    return ERROR_UNKNOWN


# ---------------------------------------------------------------- scrubbing and logging

_SECRETS: set[str] = set()
_SECRET_PATTERNS = (
    re.compile(r"eyJ[A-Za-z0-9_\-.]{8,}"),
    re.compile(r"sk-[A-Za-z0-9_\-]{8,}"),
    re.compile(r"ya29\.[A-Za-z0-9_\-.]+"),
    re.compile(r"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"),
)


def remember_secret(value):
    """Register a token or account id so that scrub() masks it wherever it shows up."""
    if isinstance(value, str) and len(value) >= 8:
        _SECRETS.add(value)
    return value


def scrub(text) -> str:
    out = str(text)
    for secret in sorted(_SECRETS, key=len, reverse=True):
        out = out.replace(secret, "[redacted]")
    for pattern in _SECRET_PATTERNS:
        out = pattern.sub("[redacted]", out)
    return out


def log(message) -> None:
    stamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    sys.stderr.write(f"{stamp} {scrub(message)}\n")
    sys.stderr.flush()


def clean_label(value, fallback: str, limit: int = 40) -> str:
    """A name that a CLI reported, safe to show: no control characters, no e-mail address, at most `limit`
    characters. Anything that is not text gives the fallback."""
    if not isinstance(value, str):
        return fallback
    text = re.sub(r"[\x00-\x1f\x7f]+", " ", scrub(value))
    text = re.sub(r"\s+", " ", text).strip()
    return text[:limit] if text else fallback


# ---------------------------------------------------------------- time and number helpers

def iso_z(moment: datetime) -> str:
    return moment.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_time(value):
    """ISO-8601 text (Z, offset, or naive meaning local time) or unix s/ms -> aware UTC datetime."""
    if value is None or isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        if not math.isfinite(value):
            return None
        seconds = value / 1000.0 if abs(value) > 1e11 else float(value)
        try:
            return datetime.fromtimestamp(seconds, timezone.utc)
        except (OverflowError, OSError, ValueError):
            return None
    if isinstance(value, str) and value.strip():
        text = value.strip()
        if text[-1] in "zZ":
            text = text[:-1] + "+00:00"
        try:
            moment = datetime.fromisoformat(text)
        except ValueError:
            return None
        if moment.tzinfo is None:
            moment = moment.astimezone()
        return moment.astimezone(timezone.utc)
    return None


def iso_or_none(value):
    moment = parse_time(value)
    return iso_z(moment) if moment else None


def local_day(value):
    moment = parse_time(value)
    return moment.astimezone(DAY_ZONE).date().isoformat() if moment else None


def local_today(now: datetime) -> str:
    return now.astimezone(DAY_ZONE).date().isoformat()


def window_start_day(now: datetime) -> str:
    """First day of the previous month (local day). Older log lines cannot affect today or this month."""
    first_this = now.astimezone(DAY_ZONE).date().replace(day=1)
    return (first_this - timedelta(days=1)).replace(day=1).isoformat()


def day_start_epoch(day: str) -> float:
    """Epoch seconds of local midnight at the start of `day` (YYYY-MM-DD)."""
    start = datetime.fromisoformat(day)
    return (start.replace(tzinfo=DAY_ZONE) if DAY_ZONE is not None else start.astimezone()).timestamp()


def to_num(value):
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return float(value) if math.isfinite(value) else None
    if isinstance(value, str):
        try:
            number = float(value.strip())
        except ValueError:
            return None
        return number if math.isfinite(number) else None
    return None


def to_int(value):
    number = to_num(value)
    return int(number) if number is not None else None


def clamp_pct(value) -> float:
    return max(0.0, min(100.0, float(value)))


def round_or_none(value, digits: int = 2):
    return None if value is None else round(value, digits)


def dig(value, *keys):
    """value[k1][k2]... or None when a level is missing or is not an object."""
    for key in keys:
        if not isinstance(value, dict):
            return None
        value = value.get(key)
    return value


# ---------------------------------------------------------------- files, processes, HTTP

def read_json_file(path):
    try:
        with open(path, "rb") as handle:
            return json.loads(handle.read())
    except (OSError, ValueError):
        return None


def read_json_bytes(payload):
    if not payload:
        return None
    try:
        return json.loads(payload)
    except (ValueError, TypeError):
        return None


def atomic_write(path: Path, data: bytes) -> None:
    """Write path.tmp, fsync, then rename over path so readers never see a half file."""
    tmp = path.with_name(path.name + ".tmp")
    with open(tmp, "wb") as handle:
        handle.write(data)
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(tmp, path)


def run_cmd(args, timeout: float = 30, stdin_text=None):
    """Returns (returncode, stdout). Never raises and never returns stderr: exception text and
    stderr can echo argv, and argv can hold a credential, so only the exception class is logged."""
    try:
        result = subprocess.run(args, capture_output=True, text=True, timeout=timeout,
                                input=stdin_text)
        return result.returncode, result.stdout
    except Exception as error:  # noqa: BLE001 - see docstring
        log(f"คำสั่งระบบล้มเหลว: {type(error).__name__}")
        return -1, ""


def http_request(method, url, headers, body=None, timeout=HTTP_TIMEOUT):
    """Returns (status, body_bytes). status is None when the request never got an HTTP answer."""
    request = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        try:
            payload = error.read()
        except Exception:  # noqa: BLE001 - the body is only parsed for an error code
            payload = b""
        return error.code, payload
    except Exception as error:  # noqa: BLE001 - DNS, TLS, timeout, reset
        log(f"เชื่อมต่อ {urllib.parse.urlsplit(url).hostname} ไม่ได้: {type(error).__name__}")
        return None, b""


def osascript_notify(title: str, text: str) -> bool:
    rc, _ = run_cmd(["osascript", "-e", "on run argv",
                     "-e", "display notification (item 1 of argv) with title (item 2 of argv)",
                     "-e", "end run", text, title])
    return rc == 0


class SystemKeychain:
    """Reads the agy item through /usr/bin/security (direct mode only), and checks that the agy item exists.
    Nothing is written to the Keychain, and no Claude item is ever touched."""

    def read(self, service: str, account=None):
        """The password, or None when the item does not exist. Any other failure raises FetchError, so
        a login that is there but cannot be read is never reported as missing."""
        args = ["security", "find-generic-password", "-s", service]
        if account:
            args += ["-a", account]
        rc, out = run_cmd(args + ["-w"])
        if rc == KEYCHAIN_NOT_FOUND_RC:
            return None
        if rc != 0:
            log(f"security อ่าน Keychain ไม่สำเร็จ (rc {rc})")
            raise FetchError(MSG_KEYCHAIN_READ)
        return out[:-1] if out.endswith("\n") else out

    def exists(self, service: str, account=None) -> bool:
        """Whether the item is there. Only the attributes are asked for, never the password. Only 'not found'
        means missing; any other failure counts as present, so the login is still read and its error shown."""
        args = ["security", "find-generic-password", "-s", service]
        if account:
            args += ["-a", account]
        rc, _ = run_cmd(args)
        return rc != KEYCHAIN_NOT_FOUND_RC


class Paths:
    def __init__(self, home, state_dir=None):
        self.home = Path(home)
        self.app_dir = self.home / "Library" / "Application Support" / "AIUsage"
        self.state_dir = Path(state_dir) if state_dir else self.app_dir
        self.usage_mac = self.app_dir / "usage.json"
        self.settings_file = self.app_dir / "settings.json"  # written by the Mac app
        self.accounts_file = self.app_dir / "accounts.json"  # optional, written by hand: extra config folders
        self.known_file = self.app_dir / "known-accounts.json"  # written by the collector
        self.usage_icloud = (self.home / "Library" / "Mobile Documents"
                             / "iCloud~dk~simonbs~Scriptable" / "Documents" / SCRIPTABLE_FILE)
        self.cache_file = self.state_dir / "cache.json"
        self.notify_file = self.state_dir / "notify-state.json"
        self.run_lock = self.state_dir / "collector.lock"
        self.codex_auth = self.home / ".codex" / "auth.json"
        self.codex_sessions = self.home / ".codex" / "sessions"
        self.claude_projects = self.home / ".claude" / "projects"


class Env:
    """Everything that touches the outside world goes through here, so tests can replace it."""

    def __init__(self, paths, now, allow_refresh=True, keychain=None, http=None, run=None,
                 notify=None, cache=None, direct=None):
        self.paths = paths
        self.now = now
        self.allow_refresh = allow_refresh
        self.keychain = keychain or SystemKeychain()
        self.http = http or http_request
        self.run = run or run_cmd
        self.notify = notify or osascript_notify
        self.cache = cache if cache is not None else {}
        self.direct = dict(direct or {})  # provider -> True for each provider in direct mode

    def cli_cwd(self) -> str:
        """Working folder for a CLI run: the app folder, which is the job's own folder under launchd. Claude
        keeps per-folder state, so the folder stays the same from run to run."""
        return str(self.paths.app_dir if self.paths.app_dir.is_dir() else self.paths.home)


def direct_enabled(env: Env, provider: str) -> bool:
    return env.direct.get(provider) is True


def list_files(root: Path, pattern: str):
    try:
        return sorted(root.rglob(pattern))
    except OSError:
        return []


# ---------------------------------------------------------------- CLI runs (default mode)

@dataclass
class CliRun:
    """What one CLI run produced. stdout lines are kept only for the caller to parse; stderr is never read.

    lines: stdout lines (bytes), in order. found: the JSON message that answered the request (protocol runs).
    returncode: the exit code, negative when the run was killed. timed_out / too_large: the run was stopped by
    the collector. spawn_error: "missing" when the program does not exist, "failed" for any other start error."""
    lines: list = field(default_factory=list)
    found: object = None
    returncode: object = None
    timed_out: bool = False
    too_large: bool = False
    spawn_error: str = ""


def cli_search_dirs() -> list:
    dirs = [item for item in os.environ.get("PATH", "").split(os.pathsep) if item]
    dirs += [os.path.expanduser(item) for item in CLI_STANDARD_DIRS]
    return list(dict.fromkeys(dirs))


def find_cli(name: str):
    """The path of a provider CLI, searched in PATH and then in the standard install folders. None when absent."""
    return shutil.which(name, path=os.pathsep.join(cli_search_dirs()))


def require_cli(name: str) -> str:
    binary = find_cli(name)
    if binary is None:
        raise FetchError(MSG_CLI_MISSING.format(name=name), ERROR_UNKNOWN, detail=f"{name}: not on PATH")
    return binary


def cli_environment(extra: dict) -> dict:
    """The child's environment: the whitelisted variables, the search PATH and the one account setting (extra)."""
    env = {key: os.environ[key] for key in CLI_ENV_KEYS if key in os.environ}
    env["PATH"] = os.pathsep.join(cli_search_dirs())
    env.update(extra)
    return env


def json_line(message) -> bytes:
    return (json.dumps(message, separators=(",", ":"), ensure_ascii=False) + "\n").encode("utf-8")


def parse_message(raw: bytes):
    try:
        message = json.loads(raw)
    except ValueError:
        return None
    return message if isinstance(message, dict) else None


def pump_output(stream, sink) -> None:
    """Reads a CLI's stdout line by line into a queue, then puts None when the stream ends."""
    try:
        for raw in iter(stream.readline, b""):
            sink.put(raw)
    except (OSError, ValueError):
        pass
    finally:
        sink.put(None)


def kill_cli(proc) -> None:
    """Kills the CLI and every process it started. It runs in its own session, so its process group id is its pid."""
    if isinstance(proc.pid, int):
        with contextlib.suppress(OSError):
            os.killpg(proc.pid, signal.SIGKILL)
    with contextlib.suppress(OSError):
        proc.kill()


def write_lines(proc, lines) -> None:
    """Writes protocol lines to a server's stdin. A server that has already quit gets no more lines; its output
    then ends and the run has no answer."""
    if proc.stdin is None:
        return
    try:
        for line in lines:
            proc.stdin.write(line)
        proc.stdin.flush()
    except OSError:
        pass


def run_cli(argv, cwd, env, feed=None, until=None, timeout=None, follow=None) -> CliRun:
    """Runs one provider CLI and reads its stdout.

    feed=None: stdin is /dev/null and stdout is read to the end (one-shot commands).
    feed=[lines]: a protocol server. The lines go to stdin at once. follow(message), when given, returns more
    lines to send each time a stdout JSON message arrives (a request that must wait for an earlier reply).
    stdin stays open until until(message) is true for one stdout JSON message. Then stdin is closed and the run
    ends. Each run is stopped after `timeout` seconds (CLI_TIMEOUT_S when not given), and its whole process group
    is killed."""
    run = CliRun()
    protocol = feed is not None
    if timeout is None:
        timeout = CLI_TIMEOUT_S
    try:
        proc = subprocess.Popen(
            argv, stdin=subprocess.PIPE if protocol else subprocess.DEVNULL, stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL, cwd=cwd, env=env, start_new_session=True)
    except FileNotFoundError:
        run.spawn_error = "missing"
        return run
    except OSError:
        run.spawn_error = "failed"
        return run
    chunks: queue.Queue = queue.Queue()
    reader = threading.Thread(target=pump_output, args=(proc.stdout, chunks), daemon=True)
    reader.start()
    if protocol:
        write_lines(proc, feed)
    deadline = time.monotonic() + timeout
    total = 0
    quiet_since = None  # when the program was seen to have ended, and no line came after that
    while True:
        if time.monotonic() >= deadline:
            run.timed_out = True
            break
        try:
            raw = chunks.get(timeout=0.1)
        except queue.Empty:
            if proc.poll() is not None:
                quiet_since = time.monotonic() if quiet_since is None else quiet_since
                if time.monotonic() - quiet_since >= CLI_QUIET_AFTER_EXIT_S:
                    break
            continue
        quiet_since = None
        if raw is None:
            break
        total += len(raw)
        if total > CLI_OUTPUT_LIMIT:
            run.too_large = True
            break
        run.lines.append(raw)
        message = parse_message(raw) if (until is not None or follow is not None) else None
        if message is not None and protocol and follow is not None:
            write_lines(proc, follow(message) or [])
        if message is not None and until is not None and until(message):
            run.found = message
            break
    if protocol and proc.stdin is not None:
        with contextlib.suppress(OSError):
            proc.stdin.close()
    if run.timed_out or run.too_large:
        kill_cli(proc)
    else:
        try:
            proc.wait(timeout=CLI_STOP_GRACE_S)
        except subprocess.TimeoutExpired:
            kill_cli(proc)
    kill_cli(proc)  # every run: whatever is left of its process group, such as a child that was not ended
    with contextlib.suppress(OSError, subprocess.TimeoutExpired):
        proc.wait(timeout=CLI_STOP_GRACE_S)
    reader.join(timeout=CLI_STOP_GRACE_S)  # the reader ends at the end of the output, once the process is gone
    if not reader.is_alive():
        with contextlib.suppress(OSError):
            proc.stdout.close()
    run.returncode = proc.returncode
    return run


def raise_for_run(run: CliRun, name: str, timeout_message: str, format_message: str) -> None:
    """Turns a run the collector stopped or could not start into the matching FetchError. Returns when the run
    finished on its own, so the caller can read its output."""
    if run.spawn_error == "missing":
        raise FetchError(MSG_CLI_MISSING.format(name=name), ERROR_UNKNOWN, detail=f"{name}: not on PATH")
    if run.spawn_error:
        raise FetchError(MSG_CLI_FAILED.format(name=name), ERROR_UNKNOWN, detail=f"{name}: could not start")
    if run.timed_out:
        raise FetchError(timeout_message, ERROR_NETWORK, detail=f"{name}: no answer in {CLI_TIMEOUT_S} s")
    if run.too_large:
        raise FetchError(format_message, ERROR_UNKNOWN, detail=f"{name}: output too large")


def cli_output_document(run: CliRun, name: str, format_message: str):
    """The whole stdout of a one-shot run as one JSON object, or FetchError when it is not one."""
    doc = read_json_bytes(b"".join(run.lines))
    if not isinstance(doc, dict):
        raise FetchError(format_message, ERROR_UNKNOWN, detail=f"{name}: output is not a JSON object")
    return doc


# ---------------------------------------------------------------- Claude

CLAUDE_LABELS = {
    "five_hour": "5 ชม.",
    "seven_day": "สัปดาห์",
    "seven_day_opus": "Opus สัปดาห์",
    "seven_day_sonnet": "Sonnet สัปดาห์",
}
CLAUDE_PLANS = {"max": "Max", "pro": "Pro", "team": "Team", "enterprise": "Enterprise"}
LOGGED_OUT = re.compile(r"not logged in", re.IGNORECASE)


def window_seconds_for(provider: str, key: str):
    """window_seconds for a limit whose length its key fixes: Claude's five_hour is 5 hours and every
    seven_day* window is 7 days. None otherwise (Codex reports its length; agy groups have none)."""
    if provider == "claude":
        if key == "five_hour":
            return 18000
        if key.startswith("seven_day"):
            return 604800
    return None


def claude_plan(subscription, tier=None):
    """Plan label from get_usage's subscription_type. The tier multiplier ("Max 5x") is shown only when a tier
    string is given, and the CLI's usage reply does not carry one."""
    if not isinstance(subscription, str) or not subscription.strip():
        return None
    base = CLAUDE_PLANS.get(subscription.strip().lower(), subscription.strip().title())
    match = re.search(r"_(\d+)x$", str(tier or ""))
    return f"{base} {match.group(1)}x" if match else base


def parse_claude_usage(doc):
    """Returns (limits, credits) from a rate_limits object. Unknown fields are ignored; seven_day_* windows are kept."""
    if not isinstance(doc, dict):
        raise FetchError(MSG_CLAUDE_FORMAT, ERROR_UNKNOWN, detail="rate_limits is not an object")
    keys = [key for key in ("five_hour", "seven_day") if key in doc]
    keys += sorted(key for key in doc if key.startswith("seven_day_") and key not in keys)
    limits = []
    for key in keys:
        window = doc.get(key)
        if not isinstance(window, dict):
            continue
        utilization = to_num(window.get("utilization"))
        if utilization is None:
            continue
        label = CLAUDE_LABELS.get(key) or f"{key[len('seven_day_'):].replace('_', ' ')} สัปดาห์"
        limits.append({"key": key, "label": label, "used_percent": clamp_pct(utilization),
                       "resets_at": iso_or_none(window.get("resets_at")),
                       "window_seconds": window_seconds_for("claude", key)})
    if not limits:
        raise FetchError(MSG_CLAUDE_NO_QUOTA, ERROR_QUOTA_UNAVAILABLE, detail="rate_limits has no usable window")
    credits = None
    extra = doc.get("extra_usage")
    if isinstance(extra, dict):
        enabled = bool(extra.get("is_enabled"))
        currency = str(extra.get("currency") or "USD").upper()
        if currency == "USD":
            # The API reports extra-usage amounts in minor units (cents for USD).
            used = to_num(extra.get("used_credits"))
            limit = to_num(extra.get("monthly_limit"))
            credits = {"extra_usage_enabled": enabled,
                       "used_usd": round_or_none(used / 100.0 if used is not None else None),
                       "limit_usd": round_or_none(limit / 100.0 if limit is not None else None),
                       "balance_usd": None}
        else:
            credits = {"extra_usage_enabled": enabled, "used_usd": None,
                       "limit_usd": None, "balance_usd": None}
    return limits, credits


def claude_with_models(rate: dict) -> dict:
    """rate_limits with the Opus and Sonnet weekly windows filled in from model_scoped, where the top-level
    key is empty. Other models are left out: the readers have no name to show for them."""
    doc = dict(rate)
    items = rate.get("model_scoped")
    for item in (items if isinstance(items, list) else []):
        if not isinstance(item, dict):
            continue
        name = str(item.get("display_name") or "").lower()
        key = "seven_day_opus" if "opus" in name else "seven_day_sonnet" if "sonnet" in name else None
        if key and not isinstance(doc.get(key), dict) and to_num(item.get("utilization")) is not None:
            doc[key] = {"utilization": item.get("utilization"), "resets_at": item.get("resets_at")}
    return doc


MONTHS = {name: number for number, name in enumerate(
    ("jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"), 1)}
RESET_DATE = re.compile(
    r"resets?\s+(?P<mon>[A-Za-z]{3})[a-z]*\.?\s+(?P<day>\d{1,2})(?:,?\s+(?P<year>\d{4}))?\s+at\s+"
    r"(?P<clock>\d{1,2}(?::\d{2})?\s*[ap]m|\d{1,2}:\d{2})(?:\s*\((?P<zone>[^)]+)\))?", re.IGNORECASE)
RESET_TIME = re.compile(
    r"resets?\s+(?P<clock>\d{1,2}(?::\d{2})?\s*[ap]m|\d{1,2}:\d{2})(?:\s*\((?P<zone>[^)]+)\))?",
    re.IGNORECASE)
USAGE_LINE = re.compile(
    r"^[ \t]*Current[ \t]+(?P<name>session|week)(?:[ \t]*\((?P<model>[^)\r\n]*)\))?"
    r"[ \t]*:?[ \t]*(?:\r?\n[ \t]*)?(?P<pct>\d+(?:\.\d+)?)[ \t]*%[ \t]*used"
    r"(?P<rest>[^\r\n]*(?:\r?\n[ \t]*resets?\b[^\r\n]*)?)", re.IGNORECASE | re.MULTILINE)
CLAUDE_USAGE_RATE_LIMITED = re.compile(r"\brate_limit_error\b|\brate limited\. please try again later\b", re.IGNORECASE)


def parse_clock(text: str):
    """(hour, minute) from '2pm', '2:30 pm' or '14:05', or None."""
    match = re.fullmatch(r"(\d{1,2})(?::(\d{2}))?\s*([ap]m)?", text.strip(), re.IGNORECASE)
    if not match:
        return None
    hour, minute = int(match.group(1)), int(match.group(2) or 0)
    suffix = (match.group(3) or "").lower()
    if suffix:
        if not 1 <= hour <= 12:
            return None
        hour = hour % 12 + (12 if suffix == "pm" else 0)
    elif hour > 23:
        return None
    if minute > 59:
        return None
    return hour, minute


def usage_zone(name, now: datetime):
    """The zone named in a /usage line (Europe/Berlin), or this Mac's own zone when the name is missing or unknown."""
    if name:
        try:
            return ZoneInfo(name.strip())
        except Exception:  # noqa: BLE001 - unknown zone name or no zone data
            pass
    return now.astimezone().tzinfo


def parse_usage_reset(text: str, now: datetime):
    """resets_at (ISO UTC) from the text after a /usage line, such as 'resets Nov 20 at 2pm (Europe/Berlin)'.
    None when no time can be read; the limit's percentage is still kept."""
    date = RESET_DATE.search(text)
    if date:
        month = MONTHS.get(date.group("mon").lower())
        clock = parse_clock(date.group("clock"))
        if month is None or clock is None:
            return None
        zone = usage_zone(date.group("zone"), now)
        local_now = now.astimezone(zone)
        try:
            if date.group("year"):
                moment = datetime(int(date.group("year")), month, int(date.group("day")),
                                  clock[0], clock[1], tzinfo=zone)
            else:
                moment = datetime(local_now.year, month, int(date.group("day")),
                                  clock[0], clock[1], tzinfo=zone)
                # The year is not printed: take the one that puts the reset nearest to now.
                if moment < local_now - timedelta(days=183):
                    moment = moment.replace(year=moment.year + 1)
                elif moment > local_now + timedelta(days=183):
                    moment = moment.replace(year=moment.year - 1)
        except ValueError:
            return None
        return iso_z(moment)
    clock_only = RESET_TIME.search(text)
    if clock_only:
        clock = parse_clock(clock_only.group("clock"))
        if clock is None:
            return None
        zone = usage_zone(clock_only.group("zone"), now)
        local_now = now.astimezone(zone)
        moment = datetime(local_now.year, local_now.month, local_now.day, clock[0], clock[1], tzinfo=zone)
        if moment <= local_now:
            moment += timedelta(days=1)
        return iso_z(moment)
    return None


def parse_claude_usage_text(text: str, now: datetime):
    """Limits from the text of `claude -p "/usage"`. Lines such as 'Current session: 40% used · resets ...'.
    The session line is the 5-hour window and the all-models line is the week. Only Opus and Sonnet get their
    own week (the readers can name them); other models are skipped."""
    windows = {}
    for match in USAGE_LINE.finditer(text):
        name = match.group("name").lower()
        model = (match.group("model") or "").strip().lower()
        if name == "session":
            key = "five_hour"
        elif model in ("", "all models"):
            key = "seven_day"
        elif model in ("opus", "sonnet"):
            key = f"seven_day_{model}"
        else:
            continue
        if key not in windows:
            windows[key] = {"used": clamp_pct(float(match.group("pct"))),
                            "resets": parse_usage_reset(match.group("rest"), now)}
    limits = []
    for key in ("five_hour", "seven_day", "seven_day_opus", "seven_day_sonnet"):
        if key in windows:
            info = windows[key]
            limits.append({"key": key, "label": CLAUDE_LABELS[key], "used_percent": info["used"],
                           "resets_at": info["resets"], "window_seconds": window_seconds_for("claude", key)})
    return limits


def claude_requests() -> list:
    """The two control requests of the get_usage protocol: initialize, then get_usage without a user message."""
    return [json_line({"type": "control_request", "request_id": "init-1", "request": {"subtype": "initialize"}}),
            json_line({"type": "control_request", "request_id": "usage-1",
                       "request": {"subtype": "get_usage", "skip_behaviors": True}})]


def control_reply(message, request_id: str):
    """The control_response that answers request_id, or None. The CLI nests the id under response."""
    if not isinstance(message, dict) or message.get("type") != "control_response":
        return None
    reply = message.get("response")
    if not isinstance(reply, dict):
        return None
    if reply.get("request_id", message.get("request_id")) != request_id:
        return None
    return reply


def said_logged_out(lines) -> bool:
    return any(LOGGED_OUT.search(raw.decode("utf-8", "replace")) for raw in lines)


def claude_stream_usage(env: Env, source, binary: str):
    """Usage from the get_usage control request, the primary way. Raises NotLoggedIn, or FetchError."""
    run = run_cli([binary, *CLAUDE_STREAM_ARGS], cwd=env.cli_cwd(), env=cli_environment(source.cli_env),
                  feed=claude_requests(), until=lambda message: control_reply(message, "usage-1") is not None)
    raise_for_run(run, "claude", MSG_CLAUDE_TIMEOUT, MSG_CLAUDE_FORMAT)
    reply = control_reply(run.found, "usage-1") if run.found is not None else None
    if reply is None:
        if said_logged_out(run.lines):
            raise NotLoggedIn("get_usage: the CLI said not logged in")
        raise FetchError(MSG_CLAUDE_FORMAT, ERROR_UNKNOWN, detail="get_usage: no reply")
    if reply.get("subtype") == "error":
        if said_logged_out(run.lines):
            raise NotLoggedIn("get_usage: the CLI said not logged in")
        raise FetchError(MSG_CLAUDE_REJECTED, ERROR_UNKNOWN, detail="get_usage: the CLI returned an error")
    payload = reply.get("response")
    if not isinstance(payload, dict):
        raise FetchError(MSG_CLAUDE_FORMAT, ERROR_UNKNOWN, detail="get_usage: no response object")
    if payload.get("rate_limits_available") is False:
        # Not a silent drop: an error keeps the last good data (stale), and the stage is logged.
        raise FetchError(MSG_CLAUDE_NO_QUOTA, ERROR_QUOTA_UNAVAILABLE,
                         detail="get_usage: rate_limits_available is false")
    rate = payload.get("rate_limits")
    if not isinstance(rate, dict):
        raise FetchError(MSG_CLAUDE_FORMAT, ERROR_UNKNOWN, detail="get_usage: rate_limits missing")
    limits, credits = parse_claude_usage(claude_with_models(rate))
    return {"plan": claude_plan(payload.get("subscription_type")), "limits": limits, "credits": credits}


def claude_text_usage(env: Env, source, binary: str):
    """Usage from `claude -p "/usage"`, the fallback when get_usage fails. The reply is text, so only the
    percentages and reset times are read; the plan is not known from it."""
    run = run_cli([binary, *CLAUDE_USAGE_ARGS], cwd=env.cli_cwd(), env=cli_environment(source.cli_env))
    raise_for_run(run, "claude", MSG_CLAUDE_TIMEOUT, MSG_CLAUDE_FORMAT)
    doc = cli_output_document(run, "/usage", MSG_CLAUDE_FORMAT)
    text = doc.get("result")
    if not isinstance(text, str):
        raise FetchError(MSG_CLAUDE_FORMAT, ERROR_UNKNOWN, detail="/usage: result text missing")
    limits = [] if doc.get("is_error") is True else parse_claude_usage_text(text, env.now)
    if not limits:
        if LOGGED_OUT.search(text):
            raise NotLoggedIn("/usage: the CLI said not logged in")
        if CLAUDE_USAGE_RATE_LIMITED.search(text):
            raise FetchError(MSG_CLAUDE_RATE_LIMITED, ERROR_RATE_LIMITED, detail="/usage: rate limited")
        if doc.get("is_error") is True:
            raise FetchError(MSG_CLAUDE_REJECTED, ERROR_UNKNOWN, detail="/usage: the CLI returned an error")
        raise FetchError(MSG_CLAUDE_NO_QUOTA, ERROR_QUOTA_UNAVAILABLE, detail="/usage: no session or week line")
    return {"plan": None, "limits": limits, "credits": None}


def fetch_claude(env: Env, source):
    """Claude is read only through its CLI. get_usage first; /usage when get_usage fails in a way that a
    second try may fix (unknown output or no answer in time)."""
    binary = require_cli("claude")
    try:
        return claude_stream_usage(env, source, binary)
    except FetchError as error:
        if error.code not in (ERROR_UNKNOWN, ERROR_NETWORK, ERROR_QUOTA_UNAVAILABLE):
            raise
        log(f"{source.id}: ลองอ่านด้วยคำสั่ง /usage แทน ({error.detail})")
    return claude_text_usage(env, source, binary)


# Per million tokens: (input, cache write 5m, cache write 1h, cache read, output).
# Source: https://platform.claude.com/docs/en/about-claude/pricing (fetched 2026-11-19).
# Haiku 5.5 is priced by prompt size: up to 100k tokens, then the higher tier.
PRICE_TABLE = (
    (r"^claude-fable-5-2", ((None, (8.00, 10.00, 16.00, 0.20, 40.00)),)),
    (r"^claude-opus-5-5", ((None, (4.00, 5.00, 8.00, 0.20, 20.00)),)),
    (r"^claude-opus-(4-[5-8]|5)(-|$)", ((None, (5.00, 6.25, 10.00, 0.50, 25.00)),)),
    (r"^claude-opus-4(-1)?(-|$)", ((None, (15.00, 18.75, 30.00, 1.50, 75.00)),)),
    (r"^claude-sonnet-5-5", ((None, (2.00, 2.50, 4.00, 0.10, 10.00)),)),
    (r"^claude-sonnet-5(-|$)", ((None, (2.00, 2.50, 4.00, 0.20, 10.00)),)),
    (r"^claude-sonnet-4(-[56]|-|$)", ((None, (3.00, 3.75, 6.00, 0.30, 15.00)),)),
    (r"^claude-haiku-5-5", ((100_000, (0.10, 0.125, 0.20, 0.01, 0.50)),
                            (None, (0.50, 0.625, 1.00, 0.05, 2.50)))),
    (r"^claude-haiku-4-5", ((None, (1.00, 1.25, 2.00, 0.10, 5.00)),)),
)


def cost_usd(model: str, inp: int, out: int, cw5m: int, cw1h: int, cr: int):
    """Estimated API list-price cost in USD, or None when the model has no price here."""
    for pattern, tiers in PRICE_TABLE:
        if re.search(pattern, model):
            prompt = inp + cw5m + cw1h + cr
            for limit, prices in tiers:
                if limit is None or prompt <= limit:
                    break
            p_in, p_cw5m, p_cw1h, p_cr, p_out = prices
            return (inp * p_in + out * p_out + cw5m * p_cw5m + cw1h * p_cw1h + cr * p_cr) / 1_000_000
    return None


# The four latest models shown in the Mac model-mix section, in the order of the app's default list.
PRICE_MODELS = (("claude-opus-5-5", "opus", "Opus 5.5"), ("claude-sonnet-5-5", "sonnet", "Sonnet 5.5"),
                ("claude-haiku-5-5", "haiku", "Haiku 5.5"), ("claude-fable-5-2", "fable", "Fable 5.2"))


def base_prices(model: str):
    """(input, cache write 5m, cache write 1h, cache read, output) per million tokens for the base tier of
    the first PRICE_TABLE pattern that matches the model id. None when there is no price."""
    for pattern, tiers in PRICE_TABLE:
        if re.search(pattern, model):
            return tiers[0][1]
    return None


def model_prices() -> dict:
    """usage.json model_prices, read from PRICE_TABLE so the numbers are kept in one place only."""
    prices = {}
    for model, family, label in PRICE_MODELS:
        found = base_prices(model)
        if found is None:
            continue
        p_in, p_cw5m, p_cw1h, p_cr, p_out = found
        prices[model] = {"provider": "anthropic", "family": family, "label": label, "input": p_in,
                         "cache_write_5m": p_cw5m, "cache_write_1h": p_cw1h, "cache_read": p_cr, "output": p_out}
    for model_id, _pattern, family, label, short, long_rates in GPT_PRICES:
        p_in, p_cached, p_cache_write, p_out = short
        l_in, l_cached, l_out = long_rates
        prices[model_id] = {"provider": "openai", "family": family, "label": label, "input": p_in,
                            "cached_input": p_cached, "cache_write": p_cache_write, "output": p_out,
                            "long_context": {"threshold": GPT_LONG_CONTEXT, "input": l_in,
                                             "cached_input": l_cached, "output": l_out}}
    return prices


def dedupe_key(message_id, request_id, uuid, path, lineno) -> str:
    """Hashed so no message or request id is stored in the cache in clear text."""
    if isinstance(message_id, str) and message_id and isinstance(request_id, str) and request_id:
        raw = f"msg|{message_id}|{request_id}"
    elif isinstance(uuid, str) and uuid:
        raw = f"uuid|{uuid}"
    else:
        raw = f"line|{path}|{lineno}"
    return hashlib.sha1(raw.encode("utf-8")).hexdigest()[:20]


def parse_claude_file(path: Path, cutoff_day: str):
    """Usage records [key, day, model, input, output, cw5m, cw1h, cache_read] from one jsonl file."""
    records = []
    try:
        handle = open(path, "rb")
    except OSError:
        return records
    with handle:
        for lineno, raw in enumerate(handle, 1):
            if b'"usage"' not in raw:
                continue
            try:
                line = json.loads(raw)
            except ValueError:
                continue  # a partly written last line is normal for an open session
            if not isinstance(line, dict):
                continue
            message = line.get("message")
            if not isinstance(message, dict):
                continue
            usage = message.get("usage")
            model = message.get("model")
            if not isinstance(usage, dict) or not isinstance(model, str) or model.startswith("<"):
                continue
            day = local_day(line.get("timestamp"))
            if day is None or day < cutoff_day:
                continue
            inp = to_int(usage.get("input_tokens")) or 0
            out = to_int(usage.get("output_tokens")) or 0
            cw = to_int(usage.get("cache_creation_input_tokens")) or 0
            cr = to_int(usage.get("cache_read_input_tokens")) or 0
            if inp + out + cw + cr == 0:
                continue
            detail = usage.get("cache_creation")
            cw1h = 0
            if isinstance(detail, dict):
                cw1h = min(cw, to_int(detail.get("ephemeral_1h_input_tokens")) or 0)
            key = dedupe_key(message.get("id"), line.get("requestId"), line.get("uuid"), path, lineno)
            records.append([key, day, model, inp, out, cw - cw1h, cw1h, cr])
    return records


FAMILIES = ("opus", "sonnet", "haiku", "fable")
FAMILY_KEYS = FAMILIES + ("other",)  # "other" = a Claude model id that matches no known family
KINDS = ("input", "output", "cache_write_5m", "cache_write_1h", "cache_read")


def family_of(model: str) -> str:
    """Family by id prefix: claude-opus-*, claude-sonnet-*, claude-haiku-*, claude-fable-*. Anything else is other."""
    for family in FAMILIES:
        if model.startswith(f"claude-{family}-"):
            return family
    return "other"


class Bucket:
    def __init__(self):
        self.tokens = 0
        self.cost = 0.0
        self.unknown = False
        self.families = {family: dict.fromkeys(KINDS, 0) for family in FAMILY_KEYS}

    def add(self, tokens: int, cost, family: str, kinds):
        self.tokens += tokens
        if cost is None:
            self.unknown = True
        else:
            self.cost += cost
        for kind, count in zip(KINDS, kinds):
            self.families[family][kind] += count

    def result(self):
        return {"tokens": self.tokens, "cost_usd": None if self.unknown else round(self.cost, 2),
                "by_family": {family: dict(kinds) for family, kinds in self.families.items()}}


def summarize_claude(records, now: datetime):
    best = {}
    for record in records:  # one message can appear several times, also across files
        full = record[3] + record[4] + record[5] + record[6] + record[7]  # ranks duplicates
        held = best.get(record[0])
        if held is None or full > held[0]:
            best[record[0]] = (full, record)
    today = local_today(now)
    month = today[:7]
    buckets = {"today": Bucket(), "month": Bucket()}
    for _, record in best.values():
        _, day, model, inp, out, cw5m, cw1h, cr = record
        tokens = inp + out + cw5m + cw1h + (cr if TOKENS_INCLUDE_CACHE_READS else 0)
        cost = cost_usd(model, inp, out, cw5m, cw1h, cr)
        family = family_of(model)
        kinds = (inp, out, cw5m, cw1h, cr)
        if day == today:
            buckets["today"].add(tokens, cost, family, kinds)
        if day.startswith(month):
            buckets["month"].add(tokens, cost, family, kinds)
    return {name: bucket.result() for name, bucket in buckets.items()}


def claude_local_usage(env: Env, source=None):
    """Token totals from one account's Claude Code logs; the default account when no source is given."""
    source = source or default_source("claude", env.paths)
    root = source.projects_dir
    if not root.is_dir():
        return None
    files = list_files(root, "*.jsonl")
    if not files:
        return None
    cutoff_day = window_start_day(env.now)
    cutoff_epoch = day_start_epoch(cutoff_day)
    store = account_cache(env, "claude", source)
    current = {}
    records = []
    for path in files:
        try:
            stat = path.stat()
        except OSError:
            continue
        if stat.st_mtime < cutoff_epoch:
            continue  # nothing in an untouched-since-last-month file can fall in this window
        key = str(path)
        entry = store.get(key)
        if not (isinstance(entry, dict) and entry.get("mtime_ns") == stat.st_mtime_ns
                and entry.get("size") == stat.st_size):
            entry = {"mtime_ns": stat.st_mtime_ns, "size": stat.st_size,
                     "records": parse_claude_file(path, cutoff_day)}
        current[key] = entry
        records.extend(entry["records"])
    store.clear()
    store.update(current)
    return summarize_claude(records, env.now)


# ---------------------------------------------------------------- Codex (ChatGPT)

CODEX_PLANS = {"prolite": "Pro Lite", "pro": "Pro", "plus": "Plus", "team": "Team",
               "business": "Business", "enterprise": "Enterprise", "free": "Free", "go": "Go"}
CODEX_LOGIN_ERROR = re.compile(r"\b(?:log(?:ged)?[ -]?in|sign[ -]?in)\b|unauthori[sz]ed|authenticat|\b401\b",
                               re.IGNORECASE)


def window_label(seconds) -> str:
    if seconds is None or seconds <= 0:
        return "ช่วงเวลา"
    if seconds == 18000:
        return "5 ชม."
    if seconds == 604800:
        return "สัปดาห์"
    if seconds % 86400 == 0:
        return f"{int(seconds // 86400)} วัน"
    if seconds % 3600 == 0:
        return f"{int(seconds // 3600)} ชม."
    return f"{round(seconds / 60)} นาที"


def codex_plan(raw):
    if not isinstance(raw, str) or not raw.strip():
        return None
    return scrub(CODEX_PLANS.get(raw.strip().lower(), raw.strip().replace("_", " ").title()))


def codex_init_lines() -> list:
    """The first message: initialize. Sent when the server starts."""
    return [json_line({"id": 1, "method": "initialize",
                       "params": {"clientInfo": {"name": "ai-usage-collector", "title": None, "version": "1.0"}}})]


def codex_after_init_lines() -> list:
    """Sent only after the reply to initialize: the initialized notification, then the one read,
    account/rateLimits/read. No other method is ever sent (in particular none that uses a reset credit, sends
    an e-mail or changes the login)."""
    return [json_line({"method": "initialized"}),
            json_line({"id": 2, "method": "account/rateLimits/read",
                       "params": {"excludeResetCreditDetails": True}})]


def codex_follow():
    """follow() for run_cli: after the successful reply to initialize, it returns the two lines that follow.
    It returns nothing for any other message, and nothing once it has sent them."""
    sent = []

    def follow(message):
        if not sent and message.get("id") == 1 and "result" in message:
            sent.append(True)
            return codex_after_init_lines()
        return []

    return follow


def parse_codex_rate_limits(result: dict, now: datetime):
    """(plan, limits, credits) from the account/rateLimits/read result. Each window is labelled by its own length
    (windowDurationMins), and keeps its slot name (primary or secondary) as the key."""
    rate = result.get("rateLimits")
    if not isinstance(rate, dict):
        raise FetchError(MSG_CODEX_FORMAT, ERROR_UNKNOWN, detail="rateLimits missing")
    limits = []
    for slot in ("primary", "secondary"):
        window = rate.get(slot)
        if not isinstance(window, dict):
            continue
        used = to_num(window.get("usedPercent"))
        if used is None:
            continue
        minutes = to_num(window.get("windowDurationMins"))
        length = int(minutes * 60) if minutes is not None and minutes > 0 else None
        reset = parse_time(window.get("resetsAt"))
        limits.append({"key": slot, "label": window_label(length), "used_percent": clamp_pct(used),
                       "resets_at": iso_z(reset) if reset else None, "window_seconds": length})
    if not limits:
        raise FetchError(MSG_CODEX_NO_QUOTA, ERROR_UNKNOWN, detail="rateLimits has no usable window")
    credits = None
    raw_credits = rate.get("credits")
    if isinstance(raw_credits, dict):
        credits = {"extra_usage_enabled": bool(raw_credits.get("hasCredits")),
                   "used_usd": None, "limit_usd": None,
                   "balance_usd": round_or_none(to_num(raw_credits.get("balance")))}
    return codex_plan(rate.get("planType")), limits, credits


def fetch_codex_cli(env: Env, source):
    binary = require_cli("codex")
    run = run_cli([binary, *CODEX_APP_ARGS], cwd=env.cli_cwd(), env=cli_environment(source.cli_env),
                  feed=codex_init_lines(), follow=codex_follow(),
                  until=lambda message: message.get("id") == 2 and ("result" in message or "error" in message))
    raise_for_run(run, "codex", MSG_CODEX_TIMEOUT, MSG_CODEX_FORMAT)
    reply = run.found
    if reply is None:
        raise FetchError(MSG_CODEX_FORMAT, ERROR_UNKNOWN, detail="app-server: no reply")
    if "error" in reply:
        # The message is only classified here, never shown or logged.
        if CODEX_LOGIN_ERROR.search(json.dumps(reply.get("error"), ensure_ascii=False)):
            raise FetchError(MSG_CODEX_EXPIRED, ERROR_LOGIN_EXPIRED, detail="app-server: login rejected")
        raise FetchError(MSG_CODEX_REJECTED, ERROR_UNKNOWN, detail="app-server: the CLI returned an error")
    result = reply.get("result")
    if not isinstance(result, dict):
        raise FetchError(MSG_CODEX_FORMAT, ERROR_UNKNOWN, detail="app-server: result missing")
    plan, limits, credits = parse_codex_rate_limits(result, env.now)
    return {"plan": plan, "limits": limits, "credits": credits}


def parse_codex_usage(doc, now: datetime):
    """Direct mode only. Returns (plan, limits, credits) from the wham/usage response."""
    if not isinstance(doc, dict):
        raise FetchError("ข้อมูล ChatGPT ผิดรูปแบบ")
    raw_plan = doc.get("plan_type")
    plan = None
    if isinstance(raw_plan, str) and raw_plan.strip():
        plan = CODEX_PLANS.get(raw_plan.strip().lower(), raw_plan.strip().replace("_", " ").title())
    rate = doc.get("rate_limit") if isinstance(doc.get("rate_limit"), dict) else {}
    limits = []
    for slot, key in (("primary_window", "primary"), ("secondary_window", "secondary")):
        window = rate.get(slot)
        if not isinstance(window, dict):
            continue
        used = to_num(window.get("used_percent"))
        if used is None:
            continue
        reset = parse_time(window.get("reset_at"))
        if reset is None:
            after = to_num(window.get("reset_after_seconds"))
            reset = now + timedelta(seconds=after) if after is not None else None
        length = to_num(window.get("limit_window_seconds"))
        length = int(length) if length is not None and length > 0 else None
        limits.append({"key": key,
                       "label": window_label(length),
                       "used_percent": clamp_pct(used),
                       "resets_at": iso_z(reset) if reset else None,
                       "window_seconds": length})
    if not limits:
        raise FetchError("ไม่พบข้อมูลโควตา ChatGPT")
    credits = None
    raw_credits = doc.get("credits")
    if isinstance(raw_credits, dict):
        credits = {"extra_usage_enabled": bool(raw_credits.get("has_credits")),
                   "used_usd": None, "limit_usd": None,
                   "balance_usd": round_or_none(to_num(raw_credits.get("balance")))}
    return plan, limits, credits


# GPT (Codex) prices per million tokens, standard tier.
# Source: https://developers.openai.com/api/docs/pricing (the target of platform.openai.com/docs/pricing; read 2026-11-20).
# Short context: up to 272,000 input tokens. Long context: a turn with more input than that is priced at the
# long-context rates. The long-context table has no cache write price, so the short cache write rate is used there.
# The cache write rate is the 30-minute rate, since the log does not say which retention was used.
# Reasoning has no price of its own; it is billed as output (see gpt_cost_usd).
GPT_LONG_CONTEXT = 272_000
# (model id, id pattern, family, label, (input, cached input, cache write, output), (long input, long cached input, long output))
GPT_PRICES = (
    ("gpt-6-luna", r"^gpt-6-luna(-|$)", "luna", "GPT-6 Luna",
     (0.10, 0.01, 0.125, 0.50), (0.20, 0.02, 0.75)),
    ("gpt-6.2-sol", r"^gpt-6\.2-sol(-|$)", "sol", "GPT-6.2 Sol",
     (2.00, 0.10, 2.50, 10.00), (4.00, 0.20, 15.00)),
    ("gpt-6.1-sol", r"^gpt-6\.1-sol(-|$)", "sol", "GPT-6.1 Sol",
     (2.00, 0.10, 2.50, 10.00), (4.00, 0.20, 15.00)),
)
CODEX_KINDS = ("input", "cached_input", "cache_write", "output", "reasoning")
CODEX_UNKNOWN_MODEL = "unknown"  # a turn with no model in its session log


def gpt_model_id(model) -> str:
    """The price table's id when the model matches a row, else the logged name (lower case, 64 characters at most),
    or "unknown" when the log names no model."""
    if not isinstance(model, str) or not model.strip():
        return CODEX_UNKNOWN_MODEL
    name = model.strip().lower()
    for row in GPT_PRICES:
        if re.search(row[1], name):
            return row[0]
    return name[:64]


def gpt_price_row(model_id: str):
    for row in GPT_PRICES:
        if row[0] == model_id:
            return row
    return None


def gpt_cost_usd(model_id: str, inp: int, cached: int, cache_write: int, output: int, extra_reasoning: int):
    """Estimated API list-price cost of one turn in USD, or None when the model has no price here.
    inp is input_tokens as logged (it includes cached input). The plain input is inp minus cached, and cache
    writes are a separate kind. extra_reasoning is the reasoning count that output_tokens does not include
    (0 when the log says output already includes it)."""
    row = gpt_price_row(model_id)
    if row is None:
        return None
    short, long_rates = row[4], row[5]
    if inp > GPT_LONG_CONTEXT:
        p_in, p_cached, p_out = long_rates
        p_cache_write = short[2]
    else:
        p_in, p_cached, p_cache_write, p_out = short
    plain = max(inp - cached, 0)
    billed_output = output + extra_reasoning
    return (plain * p_in + cached * p_cached + cache_write * p_cache_write + billed_output * p_out) / 1_000_000


def parse_codex_file(path: Path, cutoff_day: str):
    """One record per turn in one session log: [key, day, model id, input, cached input, cache write, output,
    reasoning, extra reasoning billed as output, tokens]. A turn is the last_token_usage of a token_count event,
    never the running total. The model comes from the latest turn_context line before the event.

    Reasoning: the Codex log has last_usage_includes_reasoning on token_count info. When it is false, the
    reasoning tokens are not in output_tokens, so they are billed as output. When it is true, or missing (the
    OpenAI convention: reasoning is part of output_tokens), nothing is added, so reasoning is never counted twice."""
    records = []
    model_now = None
    try:
        handle = open(path, "rb")
    except OSError:
        return records
    with handle:
        for raw in handle:
            if b"token_count" not in raw and b"turn_context" not in raw:
                continue
            try:
                line = json.loads(raw)
            except ValueError:
                continue
            payload = line.get("payload") if isinstance(line, dict) else None
            if not isinstance(payload, dict):
                continue
            if line.get("type") == "turn_context":
                if isinstance(payload.get("model"), str):
                    model_now = payload["model"]
                continue
            if payload.get("type") != "token_count":
                continue
            info = payload.get("info")
            last = info.get("last_token_usage") if isinstance(info, dict) else None
            if not isinstance(last, dict):
                continue
            stamp = line.get("timestamp")
            day = local_day(stamp)
            if day is None or day < cutoff_day:
                continue
            model_id = gpt_model_id(info.get("model") or payload.get("model") or model_now)
            inp = to_int(last.get("input_tokens")) or 0
            cached = to_int(last.get("cached_input_tokens")) or 0
            cache_write = to_int(last.get("cache_write_input_tokens")) or 0
            output = to_int(last.get("output_tokens")) or 0
            reasoning = to_int(last.get("reasoning_output_tokens")) or 0
            extra = reasoning if info.get("last_usage_includes_reasoning") is False else 0
            tokens = to_int(last.get("total_tokens"))
            if tokens is None:
                tokens = inp + output + extra
            # Hashed, so no content of the log is kept as a readable key. The same turn can sit in two files
            # (a resumed session copies its earlier events), so the key is the turn itself, not the file.
            raw_key = json.dumps([stamp, model_id, last], sort_keys=True)
            key = hashlib.sha1(raw_key.encode("utf-8")).hexdigest()[:20]
            records.append([key, day, model_id, inp, cached, cache_write, output, reasoning, extra, tokens])
    return records


class CodexBucket:
    def __init__(self):
        self.tokens = 0
        self.cost = 0.0
        self.unknown = False
        self.models = {row[0]: dict.fromkeys(CODEX_KINDS, 0) for row in GPT_PRICES}
        self.long = {}  # model id -> kinds of its turns above GPT_LONG_CONTEXT only; a model with none has no entry

    def add(self, model_id: str, tokens: int, cost, kinds, long_turn: bool = False):
        self.tokens += tokens
        if cost is None:
            self.unknown = True
        else:
            self.cost += cost
        bucket = self.models.setdefault(model_id, dict.fromkeys(CODEX_KINDS, 0))
        for kind, count in zip(CODEX_KINDS, kinds):
            bucket[kind] += count
        if long_turn:
            long_bucket = self.long.setdefault(model_id, dict.fromkeys(CODEX_KINDS, 0))
            for kind, count in zip(CODEX_KINDS, kinds):
                long_bucket[kind] += count

    def result(self):
        by_model = {}
        for model, kinds in self.models.items():
            entry = dict(kinds)  # the totals: short and long turns together
            if model in self.long:
                entry["long_context"] = dict(self.long[model])  # the part of the totals from turns over 272K
            by_model[model] = entry
        return {"tokens": self.tokens, "cost_usd": None if self.unknown else round(self.cost, 2),
                "by_model": by_model}


def summarize_codex(records, now: datetime):
    seen = {}
    for record in records:  # the same turn can appear in more than one file: count it once
        seen.setdefault(record[0], record)
    today = local_today(now)
    month = today[:7]
    buckets = {"today": CodexBucket(), "month": CodexBucket()}
    for record in seen.values():
        _, day, model_id, inp, cached, cache_write, output, reasoning, extra, tokens = record
        cost = gpt_cost_usd(model_id, inp, cached, cache_write, output, extra)
        kinds = (max(inp - cached, 0), cached, cache_write, output, reasoning)
        long_turn = inp > GPT_LONG_CONTEXT  # the same rule as gpt_cost_usd: this turn is priced at long-context rates
        if day == today:
            buckets["today"].add(model_id, tokens, cost, kinds, long_turn)
        if day.startswith(month):
            buckets["month"].add(model_id, tokens, cost, kinds, long_turn)
    return {name: bucket.result() for name, bucket in buckets.items()}


def codex_local_usage(env: Env, source=None):
    """None when there are no session logs (the widget then shows no token figures)."""
    source = source or default_source("codex", env.paths)
    root = source.sessions_dir
    if not root.is_dir():
        return None
    files = list_files(root, "*.jsonl")
    if not files:
        return None
    cutoff_day = window_start_day(env.now)
    cutoff_epoch = day_start_epoch(cutoff_day)
    store = account_cache(env, "codex", source)
    current = {}
    records = []
    for path in files:
        try:
            stat = path.stat()
        except OSError:
            continue
        if stat.st_mtime < cutoff_epoch:
            continue
        key = str(path)
        entry = store.get(key)
        if not (isinstance(entry, dict) and entry.get("mtime_ns") == stat.st_mtime_ns
                and entry.get("size") == stat.st_size and isinstance(entry.get("records"), list)):
            entry = {"mtime_ns": stat.st_mtime_ns, "size": stat.st_size,
                     "records": parse_codex_file(path, cutoff_day)}
        current[key] = entry
        records.extend(entry["records"])
    store.clear()
    store.update(current)
    return summarize_codex(records, env.now)


def fetch_codex_direct(env: Env, source):
    """Direct mode only: reads the Codex login file and calls the usage endpoint with its token."""
    auth_file = source.auth_file if source is not None else env.paths.codex_auth
    if not auth_file.exists():
        raise NotLoggedIn()  # no Codex login file on this Mac
    auth = read_json_file(auth_file)  # None when the file is unreadable or corrupt
    tokens = auth.get("tokens") if isinstance(auth, dict) else None
    access = tokens.get("access_token") if isinstance(tokens, dict) else None
    if not isinstance(access, str) or not access:
        raise FetchError(MSG_CODEX_EXPIRED, ERROR_RELOGIN_NEEDED)
    remember_secret(access)
    headers = {"Authorization": f"Bearer {access}", "User-Agent": "codex_cli_rs",
               "Accept": "application/json"}
    account_id = tokens.get("account_id")
    if isinstance(account_id, str) and account_id:
        remember_secret(account_id)
        headers["ChatGPT-Account-Id"] = account_id
    status, body = env.http("GET", CODEX_USAGE_URL, headers, None, HTTP_TIMEOUT)
    if status is None:
        raise FetchError(MSG_CODEX_RETRY, ERROR_NETWORK)
    if status == 401:
        raise FetchError(MSG_CODEX_EXPIRED, ERROR_LOGIN_EXPIRED)
    if status != 200:
        raise FetchError(f"เรียก ChatGPT ไม่สำเร็จ (HTTP {status})", http_error_code(status))
    plan, limits, credits = parse_codex_usage(read_json_bytes(body), env.now)
    return {"plan": plan, "limits": limits, "credits": credits}


def fetch_codex(env: Env, source):
    if direct_enabled(env, "codex"):
        return fetch_codex_direct(env, source)
    return fetch_codex_cli(env, source)


# ---------------------------------------------------------------- agy (Antigravity)

AGY_WINDOW_TAGS = {"5h": "5h", "weekly": "Weekly"}
AGY_LOGIN_ERROR = re.compile(r"\b(?:log(?:ged)?[ -]?in|sign[ -]?in)\b|unauthori[sz]ed|authenticat|\b401\b",
                             re.IGNORECASE)
AGY_GROUPS = (("claude", "Claude"), ("gemini_pro", "Gemini Pro"),
              ("gemini_flash", "Gemini Flash"), ("gpt_oss", "GPT-OSS"))
# Display: the "Gemini" group first, then the "add-ons" group (Claude and GPT on their own quota), then the rest.
# Known CLI bucket keys keep this order and label; unknown keys follow their group by prefix.
AGY_GROUP_GEMINI, AGY_GROUP_ADDON, AGY_GROUP_OTHER = "gemini", "addon", "other"
AGY_GROUP_RANK = {AGY_GROUP_GEMINI: 0, AGY_GROUP_ADDON: 1, AGY_GROUP_OTHER: 2}
AGY_KNOWN_CLI = (("gemini-5h", "Gemini Models · 5h"), ("gemini-weekly", "Gemini Models · Weekly"),
                 ("gemini-argon-wtu-weekly", "Gemini Argon · Weekly"),
                 ("3p-5h", "Claude & GPT · 5h"), ("3p-weekly", "Claude & GPT · Weekly"))
AGY_KNOWN_LABEL = dict(AGY_KNOWN_CLI)
AGY_DIRECT_GROUP = {"gemini_pro": AGY_GROUP_GEMINI, "gemini_flash": AGY_GROUP_GEMINI,
                    "claude": AGY_GROUP_ADDON, "gpt_oss": AGY_GROUP_ADDON}


def agy_key(raw, fallback: str, taken: set) -> str:
    """A stable key for a bucket: the CLI's own id (lower case, safe characters), made unique in the account."""
    text = re.sub(r"[^a-z0-9_\-]+", "-", str(raw).lower()).strip("-")[:40] if isinstance(raw, str) else ""
    key = text or fallback
    candidate, number = key, 2
    while candidate in taken:
        candidate = f"{key}-{number}"
        number += 1
    taken.add(candidate)
    return candidate


def agy_limit_group(key: str) -> str:
    """The display group of an agy limit by its key: known keys, then gemini-* (Gemini), 3p-* (add-ons), else other."""
    if key in AGY_DIRECT_GROUP:
        return AGY_DIRECT_GROUP[key]
    if key.startswith("gemini"):
        return AGY_GROUP_GEMINI
    if key.startswith("3p-"):
        return AGY_GROUP_ADDON
    return AGY_GROUP_OTHER


def arrange_agy_limits(limits: list) -> list:
    """Adds `group` to each agy limit and puts them in display order: group first, then the known order of the
    key, then the order the CLI gave. Known CLI keys also get their display label."""
    known_order = {key: index for index, (key, _label) in enumerate(AGY_KNOWN_CLI)}
    arranged = []
    for position, limit in enumerate(limits):
        key = limit["key"]
        group = agy_limit_group(key)
        if key in AGY_KNOWN_LABEL:
            limit = dict(limit, label=AGY_KNOWN_LABEL[key])
        rank = (AGY_GROUP_RANK[group], known_order.get(key, len(known_order)), position)
        arranged.append((rank, dict(limit, group=group)))
    return [limit for _rank, limit in sorted(arranged, key=lambda item: item[0])]


def agy_cli_limits(groups) -> list:
    """Limits from `agy -p "/usage"`: one per bucket of each group. A group's 5-hour and weekly buckets are kept
    apart by their label, because a limit with a window length would drop the group name in the readers.
    window_seconds is therefore null for these limits, as it is for every agy limit."""
    limits, taken = [], set()
    for group_index, group in enumerate(groups):
        if not isinstance(group, dict):
            continue
        group_name = clean_label(group.get("name"), f"Group {group_index + 1}")
        buckets = group.get("buckets")
        if not isinstance(buckets, list):
            continue
        for bucket_index, bucket in enumerate(buckets):
            if not isinstance(bucket, dict):
                continue
            remaining = to_num(bucket.get("remaining_fraction"))
            reset = parse_time(bucket.get("reset_time"))
            if remaining is None:
                if reset is None:
                    continue
                remaining = 0.0  # the CLI leaves out a zero value, as the direct API does
            used = clamp_pct((1.0 - remaining) * 100.0)
            tag = AGY_WINDOW_TAGS.get(str(bucket.get("window") or "").lower())
            if tag is None:
                tag = clean_label(bucket.get("name"), "")
            label = f"{group_name} · {tag}" if tag else group_name
            limits.append({"key": agy_key(bucket.get("id"), f"group-{group_index + 1}-{bucket_index + 1}", taken),
                           "label": label, "used_percent": round(used, 1),
                           "resets_at": iso_z(reset) if reset else None, "window_seconds": None})
    return arrange_agy_limits(limits)


def fetch_agy_cli(env: Env, source):
    binary = require_cli("agy")
    run = run_cli([binary, *AGY_USAGE_ARGS], cwd=env.cli_cwd(), env=cli_environment(source.cli_env))
    raise_for_run(run, "agy", MSG_AGY_TIMEOUT, MSG_AGY_FORMAT)
    doc = cli_output_document(run, "agy", MSG_AGY_FORMAT)
    status = doc.get("status")
    if not (isinstance(status, str) and status.strip().upper() == "SUCCESS"):
        # The text is only classified here, never shown or logged.
        text = " ".join(str(doc.get(key) or "") for key in ("response", "error", "message"))
        if AGY_LOGIN_ERROR.search(text):
            raise FetchError(MSG_AGY_EXPIRED, ERROR_LOGIN_EXPIRED, detail="/usage: login rejected")
        raise FetchError(MSG_AGY_FORMAT, ERROR_UNKNOWN, detail="/usage: status is not SUCCESS")
    groups = dig(doc, "command", "data", "groups")
    if not isinstance(groups, list):
        raise FetchError(MSG_AGY_FORMAT, ERROR_UNKNOWN, detail="/usage: command.data.groups missing")
    limits = agy_cli_limits(groups)
    if not limits:
        raise FetchError(MSG_AGY_NO_QUOTA, ERROR_UNKNOWN, detail="/usage: no bucket with a quota")
    return {"plan": None, "limits": limits, "credits": None}


def group_agy_models(models):
    """Direct mode only. Limits per model group. used = max over the group of (1 - remainingFraction) * 100.

    Proto JSON omits zero values, so a quotaInfo that has a resetTime but no remainingFraction
    means the quota is used up (0 left), not unknown."""
    if not isinstance(models, dict):
        return []
    worst = {}
    earliest = {}
    for name, info in models.items():
        group = agy_group(str(name))
        if group is None or not isinstance(info, dict):
            continue
        quota = info.get("quotaInfo")
        if not isinstance(quota, dict) or not quota:
            continue
        remaining = to_num(quota.get("remainingFraction"))
        reset = parse_time(quota.get("resetTime"))
        if remaining is None:
            if reset is None:
                continue
            remaining = 0.0
        used = clamp_pct((1.0 - remaining) * 100.0)
        worst[group] = max(worst.get(group, 0.0), used)
        if reset is not None and (group not in earliest or reset < earliest[group]):
            earliest[group] = reset
    result = []
    for key, label in AGY_GROUPS:
        if key in worst:
            result.append({"key": key, "label": label, "used_percent": round(worst[key], 1),
                           "resets_at": iso_z(earliest[key]) if key in earliest else None,
                           "window_seconds": None})
    return arrange_agy_limits(result)


def agy_group(name: str):
    lowered = name.lower()
    if lowered.startswith("tab_"):
        return None
    if lowered.startswith("claude-"):
        return "claude"
    if lowered.startswith("gpt-oss"):
        return "gpt_oss"
    if "flash" in lowered:
        return "gemini_flash"
    if "pro" in lowered or lowered.startswith("gemini-4"):
        return "gemini_pro"
    return None


def read_agy_token(env: Env):
    """Direct mode only: the agy token from the Keychain, or None. A read that fails also gives None, so the
    token the run already has is kept."""
    try:
        password = env.keychain.read(AGY_KEYCHAIN_SERVICE, AGY_KEYCHAIN_ACCOUNT)
    except FetchError:
        return None
    return parse_agy_token(password)


def parse_agy_token(password):
    """Direct mode only: the token dict from the Keychain password text, or None when it is not an agy login."""
    if not password:
        return None
    text = password
    prefix = "go-keyring-base64:"
    if text.startswith(prefix):
        try:
            text = base64.b64decode(text[len(prefix):]).decode("utf-8")
        except (ValueError, UnicodeDecodeError):
            return None
    try:
        doc = json.loads(text)
    except ValueError:
        return None
    token = doc.get("token") if isinstance(doc, dict) else None
    if not isinstance(token, dict) or not isinstance(token.get("access_token"), str):
        return None
    remember_secret(token.get("access_token"))
    remember_secret(token.get("refresh_token"))
    return token


def agy_expired(token: dict, now: datetime) -> bool:
    expiry = parse_time(token.get("expiry"))
    return expiry is not None and expiry <= now + timedelta(seconds=EXPIRY_MARGIN_S)


def find_agy():
    found = shutil.which("agy")
    if found:
        return found
    for candidate in AGY_CANDIDATES:
        path = os.path.expanduser(candidate)
        if os.path.isfile(path) and os.access(path, os.X_OK):
            return path
    return None


def fetch_agy_direct(env: Env, source=None):
    """Direct mode only: reads the agy login from the Keychain and calls agy's endpoints with its token."""
    password = env.keychain.read(AGY_KEYCHAIN_SERVICE, AGY_KEYCHAIN_ACCOUNT)
    if password is None:
        raise NotLoggedIn()  # no agy login in the Keychain
    token = parse_agy_token(password)
    if token is None:
        raise FetchError(MSG_AGY_MISSING, ERROR_RELOGIN_NEEDED)
    if env.allow_refresh and agy_expired(token, env.now):
        binary = find_agy()
        if binary:
            env.run([binary, "models"], timeout=90)  # agy renews its own token; this costs no quota
        token = read_agy_token(env) or token
    headers = {"Authorization": f"Bearer {token['access_token']}",
               "Content-Type": "application/json", "Accept": "application/json",
               "User-Agent": AGY_USER_AGENT}
    status, body = env.http("POST", AGY_LOAD_URL, headers,
                            json.dumps({"metadata": {"ideType": "ANTIGRAVITY"}}).encode("utf-8"),
                            HTTP_TIMEOUT)
    if status is None:
        raise FetchError(MSG_AGY_RETRY, ERROR_NETWORK)
    if status == 401:
        raise FetchError(MSG_AGY_EXPIRED, ERROR_LOGIN_EXPIRED)
    if status != 200:
        raise FetchError(f"เรียก agy ไม่สำเร็จ (HTTP {status})", http_error_code(status))
    loaded = read_json_bytes(body)
    if not isinstance(loaded, dict):
        raise FetchError("ข้อมูล agy ผิดรูปแบบ")
    project = loaded.get("cloudaicompanionProject")
    if not project:
        raise FetchError(MSG_AGY_NO_PROJECT, ERROR_NOT_SET_UP)
    if isinstance(project, str):
        remember_secret(project)
    tier = loaded.get("currentTier")
    plan = tier.get("id") if isinstance(tier, dict) and isinstance(tier.get("id"), str) else None
    status, body = env.http("POST", AGY_MODELS_URL, headers,
                            json.dumps({"project": project}).encode("utf-8"), HTTP_TIMEOUT)
    if status is None:
        raise FetchError(MSG_AGY_RETRY, ERROR_NETWORK)
    if status == 401:
        raise FetchError(MSG_AGY_EXPIRED, ERROR_LOGIN_EXPIRED)
    if status != 200:
        raise FetchError(f"เรียก agy ไม่สำเร็จ (HTTP {status})", http_error_code(status))
    limits = group_agy_models((read_json_bytes(body) or {}).get("models"))
    if not limits:
        raise FetchError("ไม่พบข้อมูลโควตา agy")
    return {"plan": plan, "limits": limits, "credits": None}


def fetch_agy(env: Env, source=None):
    if direct_enabled(env, "agy"):
        return fetch_agy_direct(env, source)
    return fetch_agy_cli(env, source)


# ---------------------------------------------------------------- orchestration

MAIN_IDS = {"claude": "claude-main", "codex": "codex-main", "agy": "agy-main"}
PROVIDER_LABEL = {"claude": "Claude", "codex": "ChatGPT", "agy": "agy"}
PROVIDER_RANK = {"claude": 0, "codex": 1, "agy": 2}  # the "provider" sort: Claude, ChatGPT, agy
SORT_MODES = ("manual", "lowest", "provider")
FETCHERS = {"claude": fetch_claude, "codex": fetch_codex, "agy": fetch_agy}
LOCAL_USAGE = {"claude": claude_local_usage, "codex": codex_local_usage, "agy": None}  # agy keeps no local logs


@dataclass
class Source:
    """One account to collect: its id, where its login lives and where its local logs are."""
    id: str
    provider: str
    source: str  # display text for known-accounts.json; never a secret
    config_dir: Path | None = None
    projects_dir: Path | None = None  # Claude: token logs
    auth_file: Path | None = None  # Codex: the login file (direct mode reads it)
    sessions_dir: Path | None = None  # Codex: token logs
    cli_env: dict = field(default_factory=dict)  # the one variable that picks this account's folder
    default_label: str = ""  # the provider name; numbered once the accounts that answered are known


def default_source(provider: str, paths: Paths) -> Source:
    """The default account of a provider: ~/.claude, ~/.codex, or the agy login."""
    if provider == "claude":
        return Source(id=MAIN_IDS[provider], provider=provider, source="Claude Code (main)",
                      config_dir=paths.home / ".claude", projects_dir=paths.claude_projects,
                      default_label=PROVIDER_LABEL[provider])
    if provider == "codex":
        return Source(id=MAIN_IDS[provider], provider=provider, source="Codex (~/.codex)",
                      config_dir=paths.home / ".codex", auth_file=paths.codex_auth,
                      sessions_dir=paths.codex_sessions, default_label=PROVIDER_LABEL[provider])
    return Source(id=MAIN_IDS["agy"], provider="agy", source="agy (Keychain)",
                  default_label=PROVIDER_LABEL["agy"])


def natural_key(name: str):
    """Sort key that puts .claude-2 before .claude-10."""
    return [int(part) if part.isdigit() else part for part in re.split(r"(\d+)", name)]


def glob_dirs(folder: Path, pattern: str):
    """The folders directly in folder whose name matches pattern, in natural order."""
    try:
        matches = [path for path in folder.glob(pattern) if path.is_dir()]
    except OSError:
        return []
    return sorted(matches, key=lambda path: natural_key(path.name))


def unique_paths(paths):
    seen, result = set(), []
    for path in paths:
        key = unicodedata.normalize("NFC", str(path))
        if key not in seen:
            seen.add(key)
            result.append(path)
    return result


def display_dir(folder: Path, home: Path) -> str:
    """A folder as display text, with the home folder shown as ~."""
    text, home_text = str(folder), str(home)
    if text == home_text:
        return "~"
    if text.startswith(home_text + "/"):
        return "~" + text[len(home_text):]
    return text


def slug_for(folder: Path, provider: str) -> str:
    """The part of an account id that comes from the folder name: .claude-2 gives 2, Team Claude gives team-claude."""
    name = re.sub(rf"^\.?{provider}-?", "", folder.name.lower())
    return re.sub(r"[^a-z0-9]+", "-", name).strip("-") or "account"


def unique_id(provider: str, slug: str, taken: set) -> str:
    candidate, number = f"{provider}-{slug}", 2
    while candidate in taken:
        candidate = f"{provider}-{slug}-{number}"
        number += 1
    taken.add(candidate)
    return candidate


def read_extra_dirs(path: Path) -> dict:
    """Folders listed by hand in accounts.json: {"claude": [...], "codex": [...]}. A missing or broken file
    lists none."""
    data = read_json_file(path)
    extra = {"claude": [], "codex": []}
    if isinstance(data, dict):
        for provider in extra:
            items = data.get(provider)
            if isinstance(items, list):
                extra[provider] = [item for item in items if isinstance(item, str) and item.strip()]
    return extra


def listed_folders(entries) -> list:
    """The folders from accounts.json. ~ is the home folder. Only absolute folders that exist are used."""
    folders = []
    for entry in entries:
        expanded = os.path.expanduser(entry.strip())
        if os.path.isabs(expanded) and os.path.isdir(expanded):
            folders.append(Path(os.path.normpath(expanded)))
    return folders


def number_default_labels(sources) -> None:
    """A provider with one account keeps its plain label (Claude). With two or more, each account gets a number in
    discovery order (Claude 1, Claude 2). Call it on the accounts that answered, so a logged-out folder is not counted."""
    for provider in PROVIDER_RANK:
        group = [source for source in sources if source.provider == provider]
        for number, source in enumerate(group, 1):
            source.default_label = (f"{PROVIDER_LABEL[provider]} {number}" if len(group) > 1
                                    else PROVIDER_LABEL[provider])


def claude_main_found(paths: Paths) -> bool:
    """The default Claude folder counts when Claude Code has written its config (~/.claude.json, or
    ~/.claude/.claude.json) or its projects folder. No Keychain item is read."""
    main = paths.home / ".claude"
    return ((paths.home / ".claude.json").is_file() or (main / ".claude.json").is_file()
            or (main / "projects").is_dir())


def claude_folder_found(folder: Path) -> bool:
    """A config folder counts when it holds .claude.json or projects/, as Claude Code leaves them. No Keychain item is read."""
    return (folder / ".claude.json").is_file() or (folder / "projects").is_dir()


def discover_sources(env: Env) -> list:
    """Every account that may have a login on this Mac, in discovery order: Claude (~/.claude first), then Codex
    (~/.codex first), then agy. Claude folders are found by their files, Codex by its auth.json, and agy by its
    Keychain item (presence only, never the password). Whether a Claude login is really there is decided by the
    CLI when the account is collected: an account that is not logged in is left out of usage.json."""
    paths = env.paths
    extra = read_extra_dirs(paths.accounts_file)
    taken = set(MAIN_IDS.values())
    sources = []

    main_claude = paths.home / ".claude"
    if claude_main_found(paths):
        sources.append(default_source("claude", paths))
    claude_folders = [folder for folder in glob_dirs(paths.home, ".claude-*") if claude_folder_found(folder)]
    claude_folders += [folder for folder in listed_folders(extra["claude"]) if claude_folder_found(folder)]
    for folder in unique_paths(claude_folders):
        if folder == main_claude:
            continue  # the default folder is added above
        sources.append(Source(
            id=unique_id("claude", slug_for(folder, "claude"), taken), provider="claude",
            source=f"Claude Code ({display_dir(folder, paths.home)})", config_dir=folder,
            projects_dir=folder / "projects", cli_env={"CLAUDE_CONFIG_DIR": str(folder)},
            default_label=PROVIDER_LABEL["claude"]))

    main_codex = paths.home / ".codex"
    if paths.codex_auth.exists():
        sources.append(default_source("codex", paths))
    codex_folders = [folder for folder in glob_dirs(paths.home, ".codex-*") if (folder / "auth.json").exists()]
    codex_folders += [folder for folder in listed_folders(extra["codex"]) if (folder / "auth.json").exists()]
    for folder in unique_paths(codex_folders):
        if folder == main_codex:
            continue  # the default folder is added above
        sources.append(Source(
            id=unique_id("codex", slug_for(folder, "codex"), taken), provider="codex",
            source=f"Codex ({display_dir(folder, paths.home)})", config_dir=folder,
            auth_file=folder / "auth.json", sessions_dir=folder / "sessions",
            cli_env={"CODEX_HOME": str(folder)}, default_label=PROVIDER_LABEL["codex"]))

    if env.keychain.exists(AGY_KEYCHAIN_SERVICE, AGY_KEYCHAIN_ACCOUNT):
        sources.append(default_source("agy", paths))
    return sources


def account_cache(env: Env, provider: str, source: "Source") -> dict:
    """The token-log cache of one account, so that one account's refresh never clears another account's."""
    store = env.cache.setdefault(provider, {})
    if not isinstance(store.get(source.id), dict):
        store[source.id] = {}
    return store[source.id]


def prune_cache(cache: dict, sources) -> None:
    """Drops the token-log cache of accounts that are no longer found."""
    keep = {source.id for source in sources}
    for name in ("claude", "codex"):
        store = cache.get(name)
        if isinstance(store, dict):
            for key in [key for key in store if key not in keep]:
                del store[key]


def local_usage_or_none(env: Env, source: "Source"):
    """Token totals from the account's local logs. They are read on every run, even when the API call fails."""
    local = LOCAL_USAGE[source.provider]
    if local is None:
        return None
    try:
        return local(env, source)
    except Exception as error:  # noqa: BLE001 - a broken log must not stop the account
        log(f"{source.id}: อ่านบันทึกการใช้งานในเครื่องไม่สำเร็จ: {type(error).__name__}")
        return None


def carried_limits(provider: str, limits):
    """Limits kept from the previous run. A file written before window_seconds existed gets the length
    filled in from the key wherever the key fixes it."""
    return [dict(limit, window_seconds=limit.get(
                "window_seconds", window_seconds_for(provider, str(limit.get("key", "")))))
            for limit in limits if isinstance(limit, dict)]


def collect_account(env: Env, source: "Source", previous):
    """Limits come from the provider when it answers. When it fails they fall back to the previous run
    (status stale) if there is one, otherwise status error with no limits. Token usage always comes
    from the local logs, so it stays current even when the provider call fails. Returns None when the
    provider has no login on this Mac: the account is then left out of usage.json. error_code says
    why an account failed; it is null when the account is ok."""
    account_id, provider = source.id, source.provider
    usage = local_usage_or_none(env, source)
    try:
        data = FETCHERS[provider](env, source)
        return {"id": account_id, "provider": provider, "label": source.default_label,
                "plan": data.get("plan"), "status": "ok", "error": None, "error_code": None,
                "updated_at": iso_z(env.now), "limits": data["limits"], "usage": usage,
                "credits": data.get("credits")}
    except NotLoggedIn as error:
        note = str(error)
        log(f"{account_id}: ไม่มีการล็อกอิน ข้ามบัญชีนี้" + (f" ({note})" if note else ""))
        return None  # no login on this Mac: the account is left out of usage.json
    except FetchError as error:
        message, code, detail = str(error), error.code, error.detail
    except Exception as error:  # noqa: BLE001 - one provider must not stop the others
        log(f"{account_id}: ข้อผิดพลาดภายใน {type(error).__name__}")
        message, code, detail = MSG_GENERIC, ERROR_UNKNOWN, ""
    log(f"{account_id}: {message}" + (f" ({detail})" if detail else ""))
    result = {"id": account_id, "provider": provider, "label": source.default_label, "plan": None,
              "status": "error", "error": scrub(message), "error_code": code,
              "updated_at": None, "limits": [], "usage": usage, "credits": None}
    if isinstance(previous, dict):
        result["plan"] = previous.get("plan")
        if previous.get("updated_at") and previous.get("status") in ("ok", "stale") \
                and isinstance(previous.get("limits"), list):
            result.update({"status": "stale", "updated_at": previous.get("updated_at"),
                           "limits": carried_limits(provider, previous.get("limits")),
                           "credits": previous.get("credits")})
    return result


def account_settings(settings: dict):
    """(sort, per-account settings) from settings.json. A missing key or an unknown value counts as the default."""
    sort = settings.get("sort")
    if sort not in SORT_MODES:
        sort = "manual"
    raw = settings.get("accounts")
    per_account = {}
    if isinstance(raw, dict):
        per_account = {key: value for key, value in raw.items() if isinstance(value, dict)}
    return sort, per_account


def order_accounts(pairs, settings: dict) -> list:
    """The accounts for usage.json: the enabled ones only, in the chosen order, each with its label. pairs holds
    (source, account) in discovery order. A hidden account is still collected, so its login stays fresh, but it is
    not written and it does not alert."""
    sort, per_account = account_settings(settings)
    rows = []
    for index, (source, account) in enumerate(pairs):
        mine = per_account.get(source.id, {})
        if mine.get("enabled") is False:
            continue
        order = mine.get("order")
        if not isinstance(order, int) or isinstance(order, bool):
            order = None
        manual = (0, order, index) if order is not None else (1, 0, index)  # no order: after the ordered ones
        nickname = mine.get("label")
        nickname = nickname.strip() if isinstance(nickname, str) else ""
        account["label"] = nickname or source.default_label
        limits = account.get("limits") or []
        remaining = (100.0 - max(limit["used_percent"] for limit in limits)) if limits else None
        rows.append((source, account, manual, remaining))
    if sort == "lowest":  # the smallest quota left first; accounts with no limits last; ties keep the manual order
        rows.sort(key=lambda row: (row[3] is None, row[3] or 0.0, row[2]))
    elif sort == "provider":
        rows.sort(key=lambda row: (PROVIDER_RANK[row[0].provider], row[2]))
    else:
        rows.sort(key=lambda row: row[2])
    return [row[1] for row in rows]


def write_known_accounts(paths: Paths, sources, now: datetime) -> None:
    """known-accounts.json: the accounts with a login found in this run, each with the time it was first seen. An
    account keeps its first_seen while it stays found; an account that is no longer found is dropped from the file."""
    previous = read_json_file(paths.known_file)
    first_seen = {}
    if isinstance(previous, dict) and isinstance(previous.get("accounts"), list):
        for item in previous["accounts"]:
            if isinstance(item, dict) and isinstance(item.get("id"), str):
                first_seen[item["id"]] = item.get("first_seen")
    accounts = []
    for source in sources:
        kept = first_seen.get(source.id)
        accounts.append({"id": source.id, "provider": source.provider, "source": scrub(source.source),
                         "first_seen": kept if isinstance(kept, str) and parse_time(kept) else iso_z(now)})
    data = serialize({"schema": SCHEMA, "accounts": accounts})
    try:
        if paths.known_file.read_bytes() == data:
            return
    except OSError:
        pass
    try:
        paths.known_file.parent.mkdir(parents=True, exist_ok=True)
        atomic_write(paths.known_file, data)
    except OSError as error:
        log(f"บันทึก known-accounts.json ไม่สำเร็จ: {type(error).__name__}")


def build_document(now: datetime, accounts) -> dict:
    return {"schema": SCHEMA, "generated_at": iso_z(now), "accounts": accounts,
            "model_prices": model_prices()}


def serialize(doc) -> bytes:
    return (json.dumps(doc, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def load_previous(path: Path):
    doc = read_json_file(path)
    accounts = doc.get("accounts") if isinstance(doc, dict) else None
    if not isinstance(accounts, list):
        return {}
    return {account["id"]: account for account in accounts
            if isinstance(account, dict) and isinstance(account.get("id"), str)}


def load_cache(path: Path):
    data = read_json_file(path)
    if not isinstance(data, dict) or data.get("version") != CACHE_VERSION:
        data = {}
    data["version"] = CACHE_VERSION
    for name in ("claude", "codex"):
        if not isinstance(data.get(name), dict):
            data[name] = {}
    return data


def save_cache(path: Path, cache) -> None:
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        atomic_write(path, json.dumps(cache, separators=(",", ":")).encode("utf-8"))
    except OSError as error:
        log(f"บันทึก cache ไม่สำเร็จ: {type(error).__name__}")


def minute_key(resets_at) -> str:
    """resets_at rounded to the nearest minute, so a few seconds of jitter does not re-notify."""
    moment = parse_time(resets_at)
    if moment is None:
        return ""
    return iso_z((moment + timedelta(seconds=30)).replace(second=0, microsecond=0))


def read_settings(path: Path) -> dict:
    """The Mac app's settings.json. A missing or broken file reads as {}, so every setting takes its default."""
    data = read_json_file(path)
    return data if isinstance(data, dict) else {}


def direct_modes(settings: dict) -> dict:
    """The providers in direct mode, from settings.json "direct_mode". Only the JSON value true turns one on.
    Claude is not listed: it has no direct mode."""
    raw = settings.get("direct_mode")
    if not isinstance(raw, dict):
        return {}
    return {provider: True for provider in DIRECT_PROVIDERS if raw.get(provider) is True}


def notify_enabled(settings: dict) -> bool:
    """The app's notification switch. Only the JSON value false turns notifications off. A missing key or any
    other value counts as on."""
    return settings.get("notify") is not False


def preferred_languages(home: Path) -> list:
    """The user's preferred languages in order: the AppleLanguages list of the global defaults. The Mac app
    reads the same list through Locale.preferredLanguages."""
    try:
        with open(home / "Library" / "Preferences" / ".GlobalPreferences.plist", "rb") as handle:
            data = plistlib.load(handle)
    except (OSError, ValueError):
        return []
    languages = data.get("AppleLanguages") if isinstance(data, dict) else None
    if not isinstance(languages, list):
        return []
    return [item for item in languages if isinstance(item, str)]


def notification_language(settings: dict, home: Path) -> str:
    """"th" or "en". "system", a missing value and any unknown value follow the first preferred language:
    Thai when it starts with th, English otherwise, as the Mac app does."""
    choice = settings.get("language")
    if choice in ("th", "en"):
        return choice
    preferred = preferred_languages(home)
    return "th" if preferred and preferred[0].lower().startswith("th") else "en"


def window_english(seconds: int) -> str:
    if seconds == 18000:
        return "5h"
    if seconds == 604800:
        return "Week"
    if seconds % 86400 == 0:
        return f"{seconds // 86400}d"
    if seconds % 3600 == 0:
        return f"{seconds // 3600}h"
    return f"{round(seconds / 60)}m"


def english_limit_label(limit: dict) -> str:
    """The limit label in English, built from window_seconds and key the way readers build it. A limit without
    a length (an agy model group) keeps its own name, which is the same in both languages."""
    seconds = limit.get("window_seconds")
    if not isinstance(seconds, int) or seconds <= 0:
        return str(limit.get("label", ""))
    label = window_english(seconds)
    key = str(limit.get("key", ""))
    if key.endswith("_opus"):
        return f"{label} (Opus)"
    if key.endswith("_sonnet"):
        return f"{label} (Sonnet)"
    return label


def notification_text(language: str, account: dict, limit: dict, threshold: int, used: float):
    """(title, text) of one alert. threshold is 80 or 95."""
    percent = f"{used:.0f}%"
    if language == "th":
        title = "Quota Battery"
        if threshold >= 95:
            return title, f"{account['label']} · {limit['label']} ใกล้เต็มแล้ว {percent}"
        return title, f"{account['label']} · {limit['label']} ใช้ไปแล้ว {percent}"
    label = english_limit_label(limit)
    if threshold >= 95:
        return "Quota Battery", f"{account['label']} · {label} near limit, {percent} used"
    return "Quota Battery", f"{account['label']} · {label} used {percent}"


def notify_pass(env: Env, accounts, notify_file: Path, language: str = "en", send: bool = True) -> None:
    """Alerts at 80% and 95%, once per window. With send False (the app's switch is off, or --no-notify) nothing
    is sent, but the crossings are still recorded, so turning the switch back on does not send old alerts."""
    state = read_json_file(notify_file)
    if not isinstance(state, dict):
        state = {}
    changed = False
    for account in accounts:
        if account["status"] != "ok":
            continue  # stale or error data never triggers a notification
        for limit in account["limits"]:
            used = limit["used_percent"]
            key = f"{account['id']}|{limit['key']}|{minute_key(limit['resets_at'])}"
            record = state.get(key) if isinstance(state.get(key), dict) else {}
            sent = {int(value) for value in record.get("sent", [])
                    if isinstance(value, (int, float))}
            crossed = [level for level in NOTIFY_THRESHOLDS if used >= level and level not in sent]
            if not crossed:
                continue
            if not send:
                state[key] = {"sent": sorted(sent | set(crossed)), "seen": iso_z(env.now)}
                changed = True
                continue
            title, text = notification_text(language, account, limit, max(crossed), used)
            if env.notify(title, text):
                # One notification for the highest level reached; the lower ones count as sent.
                state[key] = {"sent": sorted(sent | set(crossed)), "seen": iso_z(env.now)}
                changed = True
            else:
                log("ส่งการแจ้งเตือนไม่สำเร็จ จะลองใหม่รอบถัดไป")
    cutoff = env.now - timedelta(days=NOTIFY_KEEP_DAYS)
    for key in list(state):
        record = state[key]
        seen = parse_time(record.get("seen")) if isinstance(record, dict) else None
        if seen is None or seen < cutoff:
            del state[key]
            changed = True
    if changed:
        try:
            notify_file.parent.mkdir(parents=True, exist_ok=True)
            atomic_write(notify_file, json.dumps(state, ensure_ascii=False).encode("utf-8"))
        except OSError as error:
            log(f"บันทึกสถานะการแจ้งเตือนไม่สำเร็จ: {type(error).__name__}")


def try_lock(path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    handle = open(path, "a+")
    try:
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        handle.close()
        return None
    return handle


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="Collect AI usage and write usage.json")
    parser.add_argument("--dry-run", action="store_true",
                        help="print the JSON to stdout; write nothing, notify nothing, renew no token")
    parser.add_argument("--no-refresh", action="store_true",
                        help="never renew a token (direct mode: agy's own renewal)")
    parser.add_argument("--no-notify", action="store_true",
                        help="send no macOS notifications; the 80%% and 95%% crossings are still recorded")
    parser.add_argument("--state-dir", help="folder for cache.json, notify-state.json and the run lock")
    args = parser.parse_args(argv)

    paths = Paths(Path.home(), args.state_dir)
    now = datetime.now(timezone.utc)
    lock = None
    if not args.dry_run:
        paths.state_dir.mkdir(parents=True, exist_ok=True)
        lock = try_lock(paths.run_lock)
        if lock is None:
            log("รอบก่อนยังทำงานอยู่ ข้ามรอบนี้")
            return 0
    try:
        cache = load_cache(paths.cache_file)
        settings = read_settings(paths.settings_file)
        # A dry run is read-only everywhere, so it never renews a token either.
        env = Env(paths, now, allow_refresh=not (args.no_refresh or args.dry_run), cache=cache,
                  direct=direct_modes(settings))
        previous = load_previous(paths.usage_mac)
        sources = discover_sources(env)
        prune_cache(cache, sources)
        pairs = []
        for source in sources:
            account = collect_account(env, source, previous.get(source.id))
            if account is not None:  # None: no login on this Mac (or it was removed while the run was going)
                pairs.append((source, account))
        number_default_labels([source for source, _ in pairs])
        accounts = order_accounts(pairs, settings)
        data = serialize(build_document(now, accounts))
        if args.dry_run:
            sys.stdout.write(data.decode("utf-8"))
            if args.state_dir:
                save_cache(paths.cache_file, cache)
            return 0
        paths.app_dir.mkdir(parents=True, exist_ok=True)
        atomic_write(paths.usage_mac, data)
        if paths.usage_icloud.parent.is_dir():
            try:
                atomic_write(paths.usage_icloud, data)
            except OSError as error:
                log(f"เขียนสำเนา iCloud ไม่สำเร็จ: {type(error).__name__}")
        else:
            log("ไม่พบโฟลเดอร์ iCloud ของ Scriptable ข้ามสำเนาสำหรับ iPhone")
        write_known_accounts(paths, [source for source, _ in pairs], now)
        notify_pass(env, accounts, paths.notify_file,
                    language=notification_language(settings, paths.home),
                    send=not args.no_notify and notify_enabled(settings))
        save_cache(paths.cache_file, cache)
        return 0
    finally:
        if lock is not None:
            lock.close()


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:  # noqa: BLE001 - last resort, class name only
        log(f"หยุดการทำงานด้วยข้อผิดพลาด {type(error).__name__}")
        sys.exit(1)
