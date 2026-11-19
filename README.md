# AI Usage Widget

Shows how much of your AI usage limit you have used, for three accounts you are already logged in to
on your own Mac:

- **Claude**, through the Claude Code login
- **ChatGPT**, through the Codex CLI login
- **agy** (Antigravity CLI)

It has a macOS widget (WidgetKit) and an optional iPhone widget (Scriptable). Nothing is hosted and
there is no login screen: the accounts are found from the logins that already exist on your Mac.

- `collector/`: a Python 3 script (standard library only) that a launchd job runs every 5 minutes. It
  reads the logins, asks each provider for your current limits and writes `usage.json`.
- `mac/`: a SwiftUI macOS app and a WidgetKit widget. The Xcode project is generated with XcodeGen.
- `scriptable/`: the iPhone widget script. It reads the copy of `usage.json` in iCloud Drive.
- `docs/usage-json.md`: the data format that connects the three parts.

For each account the widgets show the limit windows with their reset times, tokens used today and this
month, an estimated API cost, and extra usage or credits when the provider reports them. macOS
notifications come at 80% and 95% of a limit.

## How to use

1. **Install.** The easy way: ask your coding assistant (for example Claude Code or Codex) to follow [AGENTS.md](AGENTS.md). By hand: follow [docs/guide-mac.md](docs/guide-mac.md).
2. **Open the app once.** Open **AI Usage**. The widget appears in the widget list only after the app has been opened.
3. **Add the widget.** Right-click an empty part of the desktop, choose **Edit Widgets**, search for **AI Usage**, pick a size and add it.
4. **Read the battery.** It shows how much quota you have **left**. White means plenty is left (more than 20%). Yellow means 6 to 20% is left. Red means 5% or less is left.
5. **Check the menu bar icon.** It shows the account with the least quota left, as a ring and a number. Click it to see the details.
6. **Choose the language.** Near the bottom of the app window, under the two switches, choose **System**, **ไทย** or **English**.
7. **iPhone (optional).** See [docs/guide-iphone.md](docs/guide-iphone.md).

Tested with macOS 27.2.1, Xcode 27.2 and iOS 27.2.1. Other versions are untested.

## Privacy and security

- **What is read.** Nothing secret by default. The collector runs each provider's own command-line tool and
  reads the usage that it prints: Claude Code (`claude`), the Codex CLI (`codex app-server`) and agy (`agy`).
  Each tool uses the login it already has on this Mac. In this default mode the collector never reads,
  refreshes or stores a provider token. It also reads the local usage logs `~/.claude/projects/**/*.jsonl`
  and `~/.codex/sessions/**/*.jsonl`. From those logs only token counts, model names and dates are kept, and
  message text is not stored. It checks which Claude and Codex folders exist (`~/.claude*`, `~/.codex*`, and any
  folder listed in `accounts.json`). For agy it checks only that the Keychain item is there; it does not open it.
- **Where it is sent.** The collector sends nothing itself. Each provider's own tool contacts its own service
  to get your usage, the same as when you use that tool. The collector makes no model request: it asks for
  usage only, and it stops any run that takes longer than 30 seconds.
- **Direct mode (off by default; Codex and agy only).** `settings.json` can turn it on for one provider:
  `"direct_mode": {"codex": true, "agy": true}`. Only the JSON value `true` turns it on. In direct mode the
  collector reads that provider's login itself and calls its usage endpoint:
  - Codex: the token in `~/.codex/auth.json` is sent to `https://chatgpt.com/backend-api/wham/usage`.
  - agy: the token in the Keychain (service `gemini`, account `antigravity`) is sent to
    `https://daily-cloudcode-pa.googleapis.com/v1internal:loadCodeAssist` and
    `https://daily-cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels`. When that token has expired and
    the `agy` command is installed, the collector runs `agy models` once. That command renews agy's own token
    and costs no quota.

  Claude has no direct mode.
- **Nothing else is uploaded.** There is no server of this project, no analytics and no telemetry. The iPhone
  copy goes only to your own iCloud Drive.
- **Tokens never enter `usage.json`**, the logs or the output. The collector masks token-like text and e-mail
  addresses before it writes any log line, and it never writes a provider tool's own output to the log.
