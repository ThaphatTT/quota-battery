"""Tests for install.sh, the launchd template and the collector's runtime paths.

install.sh itself is never executed here. The tests pull single functions out of it by name and run
them with a temporary HOME, and they run `bash -n` and `plutil -lint`. No launchctl, no real
LaunchAgents, no Keychain, no network.
"""
import os
import plistlib
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

import ai_usage_collect as m

# Captured before any test patches subprocess.run, so the real macOS tools can run.
REAL_RUN = subprocess.run
COLLECTOR = Path(__file__).resolve().parent.parent
INSTALL_SH = COLLECTOR / "install.sh"
TEMPLATE = COLLECTOR / "com.user.aiusage.plist.template"
PROTECTED = ("Desktop", "Documents", "Downloads")
KEPT_FILES = ("usage.json", "cache.json", "notify-state.json", "collector.lock", "refresh.lock")


def bash_function(script_text: str, name: str) -> str:
    start = script_text.index(f"{name}() {{")
    end = script_text.index("\n}\n", start) + len("\n}\n")
    return script_text[start:end]


def under_protected_folder(path: Path, home: Path) -> bool:
    protected = [home / name for name in PROTECTED]
    return any(folder in [path, *path.parents] for folder in protected)


class InstallScriptTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        self.app = self.home / "Library" / "Application Support" / "AIUsage"
        self.bin = self.app / "bin"
        self.installed = self.bin / "ai_usage_collect.py"
        self.source = self.home / "repo" / "ai_usage_collect.py"
        self.source.parent.mkdir(parents=True)
        install_text = INSTALL_SH.read_text(encoding="utf-8")
        self.functions = self.home / "install-functions.sh"
        self.functions.write_text(
            "".join(bash_function(install_text, name)
                    for name in ("install_copy", "launchd_path", "render_plist", "remove_copy")),
            encoding="utf-8")

    def call(self, *command, path=None):
        env = {"PATH": path if path is not None else os.environ.get("PATH", "/usr/bin:/bin"),
               "HOME": str(self.home),
               "SOURCE_SCRIPT": str(self.source), "BIN_DIR": str(self.bin),
               "INSTALLED_SCRIPT": str(self.installed), "APP_DIR": str(self.app)}
        return REAL_RUN(["bash", "-c", 'set -euo pipefail; source "$1"; shift; "$@"', "bash",
                         str(self.functions), *command],
                        env=env, capture_output=True, text=True, timeout=60)

    def stub_tools(self, folder, *names):
        """Executable stand-ins for node, claude and the rest. install.sh only looks at where they are."""
        folder.mkdir(parents=True, exist_ok=True)
        for name in names:
            path = folder / name
            path.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
            path.chmod(0o755)

    def test_install_copy_puts_the_collector_in_application_support_and_overwrites_it(self):
        self.source.write_text("# version one\n", encoding="utf-8")
        result = self.call("install_copy")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.installed.read_text(encoding="utf-8"), "# version one\n")
        self.source.write_text("# version two\n", encoding="utf-8")
        result = self.call("install_copy")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.installed.read_text(encoding="utf-8"), "# version two\n")
        self.assertFalse((self.bin / "ai_usage_collect.py.tmp").exists())
        self.assertFalse(under_protected_folder(self.installed, self.home))

    def test_uninstall_removes_only_the_copied_script_and_keeps_the_data(self):
        self.bin.mkdir(parents=True)
        self.installed.write_text("# copy\n", encoding="utf-8")
        for name in KEPT_FILES:
            (self.app / name).write_text("kept", encoding="utf-8")
        result = self.call("remove_copy")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.bin.exists())
        for name in KEPT_FILES:
            self.assertEqual((self.app / name).read_text(encoding="utf-8"), "kept")

    def test_launchd_path_has_homebrew_local_bin_and_the_folders_of_the_installed_tools(self):
        tools = self.home / "tools"
        self.stub_tools(tools, "node", "claude", "codex")  # agy is not installed
        result = self.call("launchd_path", path=f"{tools}:/usr/bin:/bin")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(),
                         f"/opt/homebrew/bin:/usr/local/bin:{self.home}/.local/bin:{tools}"
                         ":/usr/bin:/bin:/usr/sbin:/sbin")

    def test_launchd_path_keeps_the_folder_of_a_symlink_and_never_resolves_it(self):
        real = self.home / "real"
        link = self.home / "link"
        self.stub_tools(real, "claude-real")
        link.mkdir()
        (link / "claude").symlink_to(real / "claude-real")
        result = self.call("launchd_path", path=f"{link}:/usr/bin:/bin")
        self.assertEqual(result.returncode, 0, result.stderr)
        folders = result.stdout.strip().split(":")
        self.assertIn(str(link), folders)
        self.assertNotIn(str(real), folders)

    def test_launchd_path_leaves_out_a_tool_that_is_not_installed_and_adds_each_folder_once(self):
        tools = self.home / "tools"
        self.stub_tools(tools, "node", "codex", "claude", "agy")
        result = self.call("launchd_path", path=f"{tools}:{tools}:/usr/bin:/bin")
        folders = result.stdout.strip().split(":")
        self.assertEqual(folders.count(str(tools)), 1)
        self.assertEqual(len(folders), len(set(folders)))

    def test_rendered_plist_runs_the_copy_and_passes_plutil_lint(self):
        out = self.home / "job.plist"
        python3 = "/opt/homebrew/bin/python3"
        logs = self.home / "Library" / "Logs" / "AIUsage"
        job_path = "/opt/homebrew/bin:/usr/local/bin:/Users/fixture/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        result = self.call("render_plist", str(TEMPLATE), str(out), python3,
                           str(self.installed), str(logs), str(self.app), job_path)
        self.assertEqual(result.returncode, 0, result.stderr)
        text = out.read_text(encoding="utf-8")
        data = plistlib.loads(out.read_bytes())
        self.assertEqual(data["Label"], "com.user.aiusage")
        self.assertEqual(data["ProgramArguments"], [python3, "-I", str(self.installed)])
        self.assertEqual(data["WorkingDirectory"], str(self.app))
        self.assertEqual(data["StartInterval"], 300)
        self.assertEqual(data["EnvironmentVariables"], {"PATH": job_path})
        # The temp folder name is random and may contain "__", so check the template's placeholders instead.
        for placeholder in re.findall(r"__[A-Z0-9_]+__", TEMPLATE.read_text(encoding="utf-8")):
            self.assertNotIn(placeholder, text)
        self.assertNotIn("~", text)
        for value in (python3, str(self.installed), str(self.app), str(logs)):
            self.assertFalse(under_protected_folder(Path(value), self.home), value)
        lint = REAL_RUN(["plutil", "-lint", str(out)], capture_output=True, text=True, timeout=30)
        self.assertEqual(lint.returncode, 0, lint.stdout + lint.stderr)

    def test_every_placeholder_in_the_template_is_rendered_by_install_sh(self):
        template_text = TEMPLATE.read_text(encoding="utf-8")
        placeholders = set(re.findall(r"__[A-Z0-9_]+__", template_text))
        render_text = bash_function(INSTALL_SH.read_text(encoding="utf-8"), "render_plist")
        rendered = set(re.findall(r"s\|(__[A-Z0-9_]+__)\|", render_text))
        self.assertEqual(placeholders, rendered)

    def test_install_sh_has_valid_bash_syntax(self):
        result = REAL_RUN(["bash", "-n", str(INSTALL_SH)], capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)


class CollectorRuntimeTests(unittest.TestCase):
    def test_every_path_the_collector_uses_is_outside_the_protected_folders(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            paths = m.Paths(home, home / "state")
            for name, value in vars(paths).items():
                if isinstance(value, Path):
                    self.assertFalse(under_protected_folder(value, home),
                                     f"{name} is inside a protected folder")

    def test_collector_source_never_names_desktop_or_downloads(self):
        source = (COLLECTOR / "ai_usage_collect.py").read_text(encoding="utf-8")
        self.assertNotIn("Desktop", source)
        self.assertNotIn("Downloads", source)


if __name__ == "__main__":
    unittest.main()
