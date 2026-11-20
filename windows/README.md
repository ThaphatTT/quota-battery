# Windows port (community, help wanted)

Quota Battery runs on macOS only today. A Windows version does not exist yet.

The maintainer does not build or test Windows. The Windows port is left to the community. If you want to build it, you are welcome to start.

## Who tests what

- **The maintainer** reviews pull requests and keeps the data contract stable. The maintainer does not test on Windows.
- **Contributors** build and test on real Windows 10 or 11 machines. Attach screenshots to the pull request, so that reviewers can see the result.
- **There is no Windows CI.** Nothing runs the Windows build automatically.

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
- **A UI.** See the suggested approach below.
- **The iPhone copy.** The iCloud path is macOS only. A port decides how the iPhone copy is kept, or whether it is kept at all.

## Suggested approach

This is a suggestion, not a rule. You may choose another way.

### 1. A tray app in Python

- Write the app in Python with **PySide6** (the Qt framework for Python).
- Use **QSystemTrayIcon** for a battery icon in the notification area (the system tray, next to the clock).
- Colour the battery by the lowest quota that is left:
  - white when more than 20% is left;
  - yellow when 6% to 20% is left;
  - red when 5% or less is left.
- A click opens a small popover-style window. It shows the same rows as the Mac popover.
- Optional: a small frameless window that stays on top, in a desktop corner.

### 2. Packaging

- Package the app with **BeeWare Briefcase** to make a `.msi` installer.
- **PyInstaller** is an alternative if Briefcase does not work for your app.

### 3. Reuse the collector

- Reuse the collector's Python code. Do not rewrite it.
- Replace the macOS-only parts listed in "What exists today":
  - the Keychain check, with a Windows check (see Credential sources above);
  - launchd, with **Task Scheduler**;
  - `osascript`, with a **Windows toast notification**;
  - the iCloud copy, with a decision on the iPhone copy;
  - the `fcntl` file lock, with a lock that works on Windows.

### 4. Out of scope for a first version

- **The Windows 11 Widgets board** needs a separate widget provider, built with the **Windows App SDK** in C#. This is a different project, so leave it out of a first version.

### 5. An alternative: Tauri

- **Tauri** can make a smaller app with a web user interface.
- It does not run Python. The collector must still ship with Python as a separate program.

## The Claude model mix (optional)

`usage.json` now also carries `by_family` and `model_prices`. These show the token counts per Claude model family, and the list prices. See [docs/usage-json.md](../docs/usage-json.md).

A Windows app can show the Claude model mix too. This is optional. A first version can leave it out.

## Where to start

Read [docs/usage-json.md](../docs/usage-json.md) and [CONTRIBUTING.md](../CONTRIBUTING.md). Open an issue that says what you want to build, so that two people do not build the same thing. Discuss the choice of UI in the issue before you start.

---

# พอร์ตไป Windows (ภาษาไทย)

Quota Battery ทำงานบน macOS เท่านั้นในตอนนี้ ยังไม่มีเวอร์ชัน Windows

ผู้ดูแลโปรเจกต์ไม่ได้สร้างหรือทดสอบบน Windows การพอร์ตไป Windows จึงฝากไว้ให้ชุมชน หากคุณอยากสร้าง ยินดีต้อนรับเลย

## ใครทดสอบอะไร

- **ผู้ดูแลโปรเจกต์** ตรวจ pull request และรักษาความเสถียรของ data contract ผู้ดูแลไม่ได้ทดสอบบน Windows
- **ผู้ร่วมพัฒนา** สร้างและทดสอบบนเครื่อง Windows 10 หรือ 11 จริง แนบภาพหน้าจอไปกับ pull request เพื่อให้ผู้ตรวจเห็นผลลัพธ์
- **ไม่มี CI สำหรับ Windows** ไม่มีระบบรันการ build บน Windows อัตโนมัติ

## สิ่งที่มีอยู่ตอนนี้

