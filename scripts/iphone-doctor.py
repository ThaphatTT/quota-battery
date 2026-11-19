#!/usr/bin/env python3
"""Check and repair the AI Usage Scriptable script on an iPhone over USB (macOS and Windows).

Commands
  check   Read-only. Reports this computer, the iPhone (connected, trusted, iOS version), the
          Scriptable app, whether Scriptable's Documents can be listed through house_arrest, the
          script on the phone and in the iCloud Drive Scriptable folder (hashed against
          scriptable/AI Usage.js), and how fresh ai-usage.json is on a Mac. It writes nothing.
  repair  Asks y/N before every write. It copies scriptable/AI Usage.js into Scriptable's Documents
          (through house_arrest) and/or into the iCloud Drive Scriptable folder, and keeps a backup
          of any file it replaces. --dry-run prints the plan without asking and without writing.

Exit codes
  0  everything is ready, or repair finished
  1  the user must act first (plug in, unlock, tap Trust, open Scriptable), or said no to a write
  2  a problem that repair can fix; run repair --dry-run first
  3  the tool could not run (pymobiledevice3 missing or broken, unexpected error)

Privacy
  The script never opens, reads, copies or prints a token, a Keychain item or a pairing-record
  file. It connects with pymobiledevice3, which reads this computer's existing pairing record
  internally to open the lockdown session, the same way Finder does. On the phone it lists
  Scriptable's Documents and hashes AI Usage.js, and reads nothing else. UDIDs are masked.
  Pairing is never started by this script (autopair is off, and pair methods are not called):
  if the phone is not trusted, the user pairs it with Finder or Apple Devices.

Requirements
  Python 3.9+ and pymobiledevice3 (python3 -m pip install pymobiledevice3). On Windows also
  Apple Mobile Device Support (iTunes from apple.com, or the Apple Devices app). Tested with
  pymobiledevice3 11.60.0.
"""

from __future__ import annotations

import argparse
import asyncio
import hashlib
import importlib
import json
import os
import platform
import shutil
import sys
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, Awaitable, Callable, Optional, TypeVar

TOOL_VERSION = "1.0.0"
TESTED_PMD3_VERSION = "11.60.0"
SCRIPTABLE_BUNDLE_ID = "dk.simonbs.Scriptable"
SCRIPT_NAME = "AI Usage.js"
DATA_NAME = "ai-usage.json"
REPO_SCRIPT = Path(__file__).resolve().parent.parent / "scriptable" / SCRIPT_NAME
ICLOUD_PARTS = ("Library", "Mobile Documents", "iCloud~dk~simonbs~Scriptable", "Documents")
STALE_AFTER_SECONDS = 15 * 60  # the Mac collector writes about every 5 minutes
DEVICE_TIMEOUT_SECONDS = 30.0
MIN_PYTHON = (3, 9)
CHECK_CMD = "python3 scripts/iphone-doctor.py check"
REPAIR_CMD = "python3 scripts/iphone-doctor.py repair"

EXIT_OK = 0
EXIT_USER = 1
EXIT_FIX = 2
EXIT_TOOL = 3
EXIT_MEANING = {
    EXIT_OK: "พร้อมใช้งานแล้ว ไม่ต้องทำอะไรต่อ",
    EXIT_USER: "ต้องให้ผู้ใช้ทำบางอย่างก่อน แล้วรันใหม่",
    EXIT_FIX: "มีจุดที่ repair แก้ให้ได้ ให้รัน repair --dry-run ก่อน",
    EXIT_TOOL: "เครื่องมือทำงานไม่ได้ ดูข้อความด้านบน",
}
STATUS_LABEL = {"ok": "ผ่าน", "warn": "เตือน", "fail": "ไม่ผ่าน"}
ACTION_LABEL = {"planned": "แผน", "done": "เสร็จ", "declined": "ไม่ได้เขียน", "failed": "ไม่สำเร็จ"}

# Library exceptions are matched by class name, so this file never imports them directly.
NO_DEVICE_ERRORS = frozenset({"DeviceNotFoundError", "NoDeviceConnectedError", "NotConnectedError"})
LOCKED_ERRORS = frozenset({"PasswordRequiredError", "PasscodeRequiredError"})
TRUST_ERRORS = frozenset(
    {
        "NotPairedError",
        "PairingError",
        "InvalidHostIDError",
        "NotTrustedError",
        "FatalPairingError",
        "PairingDialogResponsePendingError",
        "UserDeniedPairingError",
    }
)

