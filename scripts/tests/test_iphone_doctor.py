"""Unit tests for scripts/iphone-doctor.py. Standard library only, no phone needed.

pymobiledevice3 is replaced by fake modules in sys.modules, so the script's own adapter code runs
and each test can see the library calls the script made. Writes go only to temporary folders: the
real home folder, the real iCloud Drive and the real phone are never touched.

Run from the repository root:
    python3 -m unittest discover -s scripts/tests -v
"""

import asyncio
import contextlib
import hashlib
import importlib.metadata  # imported up front so sys.modules patching never drops it
import importlib.util
import io
import json
import os
import sys
import tempfile
import time
import types
import unittest
from pathlib import Path
from unittest import mock

SCRIPT_PATH = Path(__file__).resolve().parent.parent / "iphone-doctor.py"
_spec = importlib.util.spec_from_file_location("iphone_doctor", SCRIPT_PATH)
doctor = importlib.util.module_from_spec(_spec)
sys.modules["iphone_doctor"] = doctor
_spec.loader.exec_module(doctor)

SCRIPT = doctor.SCRIPT_NAME
REPO_BYTES = doctor.REPO_SCRIPT.read_bytes()
REPO_SHA = doctor.sha256_hex(REPO_BYTES)
OLD_BYTES = b"// an older copy of AI Usage.js\n"
UDID = "00008101-001A2B3C4D5E6F70"  # a fake UDID for these tests
APPS = {doctor.SCRIPTABLE_BUNDLE_ID: {"CFBundleShortVersionString": "2.1.0"}}
PAIR_METHODS = ("pair", "pair_supervised", "pair_cu", "unpair", "save_pair_record", "set_value", "remove_value")
WRITE_METHODS_ON_PHONE = ("push", "rm", "rm_single", "makedirs", "fopen")


def named_error(name):
    """An exception class whose __name__ is the library name, which is what the script matches on."""
    return type(name, (Exception,), {})


NotPairedError = named_error("NotPairedError")
PasswordRequiredError = named_error("PasswordRequiredError")
DeviceNotFoundError = named_error("DeviceNotFoundError")


def forbidden(question):
    raise AssertionError(f"must not ask: {question}")


def make_device(serial=UDID, connection_type="USB"):
    return types.SimpleNamespace(serial=serial, connection_type=connection_type, devid=1)


def make_lockdown(paired=True):
    lockdown = types.SimpleNamespace(paired=paired, udid=UDID, product_version="27.2.1", product_type="iPhone99,1")
    for name in PAIR_METHODS + ("close",):
        setattr(lockdown, name, mock.AsyncMock())
    return lockdown


class FakePhoneDocuments:
    """Scriptable's Documents as seen through house_arrest: a map of file name to bytes."""

    def __init__(self, files=None):
        self.files = dict(files or {})
        self.listdir = mock.AsyncMock(side_effect=self._listdir)
        self.get_file_contents = mock.AsyncMock(side_effect=self._read)
        self.push = mock.AsyncMock(side_effect=self._push)
        self.close = mock.AsyncMock()
        for name in ("rm", "rm_single", "makedirs", "fopen"):
            setattr(self, name, mock.AsyncMock())

    async def _listdir(self, path):
        assert path == "/", path
        return sorted(self.files)

    async def _read(self, path):
        return self.files[path.lstrip("/")]

    async def _push(self, local_path, remote_path, progress_bar=True):
        with open(local_path, "rb") as handle:
            self.files[remote_path.lstrip("/")] = handle.read()


