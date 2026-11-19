# AI Usage: คู่มือวิดเจ็ตบน iPhone / AI Usage: iPhone widget guide

คู่มือนี้มีสองภาษา อ่านภาษาไทยก่อน ภาษาอังกฤษอยู่ต่อท้าย ([English](#english))
ทำ [guide-mac.md](guide-mac.md) ให้ถึงขั้นที่ 6 ก่อน (มีตัวเก็บข้อมูลและแอปติดตั้งแล้ว) แล้วค่อยทำวิดเจ็ตบน iPhone ตามลำดับในคู่มือนี้
รายละเอียดของสคริปต์อยู่ใน [scriptable/README.md](../scriptable/README.md)

## ภาษาไทย

### เวอร์ชันที่ทดสอบแล้ว

ทดสอบเมื่อ 2026-11-19 บน iPhone ที่ใช้ iOS 27.2.1 กับแอป Scriptable (ฟรี) เวอร์ชันอื่นยังไม่ได้ทดสอบ

### สิ่งที่ต้องมี

- Mac ที่ติดตั้ง AI Usage และตัวเก็บข้อมูลแล้ว (ตามคู่มือ Mac ขั้นที่ 3–6)
- iPhone และ Mac ใช้ **Apple ID เดียวกัน** และเปิด **iCloud Drive** ทั้งคู่
- แอป **Scriptable** จาก App Store (ฟรี)

### ข้อสำคัญ: Mac ต้องทำงานอยู่ก่อน

วิดเจ็ตบน iPhone ไม่ได้เก็บข้อมูลเอง Mac เป็นผู้เก็บข้อมูลแล้วเขียนไฟล์ `ai-usage.json` ลงใน iCloud Drive iPhone ทำหน้าที่อ่านไฟล์นั้นอย่างเดียว ดังนั้นตรวจสิ่งต่อไปนี้บน Mac ก่อน

1. **ตัวเก็บข้อมูลทำงานอยู่** ค่า `last exit code` ควรเป็น 0

   ```sh
   launchctl print "gui/$(id -u)/com.user.aiusage" | grep -E 'state|last exit code'
   ```
2. **มีโฟลเดอร์ Scriptable ใน iCloud Drive ของ Mac** ถ้าไม่มี แปลว่า Scriptable บน iPhone ยังไม่ได้ซิงก์มาที่ iCloud ให้ทำขั้นที่ 1–3 ด้านล่างบน iPhone ก่อน แล้วรอสักครู่

   ```sh
   test -d "$HOME/Library/Mobile Documents/iCloud~dk~simonbs~Scriptable/Documents" && echo "มีโฟลเดอร์แล้ว" || echo "ยังไม่มี"
   ```
3. **มีสคริปต์ AI Usage ในโฟลเดอร์นั้น**

   ```sh
   test -f "$HOME/Library/Mobile Documents/iCloud~dk~simonbs~Scriptable/Documents/AI Usage.js" && echo "มีสคริปต์แล้ว" || echo "ยังไม่มี"
   ```

   ถ้ายังไม่มี ให้คัดลอกด้วยมือ: ใน Finder กด ⌘⇧G พิมพ์ `~/Library/Mobile Documents/iCloud~dk~simonbs~Scriptable/Documents` แล้วลากไฟล์ `scriptable/AI Usage.js` ของโปรเจกต์ไปวางในโฟลเดอร์นั้น
4. **มีไฟล์ข้อมูลสำหรับ iPhone** ถ้ายังไม่มี ให้รอให้ตัวเก็บข้อมูลรอบถัดไปทำงาน (ไม่เกิน 5 นาที) แล้วตรวจอีกครั้ง

   ```sh
   test -f "$HOME/Library/Mobile Documents/iCloud~dk~simonbs~Scriptable/Documents/ai-usage.json" && echo "มีไฟล์แล้ว" || echo "ยังไม่มี"
   ```
5. **Mac เปิดอยู่** ตัวเลขบน iPhone จะอัปเดตเฉพาะตอนที่ Mac เปิดอยู่
6. **macOS อนุญาตให้ Python เข้าถึง iCloud Drive แล้ว** ถ้าเคยปฏิเสธไป ให้เปิดสิทธิ์ใน System Settings > Privacy & Security (ความเป็นส่วนตัวและความปลอดภัย) แล้วรัน `collector/install.sh` อีกครั้ง

### ขั้นตอนบน iPhone

1. ติดตั้ง **Scriptable** จาก App Store แล้วเปิดหนึ่งครั้ง
2. ตั้ง iCloud Drive ให้ Scriptable: ไปที่ **การตั้งค่า > [ชื่อของคุณ] > iCloud > iCloud Drive** ให้เปิดอยู่ แล้วเปิดแอป **Scriptable** ในรายการแอปที่ใช้ iCloud Drive
3. เปิด Scriptable แล้วดูรายการสคริปต์ ต้องเห็นสคริปต์ชื่อ **AI Usage**
   - ถ้ายังไม่เห็น ให้ดึงรายการลงเพื่อรีเฟรช หรือปิดแอปแล้วเปิดใหม่ รอสักครู่ เพราะสคริปต์ซิงก์มาจาก Mac ทาง iCloud
   - ถ้าผ่านไปหลายนาทียังไม่เห็น ให้กลับไปตรวจบน Mac ตามข้อ 2 และข้อ 3 ด้านบน
4. แตะ ▶ ที่สคริปต์ **AI Usage** หนึ่งครั้ง แอปจะแสดงตัวอย่างวิดเจ็ตขนาดกลาง
   - ถ้าขึ้นข้อความ "ยังไม่มีข้อมูล เปิด Mac ไว้" แปลว่ายังไม่มีข้อมูลใน iCloud ให้เปิด Mac แล้วรอสักครู่
5. เพิ่มวิดเจ็ตที่หน้าจอโฮม
   1. กดค้างที่พื้นที่ว่างบนหน้าจอโฮม จนไอคอนเริ่มขยับ
   2. กด **แก้ไข (Edit)** แล้วกด **เพิ่มวิดเจ็ต (Add Widget)** ถ้า iPhone ของคุณแสดงปุ่ม **+** แทน ให้กด **+** แล้วทำตามนั้น
   3. เลือก **Scriptable**
   4. เลือกขนาด เล็ก กลาง หรือใหญ่
   5. กด **เพิ่มวิดเจ็ต (Add Widget)**
6. กดค้างที่วิดเจ็ต แล้วเลือก **แก้ไขวิดเจ็ต (Edit Widget)**
   - ช่อง **Script**: เลือก **AI Usage**
   - ช่อง **Parameter**: เว้นว่างไว้ หรือพิมพ์ `th` หรือ `en` (ดูหัวข้อภาษาด้านล่าง)
7. กลับไปที่หน้าโฮม

**คุณจะเห็น:** "เหลือ N%" กับแถบแบตเตอรี่หรือวงแหวน (ดูหัวข้อการอ่านตัวเลข)

### ภาษา

- ค่าเริ่มต้นตามภาษาของ iPhone ถ้าภาษาขึ้นต้นด้วย `th` จะแสดงภาษาไทย นอกนั้นแสดงภาษาอังกฤษ
- บังคับได้ที่ช่อง **Parameter**: พิมพ์ `th` ให้แสดงภาษาไทยเสมอ หรือ `en` ให้แสดงภาษาอังกฤษเสมอ
- ตัวพิมพ์เล็กหรือใหญ่ไม่สำคัญ ช่องว่างหน้าหลังถูกตัดออก ค่าอื่น เช่น `ja` จะถูกเมิน แล้วใช้ภาษาของ iPhone แทน
- วิดเจ็ตบน iPhone ไม่ได้ตามตัวเลือกภาษาในหน้าต่างของแอป Mac

### การอ่านตัวเลข

- แถบแบตเตอรี่และวงแหวนแสดง **จำนวนที่เหลือ** แถบจะหมดลงเมื่อใช้มากขึ้น
- ตัวเลขใหญ่คือ "เหลือ N%" และตัวเลขเล็กใต้ตัวเลขนั้นคือ "ใช้ไป N%" ตัวเลขที่เหลือปัดขึ้น ตัวเลขที่ใช้ไปปัดลง รวมกันได้ 100 เสมอ
- สี
  - มากกว่า 20% เหลือ: สีเทา
  - 6–20% เหลือ: สีเหลืองเข้ม และมีป้าย "ใกล้หมด"
  - 5% เหลือหรือน้อยกว่า: สีแดงเข้ม และมีป้าย "ใกล้หมด" กรอบกับหัวแบตเตอรี่เป็นสีแดงด้วย
- สีของแถบและวงแหวนเหมือนกันทั้งโหมดสว่างและโหมดมืด สีเหลืองและแดงของตัวอักษรและป้ายจะสว่างขึ้นในโหมดมืด
- สีบน iPhone เข้มกว่าบน Mac เพื่อให้อ่านออกในโหมดสว่าง กฎการแบ่งระดับเหมือนกันทุกที่ (เมนูบาร์ วิดเจ็ตบน Mac และ iPhone)
- วิดเจ็ตขนาดเล็กแสดงเฉพาะตัวเลขที่เหลือในวงแหวน ส่วนท้ายวิดเจ็ตนับจำนวนวงแหวนที่ใกล้หมด

### ข้อควรรู้

- ตัวเลขอัปเดตเฉพาะตอนที่ Mac เปิดอยู่ เพราะ Mac เป็นผู้เขียนไฟล์
- วิดเจ็ตขอให้รีเฟรชทุก 5 นาที แต่ iOS เป็นผู้ตัดสินเวลาจริง อาจช้ากว่านั้นได้มาก
- ข้อความ "อัปเดต N นาทีก่อน" บอกว่าไฟล์ถูกเขียนเมื่อไร ถ้าบัญชีใดมีข้อผิดพลาดหรือข้อมูลเก่า วิดเจ็ตจะแสดงข้อความของบัญชีนั้นแทนเวลารีเซ็ต
- การกดรีเฟรชในแอป Mac จะสั่งให้เก็บข้อมูลและเขียนไฟล์ใหม่ แต่การอัปเดตวิดเจ็ตบน iPhone ยังขึ้นกับ iOS

### แก้ปัญหา

- **ยังไม่มีข้อมูล เปิด Mac ไว้**: ยังไม่มี `ai-usage.json` ใน iCloud หรือไฟล์ไม่มีบัญชี ตรวจตามหัวข้อ "ข้อสำคัญ: Mac ต้องทำงานอยู่ก่อน"
- **แสดงผลไม่ได้**: วิดเจ็ตวาดข้อมูลไม่สำเร็จ ให้รอรอบถัดไปก่อน ถ้ายังเป็นอยู่ ให้กดรีเฟรชในแอป AI Usage บน Mac แล้วรอสักครู่
- **ไม่เห็น AI Usage ในรายการสคริปต์**: ดึงรายการลงเพื่อรีเฟรช หรือปิดแอปแล้วเปิดใหม่ ตรวจว่า iCloud Drive ของ Scriptable เปิดอยู่ และตรวจว่า Mac มีไฟล์สคริปต์ในโฟลเดอร์ (ข้อ 3 ด้านบน)
- **ตัวเลขไม่เปลี่ยนนาน ๆ**: ตรวจว่า Mac เปิดอยู่ ตัวเก็บข้อมูลยังทำงาน (ข้อ 1) และ iCloud ซิงก์อยู่
- **ภาษาไม่ตรงกับที่ต้องการ**: ตรวจช่อง Parameter ค่าที่ไม่ใช่ `th` หรือ `en` จะถูกเมิน
- **หลังอัปเดตสคริปต์**: คัดลอก `scriptable/AI Usage.js` ใหม่ไปยังโฟลเดอร์ Scriptable ใน iCloud ของ Mac รอให้ iCloud ซิงก์ แล้วเปิด Scriptable ดูอีกครั้ง
- **วิดเจ็ตยังแสดงของเก่า**: ลองลบวิดเจ็ตออกจากหน้าโฮมแล้วเพิ่มใหม่ตามขั้นที่ 5 และ 6

### ซ่อมด้วยสคริปต์ iphone-doctor

ใช้เมื่อวิดเจ็ตบน iPhone ไม่ขึ้น หรือยังเป็นสคริปต์เวอร์ชันเก่า สคริปต์ทำงานผ่านสาย USB บน Mac หรือ Windows ไม่ใช้ Wi-Fi

> สถานะการทดสอบ: ยังไม่ได้ซ่อมจริงบน iPhone ทดสอบเฉพาะด้วยชุดทดสอบอัตโนมัติ

1. **ติดตั้งเครื่องมือบนคอมพิวเตอร์ (ทำครั้งเดียว)**
   - ต้องมี Python 3.9 ขึ้นไป แล้วติดตั้งไลบรารี `pymobiledevice3` (ไลบรารีที่คุยกับ iPhone ผ่านสาย)

     ```sh
     python3 -m pip install pymobiledevice3
     ```

   - ถ้า pip ไม่ยอมติดตั้ง (มักเกิดกับ Python จาก Homebrew) ให้สร้าง venv ก่อน (venv คือโฟลเดอร์ Python แยกต่างหาก) แล้วติดตั้งในนั้น
     `python3 -m venv ~/iphone-doctor-venv` แล้วใช้ `~/iphone-doctor-venv/bin/pip install pymobiledevice3`
   - บน Windows ใช้ `py -m pip install pymobiledevice3` และต้องมีไดรเวอร์ Apple Mobile Device Support จาก iTunes ที่โหลดจาก apple.com (ไม่ใช่เวอร์ชันจาก Microsoft Store) หรือจากแอป Apple Devices
2. **เสียบ iPhone ด้วยสาย USB ตรงเข้าคอมพิวเตอร์ แล้วปลดล็อก iPhone**
   - ถ้า iPhone ขึ้นหน้าต่าง **เชื่อถือคอมพิวเตอร์เครื่องนี้ (Trust This Computer)** ให้กด **เชื่อถือ** แล้วใส่รหัสผ่าน iPhone
   - ถ้าไม่มีหน้าต่างนี้ ให้เปิด Finder (Mac) หรือแอป Apple Devices (Windows) แล้วเชื่อมต่อ iPhone ใหม่ จนหน้าต่างขึ้น
3. **ตรวจก่อน (อ่านอย่างเดียว ไม่เขียนอะไร)** รันจากโฟลเดอร์โปรเจกต์ (บน Windows ใช้ `py scripts\iphone-doctor.py` แทน)

   ```sh
   python3 scripts/iphone-doctor.py check
   ```

   ผลจะเป็นรายการ ผ่าน / เตือน / ไม่ผ่าน และรหัสออกดังนี้
   - 0 พร้อมใช้งาน ไม่ต้องทำอะไรต่อ
   - 1 ต้องให้ผู้ใช้ทำก่อน เช่น เสียบสาย ปลดล็อก กด Trust หรือเปิด Scriptable แล้วรันใหม่
   - 2 มีจุดที่สคริปต์ซ่อมให้ได้ ไปขั้นที่ 4
   - 3 เครื่องมือทำงานไม่ได้ ให้อ่านข้อความด้านบน เช่น ยังไม่ได้ติดตั้ง pymobiledevice3

   เพิ่ม `--json` ถ้าต้องการผลแบบ JSON ค่า UDID ของ iPhone จะถูกซ่อนในผลทั้งหมด
4. **ดูแผนซ่อมก่อน (ยังไม่เขียนอะไร)**

   ```sh
   python3 scripts/iphone-doctor.py repair --dry-run
   ```

5. **ซ่อมจริง** เมื่อพร้อมแล้ว

   ```sh
   python3 scripts/iphone-doctor.py repair
   ```

   สคริปต์จะถาม `[y/N]` ก่อนทุกการเขียน พิมพ์ `y` แล้วกด Enter เฉพาะตอนที่ยอมรับ ไฟล์เดิมที่จะถูกแทนที่จะถูกสำรองไว้ก่อนที่โฟลเดอร์ `~/Library/Application Support/AIUsage/iphone-doctor-backups` บน Mac หรือ `%APPDATA%\AIUsage\iphone-doctor-backups` บน Windows
6. **ทำต่อบน iPhone** ตามข้อความที่สคริปต์พิมพ์ออกมา แล้วรัน `check` อีกครั้งเพื่อยืนยัน

หมายเหตุ
- สคริปต์เองไม่อ่านหรือคัดลอก token, Keychain หรือไฟล์การจับคู่ ไลบรารี pymobiledevice3 ใช้ข้อมูลการจับคู่ของคอมพิวเตอร์เครื่องนี้ตอนเปิดการเชื่อมต่อ เหมือนที่ Finder ทำ สคริปต์ไม่เริ่มการจับคู่เอง ถ้า iPhone ยังไม่เชื่อถือคอมพิวเตอร์ ให้จับคู่ผ่าน Finder หรือ Apple Devices ก่อน
- สคริปต์ไม่ลบข้อมูลแอปและไม่รีเซ็ต iPhone
- บน Windows ยังไม่ทราบเส้นทางโฟลเดอร์ Scriptable ใน iCloud for Windows ถ้าต้องคัดลอกไฟล์ไปที่นั่น ให้ระบุเส้นทางด้วย `--icloud-dir` หรือคัดลอกด้วยมือ
- ถ้าเสียบ iPhone มากกว่าหนึ่งเครื่อง ให้ระบุเครื่องด้วย `--udid`

### ถอนการติดตั้งบน iPhone

1. กดค้างที่วิดเจ็ตบนหน้าโฮม แล้วเลือกลบวิดเจ็ต (Remove Widget)
2. ถ้าต้องการ ลบสคริปต์ AI Usage ในแอป Scriptable
3. ไฟล์ข้อมูลและสคริปต์ที่คัดลอกไว้ใน iCloud ลบจาก Mac ตามขั้นถอนการติดตั้งในคู่มือ Mac (ข้อ 4)

---

## English

### Tested versions

Tested on 2026-11-19 on an iPhone running iOS 27.2.1, with the Scriptable app (free). Other versions are untested.

### What you need

- A Mac with AI Usage and the collector installed (guide-mac.md, steps 3 to 6).
- The iPhone and the Mac use the **same Apple ID**, and **iCloud Drive** is on for both.
- The **Scriptable** app from the App Store (free).

### Important: the Mac must be running first

The iPhone widget does not collect any data itself. The Mac collects the data and writes `ai-usage.json` to iCloud Drive. The iPhone only reads that file. Check these on the Mac first.

1. **The collector job runs.** `last exit code` should be 0.

   ```sh
   launchctl print "gui/$(id -u)/com.user.aiusage" | grep -E 'state|last exit code'
   ```
2. **The Scriptable folder exists in the Mac's iCloud Drive.** If it does not, Scriptable on the iPhone has not synced to iCloud yet. Do steps 1 to 3 of the iPhone section below first, then wait a moment.

   ```sh
   test -d "$HOME/Library/Mobile Documents/iCloud~dk~simonbs~Scriptable/Documents" && echo "folder exists" || echo "not there yet"
   ```
3. **The AI Usage script is in that folder.**

   ```sh
   test -f "$HOME/Library/Mobile Documents/iCloud~dk~simonbs~Scriptable/Documents/AI Usage.js" && echo "script exists" || echo "not there yet"
   ```

   If it is not there, copy it by hand. In Finder press ⌘⇧G, type `~/Library/Mobile Documents/iCloud~dk~simonbs~Scriptable/Documents`, and drag `scriptable/AI Usage.js` from the project into that folder.
4. **The data file for the iPhone exists.** If not, wait for the next collector run (within 5 minutes), then check again.

   ```sh
   test -f "$HOME/Library/Mobile Documents/iCloud~dk~simonbs~Scriptable/Documents/ai-usage.json" && echo "file exists" || echo "not there yet"
   ```
5. **The Mac is on.** The numbers on the iPhone update only while the Mac is on.
6. **macOS allows Python to access iCloud Drive.** If you refused earlier, turn it on in System Settings > Privacy & Security, then run `collector/install.sh` again.

### Steps on the iPhone

1. Install **Scriptable** from the App Store and open it once.
2. Turn on iCloud Drive for Scriptable: go to **Settings > [your name] > iCloud > iCloud Drive**, keep it on, and make sure **Scriptable** is switched on in the list of apps that use iCloud Drive.
3. Open Scriptable and look at the script list. You should see a script named **AI Usage**.
   - If it is not there, pull down the list to refresh, or close the app and open it again. Give it a moment, because the script syncs from the Mac through iCloud.
   - If it still does not appear after a few minutes, check the Mac as described in items 2 and 3 above.
4. Tap ▶ on the **AI Usage** script once. The app shows a preview of the medium widget.
   - If it says "No data yet. Keep your Mac on.", there is no data in iCloud yet. Turn on the Mac and wait a moment.
5. Add the widget to the Home Screen.
   1. Press and hold an empty spot on the Home Screen until the icons start to move.
   2. Tap **Edit**, then tap **Add Widget**. If your iPhone shows a **+** button instead, tap **+** and follow it.
   3. Choose **Scriptable**.
   4. Choose a size: small, medium or large.
   5. Tap **Add Widget**.
6. Press and hold the widget, then choose **Edit Widget**.
   - **Script**: choose **AI Usage**.
   - **Parameter**: leave it empty, or type `th` or `en` (see Language below).
7. Go back to the Home Screen.

**You will see:** "N% left" with the battery bars or rings (see Reading the numbers below).

### Language

- By default the widget follows the iPhone's language. If the language starts with `th`, the widget shows Thai. Every other language shows English.
- To force a language, use the **Parameter** field. Type `th` to always show Thai, or `en` to always show English.
- Capitals do not matter, and spaces at the start or end are ignored. Any other value, such as `ja`, is ignored, and the widget uses the iPhone's language instead.
- The iPhone widget does not follow the Language choice in the Mac app window.

### Reading the numbers

- The battery bars and rings show what is **left**. A bar drains as usage grows.
- The large figure reads "N% left", and the small line under it reads "N% used". The left figure rounds up and the used figure rounds down, so the two always add up to 100.
- Colours:
  - More than 20% left: grey.
  - 6 to 20% left: dark yellow, with an "Almost out" tag.
  - 5% left or less: dark red, with an "Almost out" tag. The battery outline and nub turn red too.
- The bars and rings use the same colour in light and dark mode. Yellow and red text and tags are brighter in dark mode.
- The iPhone colours are darker than the Mac's, so they read in light mode. The same rule applies to the menu bar, the Mac widgets and the iPhone widget.
- The small widget shows only the number left in each ring. Its footer counts the rings that are "Almost out".

### Good to know

- The numbers update only while the Mac is on, because the Mac collects the data and writes the file to iCloud Drive.
- The widget asks for a refresh every 5 minutes, but iOS decides the real time. It can be much later.
- "Updated N min ago" says when the data file was written. If an account has an error or old data, the widget shows that account's message in place of its reset time.
- Pressing Refresh in the Mac app makes the Mac write a new file. The iPhone widget still waits for iOS to refresh it.

### Troubleshooting

- **No data yet. Keep your Mac on.** There is no `ai-usage.json` in iCloud yet, or the file has no accounts. Check the section "Important: the Mac must be running first".
- **Can't show the data.** The widget could not draw the data. Wait for the next update. If it continues, press Refresh in the Mac app and wait a moment.
- **AI Usage is missing from the script list.** Pull down to refresh, or close Scriptable and open it again. Check that iCloud Drive is on for Scriptable, and that the Mac has the script in the folder (item 3 above).
- **The numbers do not change for a long time.** Check that the Mac is on, that the collector job runs (item 1), and that iCloud is syncing. iOS can also refresh the widget much later than 5 minutes.
- **The language is not the one you want.** Check the Parameter field. Any value other than `th` or `en` is ignored.
- **After a script update.** Copy the new `scriptable/AI Usage.js` to the Scriptable folder in the Mac's iCloud Drive, wait for iCloud to sync, then open Scriptable and check again.
- **The widget still shows old content.** Remove the widget from the Home Screen and add it again (steps 5 and 6).

### Repair the iPhone with the iphone-doctor script

Use this when the widget does not show, or still runs an older script. The script works over the USB cable on a Mac or Windows PC. It does not use Wi-Fi.

> Test status: repair has not yet been run on a real iPhone. It is tested only with the automated test suite.

1. **Install the tools on the computer (once)**
   - You need Python 3.9 or newer, then the `pymobiledevice3` library (the library that talks to the iPhone over the cable).

     ```sh
     python3 -m pip install pymobiledevice3
     ```

   - If pip refuses to install (this often happens with Python from Homebrew), create a venv first (a venv is a separate Python folder) and install there:
     `python3 -m venv ~/iphone-doctor-venv`, then `~/iphone-doctor-venv/bin/pip install pymobiledevice3`
   - On Windows, use `py -m pip install pymobiledevice3`. You also need the Apple Mobile Device Support driver, from iTunes downloaded from apple.com (not the Microsoft Store version), or from the Apple Devices app.
2. **Plug the iPhone into the computer with a USB cable, and unlock the iPhone**
   - If the iPhone shows **Trust This Computer**, tap **Trust** and enter the iPhone passcode.
   - If that prompt never appears, open Finder (Mac) or the Apple Devices app (Windows), connect the iPhone again, and wait until the prompt shows.
3. **Check first (read-only, writes nothing).** Run it from the project folder (on Windows use `py scripts\iphone-doctor.py` instead of `python3 scripts/iphone-doctor.py`).

   ```sh
   python3 scripts/iphone-doctor.py check
   ```

   The result is a list of ok / warn / fail lines, and the exit code means:
   - 0: ready, nothing more to do
   - 1: the user must act first, for example plug in, unlock, tap Trust, or open Scriptable, then run again
   - 2: the script can repair something. Go to step 4
   - 3: the tool could not run. Read the message above, for example pymobiledevice3 is not installed

   Add `--json` for JSON output. The iPhone's UDID is hidden in all output.
4. **See the repair plan first (nothing is written)**

   ```sh
   python3 scripts/iphone-doctor.py repair --dry-run
   ```

5. **Repair for real**, when you are ready

   ```sh
   python3 scripts/iphone-doctor.py repair
   ```

   The script asks `[y/N]` before every write. Type `y` and press Enter only if you agree. A file it replaces is first backed up to `~/Library/Application Support/AIUsage/iphone-doctor-backups` on a Mac, or `%APPDATA%\AIUsage\iphone-doctor-backups` on Windows.
6. **Next steps on the iPhone**, as the script prints them. Then run `check` again to confirm.

Notes
- The script itself does not read or copy tokens, the Keychain or pairing files, and it does not start pairing. The pymobiledevice3 library uses this computer's pairing record when it opens the connection, the same way Finder does. If the iPhone does not trust this computer yet, pair it with Finder or Apple Devices first.
- The script does not delete app data and does not reset the iPhone.
- On Windows the path of the Scriptable folder in iCloud for Windows is not known yet. To copy the script there, give the path with `--icloud-dir`, or copy the file by hand.
- If more than one iPhone is plugged in, choose one with `--udid`.

### Uninstall on the iPhone

1. Press and hold the widget on the Home Screen, then choose **Remove Widget**.
2. If you want, delete the AI Usage script in the Scriptable app.
3. Delete the data file and the script copy from iCloud on the Mac, as in step 4 of the uninstall section in guide-mac.md.