- **ตัวเก็บข้อมูล (collector)** คือ `collector/ai_usage_collect.py` เป็นสคริปต์ Python 3 ที่ใช้เฉพาะไลบรารีมาตรฐาน ส่วนที่ใช้ได้เฉพาะ macOS มีดังนี้:
  - การตรวจ Keychain สำหรับ agy ผ่านคำสั่ง `security` ของ macOS (ตรวจแค่ว่ามีอยู่หรือไม่ โหมด direct ยังอ่านการล็อกอินของ agy ด้วย);
  - งาน launchd ที่รันทุก 5 นาที คือ `collector/install.sh` (bash) และ `collector/com.user.aiusage.plist.template`;
  - การแจ้งเตือนของ macOS ที่ส่งด้วย `osascript`;
  - การคัดลอกไปยัง iCloud สำหรับวิดเจ็ตบน iPhone เขียนไว้ใต้ `~/Library/Mobile Documents/`;
  - ไฟล์ล็อก ซึ่งใช้ `fcntl` จึงใช้ได้เฉพาะระบบแบบ Unix
- **data contract** คือ [docs/usage-json.md](../docs/usage-json.md) ไม่ขึ้นกับแพลตฟอร์ม โปรแกรมอ่านบน Windows ต้องอ่านไฟล์ `usage.json` ไฟล์เดียวกัน และโปรแกรมที่เขียนต้องแทนที่ไฟล์ทั้งไฟล์ในขั้นตอนเดียว (atomic)
- **แอปและวิดเจ็ตของ Mac** ใน `mac/` ใช้ SwiftUI และ WidgetKit ซึ่งใช้ได้เฉพาะ macOS การพอร์ตไป Windows จะไม่ใช้โค้ดส่วนนี้ซ้ำ

## สิ่งที่การพอร์ตไป Windows ต้องมี

- **แหล่งข้อมูลการล็อกอิน** Windows Credential Manager เป็นที่หนึ่งที่ควรดู ตัวเก็บข้อมูลไม่ได้อ่านการล็อกอินของ Claude โดยตรง แต่รันคำสั่ง `claude`, `codex` และ `agy` และแต่ละตัวเก็บการล็อกอินของตัวเอง ให้ตรวจบนเครื่อง Windows จริงว่าแต่ละคำสั่งรันได้ และ agy เก็บการล็อกอินไว้ที่ใดสำหรับโหมด direct การล็อกอินของ Codex เป็นไฟล์บน Mac (`~/.codex/auth.json`) และตัวเก็บข้อมูลยังอ่านล็อกไฟล์ในเครื่องใต้ `~/.claude/` และ `~/.codex/` ด้วย ตรวจทั้งหมดนี้บนเครื่อง Windows จริงก่อนเขียนโค้ด อย่าเดาเส้นทางไฟล์
- **ตัวตั้งเวลา** ใช้ Task Scheduler แทน launchd ควรรันตัวเก็บข้อมูลทุก 5 นาที และตอนผู้ใช้ลงชื่อเข้าใช้
- **การแจ้งเตือน** ใช้การแจ้งเตือนของ Windows แทน `osascript` ที่เกณฑ์ 80% และ 95% เดิมตามที่ data contract อธิบาย
- **ส่วนติดต่อผู้ใช้ (UI)** ดูแนวทางที่แนะนำด้านล่าง
- **สำเนาสำหรับ iPhone** เส้นทาง iCloud ใช้ได้เฉพาะ macOS การพอร์ตต้องตัดสินใจว่าจะเก็บสำเนาสำหรับ iPhone อย่างไร หรือจะไม่เก็บเลย

## แนวทางที่แนะนำ

นี่เป็นข้อเสนอแนะ ไม่ใช่กฎ คุณเลือกวิธีอื่นได้

### 1. แอปถาดระบบ (tray app) ด้วย Python

