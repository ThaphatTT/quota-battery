# Contributing to AI Usage

Thank you for helping. AI Usage shows how much of your AI usage limit you have used, for Claude, ChatGPT (Codex CLI) and agy, on your own Mac. It has a macOS widget, a menu bar app and an iPhone widget through Scriptable.

## Set up

Start with [AGENTS.md](AGENTS.md). It lists the setup steps in order, and each step starts with a check. The requirements are in [README.md](README.md): macOS 15 or newer, Xcode, XcodeGen and `python3`.

Your Apple Team id goes in `mac/Local.xcconfig`. That file is gitignored. Never commit it, and never put a Team id in a tracked file.

## Running the tests

Run all three suites before you open a pull request, from the repository root. Every test must run and pass. A skipped test does not count as a pass, so read the per-test output.

**Collector** (Python, standard library only; no network, no real Keychain and no real CLI):

```sh
python3 -m unittest discover -s collector/tests -t collector -v
```

**iPhone widget** (Scriptable script, tested with Node's built-in test runner; no `npm install` is needed):

```sh
node --test --test-reporter=spec scriptable/test/
```

**Mac app and widget** (XCTest; the tests need no signing identity):

```sh
xcodebuild -project mac/AIUsage.xcodeproj -scheme AIUsage -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
```

The snapshot tests write PNG images to `mac/build/snapshots/`. That folder is gitignored. Open the images to check the layout by eye.

If you change `mac/project.yml`, run `(cd mac && xcodegen generate)` first, and commit the regenerated `mac/AIUsage.xcodeproj`.

## Code layout

```text
collector/                  Python 3 collector, launchd job and tests
  ai_usage_collect.py       reads the logins, asks each provider, writes usage.json
  install.sh                installs the launchd job (--uninstall removes it)
  tests/                    unittest tests
mac/                        SwiftUI app, WidgetKit widget and XCTest tests
  project.yml               XcodeGen spec; AIUsage.xcodeproj is generated from it
  AIUsage/                  the app and the menu bar
  AIUsageWidget/            the WidgetKit extension
  Shared/                   code used by both the app and the widget
  Tests/                    XCTest tests
scriptable/                 iPhone widget script (AI Usage.js) and its tests
scripts/build-mac.sh        builds the Mac app and installs it in ~/Applications
scripts/release/            release plan (no scripts yet)
docs/usage-json.md          the data contract
site/                       landing page placeholder (not built yet)
windows/                    notes for a Windows port (help wanted)
```

## The data contract

The collector writes one file, `usage.json` (schema 1). The Mac app, the Mac widget and the iPhone widget only read it. The Mac app writes its own `settings.json`, which the collector reads. The full format is in [docs/usage-json.md](docs/usage-json.md). Read it before you change any field.

- Writers replace the file atomically: write `usage.json.tmp`, then rename it.
- Readers ignore unknown fields. A missing file or broken JSON means "no data yet". It must never crash a reader.
- The file never contains tokens, refresh tokens, e-mail addresses or account ids.
- Adding an optional field is fine. Renaming or removing a field, or changing what it means, changes the contract. Then update `docs/usage-json.md` and every reader in the same pull request.

## Rules

- **Never log or commit tokens.** A token is a secret that lets someone use your login. Do not print, log, write or commit one. Do not paste a Keychain item, `~/.codex/auth.json` or any other login into an issue or a pull request. The collector masks token-like text and e-mail addresses before it writes a log line. Keep that behaviour.
- **Unofficial endpoints may change.** The provider endpoints are not documented for this use, and they can change or stop working at any time. Show a failure as `status` `error` or `stale` with an `error_code`. Never let it crash the collector or a reader.
- **Keep Thai and English strings together.** Every text a user can see needs a Thai and an English version in the same change.
- **Update the privacy section first.** If a change sends data to a new place, update the privacy section of [README.md](README.md) in the same pull request.
- **Keep local files out of git.** `mac/Local.xcconfig` holds your Team id and is gitignored. Build output (`build/`, `DerivedData/` and `mac/build/`) is gitignored too.

## Good first issues

- **Windows port.** The biggest open item, built by the community. The suggested approach is a tray app in Python with PySide6, packaged with BeeWare Briefcase. See [windows/README.md](windows/README.md).
- **A Linux collector.** The collector already uses only the standard library, which helps. Check on a real Linux machine that the `claude`, `codex` and `agy` CLIs run there, and where agy keeps its login if direct mode is needed, before you write any code.
- **More providers.** Add a provider to the collector, add its `provider` value to [docs/usage-json.md](docs/usage-json.md), and add tests. Check the endpoint with a real login first.

## Sending a change

1. Fork the repository and create a branch for your change.
2. Make the change, and run the tests above.
3. Open a pull request. The template asks what changed and how you tested it.

Keep each pull request to one topic. Report a bug with the bug report template, and attach only a redacted `usage.json`.

---

# การมีส่วนร่วม (ภาษาไทย)

ขอบคุณที่ช่วยพัฒนา AI Usage โปรเจกต์นี้แสดงว่าคุณใช้โควตาของ Claude, ChatGPT (Codex CLI) และ agy ไปแล้วเท่าไร บน Mac ของคุณเอง

- **ตั้งค่า:** เริ่มจาก [AGENTS.md](AGENTS.md) ซึ่งมีขั้นตอนเรียงตามลำดับ และมีการตรวจก่อนทำแต่ละขั้น Team id ของ Apple ใส่ในไฟล์ `mac/Local.xcconfig` ซึ่งถูกตั้งให้ git ไม่ติดตาม (gitignore) อย่า commit ไฟล์นี้
- **รันเทสต์:** ใช้คำสั่งในหัวข้อ Running the tests ด้านบน รันจากโฟลเดอร์รากของโปรเจกต์ ทุกเทสต์ต้องรันและผ่าน เทสต์ที่ถูกข้าม (skipped) ไม่นับว่าผ่าน
- **กฎสำคัญ:**
  - ห้าม log หรือ commit โทเค็น (รหัสลับที่ใช้ล็อกอิน) และห้ามวางการล็อกอินใด ๆ ลงใน issue หรือ pull request
  - endpoint ของผู้ให้บริการไม่ได้เป็นทางการ อาจเปลี่ยนหรือหยุดทำงานได้ทุกเมื่อ
  - ข้อความที่ผู้ใช้เห็นต้องมีทั้งภาษาไทยและภาษาอังกฤษในการแก้ไขเดียวกัน
- **งานสำหรับมือใหม่:** พอร์ตไป Windows (ชุมชนเป็นผู้ทำ มีแนวทางที่แนะนำใน windows/README.md), ตัวเก็บข้อมูลสำหรับ Linux และผู้ให้บริการ AI รายอื่น
- **ส่งงาน:** fork โปรเจกต์ สร้าง branch สำหรับการแก้ไข แล้วเปิด pull request