- **Files it writes**, all under your home folder: `~/Library/Application Support/AIUsage/` (`usage.json`,
  `cache.json`, `notify-state.json`, a copy of the collector in `bin/`), `~/Library/Logs/AIUsage/`, and the
  launchd job `~/Library/LaunchAgents/com.user.aiusage.plist`. `cache.json` keeps the paths of your local usage
  log files, which include your project folder names, plus per-day token totals and model names, so the logs
  are not read again on every run. It stays on your Mac and is never uploaded. The provider tools may write
  their own files, as they do when you use them.
- **Unofficial.** The three provider tools are their own official programs. The Claude `get_usage` request is an
  experimental API of Claude Code (its name says so), so it may change between versions. The collector does not
  pin any CLI version. The direct-mode endpoints are not documented or supported for this use, and they may
  change or stop working at any time. The software is provided with no warranty (see LICENSE).

## No App Store: build it yourself

The app is not on the App Store and no build is distributed. You build it on your own Mac and sign it
with your own **free Apple ID** (a Personal Team in Xcode). A paid developer account is not needed. The
app is for your own Mac.

## Requirements

- macOS 15 or newer.
- Xcode, with its command-line tools selected (`xcode-select -p` shows `Xcode.app`).
- XcodeGen: `brew install xcodegen`.
- `python3` (the one that comes with Xcode or Homebrew).
- Optional, for the iPhone widget: the free **Scriptable** app.

## Quick start

Give this repository to your coding agent (Claude Code, Codex or similar) and ask it to install the
project by following [AGENTS.md](AGENTS.md). The agent checks each step first and asks you before it
touches credentials, the Keychain, launchd, `~/Applications` or iCloud Drive.

Or do it yourself, starting from [AGENTS.md](AGENTS.md). In short:

1. `python3 -I collector/ai_usage_collect.py --dry-run --no-refresh` prints which accounts were found.
2. `collector/install.sh` installs the collector as a launchd job.
3. Copy `mac/Local.xcconfig.example` to `mac/Local.xcconfig`, put your Team id in it, then run
   `scripts/build-mac.sh`. The app is installed in `~/Applications`. Open it once.
4. Add the **AI Usage** widget from the macOS widget gallery.
5. iPhone (optional): see [scriptable/README.md](scriptable/README.md).

To remove everything, see the uninstall step in [AGENTS.md](AGENTS.md).

## Project structure

- `collector/`: the Python 3 collector and its launchd job, with tests.
- `mac/`: the macOS app and the WidgetKit widget. The Xcode project is generated from `mac/project.yml`.
- `scriptable/`: the iPhone widget script, with tests.
- `docs/usage-json.md`: the data contract that connects the parts.
- `scripts/`: the build script for the Mac app. `scripts/release/` holds the release plan.
- `site/`: the landing page placeholder. It is not built yet.
- `windows/`: notes for a Windows port. Help wanted.

Contributing: see [CONTRIBUTING.md](CONTRIBUTING.md). Plans: see [ROADMAP.md](ROADMAP.md).

## License

MIT. See [LICENSE](LICENSE).

---

# AI Usage Widget (ภาษาไทย)

แสดงว่าคุณใช้โควตาของ AI ไปแล้วเท่าไร สำหรับสามบัญชีที่ล็อกอินอยู่แล้วบน Mac ของคุณ:

- **Claude** ผ่านการล็อกอินของ Claude Code
- **ChatGPT** ผ่านการล็อกอินของ Codex CLI
- **agy** (Antigravity CLI)

มีวิดเจ็ตบน macOS (WidgetKit) และวิดเจ็ตบน iPhone แบบเลือกติดตั้ง (Scriptable) ไม่มีเซิร์ฟเวอร์กลาง
และไม่มีหน้าล็อกอิน โปรเจกต์หาบัญชีจากการล็อกอินที่มีอยู่แล้วบน Mac

- `collector/`: สคริปต์ Python 3 (ใช้เฉพาะไลบรารีมาตรฐาน) ที่ launchd รันทุก 5 นาที มันอ่านการล็อกอิน
  ถามแต่ละผู้ให้บริการว่าโควตาปัจจุบันเป็นเท่าไร แล้วเขียนไฟล์ `usage.json`