- เขียนแอปด้วย Python โดยใช้ **PySide6** (เฟรมเวิร์ก Qt สำหรับ Python)
- ใช้ **QSystemTrayIcon** แสดงไอคอนรูปแบตเตอรี่ในพื้นที่แจ้งเตือน (system tray ข้างนาฬิกา)
- เปลี่ยนสีแบตเตอรี่ตามโควตาที่เหลือน้อยที่สุด:
  - สีขาว เมื่อเหลือมากกว่า 20%;
  - สีเหลือง เมื่อเหลือ 6% ถึง 20%;
  - สีแดง เมื่อเหลือ 5% หรือน้อยกว่า
- เมื่อคลิก ให้เปิดหน้าต่างขนาดเล็กแบบป๊อปโอเวอร์ แสดงแถวเดียวกับป๊อปโอเวอร์บน Mac
- ตัวเลือก: หน้าต่างขนาดเล็กไม่มีกรอบ อยู่บนสุดเสมอ วางไว้ที่มุมเดสก์ท็อป

### 2. การแพ็กเกจ

- แพ็กเกจแอปด้วย **BeeWare Briefcase** เพื่อให้ได้ตัวติดตั้งแบบ `.msi`
- **PyInstaller** เป็นทางเลือก หาก Briefcase ใช้กับแอปของคุณไม่ได้

### 3. ใช้โค้ดตัวเก็บข้อมูลซ้ำ

- ใช้โค้ด Python ของตัวเก็บข้อมูลซ้ำ ไม่ต้องเขียนใหม่
- แทนที่ส่วนที่ใช้ได้เฉพาะ macOS ที่ระบุไว้ใน "สิ่งที่มีอยู่ตอนนี้":
  - การตรวจ Keychain ใช้วิธีตรวจของ Windows (ดูแหล่งข้อมูลการล็อกอินด้านบน);
  - launchd ใช้ **Task Scheduler**;
  - `osascript` ใช้ **การแจ้งเตือนแบบ toast ของ Windows**;
  - การคัดลอก iCloud ใช้การตัดสินใจเรื่องสำเนาสำหรับ iPhone;
  - ไฟล์ล็อก `fcntl` ใช้ไฟล์ล็อกที่ทำงานบน Windows ได้

### 4. ไม่รวมในเวอร์ชันแรก

- **กระดาน Widgets ของ Windows 11** ต้องใช้ตัวให้บริการวิดเจ็ตแยกต่างหาก สร้างด้วย **Windows App SDK** ในภาษา C# นี่เป็นโปรเจกต์อีกชุดหนึ่ง จึงควรไม่รวมในเวอร์ชันแรก

### 5. ทางเลือก: Tauri

- **Tauri** สร้างแอปที่มีขนาดเล็กกว่า โดยใช้ส่วนติดต่อผู้ใช้แบบเว็บ
- Tauri ไม่ได้รัน Python ตัวเก็บข้อมูลยังต้องส่งมาพร้อม Python เป็นโปรแกรมแยกต่างหาก

## โมเดลที่ใช้ของ Claude (ไม่บังคับ)

`usage.json` ตอนนี้มี `by_family` และ `model_prices` เพิ่มเข้ามา ข้อมูลนี้แสดงจำนวนโทเค็นแยกตามตระกูลโมเดลของ Claude และราคาตามรายการ ดู [docs/usage-json.md](../docs/usage-json.md)

แอป Windows แสดงสัดส่วนโมเดลของ Claude ได้เช่นกัน ส่วนนี้ไม่บังคับ เวอร์ชันแรกจะไม่รวมก็ได้

## เริ่มต้นที่ไหน

อ่าน [docs/usage-json.md](../docs/usage-json.md) และ [CONTRIBUTING.md](../CONTRIBUTING.md) เปิด issue ที่บอกว่าคุณอยากสร้างอะไร เพื่อไม่ให้สองคนสร้างสิ่งเดียวกันซ้ำกัน และคุยเรื่องการเลือก UI ใน issue ก่อนเริ่มงาน
