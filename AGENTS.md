# AGENTS.md: install AI Usage on the user's own Mac

This file is for a coding agent (Claude Code, Codex or similar) that is asked to install this project on
the user's Mac. Follow the steps in order.

Rules for the agent:

- Every step starts with a **check**. If the check shows the step is already done, skip it. Each step can
  be run again safely.
- Steps marked **ASK FIRST** read credentials, touch the Keychain, install a launchd job, write to
  `~/Applications`, or write to iCloud Drive. Before you run one, say what it does and wait for a clear
  yes from the user.
- Never print or copy the contents of a Keychain item, of `~/.codex/auth.json`, or of any token. Never
  paste one into a file or a message. Check only that an item exists, and read only the output the steps
  name.
- Never type a password, a verification code or an Apple ID login for the user. Ask the user to do those
  steps.
- Run commands from the repository root unless a step says otherwise.

## Working with the user

Read this section first. It says what you may do on your own, what you must ask about, what the user
does by hand, and what to offer at the end.

Two guides explain the install for a person who does it by hand, in Thai and English:

- [docs/guide-mac.md](docs/guide-mac.md): the collector, Xcode signing, the app, the Mac widget, daily
  use and troubleshooting.
- [docs/guide-iphone.md](docs/guide-iphone.md): the iPhone widget with Scriptable, step by step, including
  what the Mac must already have running.

Tested on 2026-11-19: macOS 27.2.1, Xcode 27.2, Python 3.15.2 (Homebrew), app 0.1.0, iPhone
on iOS 27.2.1 with Scriptable (free), and Hidden Bar 1.13.1 (optional). Other versions are untested. The
README requires macOS 15 or newer.

Every step is marked with one of these:

- **AGENT DOES**: read-only checks, and steps the user has already approved. Do them, then report the result.
- **ASK FIRST**: say what the step does, then wait for a clear yes from the user before you run it.
- **USER DOES (by hand)**: only the user can do it, or you must not. Tell the user exactly what to click or
  type, then wait until they say it is done.

| Step | Mark | Notes |
|---|---|---|
| 1. Prerequisite checks | AGENT DOES | read-only |
| 2. Collector dry run | ASK FIRST | asks each provider's own CLI for its usage once (no model call); writes nothing |
| 3. Install the collector (launchd job) | ASK FIRST | writes `~/Library/LaunchAgents` and `~/Library/Application Support/AIUsage/bin` |
| 4a. Add the Apple ID in Xcode and pick the Personal Team | USER DOES (by hand) | the user types their own Apple ID password. Never type it, and never ask for it in a message |
| 4b. Write the Team id into `mac/Local.xcconfig` | ASK FIRST | use only the id the user gives you. Never invent one, never commit it |
| 4c. Build and install `~/Applications/AIUsage.app` | ASK FIRST | replaces the app and quits a running AIUsage |
| 4d. Open the app once | AGENT DOES | right after the install |
| 4e. Xcode "Keep Xcode Version or Use Version on Disk"; codesign and Terminal prompts | USER DOES (by hand) | the user answers. Tell them which answer to choose |
| 5. Add the Mac widget | USER DOES (by hand) | in the macOS widget gallery |
| 6a. Install Scriptable on the iPhone and open it once with iCloud Drive on | USER DOES (by hand) | on the iPhone. The Scriptable folder reaches the Mac only after this |
| 6b. Check that the Scriptable folder exists | AGENT DOES | read-only |
| 6c. Copy `scriptable/AI Usage.js` into iCloud Drive | ASK FIRST | writes into iCloud Drive |
| 6d. Add the iPhone widget, set Script and Parameter | USER DOES (by hand) | on the iPhone |
| 7. Verify | AGENT DOES | read-only. The user checks how the widgets look |
| 8. Uninstall, one item at a time | ASK FIRST | each item deletes something. Never touch the Keychain |
| Stop the old widget process (the `pkill` line) | ASK FIRST | stops a running process. See Troubleshooting |
| macOS prompts: Python and iCloud Drive, notifications | USER DOES (by hand) | the user answers. If refused, see Troubleshooting |
| Login renewal: Claude Code, `codex`, `agy models` | USER DOES (by hand) | report the message and the command. The user runs them |
| Window switches and the Language picker | USER DOES (by hand) | do not write `settings.json` yourself |
| Hidden Bar settings (optional) | USER DOES (by hand) | |