- `mac/`: แอป SwiftUI และวิดเจ็ต WidgetKit โปรเจกต์ Xcode สร้างด้วย XcodeGen
- `scriptable/`: สคริปต์วิดเจ็ตบน iPhone อ่านสำเนา `usage.json` ที่อยู่ใน iCloud Drive
- `docs/usage-json.md`: รูปแบบข้อมูลที่เชื่อมสามส่วนนี้เข้าด้วยกัน

แต่ละบัญชีแสดงช่วงเวลาของโควตาพร้อมเวลารีเซ็ต โทเค็นที่ใช้วันนี้และเดือนนี้ ค่าใช้จ่ายโดยประมาณ
และ Extra usage หรือเครดิตเมื่อผู้ให้บริการรายงานมา มีการแจ้งเตือนบน macOS เมื่อโควตาถึง 80% และ 95%

## วิธีใช้งาน

1. **ติดตั้ง** วิธีที่ง่ายที่สุดคือให้ผู้ช่วยเขียนโค้ด (เช่น Claude Code หรือ Codex) ทำตามไฟล์ [AGENTS.md](AGENTS.md) ซึ่งเป็นคู่มือขั้นตอนติดตั้งสำหรับผู้ช่วย ถ้าอยากทำเองทีละขั้น ให้ทำตาม [docs/guide-mac.md](docs/guide-mac.md)
2. **เปิดแอปหนึ่งครั้ง** เปิดแอป **AI Usage** วิดเจ็ตจะขึ้นในรายการวิดเจ็ตได้ก็ต่อเมื่อเปิดแอปแล้วเท่านั้น
3. **เพิ่มวิดเจ็ต** คลิกขวาที่พื้นที่ว่างบนเดสก์ท็อป เลือก **Edit Widgets** ค้นหา **AI Usage** เลือกขนาด แล้วกดเพิ่ม
4. **อ่านแถบแบตเตอรี่** แถบจะแสดงว่าโควตายัง **เหลือ** อยู่เท่าไร สีขาว = ยังเหลือเยอะ (มากกว่า 20%) สีเหลือง = เหลือ 6 ถึง 20% สีแดง = เหลือ 5% หรือน้อยกว่า
5. **ดูไอคอนบนแถบเมนู** (แถบด้านบนสุดของจอ) ไอคอนจะแสดงบัญชีที่โควตาเหลือน้อยที่สุด เป็นวงแหวนกับตัวเลข คลิกเพื่อดูรายละเอียด
6. **เลือกภาษา** ใกล้ด้านล่างของหน้าต่างแอป ใต้สวิตช์สองตัว เลือก **ตามระบบ**, **ไทย** หรือ **English**
7. **iPhone (ไม่บังคับ)** ดูที่ [docs/guide-iphone.md](docs/guide-iphone.md)

ทดสอบแล้วกับ macOS 27.2.1, Xcode 27.2 และ iOS 27.2.1 เวอร์ชันอื่นยังไม่ได้ทดสอบ

## ความเป็นส่วนตัวและความปลอดภัย

- **สิ่งที่อ่าน** ค่าเริ่มต้นไม่อ่านข้อมูลลับ ตัวเก็บข้อมูลรันคำสั่งเครื่องมือของผู้ให้บริการแต่ละรายแล้วอ่านผลการใช้งาน
  ที่เครื่องมือพิมพ์ออกมา ได้แก่ Claude Code (`claude`), Codex CLI (`codex app-server`) และ agy (`agy`) เครื่องมือ
  แต่ละตัวใช้การล็อกอินที่มีอยู่แล้วบน Mac นี้ ในโหมดนี้ตัวเก็บข้อมูลไม่อ่าน ไม่ต่ออายุ และไม่เก็บโทเค็นของผู้ให้บริการ
  นอกจากนี้ยังอ่านบันทึกการใช้งานในเครื่องที่ `~/.claude/projects/**/*.jsonl` กับ `~/.codex/sessions/**/*.jsonl`
  จากบันทึกเหล่านั้นเก็บเฉพาะจำนวนโทเค็น ชื่อโมเดล และวันที่ ไม่เก็บข้อความ ตัวเก็บข้อมูลดูว่ามีโฟลเดอร์ Claude และ
  Codex อะไรบ้าง (`~/.claude*`, `~/.codex*` และโฟลเดอร์ที่ระบุใน `accounts.json`) และสำหรับ agy ดูเพียงว่ามีรายการ
  ใน Keychain หรือไม่ โดยไม่เปิดอ่านรายการนั้น
