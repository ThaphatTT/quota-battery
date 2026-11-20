# AI Usage: คู่มือติดตั้งบน Mac / AI Usage: Mac install guide

คู่มือนี้มีสองภาษา อ่านภาษาไทยก่อน ภาษาอังกฤษอยู่ต่อท้าย ([English](#english))
วิดเจ็ตบน iPhone อยู่ใน [guide-iphone.md](guide-iphone.md)
ถ้าให้ coding agent (Claude Code, Codex หรืออื่น ๆ) ติดตั้งให้ ให้ดู [AGENTS.md](../AGENTS.md)

## ภาษาไทย

### เวอร์ชันที่ทดสอบแล้ว

ทดสอบเมื่อ 2026-11-19 ด้วยเวอร์ชันเหล่านี้

| รายการ | เวอร์ชัน |
|---|---|
| macOS | 27.2.1 |
| Xcode | 27.2 |
| Python 3 | 3.15.2 (จาก Homebrew) |
| แอป AI Usage | 0.1.0 |
| iPhone (ถ้าใช้วิดเจ็ตบน iPhone) | iPhone, iOS 27.2.1, แอป Scriptable (ฟรี) |
| Hidden Bar (ไม่บังคับ) | 1.13.1 |

เวอร์ชันอื่นยังไม่ได้ทดสอบ โปรเจกต์ต้องใช้ macOS 15 ขึ้นไป

### สิ่งที่ต้องมีก่อนเริ่ม

1. **Xcode** ติดตั้งจาก App Store เปิดหนึ่งครั้ง แล้วยอมรับข้อตกลงที่ขึ้นมา
2. **เครื่องมือ command line ของ Xcode** ต้องถูกเลือกไว้ รัน `xcode-select -p` แล้วต้องเห็นพาธที่มี `Xcode.app`
3. **XcodeGen** รัน `brew install xcodegen` (ต้องมี [Homebrew](https://brew.sh) ก่อน)
4. **Python 3** ตัวที่มากับ Xcode หรือจาก Homebrew ก็ได้
5. **Apple ID** แบบฟรีก็พอ ใช้เป็น Personal Team ไม่ต้องมีบัญชีนักพัฒนาแบบเสียเงิน
6. **ไม่บังคับ** แอป Scriptable บน iPhone และ Hidden Bar (ตัวซ่อนไอคอนบนแถบเมนู)

ถ้าทำได้ ให้วางโฟลเดอร์โปรเจกต์ไว้นอก Desktop, Documents และ Downloads (เหตุผลอยู่ในหัวข้อแก้ปัญหา)

รันทุกคำสั่งใน **Terminal** จากโฟลเดอร์โปรเจกต์ (โฟลเดอร์ที่มีไฟล์ `AGENTS.md`) เช่น

```sh
cd ~/Projects/ai-usage-widget
```

ให้แทน `~/Projects/ai-usage-widget` ด้วยที่อยู่ของโฟลเดอร์คุณ

### ขั้นที่ 1: ตรวจสิ่งที่ต้องมี

```sh
sw_vers -productVersion     # ต้องได้ 15.0 ขึ้นไป
xcodebuild -version         # ต้องแสดงชื่อและเวอร์ชันของ Xcode
command -v xcodegen         # ต้องแสดงพาธ ถ้าไม่แสดง ให้รัน brew install xcodegen
command -v python3          # ต้องแสดงพาธเต็มที่ขึ้นต้นด้วย / เช่น /opt/homebrew/bin/python3
```

ถ้า `python3` ไม่แสดงพาธเต็ม ตัวติดตั้งจะหยุดทำงาน ให้ติดตั้ง Python 3 แล้วเปิด Terminal ใหม่

### ขั้นที่ 2: ทดลองอ่านบัญชี (ไม่เขียนอะไรลงเครื่อง)

```sh
python3 -I collector/ai_usage_collect.py --dry-run --no-refresh
```

คำสั่งนี้รันเครื่องมือ CLI ของผู้ให้บริการแต่ละราย คือ `claude`, `codex app-server` และ `agy` เครื่องมือเหล่านั้นติดต่อบริการของตัวเองเพื่อดึงข้อมูลการใช้งาน ตัวเก็บข้อมูลไม่อ่านและไม่เก็บโทเค็นของผู้ให้บริการ แล้วพิมพ์ผลเป็น JSON ออกมา โดยไม่เขียนไฟล์และไม่ต่ออายุโทเค็น ถ้าเปิดโหมดตรงใน `settings.json` (ใช้ได้กับ Codex และ agy เท่านั้น) ตัวเก็บข้อมูลจะอ่านการล็อกอินของผู้ให้บริการนั้นเองและเรียก endpoint ของผู้ให้บริการด้วย

**คุณจะเห็น:** JSON ที่มีรายการ `accounts` แต่ละบัญชีมี `status` ดังนี้
- `ok` ใช้ได้
- `stale` หรือ `error` ให้อ่านข้อความในช่อง `error` และดูหัวข้อแก้ปัญหาด้านล่าง
- ถ้าบัญชีใดไม่อยู่ในรายการ แปลว่าไม่ได้ล็อกอินไว้บน Mac เครื่องนี้ ซึ่งเป็นเรื่องปกติ

### ขั้นที่ 3: ติดตั้งตัวเก็บข้อมูล

```sh
collector/install.sh
```

สคริปต์นี้จะ
- คัดลอกตัวเก็บข้อมูลไปที่ `~/Library/Application Support/AIUsage/bin`
- เขียนงานไว้ที่ `~/Library/LaunchAgents/com.user.aiusage.plist` งานนี้ให้ launchd (ตัวจัดการงานเบื้องหลังของ macOS) เป็นผู้รัน
- ตั้งให้งานรันทุก 5 นาที และตอนเข้าสู่ระบบ

**คุณจะเห็น:** ข้อความที่ขึ้นต้นด้วย `ติดตั้ง com.user.aiusage แล้ว` จากนั้นรอสักครู่ แล้วตรวจว่ามีไฟล์ข้อมูล

```sh
test -f "$HOME/Library/Application Support/AIUsage/usage.json" && echo "มีไฟล์ข้อมูลแล้ว"
```

**สิ่งที่อาจเห็น:** macOS อาจถามว่าให้ Python เข้าถึง iCloud Drive ได้หรือไม่ ให้กด **อนุญาต** ถ้าไม่อนุญาต สำเนาสำหรับ iPhone จะไม่ถูกเขียน

รันซ้ำได้อย่างปลอดภัย สคริปต์จะแทนที่สำเนาและงานเดิม

### ขั้นที่ 4: ตั้ง Team id ของ Apple ใน Xcode (ทำด้วยมือ)

ขั้นนี้คุณต้องทำเอง คุณพิมพ์รหัส Apple ID ของคุณเองและเลือกทีมเอง ไม่ให้ผู้ช่วยหรือโปรแกรมทำแทน

1. เปิด Xcode แล้วไปที่ **Xcode > Settings** (หรือกด ⌘,) เลือกแท็บ **Accounts** กด **+** เลือก **Apple ID** แล้วล็อกอินด้วย Apple ID ของคุณ
   **คุณจะเห็น:** Apple ID ของคุณในรายการ Accounts
2. สร้างโปรเจกต์หนึ่งครั้ง เพื่อให้ Xcode เปิดโปรเจกต์ได้

   ```sh
   (cd mac && xcodegen generate)
   ```
3. เปิดไฟล์ `mac/AIUsage.xcodeproj` ใน Xcode แล้วทำทีละเป้าหมาย
   - เลือกเป้าหมาย **AIUsage** เลือกแท็บ **Signing & Capabilities** แล้วตั้งช่อง **Team** เป็น **Personal Team** ของคุณ
   - เลือกเป้าหมาย **AIUsageWidget** แล้วทำแบบเดียวกัน

   ขั้นนี้จะสร้างใบรับรองสำหรับเซ็นชื่อแอป ทำครั้งเดียวก็พอ
4. อ่าน Team id ที่ Xcode เลือกไว้

   ```sh
   xcodebuild -project mac/AIUsage.xcodeproj -target AIUsage -configuration Release -showBuildSettings 2>/dev/null | grep -E ' DEVELOPMENT_TEAM = [A-Za-z0-9]+'
   ```

   **คุณจะเห็น:** บรรทัดที่มี `DEVELOPMENT_TEAM = ` ตามด้วยรหัสของทีม
5. สร้างไฟล์ตั้งค่าในเครื่อง แล้วใส่รหัสนั้นลงไป

   ```sh
   cp mac/Local.xcconfig.example mac/Local.xcconfig
   ```

   เปิด `mac/Local.xcconfig` แล้วแทน `YOURTEAMID` ด้วยรหัสของคุณ ไฟล์นี้อยู่ใน `.gitignore` จึงไม่ถูกส่งขึ้น Git **ห้ามคอมมิตไฟล์นี้**
6. สร้างโปรเจกต์อีกครั้ง

   ```sh
   (cd mac && xcodegen generate)
   ```

   ถ้า Xcode ที่เปิดอยู่ถามว่า **Keep Xcode Version** หรือ **Use Version on Disk** ให้เลือก **Use Version on Disk** เสมอ

### ขั้นที่ 5: สร้างและติดตั้งแอป

```sh
scripts/build-mac.sh
```

สคริปต์จะสร้างแอปแบบ Release แล้วติดตั้งที่ `~/Applications/AIUsage.app` โดยแทนของเดิมถ้ามี ถ้าแอปกำลังเปิดอยู่ สคริปต์จะปิดให้ก่อนแล้วเปิดใหม่ให้ อาจมีคำถามเรื่องสิทธิ์ดังนี้
- ถ้า macOS ถามว่า Terminal ควบคุม AIUsage ได้หรือไม่ ให้อนุญาต ถ้าไม่อนุญาต สคริปต์จะบังคับปิดแอปหลัง 10 วินาที
- ถ้า codesign ขอใช้กุญแจสำหรับเซ็นชื่อ ให้กด **Allow** (หรือ **Always Allow** ถ้ามี)

**คุณจะเห็น:** บรรทัด `ติดตั้งแล้วที่ ...` ตามด้วย `เปิดแอป AIUsage หนึ่งครั้ง แล้วเพิ่มวิดเจ็ต Quota Battery จากหน้าวิดเจ็ตของ macOS`

ถ้าต้องการแค่สร้างโดยไม่ติดตั้ง ใช้ `scripts/build-mac.sh --no-install` ผลจะอยู่ที่ `mac/build/AIUsage.app`

### ขั้นที่ 6: เปิดแอปหนึ่งครั้ง

```sh
open "$HOME/Applications/AIUsage.app"
```

**คุณจะเห็น:** หน้าต่าง **Quota Battery** และไอคอนเล็ก ๆ (วงแหวนกับตัวเลข) บนแถบเมนู วิดเจ็ตจะไปปรากฏในหน้าวิดเจ็ตของ macOS ก็ต่อเมื่อเปิดแอปอย่างน้อยหนึ่งครั้งแล้วเท่านั้น

### ขั้นที่ 7: เพิ่มวิดเจ็ตบน Mac

1. คลิกขวาที่พื้นหลังเดสก์ท็อป แล้วเลือก **Edit Widgets** (แก้ไขวิดเจ็ต)
2. ค้นหา **Quota Battery** ชื่อวิดเจ็ตเป็นชื่อเดียวกันทั้งภาษาไทยและภาษาอังกฤษ
3. เลือกขนาด (เล็ก กลาง หรือใหญ่) แล้วกด **Add Widget** (เพิ่มวิดเจ็ต)

**คุณจะเห็น:** วิดเจ็ตที่แสดงตัวเลขการใช้งานบนเดสก์ท็อป

### ขั้นที่ 8: ตรวจว่าทำงานครบ

1. ไฟล์ข้อมูลเป็นปัจจุบัน (คำสั่งนี้แสดงเฉพาะเวลาและสถานะ ไม่มีโทเค็น)

   ```sh
   python3 -c 'import json,os; p=os.path.expanduser("~/Library/Application Support/AIUsage/usage.json"); d=json.load(open(p)); print(d["generated_at"], [(a["id"], a["status"]) for a in d["accounts"]])'
   ```
2. งานทำงานอยู่ ค่า `last exit code` ควรเป็น 0

   ```sh
   launchctl print "gui/$(id -u)/com.user.aiusage" | grep -E 'state|last exit code'
   ```
3. ไม่มีข้อผิดพลาดล่าสุดในบันทึก

   ```sh
   tail -n 20 "$HOME/Library/Logs/AIUsage/collector.err.log"
   ```
4. หน้าต่างแอปและวิดเจ็ตแสดงบัญชีชุดเดียวกับไฟล์ข้อมูล

### การใช้งานประจำวัน

**หน้าต่างแอป**
- การ์ดของแต่ละบัญชี แสดงช่วงโควตาพร้อมเวลารีเซ็ต โทเค็นที่ใช้วันนี้และเดือนนี้ ค่าใช้จ่ายโดยประมาณ และ Extra usage หรือเครดิตเมื่อผู้ให้บริการรายงาน
- **รีเฟรช** สั่งให้ตัวเก็บข้อมูลทำงานทันที
- **ภาษา** เลือกได้ที่ ตามระบบ / ไทย / English
- **แสดงไอคอนบนแถบเมนู** เปิดหรือปิดไอคอนบนแถบเมนู
- **แจ้งเตือนที่ 80% และ 95%** เปิดหรือปิดการแจ้งเตือน
- **เปิดโฟลเดอร์ log** เปิดโฟลเดอร์บันทึก `~/Library/Logs/AIUsage`

**ไอคอนบนแถบเมนู**
- แสดงวงแหวนกับตัวเลขที่ **เหลือ** ของบัญชีหรือโควตาที่เหลือน้อยที่สุด
- คลิกเพื่อเปิดป๊อปโอเวอร์ ซึ่งมี **รีเฟรช** **เปิดแอป** และ **ออก (Quit)**
- ปิดหน้าต่างไม่ทำให้แอปหยุด ไอคอนยังอยู่บนแถบเมนู
- **ออก (Quit)** จะปิดแอปและทำให้ไอคอนหายไป แอปไม่เปิดเองหลังเข้าสู่ระบบ ต้องเปิดเอง ส่วนตัวเก็บข้อมูลยังทำงานต่อได้โดยไม่ต้องเปิดแอป

**สีของแถบแบตเตอรี่และวงแหวน** ทั้งสองแสดง **จำนวนที่เหลือ** แถบจะหมดลงเมื่อใช้มากขึ้น
- มากกว่า 20% เหลือ: สีขาวบนพื้นมืด หรือสีตัวอักษรปกติในโหมดสว่าง
- 6–20% เหลือ: สีเหลือง
- 5% เหลือหรือน้อยกว่า: สีแดง
- เมนูบาร์ วิดเจ็ตบน Mac และวิดเจ็ตบน iPhone ใช้กฎเดียวกันนี้

**การแจ้งเตือน** จะมาเมื่อใช้ไปถึง 80% (เหลือ 20%) และ 95% (เหลือ 5%) ครั้งละหนึ่งครั้งต่อช่วงโควตา ถ้าปิดสวิตช์ ตัวเก็บข้อมูลยังจดไว้ว่าเคยข้ามเกณฑ์แล้ว เมื่อเปิดกลับมาจึงไม่แจ้งย้อนหลัง แต่ถ้าการใช้งานขึ้นไปถึงเกณฑ์ที่สูงกว่าหลังจากนั้น จะแจ้งตามปกติ

**ภาษา** ตัวเลือกในหน้าต่างใช้กับแอป วิดเจ็ตบน Mac และข้อความการแจ้งเตือน ตัวเลือก "ตามระบบ" จะใช้ภาษาไทยเมื่อภาษาแรกที่ตั้งไว้ใน Mac ขึ้นต้นด้วย `th` นอกนั้นใช้ภาษาอังกฤษ วิดเจ็ตบน iPhone ใช้ภาษาของ iPhone หรือค่าในช่อง Parameter (ดูคู่มือ iPhone)

**การรีเฟรช**
- ตัวเก็บข้อมูลทำงานทุก 5 นาที
- หน้าต่างแอปและแถบเมนูอ่านไฟล์ทุก 60 วินาที หลังกดรีเฟรช แอปจะตรวจไฟล์ทุก 2 วินาที สูงสุด 60 วินาที จนกว่าไฟล์จะเปลี่ยน
- วิดเจ็ตบน Mac ขอรีเฟรชทุก 5 นาที แต่ macOS เป็นผู้ตัดสินเวลาจริง อาจช้ากว่าเป็นนาที

### ที่เก็บไฟล์

| รายการ | ที่อยู่ |
|---|---|
| ข้อมูลการใช้งาน | `~/Library/Application Support/AIUsage/usage.json` |
| สำเนาสำหรับ iPhone | `~/Library/Mobile Documents/iCloud~dk~simonbs~Scriptable/Documents/ai-usage.json` |
| การตั้งค่า (ภาษาและการแจ้งเตือน) | `~/Library/Application Support/AIUsage/settings.json` |
| บันทึก | `~/Library/Logs/AIUsage/` |
| งานอัตโนมัติ | `~/Library/LaunchAgents/com.user.aiusage.plist` |
| แอป | `~/Applications/AIUsage.app` |

### แก้ปัญหา

**build-mac.sh บอกว่าไม่พบ Team id** ทำขั้นที่ 4 ให้ครบ แล้วตรวจว่าใน `mac/Local.xcconfig` มีรหัสจริง ไม่ใช่ `YOURTEAMID`

**Xcode ถาม Keep Xcode Version หรือ Use Version on Disk** เลือก **Use Version on Disk** เสมอ คำถามนี้เกิดหลังรัน `xcodegen generate` ตอนที่ Xcode เปิดโปรเจกต์ค้างอยู่

**ไม่เห็นวิดเจ็ต Quota Battery ในหน้าวิดเจ็ต** เปิดแอปหนึ่งครั้ง (ขั้นที่ 6) แล้วค้นหา Quota Battery

**วิดเจ็ตยังแสดงข้อความเก่าหลังอัปเดต** วิดเจ็ตทำงานเป็นโปรเซสของตัวเองชื่อ `AIUsageWidget` และอาจยังรันโค้ดเก่าอยู่ ให้หยุดด้วยคำสั่งนี้ macOS จะเปิดโค้ดใหม่เองเมื่อโหลดวิดเจ็ตครั้งถัดไป

```sh
pkill -f "[A]IUsage.app/Contents/PlugIns/AIUsageWidget.appex"
```

ถ้าไม่มีโปรเซสนั้นอยู่ `pkill` จะไม่พิมพ์อะไรและออกด้วยรหัส 1 ซึ่งไม่ใช่ข้อผิดพลาด ถ้ายังไม่หาย ให้ลองรีสตาร์ท Mac

**ไอคอนบนแถบเมนูหายไป**
1. ดูว่าสวิตช์ **แสดงไอคอนบนแถบเมนู** ในหน้าต่างแอปเปิดอยู่
2. ถ้าแอปไม่ได้เปิดอยู่ ให้เปิดแอป เพราะแอปไม่เปิดเองหลังรีสตาร์ท
3. ถ้าใช้ Hidden Bar หรือแอปซ่อนไอคอนอื่น
   - บน macOS 27 Hidden Bar รุ่นก่อน 1.11.2 จะซ่อนไอคอนของแอปภายนอกทุกตัว ให้ใช้ 1.11.2 ขึ้นไป (ทดสอบแล้วกับ 1.13.1)
   - ใน Hidden Bar 1.13.1 เมื่อเปิดแอปใหม่ macOS จะวางไอคอนไว้ในส่วนที่ซ่อน ให้ไปที่ Hidden Bar > Settings > Icons แล้วตั้ง **Quota Battery** เป็น **Visible** ในส่วน Pinned sections

**ไม่มีการแจ้งเตือน**
- ตรวจว่าสวิตช์ **แจ้งเตือนที่ 80% และ 95%** เปิดอยู่
- ในการตั้งค่าของ macOS (System Settings) หมวด การแจ้งเตือน ให้อนุญาตสำหรับ **Script Editor** หรือ **osascript** เพราะ macOS มักแสดงการแจ้งเตือนของงานเบื้องหลังนี้ด้วยชื่อนั้น
- การแจ้งเตือนมาเฉพาะตอนข้ามเกณฑ์ 80% หรือ 95% ถ้าการใช้งานยังต่ำกว่า จะไม่มีการแจ้งเตือน

**สำเนาสำหรับ iPhone ไม่ถูกเขียน** ดูบรรทัดล่าสุดใน `~/Library/Logs/AIUsage/collector.err.log` หรือ `collector.out.log`
- "ไม่พบโฟลเดอร์ iCloud ของ Scriptable": ติดตั้ง Scriptable บน iPhone แล้วเปิดด้วย iCloud Drive ให้ซิงก์มาที่ Mac ก่อน (ดูคู่มือ iPhone ข้อ 1–3)
- "เขียนสำเนา iCloud ไม่สำเร็จ": Python ยังไม่ได้รับสิทธิ์เข้าถึง iCloud Drive ให้เปิดสิทธิ์ใน System Settings > Privacy & Security (ความเป็นส่วนตัวและความปลอดภัย) แล้วรัน `collector/install.sh` อีกครั้ง

**งานเก็บข้อมูลไม่ทำงาน หรือไม่มีไฟล์ usage.json** ตรวจด้วยคำสั่งในขั้นที่ 8 แล้วดูบรรทัดล่าสุดของบันทึกข้อผิดพลาด ถ้าโปรเจกต์อยู่ใน Desktop, Documents หรือ Downloads แล้วงานค้าง ให้ย้ายโปรเจกต์ออกไป แล้วรัน `collector/install.sh` อีกครั้ง เหตุผลคือ งานที่รันสคริปต์จากสามโฟลเดอร์นี้อาจค้างเมื่อ macOS ตรวจสิทธิ์ความเป็นส่วนตัว (TCC) ตัวติดตั้งจึงคัดลอกตัวเก็บข้อมูลไปไว้ที่ `~/Library/Application Support/AIUsage/bin`

**รีเฟรชไม่สำเร็จ: เรียก launchctl ไม่ได้** หรือ **รีเฟรชไม่สำเร็จ (launchctl ...)** แปลว่างานยังไม่ได้ติดตั้งหรือถูกปิดอยู่ ให้รัน `collector/install.sh` (ขั้นที่ 3)

**แสดง "ยังไม่มีข้อมูล เปิด Mac ไว้"** ไม่มีบัญชีที่ล็อกอินบน Mac เครื่องนี้ หรือยังไม่มีไฟล์ `usage.json` ให้ทำขั้นที่ 2 และขั้นที่ 8 อีกครั้ง

**บัญชีแสดงสถานะ error หรือ stale** อ่านข้อความในช่อง `error` ซึ่งบอกว่าต้องทำอะไร
- **Claude** (ล็อกอิน Claude หมดอายุ): เปิด Claude Code หนึ่งครั้ง แล้วรอรอบถัดไป Claude Code ต่ออายุการล็อกอินของตัวเองขณะทำงาน ตัวเก็บข้อมูลไม่ได้ต่ออายุโทเค็นให้
- **ChatGPT** (ล็อกอิน Codex หมดอายุ): รัน `codex` หนึ่งครั้งในเทอร์มินัล แล้วล็อกอินใหม่ถ้าถูกถาม
- **agy** (ล็อกอิน agy หมดอายุ): รัน `agy models` หนึ่งครั้ง คำสั่งนี้ต่ออายุโทเค็นของ agy เองและไม่กินโควตา ถ้ายังไม่ได้ ให้ล็อกอิน agy ใหม่
- ผู้ให้บริการที่ไม่มีการล็อกอินเลยจะไม่อยู่ในไฟล์ ซึ่งไม่ถือเป็นข้อผิดพลาด

**หลังอัปเดตโค้ด** รัน `collector/install.sh` อีกครั้ง เพราะงานรันจากสำเนาใน Application Support การ `git pull` อย่างเดียวจึงยังไม่เปลี่ยนสำเนานั้น จากนั้นรัน `scripts/build-mac.sh` และคัดลอก `scriptable/AI Usage.js` ใหม่ไปยัง iPhone

### ถอนการติดตั้ง

ทำทีละข้อ และทำเฉพาะข้อที่ต้องการ แต่ละข้อจะลบของออก

1. งานและสำเนาตัวเก็บข้อมูล (ข้อมูลการใช้งานยังอยู่)

   ```sh
   collector/install.sh --uninstall
   ```
2. แอป

   ```sh
   rm -rf "$HOME/Applications/AIUsage.app"
   ```
3. ข้อมูลและบันทึกในเครื่อง

   ```sh
   rm -rf "$HOME/Library/Application Support/AIUsage" "$HOME/Library/Logs/AIUsage"
   ```
4. สำเนาสำหรับ iPhone และสคริปต์ที่คัดลอกไว้ใน iCloud Drive (ถ้ามี)

   ```sh
   rm -f "$HOME/Library/Mobile Documents/iCloud~dk~simonbs~Scriptable/Documents/ai-usage.json"
   rm -f "$HOME/Library/Mobile Documents/iCloud~dk~simonbs~Scriptable/Documents/AI Usage.js"
   ```
5. วิดเจ็ตบนเดสก์ท็อป คลิกขวาที่วิดเจ็ตแล้วเลือกลบ วิดเจ็ตบน iPhone ดูในคู่มือ iPhone

ไม่มีขั้นใดแตะรายการใน Keychain อย่าลบรายการใน Keychain เพราะเป็นของ Claude Code และ agy

---

## English

### Tested versions

Tested on 2026-11-19: macOS 27.2.1, Xcode 27.2, Python 3.15.2 (Homebrew), app 0.1.0, iPhone on iOS 27.2.1 with Scriptable (free), and Hidden Bar 1.13.1 (optional). Other versions are untested. The project needs macOS 15 or newer.

### What you need first

1. **Xcode** from the App Store. Open it once and accept the license.
2. **Xcode command line tools** selected. `xcode-select -p` must print a path that contains `Xcode.app`.
3. **XcodeGen**: `brew install xcodegen` (needs [Homebrew](https://brew.sh)).
4. **Python 3**, either the one that comes with Xcode or the one from Homebrew.
5. **An Apple ID.** A free one is enough. It is used as a Personal Team, so no paid developer account is needed.
6. **Optional:** the Scriptable app on the iPhone, and Hidden Bar (a menu bar hider).

If you can, keep the project folder outside Desktop, Documents and Downloads (the reason is in Troubleshooting).

Run every command in **Terminal**, from the project folder (the one that contains `AGENTS.md`), for example:

```sh
cd ~/Projects/ai-usage-widget
```

Replace `~/Projects/ai-usage-widget` with the location of your folder.

### Step 1: check the prerequisites

```sh
sw_vers -productVersion     # must print 15.0 or newer
xcodebuild -version         # must print the Xcode name and version
command -v xcodegen         # must print a path. If nothing prints, run brew install xcodegen
command -v python3          # must print a full path that starts with /, for example /opt/homebrew/bin/python3
```

If `python3` does not print a full path, the installer stops. Install Python 3, then open a new Terminal window.

### Step 2: dry run (writes nothing)

```sh
python3 -I collector/ai_usage_collect.py --dry-run --no-refresh
```

This runs each provider's own command-line tool: `claude`, `codex app-server` and `agy`. Each tool contacts its own service to get your usage. The collector reads and stores no login token in this mode. It prints the result as JSON and writes no file, and it does not renew any token. Only if you turn on direct mode in `settings.json` (Codex and agy only) does the collector read that provider's login itself and call its usage endpoint.

**You will see:** JSON with an `accounts` list. Each account has a `status`:
- `ok`: it works.
- `stale` or `error`: read the `error` text and see Troubleshooting below.
- An account that is not listed has no login on this Mac. That is normal.

### Step 3: install the collector

```sh
collector/install.sh
```

The script does three things:
- It copies the collector to `~/Library/Application Support/AIUsage/bin`.
- It writes a job to `~/Library/LaunchAgents/com.user.aiusage.plist`. The job is run by launchd (the macOS background task manager).
- It runs the job every 5 minutes and when you log in.

**You will see:** a line that starts with `ติดตั้ง com.user.aiusage แล้ว` (installed). Wait a moment, then check that the data file exists:

```sh
test -f "$HOME/Library/Application Support/AIUsage/usage.json" && echo "data file exists"
```

**You may see:** macOS asks whether Python may access iCloud Drive. Click **Allow**. If you refuse, the iPhone copy is never written.

Running the script again is safe. It replaces the copy and the job.

### Step 4: set your Apple Team id in Xcode (by hand)

You do this part yourself. You type your own Apple ID password and pick the team. Do not let an assistant or a script do it for you.

1. Open Xcode, go to **Xcode > Settings** (or press ⌘,), open the **Accounts** tab, click **+**, choose **Apple ID**, and sign in with your Apple ID.
   **You will see:** your Apple ID in the Accounts list.
2. Generate the project once so that Xcode can open it:

   ```sh
   (cd mac && xcodegen generate)
   ```
3. Open `mac/AIUsage.xcodeproj` in Xcode. Do this for each target:
   - Select the **AIUsage** target, open the **Signing & Capabilities** tab, and set **Team** to your **Personal Team**.
   - Select the **AIUsageWidget** target and do the same.

   This creates the signing certificate. You only need to do it once.
4. Read the Team id that Xcode picked:

   ```sh
   xcodebuild -project mac/AIUsage.xcodeproj -target AIUsage -configuration Release -showBuildSettings 2>/dev/null | grep -E ' DEVELOPMENT_TEAM = [A-Za-z0-9]+'
   ```

   **You will see:** a line with `DEVELOPMENT_TEAM = ` followed by your team id.
5. Create the local settings file and put the id in it:

   ```sh
   cp mac/Local.xcconfig.example mac/Local.xcconfig
   ```

   Open `mac/Local.xcconfig` and replace `YOURTEAMID` with your id. The file is listed in `.gitignore`, so it is not uploaded to Git. **Never commit this file.**
6. Generate the project again:

   ```sh
   (cd mac && xcodegen generate)
   ```

   If the open Xcode window asks **Keep Xcode Version** or **Use Version on Disk**, always choose **Use Version on Disk**.

### Step 5: build and install the app

```sh
scripts/build-mac.sh
```

The script builds a Release app and installs it at `~/Applications/AIUsage.app`, replacing an older copy. If the app is open, the script quits it first and opens it again afterwards. You may see these prompts:
- If macOS asks whether Terminal may control AIUsage, allow it. If you refuse, the script force-quits the app after 10 seconds.
- If codesign asks to use the signing key, click **Allow** (or **Always Allow** if you see it).

**You will see:** `ติดตั้งแล้วที่ ...` (installed at ...) and `เปิดแอป AIUsage หนึ่งครั้ง แล้วเพิ่มวิดเจ็ต Quota Battery จากหน้าวิดเจ็ตของ macOS` (open AIUsage once, then add the Quota Battery widget).

To build without installing, use `scripts/build-mac.sh --no-install`. The app is then at `mac/build/AIUsage.app`.

### Step 6: open the app once

```sh
open "$HOME/Applications/AIUsage.app"
```

**You will see:** the **Quota Battery** window, and a small icon (a ring with a number) in the menu bar. The widget appears in the macOS widget gallery only after the app has been opened at least once.

### Step 7: add the Mac widget

1. Right-click the desktop background and choose **Edit Widgets**.
2. Search for **Quota Battery**. The widget has the same name in Thai and English.
3. Choose a size (small, medium or large) and click **Add Widget**.

**You will see:** a widget on the desktop that shows your usage numbers.

### Step 8: check that everything works

1. The data file is up to date. This command prints only the time and each account's status. It shows no tokens.

   ```sh
   python3 -c 'import json,os; p=os.path.expanduser("~/Library/Application Support/AIUsage/usage.json"); d=json.load(open(p)); print(d["generated_at"], [(a["id"], a["status"]) for a in d["accounts"]])'
   ```
2. The job is loaded. `last exit code` should be 0.

   ```sh
   launchctl print "gui/$(id -u)/com.user.aiusage" | grep -E 'state|last exit code'
   ```
3. The log has no recent errors.

   ```sh
   tail -n 20 "$HOME/Library/Logs/AIUsage/collector.err.log"
   ```
4. The app window and the widget show the same accounts as the data file.

### Daily use

**The app window**
- An account card for each account: the limit windows with their reset times, tokens used today and this month, an estimated API cost, and extra usage or credits when the provider reports them.
- **Refresh** runs the collector now.
- **Language** lets you choose System / ไทย / English.
- **Show menu bar icon** turns the menu bar icon on or off.
- **Notify at 80% and 95%** turns the notifications on or off.
- **Open log folder** opens `~/Library/Logs/AIUsage`.

**The menu bar icon**
- It shows a ring and a number: what is **left** on the account or limit with the least left.
- Click it to open a popover with **Refresh**, **Open app** and **Quit**.
- Closing the window does not stop the app. The icon stays in the menu bar.
- **Quit** closes the app and removes the icon. The app does not start at login, so open it yourself after a restart. The collector keeps running without the app.

**Colours of the battery bars and rings.** They show what is **left**, and the bar drains as usage grows.
- More than 20% left: white on a dark background, or the normal text colour in light mode.
- 6 to 20% left: yellow.
- 5% left or less: red.
- The menu bar, the Mac widgets and the iPhone widget all follow this rule.

**Notifications** come when usage reaches 80% (20% left) and 95% (5% left), once per window. When the switch is off, the collector still records each crossing, so turning it back on does not send old alerts. A higher threshold reached later still alerts.

**Language.** The choice in the window applies to the app, the Mac widgets and the notification text. "System" uses Thai when the first language in your Mac's list starts with `th`, and English otherwise. The iPhone widget has its own setting (see the iPhone guide).

**Refresh timing**
- The collector runs every 5 minutes.
- The app window and the menu bar read the file every 60 seconds. After you press Refresh, the app checks every 2 seconds for up to 60 seconds, until the file changes.
- The Mac widgets ask for a refresh every 5 minutes, but macOS decides the real time. They can be minutes late.

### Where things are

| Item | Location |
|---|---|
| Usage data | `~/Library/Application Support/AIUsage/usage.json` |
| iPhone copy | `~/Library/Mobile Documents/iCloud~dk~simonbs~Scriptable/Documents/ai-usage.json` |
| Settings (language, notifications) | `~/Library/Application Support/AIUsage/settings.json` |
| Logs | `~/Library/Logs/AIUsage/` |
| Background job | `~/Library/LaunchAgents/com.user.aiusage.plist` |
| App | `~/Applications/AIUsage.app` |

### Troubleshooting

**build-mac.sh says there is no Team id.** Finish step 4, then check that `mac/Local.xcconfig` holds your real id, not `YOURTEAMID`.

**Xcode asks Keep Xcode Version or Use Version on Disk.** Choose **Use Version on Disk**. The question comes after `xcodegen generate` runs while Xcode still has the project open.

**The Quota Battery widget is not in the widget gallery.** Open the app once (step 6), then search for **Quota Battery**.

**The widget still shows old text or the old language after an update.** The widget runs as its own process, `AIUsageWidget`, and can keep running the old code. Stop it with this command. macOS starts the new copy the next time it loads the widget.

```sh
pkill -f "[A]IUsage.app/Contents/PlugIns/AIUsageWidget.appex"
```

When no such process exists, `pkill` prints nothing and exits with code 1. That is not an error. If the widget still does not change, restart the Mac.

**The menu bar icon is missing.**
1. Check that **Show menu bar icon** is on in the app window.
2. If the app is not running, open it. It does not start by itself after a restart.
3. If you use Hidden Bar or another menu bar hider:
   - On macOS 27, Hidden Bar older than 1.11.2 hides every third-party icon. Use 1.11.2 or newer (tested with 1.13.1).
   - In Hidden Bar 1.13.1, after the app is relaunched, macOS puts its icon in the hidden section. Open Hidden Bar > Settings > Icons and set **Quota Battery** to **Visible** in the Pinned sections.

**There are no notifications.**
- Check that **Notify at 80% and 95%** is on.
- In System Settings > Notifications, allow **Script Editor** or **osascript**. macOS uses one of these names for this background job.
- Alerts come only when usage crosses 80% or 95%. Below those levels, you will see none.

**The iPhone copy is not written.** Read the last lines of `~/Library/Logs/AIUsage/collector.err.log` or `collector.out.log`.
- "The Scriptable iCloud folder was not found": install Scriptable on the iPhone, open it with iCloud Drive on, and let it sync to the Mac first (iPhone guide, steps 1 to 3).
- "The iCloud copy could not be written": Python does not have access to iCloud Drive. Turn it on in System Settings > Privacy & Security, then run `collector/install.sh` again.

**The job does not run, or there is no usage.json.** Use the commands in step 8. Read the last lines of the error log. If the project is in Desktop, Documents or Downloads and the job hangs, move the project out of those folders and run `collector/install.sh` again. macOS privacy checks (TCC) can block a job that runs a script from those folders, which is why the installer runs a copy from `~/Library/Application Support/AIUsage/bin`.

**Refresh failed: could not run launchctl**, or **Refresh failed (launchctl ...)**. The job is not installed or not loaded. Run `collector/install.sh` (step 3).

**The app shows "No data yet. Keep your Mac on."** No account is logged in on this Mac, or there is no `usage.json` yet. Repeat steps 2 and 8.

**An account shows status error or stale.** Read the `error` text, which says what to do:
- **Claude** (Claude login expired): open Claude Code once and wait for the next run. Claude Code renews its own login while it runs. The collector does not renew any token.
- **ChatGPT** (Codex login expired): run `codex` once in Terminal and sign in again if asked.
- **agy** (agy login expired): run `agy models` once. It renews agy's own token and costs no quota. If that does not work, sign in to agy again.
- A provider with no login at all is left out of the file. That is not an error.

**After an update.** Run `collector/install.sh` again, because the job runs a copy in `~/Library/Application Support/AIUsage/bin` and a `git pull` alone does not change that copy. Then run `scripts/build-mac.sh`, and copy `scriptable/AI Usage.js` to the iPhone side again.

### Uninstall

Do only the items you want. Each item deletes something.

1. The job and the copied collector. Usage data is kept.

   ```sh
   collector/install.sh --uninstall
   ```
2. The app.

   ```sh
   rm -rf "$HOME/Applications/AIUsage.app"
   ```
3. The local data and logs.

   ```sh
   rm -rf "$HOME/Library/Application Support/AIUsage" "$HOME/Library/Logs/AIUsage"
   ```
4. The iPhone copy and the script copy in iCloud Drive, if they exist.

   ```sh
   rm -f "$HOME/Library/Mobile Documents/iCloud~dk~simonbs~Scriptable/Documents/ai-usage.json"
   rm -f "$HOME/Library/Mobile Documents/iCloud~dk~simonbs~Scriptable/Documents/AI Usage.js"
   ```
5. The desktop widget: right-click it and remove it. For the iPhone widget, see the iPhone guide.

No step touches the Keychain. Do not delete any Keychain item, because the Claude Code and agy logins belong to those apps.
