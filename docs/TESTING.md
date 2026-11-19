# Testing

This page lists every test suite and how to run it, what the snapshot matrix covers, and the checks that only a person can
do on a real Mac and iPhone. Run every command from the repository root. Every test must run and pass. A skipped test does
not count as a pass, so read the per-test output.

Tested versions: macOS 27.2.1, Xcode 27.2 (27B52), iOS 27.2.1, Python 3.15.2. The iPhone suite ran on Node 26.13.0.

## 1. Test suites

| Suite | Folder | Runner | Tests (at the time of writing) | Command |
|---|---|---|---|---|
| Collector | `collector/tests/` | Python `unittest` (standard library only, no network, no real Keychain) | 219 | `python3 -m unittest discover -s collector/tests -t collector -v` |
| iPhone widget (Scriptable) | `scriptable/test/` | Node's built-in test runner (no `npm install`) | 131: `render.test.mjs` 86, `matrix.test.mjs` 6, `chatgpt.test.mjs` 39 | `node --test --test-reporter=spec scriptable/test/` |
| Mac app and widget | `mac/Tests/` | XCTest through `xcodebuild` (no signing identity needed) | 162 | `xcodebuild -project mac/AIUsage.xcodeproj -scheme AIUsage -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -derivedDataPath mac/build test` |
| iPhone doctor (scripts) | `scripts/tests/` | Python `unittest` (standard library only) | 56 | `python3 -m unittest discover -s scripts/tests -v` |

The Mac suites, with the number of passed tests at the time of writing:

- `AccountsTests` 21, `DirectModeTests` 11, `DirectModeSnapshotTests` 2, `L10nTests` 20, `LanguageTests` 10, `MediumFitTests` 3, `MenuBarIconSwitchTests` 8,
  `RefreshCommandTests` 3, `SmallFitTests` 2, `SnapshotMatrixTests` 1, `SnapshotTests` 7, `UsageFormattingTests` 19,
  `UsageLoaderTests` 7, `UsageModelTests` 12, `UsagePresenterTests` 36.
- No test records an expected failure. Section 4 lists the results that are reported, not fixed.

The collector suite is in `test_accounts.py`, `test_cli.py`, `test_collector.py`, `test_contract_fields.py`, `test_install.py` and
`test_notify_switch.py`.

The image tests write PNG files into `mac/build/`, which is gitignored:

- `mac/build/snapshots/` holds the layout images from `SnapshotTests`: Thai and English, light and dark, at 100% and 90%,
  plus the popover, the Accounts section and the app window cards.
- `mac/build/snapshots/medium-fit/` holds 11 medium widgets at the real medium frames and at 90%, from `MediumFitTests`.
- `mac/build/snapshots/small-fit/` holds 8 small widgets with five accounts, at the real frame and at 90%, from `SmallFitTests`.
- `mac/build/snapshots/matrix/` holds the 352 matrix images from `SnapshotMatrixTests`, and `index.html`, the contact sheet.

To look at the matrix, open the contact sheet in a browser: `open mac/build/snapshots/matrix/index.html`. The images are
in the same folder, and each one has a caption.

## 2. The Mac snapshot matrix

| Dimension | Values |
|---|---|
| Size and frame (points) | small 170 x 170; medium 329 x 155 and 364 x 170; large 364 x 382 |
| Language | th, en |
| Appearance | light, dark |
| Accounts | 0, 1, 3, 5. Five is two Claude (`Claude 1`, `Claude 2`), two ChatGPT (`ChatGPT 1`, `ChatGPT 2`) and one agy, the badge case |
| Tier (every limit at one share used) | white 32%, yellow 85%, red 95% |
| State | ok (fresh data); stale (the last run failed, the old limits and the error text stay); error (no data yet, no limits) |

For each frame, language and appearance there are 22 cases. Zero accounts has no tier or state, so it is one case, `acc0`.
With 1, 3 or 5 accounts there are ok and stale in each of the three tiers (6 cases), and error once. The error state has no
limits, so no tier is shown there, and it is written once (`acc5-error`). The total is 4 frames x 2 languages x 2 appearances
x 22 cases = 352 images. File names have this form: `medium-329x155_th_dark_acc5-red-ok.png`.