- **ส่งไปที่ไหน** ตัวเก็บข้อมูลไม่ได้ส่งอะไรเอง เครื่องมือของผู้ให้บริการแต่ละรายจะติดต่อบริการของตัวเองเพื่อดึงข้อมูล
  การใช้งาน เหมือนตอนที่คุณใช้เครื่องมือนั้นตามปกติ ตัวเก็บข้อมูลไม่ส่งคำขอให้โมเดลใดๆ จะขอแค่ข้อมูลการใช้งาน
  และหยุดการทำงานของแต่ละรอบที่นานเกิน 30 วินาที
- **โหมดตรง (ปิดไว้เป็นค่าเริ่มต้น ใช้ได้กับ Codex และ agy เท่านั้น)** เปิดได้รายผู้ให้บริการใน `settings.json` ด้วย
  `"direct_mode": {"codex": true, "agy": true}` มีผลเฉพาะค่า JSON `true` ในโหมดนี้ตัวเก็บข้อมูลจะอ่านการล็อกอินของ
  ผู้ให้บริการนั้นเอง แล้วเรียก endpoint ดึงข้อมูลการใช้งาน
  - Codex: โทเค็นใน `~/.codex/auth.json` ถูกส่งไปที่ `https://chatgpt.com/backend-api/wham/usage`
  - agy: โทเค็นใน Keychain (service `gemini`, account `antigravity`) ถูกส่งไปที่
    `https://daily-cloudcode-pa.googleapis.com/v1internal:loadCodeAssist` และ
    `https://daily-cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels` เมื่อโทเค็นนั้นหมดอายุและติดตั้ง
    คำสั่ง `agy` ไว้ ตัวเก็บข้อมูลจะรัน `agy models` หนึ่งครั้ง คำสั่งนี้ต่ออายุโทเค็นของ agy เองและไม่กินโควตา

  Claude ไม่มีโหมดตรง
- **ไม่มีการอัปโหลดอย่างอื่น** โปรเจกต์นี้ไม่มีเซิร์ฟเวอร์ ไม่มีการวิเคราะห์การใช้งาน และไม่มีการส่ง telemetry
  สำเนาสำหรับ iPhone ถูกส่งไปที่ iCloud Drive ของคุณเองเท่านั้น
- **โทเค็นไม่เคยเข้าไปอยู่ใน `usage.json`** ไม่อยู่ในบันทึก และไม่อยู่ในผลลัพธ์ ตัวเก็บข้อมูลจะปิดบังข้อความที่เป็น
  รูปแบบโทเค็นและอีเมลก่อนเขียนลง log ทุกบรรทัด และไม่เขียนผลลัพธ์ดิบของเครื่องมือผู้ให้บริการลงบันทึกเลย
- **ไฟล์ที่เขียน** ทั้งหมดอยู่ในโฟลเดอร์ผู้ใช้ของคุณ: `~/Library/Application Support/AIUsage/` (มี `usage.json`,
  `cache.json`, `notify-state.json` และสำเนาตัวเก็บข้อมูลใน `bin/`), `~/Library/Logs/AIUsage/` และงาน launchd
  `~/Library/LaunchAgents/com.user.aiusage.plist` ไฟล์ `cache.json` เก็บพาธของไฟล์บันทึกการใช้งานในเครื่อง ซึ่งมีชื่อ
  โฟลเดอร์โปรเจกต์ของคุณอยู่ด้วย พร้อมยอดโทเค็นรายวันและชื่อโมเดล เพื่อไม่ให้ต้องอ่านบันทึกทั้งหมดซ้ำทุกรอบ ไฟล์นี้อยู่บน
  Mac ของคุณเท่านั้นและไม่ถูกอัปโหลด เครื่องมือของผู้ให้บริการอาจเขียนไฟล์ของตัวเองด้วย เหมือนตอนที่คุณใช้งานตามปกติ