UNLOCK_FIX = "ปลดล็อก iPhone แล้วรัน check ใหม่ ถ้ายังไม่ได้ผล ให้เสียบสาย USB ใหม่"
TRUST_FIX = (
    "ปลดล็อก iPhone แล้วให้เจ้าของเครื่องกด เชื่อถือ (Trust) ที่หน้าต่าง 'เชื่อถือคอมพิวเตอร์เครื่องนี้' "
    "และใส่รหัสผ่าน iPhone ถ้าไม่มีหน้าต่างนี้ ให้เปิด Finder (Mac) หรือแอป Apple Devices (Windows) "
    "แล้วเชื่อมต่อ iPhone ใหม่ จนหน้าต่างขึ้นมา แล้วรัน check ใหม่"
)
REPAIR_HINT = f"รัน {REPAIR_CMD} --dry-run ดูแผนก่อน แล้วตอบ y ตอนถูกถามเมื่อพร้อม"
PHONE_STEPS_ICLOUD = (
    "ทำต่อบน iPhone: เปิด Scriptable แล้วรอให้ iCloud Drive ซิงก์สคริปต์ (อาจใช้เวลาหลายนาที) "
    "จากนั้นดึงรายการสคริปต์ลงเพื่อรีเฟรช และแตะ ▶ ที่ AI Usage หนึ่งครั้ง"
)
PHONE_STEPS_DEVICE = (
    "ทำต่อบน iPhone: เปิด Scriptable แล้วดึงรายการสคริปต์ลงเพื่อรีเฟรช ถ้ายังไม่เห็น AI Usage "
    "ให้ใช้วิธี iCloud Drive ตาม docs/guide-iphone.md"
)
MANUAL_FIX = (
    "คัดลอก scriptable/AI Usage.js ไปยังโฟลเดอร์ Scriptable ด้วยมือ (ดู docs/guide-iphone.md) "
    "หรือเปิด Scriptable บน iPhone ที่เปิด iCloud Drive ไว้ก่อน แล้วรันใหม่"
)

T = TypeVar("T")


class ToolError(Exception):
    """The tool itself could not finish, for example a missing repo file or an unexpected error."""


class UsbmuxUnavailable(Exception):
    """usbmuxd (Apple Mobile Device Support on Windows) did not answer."""

    def __init__(self, reason: str) -> None:
        super().__init__(reason)
        self.reason = reason


@dataclass
class Check:
    id: str
    status: str  # "ok" | "warn" | "fail"
    message: str
    fix: str = ""
    needs_user: bool = False
    details: dict = field(default_factory=dict)


@dataclass
class Context:
    os_name: str  # "macos", "windows" or "other"
    home: Path
    icloud_dir: Optional[Path]  # None when the path is not known and --icloud-dir was not given
    udid: Optional[str]
    repo_sha: str
    now: float
    backup_root: Path


@dataclass
class Report:
    command: str
    echo: bool = False
    host: dict = field(default_factory=dict)
    device: Optional[dict] = None
    checks: list[Check] = field(default_factory=list)
    actions: list[dict] = field(default_factory=list)
    next_steps: list[str] = field(default_factory=list)
    tool_error: Optional[str] = None
    # Set while the checks run; repair uses them to decide which routes can write.
    device_state: Optional[str] = None  # "missing" | "same" | "different" | None (not reachable)
    icloud_state: Optional[str] = None

    def add(self, check: Check) -> None:
        self.checks.append(check)
        if self.echo:
            print(render_check(check), flush=True)

    def say(self, text: str) -> None:
        if self.echo:
            print(text, flush=True)

    def act(self, route: str, status: str, message: str) -> None:
        self.actions.append({"route": route, "status": status, "message": message})
        self.say(f"[{ACTION_LABEL[status]}] {message}")


# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def mask_udid(udid: Optional[str]) -> str:
    """Show only the first four and last four characters of a UDID."""
    if not udid or len(udid) <= 12:
        return "..."
    return f"{udid[:4]}...{udid[-4:]}"


def same_udid(a: str, b: str) -> bool:
    return a.replace("-", "").upper() == b.replace("-", "").upper()


def short_hash(digest: str) -> str:
    return digest[:12]


def display_path(path: Path, home: Path) -> str:
    try:
        return "~/" + path.relative_to(home).as_posix()
    except ValueError:
        return str(path)


def os_family(system: Optional[str] = None) -> str:
    name = platform.system() if system is None else system
    if name == "Darwin":
        return "macos"
    if name == "Windows":
        return "windows"
    return "other"


def os_label() -> str:
    if platform.system() == "Darwin":
        return f"macOS {platform.mac_ver()[0] or platform.release()}"
    return f"{platform.system()} {platform.release()}".strip()


def default_icloud_dir(os_name: str, home: Path) -> Optional[Path]:
    """The Mac path is known. The iCloud for Windows path is not confirmed yet, so it stays unknown."""
    if os_name == "macos":
        return home.joinpath(*ICLOUD_PARTS)
    return None


def default_backup_root(os_name: str, home: Path) -> Path:
    if os_name == "macos":
        return home / "Library" / "Application Support" / "AIUsage" / "iphone-doctor-backups"
    if os_name == "windows":
        base = os.environ.get("APPDATA")
        root = Path(base) if base else home / "AppData" / "Roaming"
        return root / "AIUsage" / "iphone-doctor-backups"
    return home / ".local" / "share" / "AIUsage" / "iphone-doctor-backups"


def usbmux_fix(os_name: str) -> str:
    if os_name == "windows":
        return (
            "ติดตั้ง iTunes จาก apple.com (ไม่ใช่เวอร์ชันจาก Microsoft Store) หรือแอป Apple Devices "
            "แล้วเปิดสคริปต์นี้ใหม่"
        )
    if os_name == "macos":
        return "รีสตาร์ต Mac แล้วลองใหม่ ถ้ายังไม่ได้ผล ให้เปิด Finder ดูว่า iPhone ขึ้นหรือไม่"
    return "ติดตั้งและเปิดบริการ usbmuxd แล้วลองใหม่"