What each image is checked for (geometry, not pixels):

- The height the widget needs at its frame width is no more than the frame height.
- For small and large, the natural width is no more than the frame width, so no text is cut off.
- For medium, each row is measured without its reset text, because the reset text drops when a row is short of width. The
  row's natural width must fit the content width. The title row, with its "+N" badge, must fit the content width too.
- The no-data message wraps across lines, so only its height is checked.

The matrix does not render the 90% frames. The medium 90% frames are checked in `MediumFitTests` and written to `medium-fit/`.
The small 90% frame is written to `small-fit/` by `SmallFitTests` and is not checked (section 4).

## 3. The iPhone matrix (Scriptable)

`scriptable/test/matrix.test.mjs` runs every family (small, medium, large), in Thai and English, for 0, 1, 3 and 5 accounts,
the three tiers and the three states. Each case is checked at the smallest and the largest assumed frame. The frames are
the `MIN_FRAME` and `MAX_FRAME` values of `render.test.mjs`. They are assumptions, not device measurements.

- Appearance cannot be switched in the stubs. The check is that every text colour has a light and a dark half, both as
  six-digit hex values. The layout is the same in both appearances.
- The fit check is the rough text model of `render.test.mjs`. It can miss wrapping and it is not a device check.
- `matrix.test.mjs` copies the stub harness of `render.test.mjs` (its lines 8 to 703), so the two files must be kept in step.

## 4. Known results that are reported, not fixed

- Mac, `SmallFitTests`: the small widget at 90% of its frame (153 x 153) is not checked. Its natural width there is 154 to
  160 pt, more than the frame: five accounts in both languages (156 pt in Thai, 160 pt in English) and three accounts in
  English (154 pt). The five-account images at 90% in `small-fit/` read clearly by eye, in both languages and both
  appearances, but there is no spare width. Whether the small widget needs a change at 90% is still open.
- iPhone, `matrix.test.mjs`: medium with five accounts in the ok state, at the largest assumed frame, at full size (6
  cases: three tiers in Thai and in English). Their text is 2 to 4% wider than 364 pt (376.5 pt in Thai, 371 pt in English).
  Every medium text goes through `style()` in `AI Usage.js`, which lets it shrink to 0.7, so it should fit by shrinking on
  a device. The cases are listed in `KNOWN_OVERFLOW`. The test fails for any other overflow, and for a listed case that
  stops overflowing until the list is updated.

## 5. Checks on a real Mac and iPhone (by hand)

No test runs these. They were not run for this document. Tick each one after you have checked it on the device.

| Done | Item | Steps | What to check |
|---|---|---|---|
| [ ] | Real widget gallery | Right-click the desktop, choose Edit Widgets, search for the app's name (Quota Battery at the time of writing) and add a small, a medium and a large widget. Use five accounts if you can. | No text is cut off. The medium rows fit. With five accounts the "+2" badge shows in the medium title row, right of the updated text, and under the age text in small. The widget follows the language setting. |
| [ ] | Menu bar with Hidden Bar | Install Hidden Bar (1.11.2 or newer on macOS 27; 1.13.1 was tested). Open the app once. | The AI Usage icon is in Hidden Bar's visible section (Settings > Icons). After a relaunch it keeps its place. |
| [ ] | Notifications | Turn on "Notify at 80% and 95%" in the app and allow notifications for the sender that macOS shows. Wait for an account to cross 80% or 95% used. | One notification per crossing, with the text in the chosen language. |
| [ ] | iCloud copy to iPhone | Copy `scriptable/AI Usage.js` into the Scriptable folder in iCloud Drive (see AGENTS.md, step 6). On the iPhone open Scriptable, run AI Usage and add the widget. | The iPhone widget shows the same accounts and percentages as `usage.json`, and it updates while the Mac is on. |
| [ ] | Add account through Terminal | In the Accounts section, choose Add account. When macOS asks, allow AIUsage to control Terminal. Sign in in Terminal, then refresh. | Terminal opens with the login. The new account appears after the next run, with the New tag. |
| [ ] | Language switching | Set the app's Language to System, ไทย and English in turn. | The app, the Mac widgets and the notification text change. The iPhone widget follows the iPhone language, or the Parameter field `th` or `en`. |
| [ ] | Reduce Motion | System Settings > Accessibility > Display > Reduce motion: on. Refresh the data. | The gauges and rings change over 0.2 seconds, not with the smooth animation, and the numbers still update. |