@contextlib.contextmanager
def fake_library(
    *,
    devices=(),
    lockdown=None,
    connect_error=None,
    usbmux_error=None,
    usbmux_delay=None,
    apps=None,
    documents=None,
    documents_error=None,
):
    package = types.ModuleType("pymobiledevice3")
    usbmux_mod = types.ModuleType("pymobiledevice3.usbmux")
    if usbmux_delay is not None:

        async def slow_list(*_args, **_kwargs):
            await asyncio.sleep(usbmux_delay)
            return []

        usbmux_mod.list_devices = mock.AsyncMock(side_effect=slow_list)
    elif usbmux_error is not None:
        usbmux_mod.list_devices = mock.AsyncMock(side_effect=usbmux_error)
    else:
        usbmux_mod.list_devices = mock.AsyncMock(return_value=list(devices))

    lockdown_mod = types.ModuleType("pymobiledevice3.lockdown")
    if connect_error is not None:
        lockdown_mod.create_using_usbmux = mock.AsyncMock(side_effect=connect_error)
    else:
        lockdown_mod.create_using_usbmux = mock.AsyncMock(return_value=lockdown)

    services = types.ModuleType("pymobiledevice3.services")
    proxy_mod = types.ModuleType("pymobiledevice3.services.installation_proxy")
    proxy = mock.MagicMock(name="InstallationProxyService()")
    proxy.get_apps = mock.AsyncMock(return_value=dict(apps or {}))
    proxy_mod.InstallationProxyService = mock.MagicMock(name="InstallationProxyService", return_value=proxy)

    house_mod = types.ModuleType("pymobiledevice3.services.house_arrest")
    house = mock.MagicMock(name="HouseArrestService")
    if documents_error is not None:
        house.create = mock.AsyncMock(side_effect=documents_error)
    else:
        house.create = mock.AsyncMock(return_value=documents)
    house_mod.HouseArrestService = house

    package.usbmux = usbmux_mod
    package.lockdown = lockdown_mod
    package.services = services
    services.installation_proxy = proxy_mod
    services.house_arrest = house_mod
    modules = {
        "pymobiledevice3": package,
        "pymobiledevice3.usbmux": usbmux_mod,
        "pymobiledevice3.lockdown": lockdown_mod,
        "pymobiledevice3.services": services,
        "pymobiledevice3.services.installation_proxy": proxy_mod,
        "pymobiledevice3.services.house_arrest": house_mod,
    }
    with mock.patch.dict(sys.modules, modules):
        yield types.SimpleNamespace(
            usbmux=usbmux_mod,
            lockdown=lockdown_mod,
            proxy=proxy,
            proxy_cls=proxy_mod.InstallationProxyService,
            house=house,
        )


def make_ctx(home, *, os_name="macos", icloud_dir="default", now=None, udid=None, backup_root=None):
    icloud = doctor.default_icloud_dir(os_name, home) if icloud_dir == "default" else icloud_dir
    return doctor.Context(
        os_name=os_name,
        home=home,
        icloud_dir=icloud,
        udid=udid,
        repo_sha=REPO_SHA,
        now=time.time() if now is None else now,
        backup_root=backup_root or home / "AIUsage-backups",
    )


def write_icloud(folder, *, script=None, data=None, data_age_seconds=0):
    folder.mkdir(parents=True, exist_ok=True)
    if script is not None:
        (folder / SCRIPT).write_bytes(script)
    if data is not None:
        path = folder / doctor.DATA_NAME
        path.write_bytes(data)
        stamp = time.time() - data_age_seconds
        os.utime(path, (stamp, stamp))


def statuses(report):
    return {check.id: check for check in report.checks}


def run_device(ctx, report, *, write=False, dry=False, ask=None):
    asyncio.run(doctor.device_part(ctx, report, write=write, dry=dry, ask=ask))


def run_main(argv, **kwargs):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        code = doctor.main(argv, **kwargs)
    return code, out.getvalue(), err.getvalue()


class TempHomeMixin:
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.home = Path(tmp.name)
        self.backup_root = self.home / "AIUsage-backups"
        self.icloud = self.home / "icloud-scriptable"