**OFFER at the end.** Offer each item that applies. Do it only when the user says yes.

1. **The iPhone widget** (step 6), if the user has an iPhone with Scriptable. Point to `docs/guide-iphone.md`.
2. **A menu bar hider tip.** If the menu bar icon is hidden, or the user uses Hidden Bar, see the Hidden Bar
   notes in Troubleshooting.
3. **The language choice.** The window's Language picker (System / ไทย / English) sets the app, the Mac
   widgets and the notifications. The iPhone widget follows the iPhone language, or the Parameter `th` or `en`.
4. **Notifications.** They are on at 80% and 95% used. The window switch turns them off.
5. **Start at login (not tested).** The app does not start at login. If the user wants that, they add
   AI Usage under Login Items in System Settings, by hand.

Do not offer uninstall. Run it only when the user asks for it.

## Step 1: check the prerequisites

Checks (read-only):

- `sw_vers -productVersion` is 15.0 or newer.
- `xcodebuild -version` prints a version. If it fails, Xcode is missing or not selected. Ask the user to
  install Xcode from the App Store, open it once, and select it with `xcode-select` if needed.
- `command -v xcodegen` prints a path. If it is missing, ask before running `brew install xcodegen`.
- `command -v python3` prints an **absolute** path (for example `/usr/bin/python3` or
  `/opt/homebrew/bin/python3`). The launchd job needs an absolute path, and `collector/install.sh` stops
  without one.

If any check fails, report which one and stop until it is fixed.

## Step 2: dry run of the collector (ASK FIRST)

Check: `test -f collector/ai_usage_collect.py`.

Ask the user, in these words: "The collector will ask each provider's own command for its usage once: `claude`,
`codex app-server` and `agy`. It does not read or store any login token, and no model is called. Nothing is
written. Do you want me to run it?"

Run:

```sh
python3 -I collector/ai_usage_collect.py --dry-run
```

The command prints JSON on stdout and writes nothing. It does not renew any token: each CLI does its own.

What the collector reads in this default mode: nothing secret. It runs the three CLIs, and checks that the Claude
folders and `~/.codex/auth.json` exist and that the agy Keychain item is present, without opening any of them.
Direct mode reads the Codex token and the agy Keychain token, and it is only on when `settings.json` says so
(`"direct_mode"`). Do not turn it on for the user yourself.

Show the user which accounts are in `accounts` and each `status`. An account that is not listed has no
login on this Mac, and that is expected. If an account has `status` `error` or `stale`, show its `error`
text. Do not show the rest of the output if it contains anything that looks like a token.

## Step 3: install the collector (ASK FIRST)

Check:

```sh
launchctl print "gui/$(id -u)/com.user.aiusage" >/dev/null 2>&1 && echo installed || echo missing
```

Ask the user: "This installs a launchd job that runs the collector every 5 minutes and at login. It keeps
a copy of the collector in `~/Library/Application Support/AIUsage/bin` and writes the job to
`~/Library/LaunchAgents/com.user.aiusage.plist`. The job's PATH includes Homebrew, `~/.local/bin` and the folders
where `node`, `claude`, `codex` and `agy` are installed now, so run this step again after one of those tools moves
or is upgraded. Do you want me to install it?"

Run:

```sh
collector/install.sh
```

Verify: `test -f "$HOME/Library/Application Support/AIUsage/usage.json"`. The job runs when it is loaded, so the
file should appear shortly after the install. If it does not, check the error log in step 7. Re-running
`collector/install.sh` is safe: it replaces the copy and the job each time.

## Step 4: set the Team id, generate the project, build and install the app (ASK FIRST)

The app is signed with the user's own Apple Team id. The id is kept in `mac/Local.xcconfig`, which is
gitignored. Never write a Team id into `mac/project.yml`, into any committed file, or into a commit.

Check whether a Team id is already set. This prints a line only when a real id is set. An empty value or
the placeholder `YOURTEAMID` prints nothing:

```sh
grep -E '^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*[A-Za-z0-9]+' mac/Local.xcconfig 2>/dev/null | grep -v YOURTEAMID
```