## 6. Versions

The versions above are the ones this suite was run on. The manual checks in section 5 were not run on these versions for
this document. Other versions are untested.

---

# การทดสอบ (ภาษาไทย)

หน้านี้อธิบายชุดเทสต์ทุกชุด วิธีรันแต่ละชุด สิ่งที่ snapshot matrix ครอบคลุม และรายการที่มีแต่คนเท่านั้นที่ตรวจได้บน Mac
และ iPhone จริง ให้รันคำสั่งจากโฟลเดอร์รากของโปรเจกต์ ทุกเทสต์ต้องรันและผ่าน เทสต์ที่ถูกข้าม (skipped) ไม่นับว่าผ่าน

เวอร์ชันที่ทดสอบแล้ว: macOS 27.2.1, Xcode 27.2 (27B52), iOS 27.2.1, Python 3.15.2 ชุดเทสต์ของ iPhone รันบน Node 26.13.0

## 1. ชุดเทสต์

| ชุด | โฟลเดอร์ | ตัวรัน | จำนวนเทสต์ (ตอนเขียนเอกสาร) | คำสั่ง |
|---|---|---|---|---|
| ตัวเก็บข้อมูล (collector) | `collector/tests/` | Python `unittest` (ใช้ไลบรารีมาตรฐานอย่างเดียว ไม่ต่อเน็ตและไม่อ่าน Keychain จริง) | 219 | `python3 -m unittest discover -s collector/tests -t collector -v` |
| วิดเจ็ต iPhone (Scriptable) | `scriptable/test/` | ตัวรันเทสต์ในตัวของ Node (ไม่ต้อง `npm install`) | 131: `render.test.mjs` 86, `matrix.test.mjs` 6, `chatgpt.test.mjs` 39 | `node --test --test-reporter=spec scriptable/test/` |
| แอปและวิดเจ็ต Mac | `mac/Tests/` | XCTest ผ่าน `xcodebuild` (ไม่ต้องมีตัวตนสำหรับเซ็นชื่อ) | 162 | `xcodebuild -project mac/AIUsage.xcodeproj -scheme AIUsage -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -derivedDataPath mac/build test` |
| ตัวตรวจ iPhone (scripts) | `scripts/tests/` | Python `unittest` (ใช้ไลบรารีมาตรฐานอย่างเดียว) | 56 | `python3 -m unittest discover -s scripts/tests -v` |

ชุดเทสต์ของ Mac และจำนวนเทสต์ที่ผ่านตอนเขียนเอกสาร:

- `AccountsTests` 21, `DirectModeTests` 11, `DirectModeSnapshotTests` 2, `L10nTests` 20, `LanguageTests` 10, `MediumFitTests` 3, `MenuBarIconSwitchTests` 8,
  `RefreshCommandTests` 3, `SmallFitTests` 2, `SnapshotMatrixTests` 1, `SnapshotTests` 7, `UsageFormattingTests` 19,
  `UsageLoaderTests` 7, `UsageModelTests` 12, `UsagePresenterTests` 36
- ไม่มีเทสต์ใดบันทึก expected failure ผลที่รายงานแต่ยังไม่แก้อยู่ในหัวข้อ 4

ชุดของตัวเก็บข้อมูลประกอบด้วยไฟล์ `test_accounts.py`, `test_cli.py`, `test_collector.py`, `test_contract_fields.py`, `test_install.py`
และ `test_notify_switch.py`

เทสต์ที่สร้างภาพจะเขียนไฟล์ PNG ลงใน `mac/build/` ซึ่งถูก gitignore ไว้:

- `mac/build/snapshots/` เก็บภาพของเลย์เอาต์จาก `SnapshotTests` ทั้งภาษาไทยและอังกฤษ โหมดสว่างและมืด ที่ 100% และ 90%
  รวมถึงป๊อปโอเวอร์ ส่วนบัญชี และการ์ดในหน้าต่างแอป
- `mac/build/snapshots/medium-fit/` เก็บวิดเจ็ตขนาดกลาง 11 ภาพ ที่ขนาดจริงและที่ 90% จาก `MediumFitTests`
- `mac/build/snapshots/small-fit/` เก็บวิดเจ็ตขนาดเล็กที่มีห้าบัญชี 8 ภาพ ที่ขนาดจริงและที่ 90% จาก `SmallFitTests`
- `mac/build/snapshots/matrix/` เก็บภาพ matrix 352 ภาพจาก `SnapshotMatrixTests` และ `index.html` ซึ่งเป็น contact sheet

หากต้องการดู matrix ให้เปิด contact sheet ในเบราว์เซอร์: `open mac/build/snapshots/matrix/index.html` ภาพอยู่ในโฟลเดอร์เดียวกัน
และแต่ละภาพมีคำกำกับ

## 2. Snapshot matrix ของ Mac

| มิติ | ค่าที่ทดสอบ |
|---|---|
| ขนาดและกรอบ (จุด) | small 170 x 170; medium 329 x 155 และ 364 x 170; large 364 x 382 |
| ภาษา | th, en |
| โหมดสี | light, dark |
| จำนวนบัญชี | 0, 1, 3, 5 ค่า 5 คือ Claude สองบัญชี (`Claude 1`, `Claude 2`), ChatGPT สองบัญชี (`ChatGPT 1`, `ChatGPT 2`) และ agy หนึ่งบัญชี ซึ่งเป็นกรณีที่มีป้าย "+N" |
| ระดับ (ทุกลิมิตใช้ในสัดส่วนเดียวกัน) | white 32%, yellow 85%, red 95% |
| สถานะ | ok (ข้อมูลสด); stale (การดึงล่าสุดล้มเหลว ลิมิตเดิมและข้อความข้อผิดพลาดยังแสดง); error (ยังไม่มีข้อมูล ไม่มีลิมิต) |

แต่ละกรอบ ภาษา และโหมดสี มี 22 กรณี ศูนย์บัญชีไม่มีระดับหรือสถานะ จึงเป็นหนึ่งกรณี ชื่อ `acc0` เมื่อมี 1, 3 หรือ 5 บัญชี
จะมี ok และ stale ในแต่ละระดับทั้งสามระดับ (6 กรณี) และ error หนึ่งครั้ง สถานะ error ไม่มีลิมิต จึงไม่มีระดับให้แสดง
และเขียนเพียงครั้งเดียว (`acc5-error`) รวมเป็น 4 กรอบ x 2 ภาษา x 2 โหมดสี x 22 กรณี = 352 ภาพ ชื่อไฟล์มีรูปแบบเช่น
`medium-329x155_th_dark_acc5-red-ok.png`

สิ่งที่ตรวจในแต่ละภาพ (ตรวจด้วยขนาดทางเรขาคณิต ไม่ได้เทียบพิกเซล):

- ความสูงที่วิดเจ็ตต้องการเมื่อวางในความกว้างของกรอบ ต้องไม่เกินความสูงของกรอบ
- สำหรับ small และ large ความกว้างตามธรรมชาติต้องไม่เกินความกว้างของกรอบ เพื่อให้ไม่มีข้อความถูกตัด
- สำหรับ medium วัดแต่ละแถวโดยไม่รวมข้อความรีเซ็ต เพราะข้อความรีเซ็ตจะหายไปเมื่อแถวกว้างไม่พอ ความกว้างตามธรรมชาติของแถว
  ต้องพอดีกับความกว้างของเนื้อหา และแถวหัวข้อที่มีป้าย "+N" ต้องพอดีกับความกว้างของเนื้อหาเช่นกัน
- ข้อความว่าง (no-data) ขึ้นบรรทัดใหม่ได้ จึงตรวจเฉพาะความสูง