class PureHelperTests(unittest.TestCase):
    def test_mask_udid_keeps_only_the_edges(self):
        masked = doctor.mask_udid(UDID)
        self.assertEqual(masked, "0000...6F70")
        self.assertNotIn("8101", masked)
        self.assertNotIn("001A2B3C", masked)

    def test_mask_udid_hides_short_or_missing_values(self):
        self.assertEqual(doctor.mask_udid(None), "...")
        self.assertEqual(doctor.mask_udid(""), "...")
        self.assertEqual(doctor.mask_udid("ABC123"), "...")

    def test_same_udid_ignores_dashes_and_case(self):
        self.assertTrue(doctor.same_udid(UDID, "00008101001a2b3c4d5e6f70"))
        self.assertFalse(doctor.same_udid(UDID, "00008101-001A2B3C4D5E6F71"))

    def test_sha256_matches_hashlib(self):
        self.assertEqual(doctor.sha256_hex(b"abc"), hashlib.sha256(b"abc").hexdigest())

    def test_display_path_shortens_only_paths_under_home(self):
        home = Path("/Users/example")
        self.assertEqual(doctor.display_path(home / "Library" / "x", home), "~/Library/x")
        self.assertEqual(doctor.display_path(Path("/tmp/elsewhere"), home), "/tmp/elsewhere")

    def test_icloud_folder_is_known_only_on_macos(self):
        home = Path("/Users/example")
        self.assertEqual(
            doctor.default_icloud_dir("macos", home),
            home / "Library" / "Mobile Documents" / "iCloud~dk~simonbs~Scriptable" / "Documents",
        )
        self.assertIsNone(doctor.default_icloud_dir("windows", home))
        self.assertIsNone(doctor.default_icloud_dir("other", home))

    def test_backup_root_depends_on_the_os(self):
        home = Path("/Users/example")
        self.assertEqual(
            doctor.default_backup_root("macos", home),
            home / "Library" / "Application Support" / "AIUsage" / "iphone-doctor-backups",
        )
        with mock.patch.dict(os.environ, {"APPDATA": "C:/Users/x/AppData/Roaming"}):
            root = doctor.default_backup_root("windows", Path("C:/Users/x"))
        self.assertEqual(root.name, "iphone-doctor-backups")
        self.assertEqual(root.parent.name, "AIUsage")

    def test_python_version_gate(self):
        old = doctor.python_check((3, 8, 18, "final", 0))
        self.assertEqual(old.status, "fail")
        self.assertTrue(old.needs_user)
        self.assertEqual(doctor.python_check((3, 9, 0, "final", 0)).status, "ok")
        self.assertEqual(doctor.python_check((3, 15, 2, "final", 0)).status, "ok")

    def test_render_check_shows_the_fix_only_when_not_ok(self):
        self.assertEqual(doctor.render_check(doctor.Check("a", "ok", "fine", fix="ignored")), "[ผ่าน] fine")
        bad = doctor.render_check(doctor.Check("b", "fail", "bad", fix="do this"))
        self.assertIn("[ไม่ผ่าน] bad", bad)
        self.assertIn("ทำต่อ: do this", bad)

    def test_repo_script_is_where_the_tool_expects_it(self):
        self.assertTrue(doctor.REPO_SCRIPT.is_file())
        self.assertEqual(doctor.REPO_SCRIPT.parent.name, "scriptable")

    def test_check_exit_codes(self):
        def report_with(*checks):
            report = doctor.Report(command="check")
            report.checks = list(checks)
            return report

        ok = doctor.Check("a", "ok", "fine")
        warn = doctor.Check("b", "warn", "meh")
        stale = doctor.Check("c", "warn", "old", needs_user=True)
        fixable = doctor.Check("d", "fail", "differs")
        user = doctor.Check("e", "fail", "unplugged", needs_user=True)
        self.assertEqual(doctor.check_exit_code(report_with(ok, warn)), 0)
        self.assertEqual(doctor.check_exit_code(report_with(ok, fixable)), 2)
        self.assertEqual(doctor.check_exit_code(report_with(fixable, user)), 1)
        self.assertEqual(doctor.check_exit_code(report_with(stale)), 1)
        broken = report_with(ok)
        broken.tool_error = "boom"
        self.assertEqual(doctor.check_exit_code(broken), 3)

    def test_repair_exit_codes(self):
        def repair(statuses_=(), checks=()):
            report = doctor.Report(command="repair")
            report.actions = [{"route": "icloud", "status": s, "message": ""} for s in statuses_]
            report.checks = list(checks)
            return report

        self.assertEqual(doctor.repair_exit_code(repair(["planned"])), 2)
        self.assertEqual(doctor.repair_exit_code(repair(["done"])), 0)
        self.assertEqual(doctor.repair_exit_code(repair(["declined"])), 1)
        self.assertEqual(doctor.repair_exit_code(repair(["done", "failed"])), 3)
        self.assertEqual(doctor.repair_exit_code(repair([], [doctor.Check("x", "fail", "y", needs_user=True)])), 1)


class AskTests(unittest.TestCase):
    def test_only_y_or_yes_counts_as_yes(self):
        cases = [("y\n", True), ("Y\n", True), ("yes\n", True), ("n\n", False), ("\n", False), ("", False), ("maybe\n", False)]
        for text, expected in cases:
            with self.subTest(text=text), mock.patch.object(sys, "stdin", io.StringIO(text)), contextlib.redirect_stderr(io.StringIO()):
                self.assertIs(doctor.ask_yes_no("ok? [y/N]: "), expected)


