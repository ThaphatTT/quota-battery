# AI Usage: วิดเจ็ต iPhone (Scriptable) / AI Usage: iPhone widget (Scriptable)

วิดเจ็ตนี้อยู่ในสองภาษา อ่านส่วนที่ต้องการได้เลย: [ภาษาไทย](#ภาษาไทย) · [English](#english)

## ภาษาไทย

วิดเจ็ตนี้แสดงโควตาการใช้งานของ Claude, ChatGPT และ agy บนหน้าจอโฮม Claude และ agy อ่านจากไฟล์ `ai-usage.json`
ที่ Mac เขียนไว้ใน iCloud Drive ส่วน ChatGPT เชื่อมจาก iPhone เองได้ (ดูหัวข้อ "ChatGPT บน iPhone โดยไม่ต้องพึ่ง Mac")

### วิธีติดตั้งบน iPhone

1. ติดตั้งแอป **Scriptable** จาก App Store แล้วเปิดแอปหนึ่งครั้ง
2. ตรวจว่า Scriptable ใช้ iCloud Drive ได้: การตั้งค่า > ชื่อของคุณ > iCloud > iCloud Drive แล้วเปิด **Scriptable**
3. เปิดแอป Scriptable แล้วดูว่ามีสคริปต์ชื่อ **AI Usage** สคริปต์นี้ซิงก์มาทาง iCloud จาก Mac
   (ถ้ายังไม่เห็น ให้รอสักครู่แล้วปิดเปิดแอปใหม่)
4. กด ▶ บนสคริปต์ **AI Usage** เพื่อดูตัวอย่างขนาดกลางในแอป
5. เพิ่มวิดเจ็ต: กดค้างที่หน้าจอโฮม > กด **+** > เลือก **Scriptable** > เลือกขนาด (เล็ก กลาง หรือใหญ่)
   > กดค้างที่วิดเจ็ต > **แก้ไขวิดเจ็ต (Edit Widget)**
6. ที่ช่อง **สคริปต์ (Script)** เลือก **AI Usage**

### ChatGPT บน iPhone โดยไม่ต้องพึ่ง Mac

เชื่อม ChatGPT จาก iPhone ได้เอง เมื่อเชื่อมแล้ววิดเจ็ตจะดึงโควตา ChatGPT เองแม้ Mac จะปิดอยู่ ส่วน Claude และ agy ยังมาจาก Mac ตามเดิม

วิธีเชื่อม (ทำในแอป ไม่ใช่ในวิดเจ็ต):

1. เปิดแอป Scriptable แล้วกด ▶ บนสคริปต์ **AI Usage**
2. ถ้ายังไม่เคยเชื่อม จะมีหน้า **เชื่อม ChatGPT** ขึ้นมา กด **ยินยอมและเชื่อมต่อ** (หรือกด **ไว้ทีหลัง** เพื่อข้าม)
3. หน้ารหัสจะแสดงรหัสสั้น ๆ และเวลาที่เหลือ กด **เปิดหน้า OpenAI** แล้วกรอกรหัสนั้นในหน้าของ OpenAI ด้วยบัญชี ChatGPT ของคุณ (กด **คัดลอกรหัส** ได้ถ้าต้องการ)
4. กลับมาที่ Scriptable หน้ารหัสจะตรวจให้เองเป็นระยะ เมื่อได้รับการอนุมัติจะขึ้น **เชื่อม ChatGPT แล้ว** พร้อมชื่อแผน
5. กด **เสร็จ** การรันวิดเจ็ตครั้งถัดไปจะแสดง ChatGPT

สิ่งที่ควรรู้:

- โทเค็นเก็บไว้ใน Keychain ของ Scriptable บน iPhone เครื่องนี้เท่านั้น ไม่เก็บลงไฟล์ และไม่แสดงบนหน้าจอหรือใน log
- วิดเจ็ตไม่เคยถามอะไร การเชื่อมและการยกเลิกทำได้เฉพาะเมื่อเปิดสคริปต์ในแอป
- รหัสหมดอายุใน 15 นาที ถ้าปิดหน้ารหัสไปก่อน การตรวจจะหยุด และการเปิดแอปครั้งถัดไปจะกลับมาที่รหัสเดิม
- ยกเลิกการเชื่อม: เปิดแอป กด ▶ บนสคริปต์ แล้วกด **ยกเลิกการเชื่อมต่อ** ระบบจะลบโทเค็นบน iPhone เครื่องนี้ ไม่ได้แจ้งให้ OpenAI ทราบ
- ถ้าการเชื่อมหมดอายุ วิดเจ็ตจะขึ้น "ต้องล็อกอินใหม่" ให้เปิดแอปแล้วเชื่อมใหม่
- ช่องทางนี้ไม่ใช่ช่องทางทางการของ OpenAI และใช้ endpoint ภายในที่อาจเปลี่ยนหรือใช้ไม่ได้โดยไม่แจ้ง อาจขัดกับข้อกำหนดการใช้งานของผู้ให้บริการ ใช้ด้วยความเสี่ยงของตนเอง

### ภาษา

- ค่าเริ่มต้นคือภาษาของ iPhone ถ้าภาษาขึ้นต้นด้วย `th` วิดเจ็ตแสดงภาษาไทย ภาษาอื่นทั้งหมดแสดงภาษาอังกฤษ
- บังคับภาษาได้ที่ช่อง **Parameter** ในหน้า **แก้ไขวิดเจ็ต (Edit Widget)** ช่องนี้อยู่ในหน้าเดียวกับช่อง Script
  - พิมพ์ `th` เพื่อให้แสดงภาษาไทยเสมอ
  - พิมพ์ `en` เพื่อให้แสดงภาษาอังกฤษเสมอ
  - เว้นว่างไว้เพื่อใช้ภาษาของ iPhone (ค่าเริ่มต้น)
- ตัวพิมพ์เล็กหรือใหญ่ไม่สำคัญ และช่องว่างหน้าหลังถูกตัดออก ค่าอื่นนอกจากนี้ (เช่น `ja` หรือ `thai`) จะถูกเมิน
  แล้ววิดเจ็ตใช้ภาษาของ iPhone แทน
- ตัวอย่าง: iPhone ตั้งเป็นภาษาญี่ปุ่นแต่ช่อง Parameter พิมพ์ `th` วิดเจ็ตจะแสดงภาษาไทย

### การอ่านตัวเลข

- แถบแบตเตอรี่และวงแหวนแสดง **จำนวนที่เหลือ** แถบจะค่อย ๆ หมดลงเมื่อใช้มากขึ้น
- บรรทัดใหญ่แสดง "เหลือ N%" และบรรทัดเล็กใต้ตัวเลขแสดง "ใช้ไป N%" ตัวเลขที่เหลือปัดขึ้น ตัวเลขที่ใช้ไปปัดลง
  จึงรวมกันได้ 100 เสมอ
- สีขึ้นกับจำนวนที่เหลือ
  - มากกว่า 20% เหลือ: แถบและวงแหวนเป็นสีเทา ตัวเลขเป็นสีตัวอักษรปกติ
  - 6–20% เหลือ: สีเหลืองเข้ม และมีป้าย "ใกล้หมด"
  - 5% เหลือหรือน้อยกว่า: สีแดงเข้ม และมีป้าย "ใกล้หมด" กรอบแบตเตอรี่กับหัวแบตเตอรี่จะเป็นสีแดงด้วย
- แถบและวงแหวนใช้สีเดียวกันทั้งในโหมดสว่างและโหมดมืด ส่วนตัวอักษรและป้ายสีเหลือง/แดงจะสว่างขึ้นในโหมดมืด
- วิดเจ็ตขนาดเล็กแสดงเฉพาะตัวเลขที่เหลือในวงแหวน ส่วนท้ายนับจำนวนวงแหวนที่ "ใกล้หมด"

### หลายบัญชี

- ถ้า Mac มีหลายบัญชี (เช่น Claude สองบัญชี) ไฟล์ `ai-usage.json` จะมีทุกบัญชี และวิดเจ็ตแสดงตามลำดับในไฟล์
  ซึ่งเป็นลำดับที่ตั้งไว้ในแอป AI Usage บน Mac
- วิดเจ็ตขนาดเล็กและขนาดกลางแสดง **3 บัญชีแรก** เท่านั้น ถ้ามีมากกว่า 3 บัญชี จะมีป้าย **+N** บอกจำนวนบัญชีที่ไม่ได้แสดง
  (N คือจำนวนบัญชีทั้งหมดลบ 3) ในขนาดกลาง ป้ายอยู่ในแถวหัวข้อ ทางขวา ถัดจากข้อความเวลาอัปเดต ในขนาดเล็ก ป้ายอยู่บรรทัดของมันเอง
  ใต้ข้อความเวลาอัปเดต ชิดขวา ถ้ามี 3 บัญชีหรือน้อยกว่า จะไม่มีป้ายนี้
- วิดเจ็ตขนาดใหญ่แสดงได้ 5 แถว แถวของบัญชีที่มีข้อผิดพลาดหรือไม่มีขีดจำกัดจะถูกเลือกก่อน ส่วนแถวที่เหลือเลือกจาก
  ค่าที่ใช้ไปสูงสุด แล้วแสดงทั้งหมดตามลำดับในไฟล์
- ชื่อที่แสดงคือฟิลด์ `label` ถ้าตั้งชื่อเล่นไว้บน Mac วิดเจ็ตจะแสดงชื่อเล่นนั้น ถ้าไม่ได้ตั้ง Mac จะใช้ชื่อตั้งต้นของบริการ
  ได้แก่ Claude, ChatGPT หรือ agy และถ้ามีสองบัญชีขึ้นไปของบริการเดียวกันโดยไม่มีชื่อเล่น ชื่อตั้งต้นจะมีเลขกำกับ เช่น "Claude 2"
- ถ้าไฟล์ไม่มีฟิลด์ `label` เลย (ไฟล์รุ่นเก่า) วิดเจ็ตจะใช้ชื่อสั้นของบริการแทน ได้แก่ Claude, GPT หรือ agy
- ชื่อยาวจะย่อตัวอักษรลงเล็กน้อยให้พอดี ถ้ายังไม่พอ ส่วนท้ายจะถูกตัด
- ในวิดเจ็ตขนาดเล็ก ชื่อของแต่ละบัญชีอยู่ใต้วงแหวน ส่วนท้ายนับเฉพาะวงแหวนที่แสดงอยู่
- ถ้าเชื่อม ChatGPT จาก iPhone แล้ว แถว ChatGPT ที่มาจาก iPhone จะแทนแถว ChatGPT ของ Mac ที่ตำแหน่งเดิม และ Claude กับ agy ยังมาจาก Mac

### ข้อควรรู้

- Claude และ agy จะอัปเดตต่อเมื่อ Mac เปิดอยู่ เพราะ Mac เป็นผู้เก็บข้อมูลและเขียนไฟล์ลง iCloud Drive ส่วน ChatGPT ที่เชื่อมจาก iPhone จะอัปเดตเมื่อวิดเจ็ตรันหรือเมื่อเปิดแอป
- ถ้าขึ้นข้อความ "ยังไม่มีข้อมูล เปิด Mac ไว้" แปลว่ายังไม่มีไฟล์ข้อมูลใน iCloud ให้เปิด Mac แล้วรอสักครู่
- วิดเจ็ตขอให้รีเฟรชทุก 5 นาที แต่ iOS เป็นผู้ตัดสินเวลาจริง อาจช้ากว่านั้นได้
- ข้อความ "อัปเดต N นาทีก่อน" บอกว่าไฟล์ข้อมูลถูกเขียนเมื่อไร ถ้าบัญชีใดมีข้อผิดพลาดหรือข้อมูลเก่า
  วิดเจ็ตจะแสดงข้อความของบัญชีนั้นแทนเวลารีเซ็ต
- ถ้าไฟล์ข้อมูลยังไม่มีฟิลด์ `window_seconds` หรือ `error_code` วิดเจ็ตจะใช้ป้ายและข้อความจากไฟล์ (ภาษาไทย) แทน
- ถ้ามีทั้ง Mac และ ChatGPT จาก iPhone หัวข้อจะบอกเวลาของแต่ละแหล่ง เช่น "Mac 8 นาทีก่อน · ChatGPT 1 นาทีก่อน" ในวิดเจ็ตขนาดเล็กจะแสดงเวลาของแหล่งที่เก่ากว่า

---

## English

The widget shows the usage limits of Claude, ChatGPT and agy on your Home Screen. Claude and agy are read from the file
`ai-usage.json` that your Mac writes to iCloud Drive. ChatGPT can be connected from the iPhone itself (see "ChatGPT on iPhone, without the Mac").

### How to install on iPhone

1. Install **Scriptable** from the App Store and open it once.
2. Check that Scriptable can use iCloud Drive: Settings > your name > iCloud > iCloud Drive, then turn on **Scriptable**.
3. Open Scriptable and check that a script called **AI Usage** is there. The script syncs from the Mac through iCloud.
   (If it is not there yet, wait a moment, then close and reopen the app.)
4. Tap ▶ on the **AI Usage** script to preview the medium widget in the app.
5. Add the widget: long-press the Home Screen > tap **+** > choose **Scriptable** > choose a size (small, medium or large) > long-press the widget > **Edit Widget**.
6. In the **Script** field, choose **AI Usage**.

### ChatGPT on iPhone, without the Mac

ChatGPT can be connected from the iPhone itself. Once it is connected, the widget fetches the ChatGPT usage on its own, even when the Mac is off. Claude and agy still come from the Mac as before.

How to connect (in the app, not in the widget):

1. Open the Scriptable app and tap ▶ on the **AI Usage** script.
2. If you have not connected before, the **Connect ChatGPT** screen appears. Tap **Consent and connect** (or **Not now** to skip).
3. The code screen shows a short code and the time left. Tap **Open the OpenAI page**, then enter the code on the OpenAI page with your ChatGPT account. **Copy code** copies it if you need.
4. Come back to Scriptable. The code screen checks by itself from time to time. When the code is approved, it shows **ChatGPT connected** with the plan.
5. Tap **Done**. The next widget run shows ChatGPT.

Good to know:

- The token is stored only in Scriptable's Keychain on this iPhone. It is not written to a file, and it is never shown on screen or in a log.
- The widget never asks anything. Connecting and disconnecting work only when the script runs in the app.
- The code expires after 15 minutes. If you close the code screen, the checks stop. The next time you open the app, the same code comes back.
- To disconnect: open the app, tap ▶ on the script, then tap **Disconnect**. This deletes the token on this iPhone only. OpenAI is not told.
- If the login stops working, the widget shows "Sign in again". Open the app and connect again.
- This is not an official OpenAI channel. It uses an internal endpoint that may change or stop working without notice, and it may conflict with the provider's terms. Use it at your own risk.

### Language

- By default the widget follows the iPhone's language. If the language starts with `th`, the widget shows Thai. Every other language shows English.
- To force a language, use the **Parameter** field in **Edit Widget**. It is on the same screen as the Script field.
  - Type `th` to always show Thai.
  - Type `en` to always show English.
  - Leave it empty to follow the iPhone's language (the default).
- Capitals do not matter, and spaces at the start or end are ignored. Any other value (for example `ja` or `thai`) is ignored, and the widget uses the iPhone's language instead.
- Example: the iPhone is set to Japanese but the Parameter field says `th`, so the widget shows Thai.

### Reading the numbers

- The battery bars and rings show what is **left**. A bar drains as usage grows.
- The main figure reads "N% left", and the small line under it reads "N% used". The left figure rounds up and
  the used figure rounds down, so the two always add up to 100.
- The colour follows what is left:
  - More than 20% left: the bars and rings are gray, and the figure is in the normal text colour.
  - 6 to 20% left: dark yellow, with an "Almost out" tag.
  - 5% left or less: dark red, with an "Almost out" tag. The battery outline and nub turn red too.
- The bars and rings use the same colour in light and dark mode. Yellow and red text and tags are brighter in dark mode.
- The small widget shows only the number left in each ring. Its footer counts the rings that are "Almost out".

### Several accounts

- If the Mac has several accounts (for example two Claude accounts), the file lists all of them, and the widget
  shows them in the file's order. That order is the one you set in the AI Usage app on the Mac.
- The small and medium widgets show only the **first 3 accounts**. If there are more than 3, a **+N** badge shows how many are not shown (N is the total minus 3). In medium it sits in the title row, on the right, beside the "Updated" text. In small it sits on its own line under the age text, on the right. With 3 accounts or fewer, there is no badge.
- The large widget shows up to 5 rows. Rows for accounts with an error or with no limits are chosen first, and the
  other rows are chosen by the highest used share. The rows are shown in file order.
- The name shown is the `label` field. With a nickname set on the Mac, the widget shows the nickname. Without one,
  the Mac uses the service's default name: Claude, ChatGPT or agy. With two or more accounts of the same service and
  no nickname, the default name has a number, for example "Claude 2".
- If the file has no `label` field at all (an older file), the widget uses the short service name: Claude, GPT or agy.
- Long names shrink a little to fit. If they are still too long, the end is cut off.
- In the small widget, each account's name is under its ring. The footer counts only the rings shown.
- If ChatGPT is connected from the iPhone, that row takes the place of the Mac's ChatGPT row, at the same position. Claude and agy still come from the Mac.

### Good to know

- The numbers update only while your Mac is on, because the Mac collects the data and writes the file to iCloud Drive.
- If the widget says "No data yet. Keep your Mac on." there is no data file in iCloud yet. Turn on the Mac and wait a moment.
- The widget asks for a refresh every 5 minutes, but iOS decides the real time, so it may be later.
- "Updated N min ago" says when the data file was written. If an account has an error or old data, the widget shows that account's message in place of its reset time.
- If the data file has no `window_seconds` or `error_code` fields yet, the widget uses the labels and messages from the file, which are in Thai.
- With both the Mac and the iPhone's ChatGPT, the header names each source and its age, for example "Mac 8 min ago · ChatGPT 1 min ago". The small widget shows the older age.