matrix ไม่ได้เรนเดอร์กรอบ 90% กรอบ 90% ของขนาดกลางถูกตรวจใน `MediumFitTests` และเขียนไว้ที่ `medium-fit/` ส่วนกรอบ 90% ของขนาดเล็กเขียนไว้ที่ `small-fit/` โดย `SmallFitTests` และไม่ได้ถูกตรวจ (หัวข้อ 4)

## 3. Matrix ของ iPhone (Scriptable)

`scriptable/test/matrix.test.mjs` รันทุกขนาด (small, medium, large) ทั้งภาษาไทยและอังกฤษ สำหรับ 0, 1, 3 และ 5 บัญชี
ระดับทั้งสาม และสถานะทั้งสาม แต่ละกรณีตรวจที่กรอบเล็กที่สุดและใหญ่ที่สุดที่สมมติไว้ กรอบเหล่านี้คือค่า `MIN_FRAME` และ
`MAX_FRAME` ใน `render.test.mjs` เป็นค่าสมมติ ไม่ได้วัดจากเครื่องจริง

- สลับโหมดสีใน stub ไม่ได้ การตรวจจึงดูว่าทุกสีของข้อความมีค่าทั้งโหมดสว่างและมืดเป็นเลขฐานสิบหกหกหลัก เลย์เอาต์เหมือนกันในทั้งสองโหมด
- การตรวจความพอดีใช้แบบจำลองข้อความโดยประมาณจาก `render.test.mjs` ซึ่งอาจพลาดการขึ้นบรรทัดใหม่ และไม่ใช่การทดสอบบนเครื่องจริง
- `matrix.test.mjs` คัดลอกชุด stub ของ `render.test.mjs` (บรรทัด 8 ถึง 703) ดังนั้นต้องแก้ไขสองไฟล์ให้ตรงกันเสมอ

## 4. ผลที่รู้อยู่แล้วและรายงานไว้ แต่ยังไม่แก้

- Mac, `SmallFitTests`: วิดเจ็ตขนาดเล็กที่ 90% ของกรอบ (153 x 153) ไม่ได้ถูกตรวจ ความกว้างตามธรรมชาติอยู่ที่ 154 ถึง 160 pt
  ซึ่งเกินกรอบ คือบัญชี 5 รายการทั้งสองภาษา (ไทย 156 pt, อังกฤษ 160 pt) และบัญชี 3 รายการภาษาอังกฤษ (154 pt) ภาพ 90% ของ
  บัญชี 5 รายการใน `small-fit/` อ่านได้ชัดเจนเมื่อดูด้วยตา ทั้งสองภาษาและทั้งสองโหมดสี แต่ไม่มีพื้นที่เหลือ เจ้าของโปรเจกต์เป็นผู้ตัดสินว่า
  ต้องแก้วิดเจ็ตขนาดเล็กที่ 90% หรือไม่
- iPhone, `matrix.test.mjs`: medium ที่มี 5 บัญชีในสถานะ ok ที่กรอบใหญ่ที่สุดที่สมมติไว้ โดยใช้ขนาดเต็ม (6 กรณี คือระดับทั้งสาม
  ทั้งภาษาไทยและอังกฤษ) ข้อความกว้างกว่า 364 จุดประมาณ 2 ถึง 4% (376.5 จุดในภาษาไทย 371 จุดในภาษาอังกฤษ) ข้อความทุกตัวใน medium
  ผ่าน `style()` ใน `AI Usage.js` ซึ่งให้หดได้ถึง 0.7 จึงน่าจะพอดีโดยการหดบนเครื่องจริง กรณีเหล่านี้ระบุไว้ใน `KNOWN_OVERFLOW`
  เทสต์จะล้มเหลวหากมีการล้นอื่น และล้มเหลวด้วยหากกรณีที่ระบุไว้ไม่ล้นแล้ว จนกว่าจะอัปเดตรายการ

## 5. รายการที่ต้องตรวจด้วยมือบน Mac และ iPhone จริง