class HostCheckTests(unittest.TestCase):
    def test_missing_library_gives_the_mac_install_hint(self):
        with mock.patch.dict(sys.modules, {"pymobiledevice3": None}):
            check, ok = doctor.library_check("macos")
        self.assertFalse(ok)
        self.assertEqual(check.status, "fail")
        self.assertTrue(check.needs_user)
        self.assertIn("python3 -m pip install pymobiledevice3", check.fix)
        self.assertNotIn("iTunes", check.fix)

    def test_missing_library_gives_the_windows_hint_with_the_driver(self):
        with mock.patch.dict(sys.modules, {"pymobiledevice3": None}):
            check, ok = doctor.library_check("windows")
        self.assertFalse(ok)
        self.assertIn("py -m pip install pymobiledevice3", check.fix)
        self.assertIn("iTunes", check.fix)
        self.assertIn("Apple Devices", check.fix)
        self.assertIn("apple.com", check.fix)

    def test_version_note_only_when_not_the_tested_release(self):
        with mock.patch.object(doctor, "library_status", return_value=(True, "11.60.0", "")):
            check, ok = doctor.library_check("macos")
        self.assertTrue(ok)
        self.assertEqual(check.status, "ok")
        self.assertNotIn("ทดสอบแล้วกับ", check.message)
        with mock.patch.object(doctor, "library_status", return_value=(True, "10.1.0", "")):
            check, _ = doctor.library_check("macos")
        self.assertIn("ทดสอบแล้วกับ 11.60.0", check.message)


class ICloudCheckTests(TempHomeMixin, unittest.TestCase):
    def run_icloud(self, ctx, *, write=False, dry=False, ask=None):
        report = doctor.Report(command="repair" if write else "check")
        doctor.icloud_part(ctx, report, write=write, dry=dry, ask=ask or forbidden)
        return report

    def setUp(self):
        super().setUp()
        self.folder = self.home.joinpath(*doctor.ICLOUD_PARTS)

    def test_missing_folder_is_a_user_step_and_is_never_created(self):
        report = self.run_icloud(make_ctx(self.home))
        check = statuses(report)["icloud_folder"]
        self.assertEqual(check.status, "fail")
        self.assertTrue(check.needs_user)
        self.assertFalse(self.folder.exists())
        self.assertIsNone(report.icloud_state)

    def test_missing_script_is_repairable_and_missing_data_needs_the_mac(self):
        write_icloud(self.folder)
        report = self.run_icloud(make_ctx(self.home))
        script = statuses(report)["script_on_icloud"]
        self.assertEqual((script.status, script.needs_user), ("fail", False))
        self.assertEqual(report.icloud_state, "missing")
        data = statuses(report)["data_file_icloud"]
        self.assertEqual((data.status, data.needs_user), ("warn", True))

    def test_older_script_is_repairable(self):
        write_icloud(self.folder, script=OLD_BYTES, data=b"{}")
        report = self.run_icloud(make_ctx(self.home))
        script = statuses(report)["script_on_icloud"]
        self.assertEqual((script.status, script.needs_user), ("fail", False))
        self.assertEqual(report.icloud_state, "different")

    def test_current_script_and_fresh_data_are_ok(self):
        write_icloud(self.folder, script=REPO_BYTES, data=b"{}", data_age_seconds=60)
        report = self.run_icloud(make_ctx(self.home))
        self.assertEqual(statuses(report)["script_on_icloud"].status, "ok")
        self.assertEqual(statuses(report)["data_file_icloud"].status, "ok")
        self.assertEqual(doctor.check_exit_code(report), 0)

    def test_stale_data_file_needs_the_mac_to_be_on(self):
        write_icloud(self.folder, script=REPO_BYTES, data=b"{}", data_age_seconds=60 * 60)
        report = self.run_icloud(make_ctx(self.home))
        data = statuses(report)["data_file_icloud"]
        self.assertEqual((data.status, data.needs_user), ("warn", True))
        self.assertIn("60 นาที", data.message)

    def test_unknown_icloud_path_on_windows_is_a_warning_only(self):
        report = self.run_icloud(make_ctx(self.home, os_name="windows"))
        check = statuses(report)["icloud_folder"]
        self.assertEqual((check.status, check.needs_user), ("warn", False))
        self.assertIsNone(report.icloud_state)

    def test_copy_after_yes_backs_up_the_old_file_and_checks_the_hash(self):
        write_icloud(self.folder, script=OLD_BYTES, data=b"{}")
        ctx = make_ctx(self.home, backup_root=self.backup_root)
        questions = []

        def ask(question):
            questions.append(question)
            return True

        report = self.run_icloud(ctx, write=True, ask=ask)
        self.assertEqual((self.folder / SCRIPT).read_bytes(), REPO_BYTES)
        backups = list(self.backup_root.rglob(SCRIPT))
        self.assertEqual([path.read_bytes() for path in backups], [OLD_BYTES])
        self.assertEqual([action["status"] for action in report.actions], ["done"])
        self.assertEqual(len(questions), 1)
        self.assertIn("[y/N]", questions[0])

    def test_declined_copy_changes_nothing(self):
        write_icloud(self.folder, script=OLD_BYTES, data=b"{}")
        ctx = make_ctx(self.home, backup_root=self.backup_root)
        report = self.run_icloud(ctx, write=True, ask=lambda question: False)
        self.assertEqual((self.folder / SCRIPT).read_bytes(), OLD_BYTES)
        self.assertFalse(self.backup_root.exists())
        self.assertEqual([action["status"] for action in report.actions], ["declined"])

    def test_dry_run_plans_but_never_asks_or_writes(self):
        write_icloud(self.folder, script=OLD_BYTES, data=b"{}")
        ctx = make_ctx(self.home, backup_root=self.backup_root)
        report = self.run_icloud(ctx, write=True, dry=True, ask=forbidden)
        self.assertEqual((self.folder / SCRIPT).read_bytes(), OLD_BYTES)
        self.assertFalse(self.backup_root.exists())
        self.assertEqual([action["status"] for action in report.actions], ["planned"])

    def test_check_never_asks_or_writes(self):
        write_icloud(self.folder, script=OLD_BYTES, data=b"{}")
        report = self.run_icloud(make_ctx(self.home, backup_root=self.backup_root))
        self.assertEqual((self.folder / SCRIPT).read_bytes(), OLD_BYTES)
        self.assertEqual(report.actions, [])

    def test_backup_names_never_collide(self):
        ctx = make_ctx(self.home, now=1_700_000_000, backup_root=self.backup_root)
        first = doctor.backup_file(b"a", "icloud", ctx)
        second = doctor.backup_file(b"b", "icloud", ctx)
        self.assertNotEqual(first, second)
        self.assertEqual((first.read_bytes(), second.read_bytes()), (b"a", b"b"))