def install_hint(os_name: str) -> str:
    py = "py" if os_name == "windows" else "python3"
    lines = [
        f"ติดตั้งด้วยคำสั่ง: {py} -m pip install pymobiledevice3",
        "ถ้า pip ไม่ยอมติดตั้ง (มักเกิดกับ Python ของ Homebrew) ให้สร้าง venv ก่อน แล้วติดตั้งในนั้น",
    ]
    if os_name == "windows":
        lines.append(
            "Windows ต้องมีไดรเวอร์ Apple Mobile Device Support: ติดตั้ง iTunes จาก apple.com "
            "(ไม่ใช่เวอร์ชันจาก Microsoft Store) หรือแอป Apple Devices แล้วรันใหม่"
        )
    return "\n".join(lines)


def render_check(check: Check) -> str:
    line = f"[{STATUS_LABEL[check.status]}] {check.message}"
    if check.status != "ok" and check.fix:
        line += "\n      ทำต่อ: " + check.fix.replace("\n", "\n            ")
    return line


async def timed(awaitable: Awaitable[T]) -> T:
    return await asyncio.wait_for(awaitable, DEVICE_TIMEOUT_SECONDS)


# ---------------------------------------------------------------------------
# Host checks (no device needed)
# ---------------------------------------------------------------------------


def os_check() -> Check:
    return Check("os", "ok", f"ระบบ: {os_label()}")


def python_check(version_info: Any) -> Check:
    parts = tuple(version_info)
    ver = ".".join(str(part) for part in parts[:3])
    if parts[:2] >= MIN_PYTHON:
        return Check("python", "ok", f"Python {ver} ใช้ได้")
    return Check(
        "python",
        "fail",
        f"Python {ver} เก่าเกินไป",
        fix=f"ติดตั้ง Python {MIN_PYTHON[0]}.{MIN_PYTHON[1]} ขึ้นไป แล้วรันด้วยเวอร์ชันนั้น",
        needs_user=True,
    )


def library_status() -> tuple[bool, str, str]:
    """Returns (importable, version, problem). The problem is "missing" or an error class name."""
    try:
        importlib.import_module("pymobiledevice3")
    except ImportError:
        return False, "", "missing"
    except Exception as exc:  # installed but broken, for example a dependency that fails to load
        return False, "", type(exc).__name__
    try:
        from importlib.metadata import version

        return True, version("pymobiledevice3"), ""
    except Exception:
        return True, "", ""


def library_check(os_name: str) -> tuple[Check, bool]:
    ok, version, problem = library_status()
    if ok:
        shown = version or "ไม่ทราบเวอร์ชัน"
        note = "" if version == TESTED_PMD3_VERSION else f" (ทดสอบแล้วกับ {TESTED_PMD3_VERSION})"
        return Check("pymobiledevice3", "ok", f"pymobiledevice3 {shown} พร้อมใช้งาน{note}"), True
    if problem == "missing":
        message = "ยังไม่ได้ติดตั้ง pymobiledevice3"
    else:
        message = f"pymobiledevice3 ติดตั้งแล้วแต่โหลดไม่ได้ ({problem})"
    return Check("pymobiledevice3", "fail", message, fix=install_hint(os_name), needs_user=True), False


# ---------------------------------------------------------------------------
# pymobiledevice3 adapter. Every library call the script makes is in this section.
# Read calls: usbmux.list_devices, create_using_usbmux(autopair=False), get_apps,
# HouseArrestService.create, listdir, get_file_contents, close.
# Write call (repair only): AfcService.push. Nothing else writes to the phone.
# ---------------------------------------------------------------------------


async def list_usb_serials() -> list[str]:
    """UDIDs of iPhones attached over USB, as usbmuxd reports them."""
    from pymobiledevice3 import usbmux

    try:
        devices = await usbmux.list_devices()
    except Exception as exc:  # usbmuxd not running, socket refused, Apple Mobile Device Support missing
        raise UsbmuxUnavailable(type(exc).__name__) from exc
    return [device.serial for device in devices if device.connection_type == "USB"]


async def open_lockdown(serial: str) -> Any:
    """Open a lockdown session without pairing. autopair=False: no Trust prompt, no new pairing record."""
    from pymobiledevice3.lockdown import create_using_usbmux

    return await create_using_usbmux(serial=serial, autopair=False)


async def scriptable_info(lockdown: Any) -> Optional[dict]:
    from pymobiledevice3.services.installation_proxy import InstallationProxyService

    apps = await InstallationProxyService(lockdown=lockdown).get_apps(bundle_identifiers=[SCRIPTABLE_BUNDLE_ID])
    return (apps or {}).get(SCRIPTABLE_BUNDLE_ID)


async def open_documents(lockdown: Any) -> Any:
    """AFC access rooted at Scriptable's Documents folder (VendDocuments)."""
    from pymobiledevice3.services.house_arrest import HouseArrestService

    return await HouseArrestService.create(lockdown, SCRIPTABLE_BUNDLE_ID, documents_only=True)


async def close_quietly(obj: Any) -> None:
    try:
        await obj.close()
    except Exception:
        pass