If this prints a line, the Team id is set and you can go to the build. If it prints nothing, ask the user
for their Team id. There are two ways the user can get it:

- **Pick the team in Xcode (recommended).** The user does this part by hand, including typing their Apple ID
  password (see the table in "Working with the user").
  1. The user adds a free Apple ID in Xcode > Settings > Accounts, if it is not there yet.
  2. Generate the project once, so that Xcode can open it: `(cd mac && xcodegen generate)`.
  3. The user opens `mac/AIUsage.xcodeproj` in Xcode, selects the `AIUsage` target and then the
     `AIUsageWidget` target, and in Signing & Capabilities chooses the Personal Team for each one.
  4. After the user confirms step 3, read the Team id. Do not run `xcodegen generate` before this step:
     it rewrites the project file, and the team picked in Xcode goes with it.

     ```sh
     xcodebuild -project mac/AIUsage.xcodeproj -target AIUsage -configuration Release -showBuildSettings 2>/dev/null | grep -E ' DEVELOPMENT_TEAM = [A-Za-z0-9]+'
     ```

  5. Write the id into `mac/Local.xcconfig` (see below). Then run `(cd mac && xcodegen generate)` again.
     That drops the team picked in Xcode from the project file, and the build reads the team from
     `mac/Local.xcconfig` instead.
- **From the certificate.** `security find-identity -v -p codesigning` lists the signing certificate. The
  Team id is the `OU` field of that certificate, not the value in parentheses in its name. This method was
  not tested while this file was written, so check the value with the user before you use it.

Write the file, with the Team id given by the user (do not invent one):

```sh
cp mac/Local.xcconfig.example mac/Local.xcconfig
```

Then replace `YOURTEAMID` in `mac/Local.xcconfig` with the Team id.

Build and install (this replaces `~/Applications/AIUsage.app` if it exists):

```sh
scripts/build-mac.sh
```

The script runs `xcodegen generate`, builds a signed Release into a temporary folder, and copies the app
into `~/Applications/AIUsage.app`. Use `scripts/build-mac.sh --no-install` to build without installing.
If AIUsage is running, the script quits it before it replaces the app, and opens it again afterwards. It
also stops the old widget process (see Troubleshooting). macOS may ask whether the terminal may control
AIUsage for the quit. If the user refuses, the script stops the app after 10 seconds.
If macOS asks for permission for codesign to use the signing key, the user must allow it.

Then open the app once: `open "$HOME/Applications/AIUsage.app"`. The widget only appears in the
macOS widget gallery after the app has been opened.

Verify: `test -d "$HOME/Applications/AIUsage.app"`.

## Step 5: add the widget (manual)

Ask the user to add it, because adding a widget is done in the macOS interface. In Finder or on the
desktop, open the widget editor (right-click the desktop, then Edit Widgets). Search for **Quota Battery** (the same name in Thai and English),
choose a size, and add it.

## Step 6: iPhone widget, optional (ASK FIRST for the iCloud copy)

1. The user installs **Scriptable** from the App Store and opens it once with iCloud Drive turned on.
2. Check that the Scriptable folder exists in iCloud Drive on this Mac:

   ```sh
   test -d "$HOME/Library/Mobile Documents/iCloud~dk~simonbs~Scriptable/Documents" && echo present || echo missing
   ```

   If it is missing, do not create it by hand. Tell the user to wait until Scriptable has synced to iCloud,
   then check again.
3. Ask the user: "I will copy `scriptable/AI Usage.js` into the Scriptable folder in iCloud Drive, so that
   the iPhone can see the script. Do you want me to copy it?"
4. Run:

   ```sh
   cp "scriptable/AI Usage.js" "$HOME/Library/Mobile Documents/iCloud~dk~simonbs~Scriptable/Documents/"
   ```

5. On the iPhone, the user adds the **Scriptable** widget to the Home Screen, chooses the script
   **AI Usage**, and selects a size. `docs/guide-iphone.md` has the full steps in Thai and English, and `scriptable/README.md` has the script's own notes.

The numbers on the iPhone update only while the Mac is on, because the Mac writes the iCloud copy.

## Step 7: verify