class DeviceCheckTests(TempHomeMixin, unittest.TestCase):
    def setUp(self):
        super().setUp()
        self.ctx = make_ctx(self.home, icloud_dir=None, backup_root=self.backup_root)
        self.report = doctor.Report(command="check")

    def run_checks(self, **kwargs):
        run_device(self.ctx, self.report, **kwargs)
        return statuses(self.report)

    def test_no_usb_device_stops_before_any_connection(self):
        with fake_library(devices=[]) as lib:
            checks = self.run_checks()
        self.assertEqual(checks["device_connected"].status, "fail")
        self.assertTrue(checks["device_connected"].needs_user)
        self.assertEqual(lib.lockdown.create_using_usbmux.await_count, 0)

    def test_network_only_device_does_not_count_as_usb(self):
        with fake_library(devices=[make_device(connection_type="Network")]) as lib:
            checks = self.run_checks()
        self.assertEqual(checks["device_connected"].status, "fail")
        self.assertEqual(lib.lockdown.create_using_usbmux.await_count, 0)

    def test_usbmuxd_not_answering_is_a_user_step(self):
        with fake_library(usbmux_error=ConnectionRefusedError("refused")):
            checks = self.run_checks()
        self.assertEqual(checks["device_connected"].status, "fail")
        self.assertTrue(checks["device_connected"].needs_user)
        self.assertIn("usbmuxd", checks["device_connected"].message)

    def test_usbmuxd_timeout_is_reported(self):
        with mock.patch.object(doctor, "DEVICE_TIMEOUT_SECONDS", 0.05), fake_library(usbmux_delay=1.0):
            checks = self.run_checks()
        self.assertEqual(checks["device_connected"].status, "fail")
        self.assertIn("หมดเวลา", checks["device_connected"].message)

    def test_not_trusted_asks_the_user_and_never_pairs(self):
        lockdown = make_lockdown(paired=False)
        with fake_library(devices=[make_device()], lockdown=lockdown) as lib:
            checks = self.run_checks()
        self.assertEqual(checks["device_trusted"].status, "fail")
        self.assertTrue(checks["device_trusted"].needs_user)
        self.assertIn("เชื่อถือ", checks["device_trusted"].fix)
        self.assertIs(lib.lockdown.create_using_usbmux.call_args.kwargs.get("autopair"), False)
        for name in PAIR_METHODS:
            self.assertEqual(getattr(lockdown, name).await_count, 0, name)
        self.assertEqual(lib.proxy.get_apps.await_count, 0)
        self.assertEqual(lib.house.create.await_count, 0)

    def test_trust_error_at_connect_is_reported_as_trust(self):
        with fake_library(devices=[make_device()], connect_error=NotPairedError("no record")):
            checks = self.run_checks()
        self.assertEqual(checks["device_trusted"].status, "fail")
        self.assertTrue(checks["device_trusted"].needs_user)

    def test_locked_phone_is_an_unlock_step_not_a_trust_step(self):
        with fake_library(devices=[make_device()], connect_error=PasswordRequiredError("locked")):
            checks = self.run_checks()
        self.assertEqual(checks["device_connected"].status, "fail")
        self.assertIn("ถูกล็อก", checks["device_connected"].message)
        self.assertNotIn("device_trusted", checks)

    def test_device_gone_at_connect_is_a_user_step(self):
        with fake_library(devices=[make_device()], connect_error=DeviceNotFoundError("gone")):
            checks = self.run_checks()
        self.assertEqual(checks["device_connected"].status, "fail")
        self.assertTrue(checks["device_connected"].needs_user)

    def test_unexpected_connect_error_is_a_tool_error(self):
        with fake_library(devices=[make_device()], connect_error=RuntimeError("bad")):
            with self.assertRaises(doctor.ToolError):
                self.run_checks()

    def test_happy_path_reads_only_and_everything_is_ok(self):
        lockdown = make_lockdown()
        phone = FakePhoneDocuments({SCRIPT: REPO_BYTES, "Other.js": b"x"})
        with fake_library(devices=[make_device()], lockdown=lockdown, apps=APPS, documents=phone) as lib:
            checks = self.run_checks()
        for check_id in (
            "device_connected",
            "device_trusted",
            "ios_version",
            "scriptable_installed",
            "documents_house_arrest",
            "script_on_device",
        ):
            self.assertEqual(checks[check_id].status, "ok", check_id)
        self.assertIn("2.1.0", checks["scriptable_installed"].message)
        self.assertEqual(self.report.device_state, "same")
        self.assertEqual(lib.house.create.call_args.args[1], doctor.SCRIPTABLE_BUNDLE_ID)
        self.assertIs(lib.house.create.call_args.kwargs.get("documents_only"), True)
        phone.listdir.assert_awaited_once_with("/")
        phone.get_file_contents.assert_awaited_once_with("/" + SCRIPT)
        for name in WRITE_METHODS_ON_PHONE:
            self.assertEqual(getattr(phone, name).await_count, 0, name)
        for name in PAIR_METHODS:
            self.assertEqual(getattr(lockdown, name).await_count, 0, name)
        lockdown.close.assert_awaited()
        phone.close.assert_awaited()

    def test_scriptable_missing_stops_before_documents(self):
        with fake_library(devices=[make_device()], lockdown=make_lockdown(), apps={}) as lib:
            checks = self.run_checks()
        self.assertEqual(checks["scriptable_installed"].status, "fail")
        self.assertTrue(checks["scriptable_installed"].needs_user)
        self.assertEqual(lib.house.create.await_count, 0)

    def test_documents_refused_is_a_warning_and_no_write_is_tried(self):
        with fake_library(
            devices=[make_device()],
            lockdown=make_lockdown(),
            apps=APPS,
            documents_error=Exception("ApplicationLookupFailed: no"),
        ):
            checks = self.run_checks(write=True, ask=forbidden)
        self.assertEqual(checks["documents_house_arrest"].status, "warn")
        self.assertFalse(checks["documents_house_arrest"].needs_user)
        self.assertIn("แอปไม่เปิดโฟลเดอร์", checks["documents_house_arrest"].message)
        self.assertNotIn("script_on_device", checks)

    def test_listing_failure_after_opening_is_a_warning_and_the_container_is_closed(self):
        phone = FakePhoneDocuments({SCRIPT: REPO_BYTES})
        phone.listdir.side_effect = RuntimeError("afc went away")
        with fake_library(devices=[make_device()], lockdown=make_lockdown(), apps=APPS, documents=phone):
            checks = self.run_checks(write=True, ask=forbidden)
        self.assertEqual(
            (checks["documents_house_arrest"].status, checks["documents_house_arrest"].needs_user),
            ("warn", False),
        )
        self.assertIsNone(self.report.device_state)
        phone.close.assert_awaited()

    def test_older_script_on_the_phone_is_repairable_and_not_changed_by_check(self):
        phone = FakePhoneDocuments({SCRIPT: OLD_BYTES})
        with fake_library(devices=[make_device()], lockdown=make_lockdown(), apps=APPS, documents=phone):
            checks = self.run_checks()
        self.assertEqual((checks["script_on_device"].status, checks["script_on_device"].needs_user), ("fail", False))
        self.assertEqual(self.report.device_state, "different")
        phone.push.assert_not_awaited()
        self.assertEqual(phone.files[SCRIPT], OLD_BYTES)

    def test_missing_script_on_the_phone_is_only_a_warning(self):
        phone = FakePhoneDocuments({"Other.js": b"x"})
        with fake_library(devices=[make_device()], lockdown=make_lockdown(), apps=APPS, documents=phone):
            checks = self.run_checks()
        self.assertEqual(checks["script_on_device"].status, "warn")
        self.assertEqual(self.report.device_state, "missing")