def error_kind(exc: BaseException) -> str:
    name = type(exc).__name__
    if name in LOCKED_ERRORS:
        return "locked"
    if name in TRUST_ERRORS:
        return "trust"
    if name in NO_DEVICE_ERRORS:
        return "no_device"
    return "other"


def documents_reason(exc: BaseException) -> str:
    text = f"{type(exc).__name__}: {exc}"
    if isinstance(exc, asyncio.TimeoutError):
        return "หมดเวลา"
    if "ApplicationLookupFailed" in text or "InstallationLookupFailed" in text or "AppNotInstalled" in text:
        return "แอปไม่เปิดโฟลเดอร์ Documents ให้เข้าถึงผ่าน house_arrest"
    if "Permission" in text or "Denied" in text:
        return "ไม่ได้รับสิทธิ์เข้าถึง"
    return type(exc).__name__


# ---------------------------------------------------------------------------
# iPhone checks and the phone-side repair write
# ---------------------------------------------------------------------------


def handle_device_error(report: Report, exc: BaseException, check_id: str) -> None:
    """Turn a library error into a check. Anything unexpected stops the run as a tool error."""
    if isinstance(exc, asyncio.TimeoutError):
        report.add(Check(check_id, "fail", "iPhone ไม่ตอบภายในเวลาที่กำหนด", fix=UNLOCK_FIX, needs_user=True))
        return
    kind = error_kind(exc)
    if kind == "locked":
        report.add(Check(check_id, "fail", "iPhone ถูกล็อกอยู่", fix=UNLOCK_FIX, needs_user=True))
    elif kind == "trust":
        report.add(Check("device_trusted", "fail", "iPhone ยังไม่เชื่อถือคอมพิวเตอร์เครื่องนี้", fix=TRUST_FIX, needs_user=True))
    elif kind == "no_device":
        report.add(Check(check_id, "fail", "ไม่พบ iPhone ผ่านสาย USB", fix=UNLOCK_FIX, needs_user=True))
    else:
        raise ToolError(f"{check_id} ใช้ไม่ได้ ({type(exc).__name__})") from exc


async def device_part(ctx: Context, report: Report, *, write: bool, dry: bool, ask: Optional[Callable[[str], bool]]) -> None:
    try:
        serials = await timed(list_usb_serials())
    except (UsbmuxUnavailable, asyncio.TimeoutError) as exc:
        reason = getattr(exc, "reason", "หมดเวลา")
        report.add(
            Check(
                "device_connected",
                "fail",
                f"คุยกับบริการ usbmuxd ไม่ได้ ({reason})",
                fix=usbmux_fix(ctx.os_name),
                needs_user=True,
            )
        )
        return
    if ctx.udid:
        serials = [serial for serial in serials if same_udid(serial, ctx.udid)]
    if not serials:
        message = "ไม่พบ iPhone ที่มี UDID ที่ระบุ ผ่านสาย USB" if ctx.udid else "ไม่พบ iPhone ผ่านสาย USB"
        report.add(
            Check(
                "device_connected",
                "fail",
                message,
                fix="เสียบสาย USB ตรงเข้าคอมพิวเตอร์ ปลดล็อก iPhone แล้วรัน check ใหม่",
                needs_user=True,
            )
        )
        return
    if len(serials) > 1 and not ctx.udid:
        report.add(
            Check(
                "device_count",
                "warn",
                f"พบ iPhone {len(serials)} เครื่องผ่าน USB ใช้เครื่องแรก (ระบุเครื่องด้วย --udid ได้)",
            )
        )
    serial = serials[0]
    try:
        lockdown = await timed(open_lockdown(serial))
    except Exception as exc:
        handle_device_error(report, exc, "device_connected")
        return
    report.add(Check("device_connected", "ok", f"พบ iPhone ผ่านสาย USB (UDID {mask_udid(serial)})"))
    try:
        await device_session(ctx, report, lockdown, serial, write=write, dry=dry, ask=ask)
    finally:
        await close_quietly(lockdown)


async def device_session(
    ctx: Context,
    report: Report,
    lockdown: Any,
    serial: str,
    *,
    write: bool,
    dry: bool,
    ask: Optional[Callable[[str], bool]],
) -> None:
    paired = bool(getattr(lockdown, "paired", False))
    ios = getattr(lockdown, "product_version", None) or "ไม่ทราบ"
    product = getattr(lockdown, "product_type", None) or "ไม่ทราบ"
    report.device = {"udid_masked": mask_udid(serial), "ios_version": ios, "product_type": product, "paired": paired}
    if not paired:
        report.add(Check("device_trusted", "fail", "iPhone ยังไม่เชื่อถือคอมพิวเตอร์เครื่องนี้ (ยังไม่ได้จับคู่)", fix=TRUST_FIX, needs_user=True))
        return
    report.add(Check("device_trusted", "ok", "iPhone เชื่อถือคอมพิวเตอร์เครื่องนี้แล้ว"))
    report.add(Check("ios_version", "ok", f"iOS {ios} (รุ่น {product})"))

    try:
        info = await timed(scriptable_info(lockdown))
    except Exception as exc:
        handle_device_error(report, exc, "scriptable_installed")
        return
    if not info:
        report.add(
            Check(
                "scriptable_installed",
                "fail",
                "ไม่พบแอป Scriptable บน iPhone",
                fix="ติดตั้ง Scriptable จาก App Store แล้วเปิดหนึ่งครั้ง (ดู docs/guide-iphone.md)",
                needs_user=True,
            )
        )
        return
    short_version = str(info.get("CFBundleShortVersionString") or "ไม่ทราบ")
    report.add(
        Check("scriptable_installed", "ok", f"พบแอป Scriptable (เวอร์ชัน {short_version})", details={"version": short_version})
    )

    try:
        svc = await timed(open_documents(lockdown))
    except Exception as exc:
        report.add(
            Check(
                "documents_house_arrest",
                "warn",
                f"อ่าน Documents ของ Scriptable ผ่าน house_arrest ไม่ได้ ({documents_reason(exc)})",
                fix="ไม่เป็นไร ให้ใช้โฟลเดอร์ iCloud Drive บน Mac (หรือ Windows) แทน",
            )
        )
        return
    try:
        await device_documents(ctx, report, svc, write=write, dry=dry, ask=ask)
    finally:
        await close_quietly(svc)


