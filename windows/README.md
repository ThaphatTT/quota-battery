# Windows port (help wanted)

AI Usage runs on macOS only today. A Windows version does not exist yet. If you want to build it, you are welcome to start.

## What exists today

- **The collector** is `collector/ai_usage_collect.py`, a Python 3 script that uses only the standard library. Its macOS-only parts are:
  - the Keychain check for agy, through the macOS `security` command (presence only; direct mode also reads the agy login);
  - the launchd job that runs it every 5 minutes: `collector/install.sh` (bash) and `collector/com.user.aiusage.plist.template`;
  - the macOS notifications, sent with `osascript`;
  - the iCloud copy for the iPhone widget, written under `~/Library/Mobile Documents/`;
  - the file lock, which uses `fcntl` and so exists only on Unix-like systems.
- **The data contract** is [docs/usage-json.md](../docs/usage-json.md). It does not depend on the platform. A Windows reader only needs to read the same `usage.json` file. A writer must replace the file atomically.
- **The Mac app and widgets** in `mac/` use SwiftUI and WidgetKit. They are macOS only. A Windows port does not reuse that code.

## What a Windows port needs

- **Credential sources.** Windows Credential Manager is one place to look. The collector does not read the Claude login: it runs the `claude`, `codex` and `agy` CLIs, and each keeps its own login. Check on a real Windows machine that each CLI runs there, and where agy keeps its login for direct mode. The Codex login is a file on the Mac (`~/.codex/auth.json`), and the collector also reads the local logs under `~/.claude/` and `~/.codex/`. Check these on a real Windows machine before you write any code. Do not guess paths.
- **A scheduler.** Task Scheduler, to replace launchd. It should run the collector every 5 minutes and at sign-in.
- **Notifications.** A Windows notification to replace `osascript`, at the same 80% and 95% thresholds that the data contract describes.
- **A UI.** Either a tray icon app, or a widget through Windows 11 Widgets. Both are open. Please discuss the choice in an issue before you start.
- **The iPhone copy.** The iCloud path is macOS only. A port decides how the iPhone copy is kept, or whether it is kept at all.

## Where to start

Read [docs/usage-json.md](../docs/usage-json.md) and [CONTRIBUTING.md](../CONTRIBUTING.md). Open an issue that says what you want to build, so that two people do not build the same thing.