class RepairTests(TempHomeMixin, unittest.TestCase):
    def run_repair(self, extra_args, *, ask, devices=(), lockdown=None, phone=None, os_name="macos"):
        lockdown = lockdown or make_lockdown()
        with fake_library(devices=devices, lockdown=lockdown, apps=APPS, documents=phone) as lib:
            code, out, err = run_main(
                ["repair", *extra_args],
                os_name=os_name,
                home=self.home,
                backup_root=self.backup_root,
                ask=ask,
            )
        return code, out, err, lib, lockdown

    def test_repair_writes_the_phone_after_yes_keeps_a_backup_and_never_pairs(self):
        write_icloud(self.icloud, script=REPO_BYTES, data=b"{}")
        phone = FakePhoneDocuments({SCRIPT: OLD_BYTES})
        questions = []

        def ask(question):
            questions.append(question)
            return True

        code, out, _err, _lib, lockdown = self.run_repair(
            ["--icloud-dir", str(self.icloud)],
            ask=ask,
            devices=[make_device()],
            phone=phone,
        )
        self.assertEqual(code, 0, out)
        phone.push.assert_awaited_once()
        self.assertEqual(phone.push.call_args.args, (str(doctor.REPO_SCRIPT), "/" + SCRIPT))
        self.assertIs(phone.push.call_args.kwargs.get("progress_bar"), False)
        self.assertEqual(phone.files[SCRIPT], REPO_BYTES)
        self.assertEqual([path.read_bytes() for path in self.backup_root.rglob(SCRIPT)], [OLD_BYTES])
        self.assertEqual(len(questions), 1)
        self.assertIn("Scriptable", questions[0])
        self.assertIn("ทำต่อบน iPhone", out)
        for name in PAIR_METHODS:
            self.assertEqual(getattr(lockdown, name).await_count, 0, name)

    def test_repair_dry_run_plans_and_writes_nothing(self):
        write_icloud(self.icloud, script=OLD_BYTES, data=b"{}")
        phone = FakePhoneDocuments({SCRIPT: OLD_BYTES})
        code, out, _err, _lib, _lockdown = self.run_repair(
            ["--dry-run", "--icloud-dir", str(self.icloud)],
            ask=forbidden,
            devices=[make_device()],
            phone=phone,
        )
        self.assertEqual(code, 2)
        phone.push.assert_not_awaited()
        self.assertEqual(phone.files[SCRIPT], OLD_BYTES)
        self.assertEqual((self.icloud / SCRIPT).read_bytes(), OLD_BYTES)
        self.assertFalse(self.backup_root.exists())
        self.assertIn("ยังไม่มีการเขียน", out)

    def test_repair_with_nothing_to_do_never_asks(self):
        write_icloud(self.icloud, script=REPO_BYTES, data=b"{}")
        phone = FakePhoneDocuments({SCRIPT: REPO_BYTES})
        code, _out, _err, _lib, _lockdown = self.run_repair(
            ["--icloud-dir", str(self.icloud)],
            ask=forbidden,
            devices=[make_device()],
            phone=phone,
        )
        self.assertEqual(code, 0)
        phone.push.assert_not_awaited()

    def test_declined_phone_write_changes_nothing(self):
        write_icloud(self.icloud, script=REPO_BYTES, data=b"{}")
        phone = FakePhoneDocuments({SCRIPT: OLD_BYTES})
        code, out, _err, _lib, _lockdown = self.run_repair(
            ["--icloud-dir", str(self.icloud)],
            ask=lambda question: False,
            devices=[make_device()],
            phone=phone,
        )
        self.assertEqual(code, 1)
        phone.push.assert_not_awaited()
        self.assertEqual(phone.files[SCRIPT], OLD_BYTES)
        self.assertFalse(self.backup_root.exists())
        self.assertIn("ไม่ได้เขียน", out)

    def test_failed_phone_write_is_a_tool_error_and_is_reported(self):
        write_icloud(self.icloud, script=REPO_BYTES, data=b"{}")
        phone = FakePhoneDocuments({SCRIPT: OLD_BYTES})
        phone.push.side_effect = RuntimeError("usb dropped")
        code, out, _err, _lib, _lockdown = self.run_repair(
            ["--icloud-dir", str(self.icloud)],
            ask=lambda question: True,
            devices=[make_device()],
            phone=phone,
        )
        self.assertEqual(code, 3)
        self.assertIn("เขียนลง iPhone ไม่สำเร็จ (RuntimeError)", out)

    def test_copy_to_icloud_after_yes_is_used_when_the_phone_is_not_reachable(self):
        write_icloud(self.icloud, script=OLD_BYTES, data=b"{}", data_age_seconds=0)
        code, out, _err, _lib, _lockdown = self.run_repair(
            ["--icloud-dir", str(self.icloud)],
            ask=lambda question: True,
            devices=[],
        )
        self.assertEqual((self.icloud / SCRIPT).read_bytes(), REPO_BYTES)
        self.assertEqual(code, 1)  # the phone is still not connected, so the user must still act
        self.assertIn("คัดลอก AI Usage.js", out)

    def test_no_route_on_windows_asks_for_a_manual_copy(self):
        code, out, _err, _lib, _lockdown = self.run_repair(
            [],
            ask=forbidden,
            devices=[],
            os_name="windows",
        )
        self.assertEqual(code, 1)
        self.assertIn("ซ่อมอัตโนมัติไม่ได้", out)

    def test_missing_icloud_folder_is_never_created_by_repair(self):
        missing = self.home / "not-there"
        code, _out, _err, _lib, _lockdown = self.run_repair(
            ["--icloud-dir", str(missing)],
            ask=lambda question: True,
            devices=[],
        )
        self.assertFalse(missing.exists())
        self.assertEqual(code, 1)