async def device_documents(
    ctx: Context,
    report: Report,
    svc: Any,
    *,
    write: bool,
    dry: bool,
    ask: Optional[Callable[[str], bool]],
) -> None:
    try:
        names = [name for name in await timed(svc.listdir("/")) if name not in (".", "..")]
    except Exception as exc:
        report.add(
            Check(
                "documents_house_arrest",
                "warn",
                f"อ่าน Documents ของ Scriptable ผ่าน house_arrest ไม่ได้ ({documents_reason(exc)})",
                fix="ไม่เป็นไร ให้ใช้โฟลเดอร์ iCloud Drive บน Mac (หรือ Windows) แทน",
            )
        )
        return
    report.add(
        Check(
            "documents_house_arrest",
            "ok",
            f"อ่านรายการใน Documents ของ Scriptable ผ่าน house_arrest ได้ ({len(names)} รายการ)",
        )
    )
    existing: Optional[bytes] = None
    if SCRIPT_NAME in names:
        try:
            existing = await timed(svc.get_file_contents("/" + SCRIPT_NAME))
        except Exception as exc:
            report.add(
                Check(
                    "script_on_device",
                    "warn",
                    f"อ่าน {SCRIPT_NAME} ใน Documents ของ iPhone ไม่ได้ ({documents_reason(exc)})",
                    fix="ตรวจสำเนาใน iCloud ของ Mac ด้านล่างแทน",
                )
            )
            return
        digest = sha256_hex(existing)
        state = "same" if digest == ctx.repo_sha else "different"
        report.add(script_check_device(ctx, state, digest))
    else:
        state = "missing"
        report.add(script_check_device(ctx, state, ""))
    report.device_state = state
    if state == "same" or not write:
        return
    await device_write(ctx, report, svc, existing, dry=dry, ask=ask)


def script_check_device(ctx: Context, state: str, device_digest: str) -> Check:
    if state == "same":
        return Check(
            "script_on_device",
            "ok",
            f"{SCRIPT_NAME} ใน Documents ของ iPhone ตรงกับในโปรเจกต์ (แฮช {short_hash(ctx.repo_sha)})",
            details={"sha256": ctx.repo_sha},
        )
    if state == "different":
        return Check(
            "script_on_device",
            "fail",
            f"{SCRIPT_NAME} ใน Documents ของ iPhone ต่างจากในโปรเจกต์",
            fix=REPAIR_HINT,
            details={"sha256_device": device_digest, "sha256_repo": ctx.repo_sha},
        )
    return Check(
        "script_on_device",
        "warn",
        f"ไม่พบ {SCRIPT_NAME} ใน Documents ของ iPhone",
        fix="ถ้า Scriptable เก็บสคริปต์ไว้ใน iCloud Drive ไฟล์จะไม่อยู่ที่นี่ ให้ดูผลตรวจสำเนาใน iCloud ของ Mac ด้านล่าง",
    )


async def device_write(
    ctx: Context,
    report: Report,
    svc: Any,
    existing: Optional[bytes],
    *,
    dry: bool,
    ask: Optional[Callable[[str], bool]],
) -> None:
    target = f"Documents ของ Scriptable บน iPhone ({SCRIPT_NAME})"
    backup_text = (
        "ยังไม่มีไฟล์เดิมให้สำรอง"
        if existing is None
        else f"ไฟล์เดิมจะถูกสำรองไว้ที่ {display_path(ctx.backup_root, ctx.home)}"
    )
    if dry:
        report.act("iphone", "planned", f"คัดลอก {SCRIPT_NAME} ไปยัง {target} ผ่าน house_arrest")
        return
    if ask is None or not ask(f"เขียน {SCRIPT_NAME} ลงใน {target} หรือไม่ ({backup_text}) [y/N]: "):
        report.act("iphone", "declined", "ผู้ใช้ไม่อนุมัติ จึงไม่ได้เขียนลง iPhone")
        return
    if existing is not None:
        backup = backup_file(existing, "iphone", ctx)
        report.say(f"สำรองไฟล์เดิมของ iPhone แล้ว: {display_path(backup, ctx.home)}")
    try:
        await timed(svc.push(str(REPO_SCRIPT), "/" + SCRIPT_NAME, progress_bar=False))
        written = await timed(svc.get_file_contents("/" + SCRIPT_NAME))
    except Exception as exc:
        report.act("iphone", "failed", f"เขียนลง iPhone ไม่สำเร็จ ({type(exc).__name__})")
        return
    if sha256_hex(written) == ctx.repo_sha:
        report.act("iphone", "done", f"เขียน {SCRIPT_NAME} ลงใน iPhone แล้ว และแฮชตรงกับโปรเจกต์")
    else:
        report.act("iphone", "failed", "เขียนแล้วแต่ตรวจแฮชไม่ตรง ลองรัน repair ใหม่")