- The collector wrote its file, and the file is recent:

  ```sh
  python3 -c 'import json,os; p=os.path.expanduser("~/Library/Application Support/AIUsage/usage.json"); d=json.load(open(p)); print(d["generated_at"], [(a["id"], a["status"]) for a in d["accounts"]])'
  ```

  This prints only the time and the account ids and statuses. It shows no tokens.
- The job is loaded:

  ```sh
  launchctl print "gui/$(id -u)/com.user.aiusage" | grep -E 'state|last exit code'
  ```

- The log has no recent errors. Read only the last lines:

  ```sh
  tail -n 20 "$HOME/Library/Logs/AIUsage/collector.err.log"
  ```

- Open the widget gallery or the Home Screen and check that the widget shows the same accounts as
  `usage.json`.

## Step 8: uninstall (ASK FIRST for each item)

Remove only what the user asks for. Each item below deletes something, so ask first.

1. The job and the copied collector. Usage data is kept:

   ```sh
   collector/install.sh --uninstall
   ```

2. The app, if the user wants it gone:

   ```sh
   rm -rf "$HOME/Applications/AIUsage.app"
   ```

3. The local data and logs, if the user wants them gone:

   ```sh
   rm -rf "$HOME/Library/Application Support/AIUsage" "$HOME/Library/Logs/AIUsage"
   ```

4. The iPhone copy and the script copy in iCloud Drive, if they exist:

   ```sh
   rm -f "$HOME/Library/Mobile Documents/iCloud~dk~simonbs~Scriptable/Documents/ai-usage.json"
   rm -f "$HOME/Library/Mobile Documents/iCloud~dk~simonbs~Scriptable/Documents/AI Usage.js"
   ```

5. The widget: the user removes it from the desktop or the Home Screen.

Nothing in these steps changes a Keychain item. Do not delete any Keychain item. The Claude Code and agy
logins belong to those apps.

## Troubleshooting

**The job hangs, or nothing is written.** A launchd job that runs a script from `~/Desktop`, `~/Documents`
or `~/Downloads` can hang on the macOS privacy (TCC) check. That is why `collector/install.sh` runs a copy
from `~/Library/Application Support/AIUsage/bin`. Keep the repository outside those three folders if you
can, and run `collector/install.sh` again after any change.

**macOS asks whether Python may access iCloud Drive.** The collector writes the iPhone copy to iCloud Drive,
so macOS may ask on the first run. The user must allow it. If the user denied it, they can turn it on again
in System Settings > Privacy & Security, then run `collector/install.sh` again.

**A login has expired.** A login that the provider's CLI reports as ended is shown as `status` `error` or `stale`,
with the message in the `error` field. The message says what to do:

- **Claude:** a Claude folder that is not logged in is left out of `usage.json`, and that is not an error. The user
  opens Claude Code once in that folder and signs in (for an extra folder, run `CLAUDE_CONFIG_DIR=<folder> claude`).
  Claude Code renews its own login while it runs.
- **ChatGPT** (`ล็อกอิน Codex หมดอายุ เปิด codex สักครั้ง`): the user runs `codex` once in a terminal and signs
  in again if asked.
- **agy** (`ล็อกอิน agy หมดอายุ`): the user runs `agy models` once in a terminal, which renews agy's own
  token and costs no quota. If it still fails, the user signs in to agy again.

A provider with no login at all is not an error. It is left out of `usage.json`.

**A provider shows `network` or `unknown`.** `network` means its CLI did not answer within 30 seconds. `unknown`
means the CLI is not installed, or its answer has a shape the collector does not know (for example after a CLI
update). The error log names the step that failed, such as `claude-main: ... (get_usage: rate_limits missing)`.
It shows no value. If the CLI moved, run `collector/install.sh` again.

**The widget shows no data.** Check these, in order:

1. `usage.json` exists and its `generated_at` is recent (step 7).
2. The job is loaded and the error log has no recent errors (step 7).
3. The Mac widget shows the placeholder "ยังไม่มีข้อมูล" when `accounts` is empty. That means no provider has
   a login on this Mac.
4. The iPhone widget needs the Mac to be on, and iCloud Drive to be synced. It shows "ยังไม่มีข้อมูล เปิด Mac ไว้"
   when the iCloud copy is missing or has no accounts.