class CliTests(TempHomeMixin, unittest.TestCase):
    def test_check_json_is_valid_and_hides_the_udid(self):
        write_icloud(self.icloud, script=REPO_BYTES, data=b"{}")
        with fake_library(devices=[make_device()], lockdown=make_lockdown(paired=False)):
            code, out, _err = run_main(
                ["check", "--json", "--icloud-dir", str(self.icloud)],
                os_name="macos",
                home=self.home,
                backup_root=self.backup_root,
            )
        data = json.loads(out)
        self.assertEqual(data["command"], "check")
        self.assertEqual(data["exit_code"], code)
        self.assertEqual(code, 1)
        self.assertNotIn(UDID, out)
        self.assertNotIn("8101-001A", out)
        self.assertEqual(data["device"]["udid_masked"], "0000...6F70")
        self.assertIn("device_trusted", [check["id"] for check in data["checks"]])

    def test_check_never_asks_even_when_a_write_would_help(self):
        write_icloud(self.icloud, script=OLD_BYTES, data=b"{}")
        phone = FakePhoneDocuments({SCRIPT: OLD_BYTES})
        with fake_library(devices=[make_device()], lockdown=make_lockdown(), apps=APPS, documents=phone):
            code, _out, _err = run_main(
                ["check", "--icloud-dir", str(self.icloud)],
                os_name="macos",
                home=self.home,
                backup_root=self.backup_root,
                ask=forbidden,
            )
        self.assertEqual(code, 2)
        phone.push.assert_not_awaited()
        self.assertEqual((self.icloud / SCRIPT).read_bytes(), OLD_BYTES)
        self.assertFalse(self.backup_root.exists())

    def test_missing_library_still_checks_the_mac_copy(self):
        write_icloud(self.icloud, script=REPO_BYTES, data=b"{}")
        with mock.patch.dict(sys.modules, {"pymobiledevice3": None}):
            code, out, _err = run_main(
                ["check", "--icloud-dir", str(self.icloud)],
                os_name="macos",
                home=self.home,
                backup_root=self.backup_root,
            )
        self.assertEqual(code, 1)
        self.assertIn("ยังไม่ได้ติดตั้ง pymobiledevice3", out)
        self.assertIn("pip install pymobiledevice3", out)
        self.assertIn("ข้ามการตรวจผ่านสาย USB", out)
        self.assertIn("ตรงกับในโปรเจกต์", out)

    def test_missing_repo_script_is_a_tool_error(self):
        with mock.patch.object(doctor, "REPO_SCRIPT", self.home / "missing.js"):
            code, out, _err = run_main(["check"], os_name="macos", home=self.home, backup_root=self.backup_root)
        self.assertEqual(code, 3)
        self.assertIn("ไม่พบ scriptable", out)

    def test_check_rejects_the_repair_only_flags(self):
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            doctor.parse_args(["check", "--dry-run"])

    def test_a_subcommand_is_required(self):
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            doctor.parse_args([])


if __name__ == "__main__":
    unittest.main()