# ---------------------------------------------------------------------------
# Mac and iCloud Drive checks, and the iCloud copy
# ---------------------------------------------------------------------------


def read_script_state(path: Path, repo_sha: str) -> tuple[str, Optional[bytes]]:
    if not path.is_file():
        return "missing", None
    data = path.read_bytes()
    return ("same" if sha256_hex(data) == repo_sha else "different"), data


def script_check_icloud(ctx: Context, state: str) -> Check:
    if state == "same":
        return Check(
            "script_on_icloud",
            "ok",
            f"{SCRIPT_NAME} ใน iCloud ของ Mac ตรงกับในโปรเจกต์ (แฮช {short_hash(ctx.repo_sha)})",
            details={"sha256": ctx.repo_sha},
        )
    if state == "different":
        return Check("script_on_icloud", "fail", f"{SCRIPT_NAME} ใน iCloud ของ Mac ต่างจากในโปรเจกต์ (แฮชไม่ตรง)", fix=REPAIR_HINT)
    return Check("script_on_icloud", "fail", f"ไม่มี {SCRIPT_NAME} ในโฟลเดอร์ iCloud ของ Mac", fix=REPAIR_HINT)


def data_check(ctx: Context, folder: Path) -> Check:
    path = folder / DATA_NAME
    if not path.is_file():
        return Check(
            "data_file_icloud",
            "warn",
            f"ยังไม่มี {DATA_NAME} ใน iCloud ของ Mac",
            fix="เปิด Mac ไว้ ตัวเก็บข้อมูลจะเขียนไฟล์ภายใน 5 นาที แล้วรัน check ใหม่",
            needs_user=True,
        )
    age_seconds = max(0.0, ctx.now - path.stat().st_mtime)
    minutes = int(age_seconds // 60)
    if age_seconds > STALE_AFTER_SECONDS:
        return Check(
            "data_file_icloud",
            "warn",
            f"{DATA_NAME} อัปเดตล่าสุดเมื่อ {minutes} นาทีที่แล้ว (เกิน 15 นาที)",
            fix="เปิด Mac ไว้ และตรวจตัวเก็บข้อมูลตาม AGENTS.md ขั้นที่ 7",
            needs_user=True,
        )
    return Check("data_file_icloud", "ok", f"{DATA_NAME} อัปเดตเมื่อ {minutes} นาทีที่แล้ว")


def backup_file(data: bytes, label: str, ctx: Context) -> Path:
    """Keep the file that a write is about to replace. Never overwrites an earlier backup."""
    stamp = time.strftime("%Y%m%d-%H%M%S", time.localtime(ctx.now))
    folder = ctx.backup_root / f"{stamp}-{label}"
    counter = 1
    while folder.exists():
        counter += 1
        folder = ctx.backup_root / f"{stamp}-{label}-{counter}"
    folder.mkdir(parents=True)
    path = folder / SCRIPT_NAME
    path.write_bytes(data)
    return path


def icloud_part(ctx: Context, report: Report, *, write: bool, dry: bool, ask: Optional[Callable[[str], bool]]) -> None:
    folder = ctx.icloud_dir
    if folder is None:
        report.add(
            Check(
                "icloud_folder",
                "warn",
                "ยังไม่ทราบเส้นทางโฟลเดอร์ Scriptable ใน iCloud for Windows จึงตรวจสำเนาใน iCloud ไม่ได้",
                fix="ระบุเส้นทางด้วย --icloud-dir เมื่อทราบแล้ว หรือคัดลอกไฟล์ scriptable/AI Usage.js ไปยังโฟลเดอร์นั้นด้วยมือ",
            )
        )
        return
    shown = display_path(folder, ctx.home)
    if not folder.is_dir():
        report.add(
            Check(
                "icloud_folder",
                "fail",
                f"ยังไม่มีโฟลเดอร์ Scriptable ใน iCloud Drive ({shown})",
                fix="เปิด Scriptable บน iPhone ที่เปิด iCloud Drive ไว้ แล้วรอให้ซิงก์ (อย่าสร้างโฟลเดอร์เอง) แล้วรัน check ใหม่",
                needs_user=True,
            )
        )
        return
    report.add(Check("icloud_folder", "ok", f"พบโฟลเดอร์ Scriptable ใน iCloud Drive ({shown})"))
    state, existing = read_script_state(folder / SCRIPT_NAME, ctx.repo_sha)
    report.icloud_state = state
    report.add(script_check_icloud(ctx, state))
    report.add(data_check(ctx, folder))
    if write and state != "same":
        icloud_write(ctx, report, folder, existing, dry=dry, ask=ask)


def icloud_write(
    ctx: Context,
    report: Report,
    folder: Path,
    existing: Optional[bytes],
    *,
    dry: bool,
    ask: Optional[Callable[[str], bool]],
) -> None:
    destination = folder / SCRIPT_NAME
    shown = display_path(destination, ctx.home)
    if dry:
        report.act("icloud", "planned", f"คัดลอก {SCRIPT_NAME} ไปยัง {shown}")
        return
    backup_text = (
        "ยังไม่มีไฟล์เดิมให้สำรอง"
        if existing is None
        else f"ไฟล์เดิมจะถูกสำรองไว้ที่ {display_path(ctx.backup_root, ctx.home)}"
    )
    if ask is None or not ask(f"คัดลอก {SCRIPT_NAME} ไปยัง {shown} หรือไม่ ({backup_text}) [y/N]: "):
        report.act("icloud", "declined", "ผู้ใช้ไม่อนุมัติ จึงไม่ได้คัดลอกไปยัง iCloud")
        return
    if existing is not None:
        backup = backup_file(existing, "icloud", ctx)
        report.say(f"สำรองไฟล์เดิมใน iCloud แล้ว: {display_path(backup, ctx.home)}")
    try:
        shutil.copyfile(REPO_SCRIPT, destination)
        written = destination.read_bytes()
    except OSError as exc:
        report.act("icloud", "failed", f"คัดลอกไปยัง iCloud ไม่สำเร็จ ({type(exc).__name__})")
        return
    if sha256_hex(written) == ctx.repo_sha:
        report.act("icloud", "done", f"คัดลอก {SCRIPT_NAME} ไปยัง {shown} แล้ว และแฮชตรงกับโปรเจกต์")
    else:
        report.act("icloud", "failed", "คัดลอกแล้วแต่ตรวจแฮชไม่ตรง ลองรัน repair ใหม่")


# ---------------------------------------------------------------------------
# Run, exit codes, output
# ---------------------------------------------------------------------------


async def run(ctx: Context, report: Report, *, write: bool, dry: bool, ask: Optional[Callable[[str], bool]]) -> None:
    report.add(os_check())
    report.add(python_check(sys.version_info))
    library, library_ok = library_check(ctx.os_name)
    report.add(library)
    if write:
        report.say("แผนซ่อม: โหมดดูแผนอย่างเดียว ยังไม่มีการเขียน" if dry else "แผนซ่อม: ถามยืนยันก่อนเขียนทุกครั้ง")
    if library_ok:
        await device_part(ctx, report, write=write, dry=dry, ask=ask)
    else:
        report.say("iPhone: ข้ามการตรวจผ่านสาย USB เพราะยังไม่มี pymobiledevice3")
    icloud_part(ctx, report, write=write, dry=dry, ask=ask)
    if write:
        finish_repair(report)


def finish_repair(report: Report) -> None:
    decided = any(action["status"] in ("planned", "done", "declined") for action in report.actions)
    script_known_ok = "same" in (report.device_state, report.icloud_state)
    if not decided and not script_known_ok:
        report.add(
            Check(
                "repair_route",
                "fail",
                "ซ่อมอัตโนมัติไม่ได้ เพราะยังไม่มีเส้นทางที่เขียนสคริปต์ได้",
                fix=MANUAL_FIX,
                needs_user=True,
            )
        )
    done_routes = {action["route"] for action in report.actions if action["status"] == "done"}
    if "iphone" in done_routes:
        report.next_steps.append(PHONE_STEPS_DEVICE)
    if "icloud" in done_routes:
        report.next_steps.append(PHONE_STEPS_ICLOUD)
    if done_routes:
        report.next_steps.append(f"รัน check อีกครั้งเพื่อยืนยัน: {CHECK_CMD}")


def check_exit_code(report: Report) -> int:
    if report.tool_error:
        return EXIT_TOOL
    open_items = [check for check in report.checks if check.status != "ok"]
    if any(check.needs_user for check in open_items):
        return EXIT_USER
    if any(check.status == "fail" for check in open_items):
        return EXIT_FIX
    return EXIT_OK


def repair_exit_code(report: Report) -> int:
    if report.tool_error or any(action["status"] == "failed" for action in report.actions):
        return EXIT_TOOL
    if any(action["status"] == "declined" for action in report.actions):
        return EXIT_USER
    if any(check.needs_user for check in report.checks if check.status != "ok"):
        return EXIT_USER
    if any(action["status"] == "planned" for action in report.actions):
        return EXIT_FIX
    return EXIT_OK


def summary_lines(report: Report, code: int) -> list[str]:
    counts = {status: sum(1 for check in report.checks if check.status == status) for status in STATUS_LABEL}
    lines = [f"สรุป: ผ่าน {counts['ok']} เตือน {counts['warn']} ไม่ผ่าน {counts['fail']}"]
    if report.tool_error:
        lines.append(f"เครื่องมือทำงานไม่สำเร็จ: {report.tool_error}")
    lines.extend(report.next_steps)
    lines.append(f"รหัสออก {code}: {EXIT_MEANING[code]}")
    return lines


def render_json(report: Report, code: int) -> dict:
    return {
        "tool": "iphone-doctor",
        "version": TOOL_VERSION,
        "command": report.command,
        "exit_code": code,
        "meaning": EXIT_MEANING[code],
        "host": report.host,
        "device": report.device,
        "checks": [asdict(check) for check in report.checks],
        "actions": report.actions,
        "next_steps": report.next_steps,
        "tool_error": report.tool_error,
    }


def ask_yes_no(question: str) -> bool:
    """A y/N question on stderr. Anything other than y or yes, or no answer at all, means no."""
    if sys.stdin is None:
        return False
    sys.stderr.write(question)
    sys.stderr.flush()
    return sys.stdin.readline().strip().lower() in {"y", "yes"}


def make_context(
    args: argparse.Namespace,
    *,
    os_name: Optional[str],
    home: Optional[Path],
    now: Optional[float],
    backup_root: Optional[Path],
) -> Context:
    if not REPO_SCRIPT.is_file():
        raise ToolError(f"ไม่พบ scriptable/{SCRIPT_NAME} ในโปรเจกต์ ({REPO_SCRIPT})")
    resolved_os = os_name or os_family()
    resolved_home = home or Path.home()
    icloud_dir = Path(args.icloud_dir).expanduser() if args.icloud_dir else default_icloud_dir(resolved_os, resolved_home)
    return Context(
        os_name=resolved_os,
        home=resolved_home,
        icloud_dir=icloud_dir,
        udid=args.udid,
        repo_sha=sha256_hex(REPO_SCRIPT.read_bytes()),
        now=time.time() if now is None else now,
        backup_root=backup_root or default_backup_root(resolved_os, resolved_home),
    )


def parse_args(argv: Optional[list[str]]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="iphone-doctor.py",
        description="ตรวจและซ่อม AI Usage บน iPhone ผ่านสาย USB (check อ่านอย่างเดียว, repair ถาม y/N ก่อนทุกการเขียน)",
    )
    sub = parser.add_subparsers(dest="command", required=True, metavar="{check,repair}")
    descriptions = {
        "check": "ตรวจอย่างเดียว ไม่เขียนอะไรลงเครื่องหรือโฟลเดอร์ใด",
        "repair": "ซ่อม โดยถาม y/N ก่อนทุกการเขียน",
    }
    for name, text in descriptions.items():
        sp = sub.add_parser(name, help=text, description=text)
        sp.add_argument("--json", action="store_true", help="พิมพ์ผลเป็น JSON")
        sp.add_argument("--udid", help="เลือก iPhone ด้วย UDID เมื่อเสียบหลายเครื่อง (ผลที่แสดงจะซ่อนค่านี้)")
        sp.add_argument(
            "--icloud-dir",
            help="โฟลเดอร์ Scriptable ใน iCloud Drive ของคอมพิวเตอร์ (มีค่าเริ่มต้นเฉพาะ Mac; Windows ต้องระบุเอง)",
        )
        if name == "repair":
            sp.add_argument("--dry-run", action="store_true", help="แสดงแผนอย่างเดียว ไม่ถามและไม่เขียนอะไร")
    return parser.parse_args(argv)


def configure_streams() -> None:
    for stream in (sys.stdout, sys.stderr):
        reconfigure = getattr(stream, "reconfigure", None)
        if reconfigure is None:
            continue
        try:
            reconfigure(encoding="utf-8", errors="replace")
        except (ValueError, OSError):
            pass


def main(
    argv: Optional[list[str]] = None,
    *,
    os_name: Optional[str] = None,
    home: Optional[Path] = None,
    now: Optional[float] = None,
    ask: Optional[Callable[[str], bool]] = None,
    backup_root: Optional[Path] = None,
) -> int:
    configure_streams()
    args = parse_args(argv)
    report = Report(command=args.command, echo=not args.json)
    write = args.command == "repair"
    dry = write and bool(getattr(args, "dry_run", False))
    library_version = library_status()[1]
    report.host = {
        "os": os_label(),
        "python": platform.python_version(),
        "pymobiledevice3": library_version or None,
    }
    if report.echo:
        if write:
            header = "iphone-doctor repair: ถามยืนยันก่อนทุกการเขียน" + (" (โหมดดูแผนอย่างเดียว)" if dry else "")
        else:
            header = "iphone-doctor check: อ่านอย่างเดียว ไม่เขียนอะไรลงเครื่องหรือโฟลเดอร์ใด"
        print(f"{header} (v{TOOL_VERSION})", flush=True)

    code = EXIT_TOOL
    try:
        ctx = make_context(args, os_name=os_name, home=home, now=now, backup_root=backup_root)
        asyncio.run(run(ctx, report, write=write, dry=dry, ask=None if (not write or dry) else (ask or ask_yes_no)))
        code = repair_exit_code(report) if write else check_exit_code(report)
    except KeyboardInterrupt:
        report.tool_error = "ยกเลิกโดยผู้ใช้"
        code = EXIT_USER
    except ToolError as exc:
        report.tool_error = str(exc)
    except Exception as exc:  # keep the report, and say what failed
        report.tool_error = f"{type(exc).__name__}: {str(exc)[:200]}"

    if args.json:
        print(json.dumps(render_json(report, code), ensure_ascii=False, indent=2))
    else:
        for line in summary_lines(report, code):
            print(line, flush=True)
    return code


if __name__ == "__main__":
    sys.exit(main())