ไม่มีเทสต์ใดรันรายการเหล่านี้ และยังไม่ได้รันสำหรับเอกสารนี้ ทำเครื่องหมายหลังตรวจบนเครื่องจริงแล้วเท่านั้น

| เสร็จ | รายการ | ขั้นตอน | สิ่งที่ต้องตรวจ |
|---|---|---|---|
| [ ] | แกลเลอรีวิดเจ็ตจริง | คลิกขวาที่เดสก์ท็อป เลือก Edit Widgets ค้นหาชื่อแอป (ตอนเขียนเอกสารคือ Quota Battery) แล้วเพิ่มวิดเจ็ตขนาดเล็ก กลาง และใหญ่ ใช้บัญชีห้ารายการถ้าทำได้ | ไม่มีข้อความถูกตัด แถวของขนาดกลางพอดี เมื่อมีห้าบัญชี ป้าย "+2" แสดงในแถวหัวข้อของขนาดกลาง (ด้านขวาของข้อความอัปเดต) และใต้ข้อความเวลาในขนาดเล็ก วิดเจ็ตทำตามการตั้งค่าภาษา |
| [ ] | แถบเมนูกับ Hidden Bar | ติดตั้ง Hidden Bar (1.11.2 ขึ้นไปบน macOS 27 ที่ทดสอบแล้วคือ 1.13.1) เปิดแอปหนึ่งครั้ง | ไอคอน AI Usage อยู่ในส่วนที่มองเห็นของ Hidden Bar (Settings > Icons) หลังเปิดแอปใหม่ ไอคอนยังอยู่ที่เดิม |
| [ ] | การแจ้งเตือน | เปิด "Notify at 80% and 95%" ในแอป และอนุญาตการแจ้งเตือนสำหรับผู้ส่งที่ macOS แสดง รอจนบัญชีใดบัญชีหนึ่งถึง 80% หรือ 95% | มีการแจ้งเตือนหนึ่งครั้งต่อการข้ามเกณฑ์ พร้อมข้อความตามภาษาที่เลือก |
| [ ] | สำเนาใน iCloud ไป iPhone | คัดลอก `scriptable/AI Usage.js` ไปยังโฟลเดอร์ Scriptable ใน iCloud Drive (ดู AGENTS.md ขั้นตอนที่ 6) บน iPhone เปิด Scriptable รัน AI Usage แล้วเพิ่มวิดเจ็ต | วิดเจ็ตบน iPhone แสดงบัญชีและเปอร์เซ็นต์เดียวกับ `usage.json` และอัปเดตขณะที่ Mac เปิดอยู่ |
| [ ] | เพิ่มบัญชีผ่าน Terminal | ในส่วน Accounts เลือก Add account เมื่อ macOS ถาม ให้อนุญาตให้ AIUsage ควบคุม Terminal ล็อกอินใน Terminal แล้วรีเฟรช | Terminal เปิดพร้อมคำสั่งล็อกอิน บัญชีใหม่ปรากฏหลังการรันครั้งถัดไป พร้อมป้าย New |
| [ ] | การสลับภาษา | ตั้ง Language เป็น System, ไทย และ English ทีละค่า | ข้อความในแอป วิดเจ็ต Mac และการแจ้งเตือนเปลี่ยนตาม วิดเจ็ต iPhone ทำตามภาษาของ iPhone หรือช่อง Parameter `th` หรือ `en` |
| [ ] | ลดการเคลื่อนไหว (Reduce Motion) | System Settings > Accessibility > Display > Reduce motion: เปิด แล้วรีเฟรชข้อมูล | เกจและวงแหวนเปลี่ยนภายใน 0.2 วินาที ไม่ใช่การเคลื่อนไหวแบบนุ่มปกติ และตัวเลขยังอัปเดต |

## 6. เวอร์ชัน

เวอร์ชันข้างต้นคือเวอร์ชันที่ชุดเทสต์นี้รันผ่าน รายการตรวจด้วยมือในหัวข้อ 5 ยังไม่ได้รันบนเวอร์ชันเหล่านี้สำหรับเอกสารนี้
เวอร์ชันอื่นยังไม่ได้ทดสอบ