**After updating the code**, run `collector/install.sh` again. The job runs a copy in
`~/Library/Application Support/AIUsage/bin`, so a `git pull` does not change it until the install runs again.
Run `scripts/build-mac.sh` again to rebuild the app. For the iPhone, copy `scriptable/AI Usage.js` again.

**The widget still shows old text after an update.** The widget runs as its own process, `AIUsageWidget`, and it
can keep running the old code after `AIUsage.app` is replaced. `scripts/build-mac.sh` stops it on install. If the
widget still shows old text, stop it by hand. macOS then starts it again from the new copy when it next loads:

```sh
pkill -f "[A]IUsage.app/Contents/PlugIns/AIUsageWidget.appex"
```

`pkill` prints nothing and exits with 1 when no such process is running; that is not an error. The `[A]` in the
pattern stops `pkill` from matching the shell that runs it.

**Xcode asks "Keep Xcode Version" or "Use Version on Disk".** This comes after `xcodegen generate` runs while the
project is open in Xcode. Choose **Use Version on Disk**. The build then reads the team from
`mac/Local.xcconfig`, which is what you want.

**The build says there is no Team id, or it signs with the wrong team.** The user picks the Personal Team once,
for both `AIUsage` and `AIUsageWidget`, in Xcode under Signing & Capabilities. That creates the signing
certificate. Then check that `mac/Local.xcconfig` holds the real id, not `YOURTEAMID`. Never write the id into
`mac/project.yml` or into any committed file.

**The widget is not in the gallery.** The widget is listed only after the app has been opened once. The gallery
name is "Quota Battery" in both languages, so the Mac system language does not change it.

**The menu bar icon is missing.** Check that "Show menu bar icon" is on in the app window. The app has no
open-at-login setting, so after a restart the user must open AIUsage again. The collector runs without it.
If the user uses Hidden Bar: on macOS 27, Hidden Bar older than 1.11.2 hides every third-party icon, so it
must be updated (tested with 1.13.1). With 1.13.1, a relaunched app's icon goes into the hidden section. The
user sets **Quota Battery** to **Visible** in Hidden Bar > Settings > Icons (Pinned sections).

**There are no notifications.** The 80% and 95% alerts come from the background collector, sent through
`osascript`. macOS shows them as from Script Editor or osascript, and may ask to allow notifications. Check the
window switch "Notify at 80% and 95%". Alerts fire only when a limit crosses 80% or 95% used. With the switch
off, the collector still records each crossing in `notify-state.json`, so turning it on again does not send
old alerts.

**Battery colours.** The battery shows what is left. Above 20% left it is white (the normal ink in light mode).
At 6 to 20% left it is yellow. At 5% left or less it is red. The menu bar, the Mac widgets and the iPhone widget
use the same rule (80% and 95% used). The iPhone uses darker grey, yellow and red so they read in light mode,
and above 20% left it shows grey, not white. If the user asks why the iPhone colours differ, this is the reason.

**Widgets refresh on the system's schedule.** The window and the menu bar read `usage.json` every 60 seconds.
After Refresh they check every 2 seconds, for up to 60 seconds. Widgets ask for a refresh every 5 minutes, but
WidgetKit (Mac) and iOS decide the real time, so they can lag by minutes. The iPhone copy changes only while the
Mac is on. Set this expectation with the user before they judge a widget stale.

**Language.** The window's Language picker (System / ไทย / English) sets the app, the Mac widgets and the
notification text. "System" is Thai when the Mac's first preferred language starts with `th`, and English
otherwise. The iPhone widget follows the iPhone language, unless the Parameter field is `th` or `en`.

**iPhone setup.** The user installs Scriptable and opens it once with iCloud Drive on, so that the Scriptable
folder syncs to the Mac. If "AI Usage" is missing from the script list, pull down to refresh. Tap the script
once to preview it. Then add the widget, set Script to AI Usage, and leave Parameter empty or type `th` or `en`.
While the Scriptable folder is missing, the collector skips the iPhone copy and its log says so. The Mac side
still works. `docs/guide-iphone.md` lists what the Mac must have running.

**Refresh failed: could not run launchctl**, or **Refresh failed (launchctl N)**. The job is not installed or not
loaded. Run `collector/install.sh` (step 3).

**"No data yet. Keep your Mac on."** No account has a login on this Mac, or there is no `usage.json` yet. Repeat
the checks in steps 2 and 7.