- **ไม่ใช่ API ทางการ** เครื่องมือทั้งสามเป็นโปรแกรมทางการของผู้ให้บริการเอง แต่คำขอ `get_usage` ของ Claude Code เป็น
  API ทดลองที่ชื่อบอกไว้แล้ว อาจเปลี่ยนไปตามเวอร์ชัน ตัวเก็บข้อมูลไม่ได้ล็อกเวอร์ชันของ CLI ใดๆ ส่วน endpoint ของโหมดตรง
  ไม่ได้เอกสารไว้สำหรับการใช้งานแบบนี้ และอาจเปลี่ยนหรือหยุดทำงานเมื่อไรก็ได้ ซอฟต์แวร์นี้ให้ใช้โดยไม่มีการรับประกัน (ดู LICENSE)

## ไม่มี App Store: ให้สร้างเอง

แอปนี้ไม่ได้อยู่บน App Store และไม่มีการแจกไฟล์ที่สร้างแล้ว คุณสร้างแอปบน Mac ของตัวเองและเซ็นด้วย
**Apple ID ฟรี** ของคุณ (Personal Team ใน Xcode) ไม่ต้องใช้บัญชีนักพัฒนาแบบเสียเงิน แอปนี้ใช้กับ Mac ของคุณเอง

## สิ่งที่ต้องมี

- macOS 15 ขึ้นไป
- Xcode และเลือก command-line tools แล้ว (`xcode-select -p` ต้องชี้ไปที่ `Xcode.app`)
- XcodeGen: `brew install xcodegen`
- `python3` (ตัวที่มาพร้อม Xcode หรือจาก Homebrew)
- ไม่บังคับ: แอป **Scriptable** (ฟรี) สำหรับวิดเจ็ตบน iPhone

## เริ่มต้นอย่างรวดเร็ว

ส่งโฟลเดอร์โปรเจกต์นี้ให้ coding agent ของคุณ (Claude Code, Codex หรืออื่น ๆ) แล้วสั่งให้ติดตั้งตาม
[AGENTS.md](AGENTS.md) เอเจนต์จะตรวจแต่ละขั้นก่อน และจะถามคุณก่อนแตะการล็อกอิน Keychain, launchd,
`~/Applications` หรือ iCloud Drive

หรือทำเองตาม [AGENTS.md](AGENTS.md) สรุปสั้น ๆ คือ:

1. `python3 -I collector/ai_usage_collect.py --dry-run --no-refresh` แสดงว่าพบบัญชีไหนบ้าง
2. `collector/install.sh` ติดตั้งตัวเก็บข้อมูลเป็นงาน launchd
3. คัดลอก `mac/Local.xcconfig.example` เป็น `mac/Local.xcconfig` แล้วใส่ Team id ของคุณ จากนั้นรัน
   `scripts/build-mac.sh` แอปจะถูกติดตั้งใน `~/Applications` เปิดแอปหนึ่งครั้ง
4. เพิ่มวิดเจ็ต **AI Usage** จากหน้าวิดเจ็ตของ macOS
5. iPhone (ไม่บังคับ): ดู [scriptable/README.md](scriptable/README.md)

ถ้าต้องการถอนการติดตั้งทั้งหมด ดูขั้นตอนถอนการติดตั้งใน [AGENTS.md](AGENTS.md)

## โครงสร้างโปรเจกต์

- `collector/`: ตัวเก็บข้อมูลด้วย Python 3 พร้อมงาน launchd และเทสต์
- `mac/`: แอป macOS และวิดเจ็ต WidgetKit โปรเจกต์ Xcode สร้างจาก `mac/project.yml`
- `scriptable/`: สคริปต์วิดเจ็ตบน iPhone พร้อมเทสต์
- `docs/usage-json.md`: รูปแบบข้อมูลที่เชื่อมแต่ละส่วนเข้าด้วยกัน
- `scripts/`: สคริปต์สร้างแอป Mac โฟลเดอร์ `scripts/release/` เก็บแผนการปล่อยเวอร์ชัน
- `site/`: พื้นที่สำหรับหน้าเว็บ ยังไม่ได้สร้าง
- `windows/`: บันทึกสำหรับพอร์ตไป Windows ต้องการผู้ช่วย

การมีส่วนร่วม: ดู [CONTRIBUTING.md](CONTRIBUTING.md) แผนงาน: ดู [ROADMAP.md](ROADMAP.md)

## ใบอนุญาต

MIT ดู [LICENSE](LICENSE)
