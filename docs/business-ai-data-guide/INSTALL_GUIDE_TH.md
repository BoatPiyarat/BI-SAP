# คู่มือติดตั้ง Skill "rabbitcare-bi-data" (สำหรับผู้ใช้ทั่วไป)

ใช้เวลาประมาณ 10 นาที · ใช้ได้บน Claude เว็บ (claude.ai) และ Claude Desktop
อ้างอิงขั้นตอนจากศูนย์ช่วยเหลือของ Anthropic ณ 26 พ.ย. 2026 — ชื่อเมนูอาจเปลี่ยนเล็กน้อยตามเวอร์ชัน

---

## Skill นี้ทำอะไร

เมื่อคุณถาม Claude เรื่องตัวเลขของ Rabbit Care (ยอดขาย เบี้ย ออร์เดอร์ ลีด ยกเลิก ผ่อน ฯลฯ) Claude จะ
1. **ถามกลับก่อน** ว่าต้องการนับแบบไหน (ยอดเงินหรือจำนวน, รวมยกเลิกไหม, นับตามวันไหน, เดือนปฏิทินหรือรอบคอม 16–15)
2. ดึงข้อมูลจาก BigQuery จากตารางที่ทีม BI อนุมัติเท่านั้น
3. ตอบพร้อมบอก **นิยามที่ใช้** และ **ข้อมูลถึงเวลาไหน**

> ตัวเลขจาก Claude ใช้ประกอบการตัดสินใจภายในได้ แต่ถ้าจะใช้ปิดบัญชี จ่าย commission ส่งบริษัทประกัน หรือ คปภ.
> ต้องให้ทีม BI ยืนยันก่อนเสมอ

---

## ก่อนเริ่ม — สิ่งที่ต้องมี

| สิ่งที่ต้องมี | ขอจากใคร |
|---|---|
| บัญชี Claude ของบริษัท (Team) | ทีม BI / IT |
| ไฟล์ `rabbitcare-bi-data.zip` | ทีม BI (data@rabbit.co.th) — **ห้ามแตกไฟล์ (unzip)** |
| สิทธิ์อ่าน BigQuery โปรเจกต์ `pacific-plating-282708` ด้วยอีเมลบริษัท | ทีม BI ขอให้ (สิทธิ์ BigQuery Job User + Data Viewer เฉพาะ dataset ที่อนุญาต) |

ถ้า admin ติดตั้ง skill ให้ทั้งบริษัทแล้ว **ข้ามไปขั้นตอนที่ 3** ได้เลย

---

## ขั้นตอนที่ 1 — เปิดการสร้างไฟล์ (ต้องเปิดก่อน Skill จึงจะทำงาน)

1. เข้า **claude.ai** แล้วล็อกอินด้วยอีเมลบริษัท
2. คลิกชื่อของคุณ (มุมซ้ายล่าง) → **Settings**
3. ไปที่ **Capabilities**
4. เปิดสวิตช์ **Code execution and file creation** (บางเวอร์ชันชื่อ **Create and edit files**) ให้เป็นสีเปิด

## ขั้นตอนที่ 2 — อัปโหลด Skill

1. ไปที่เมนู **Customize → Skills**
2. กดปุ่ม **+** → **Create skill** → **Upload a skill**
3. เลือกไฟล์ `rabbitcare-bi-data.zip` (ไฟล์ zip ทั้งไฟล์ ไม่ต้องแตก)
4. รอสักครู่ จะเห็น **rabbitcare-bi-data** ขึ้นในรายการ Skills
5. ตรวจว่าสวิตช์ข้างชื่อ skill **เปิดอยู่**

> ถ้าขึ้น error: ตรวจว่าไม่ได้แตกไฟล์แล้ว zip ใหม่เอง / ไม่ได้เปลี่ยนชื่อไฟล์หรือโฟลเดอร์ด้านใน — ขอไฟล์ใหม่จากทีม BI

## ขั้นตอนที่ 3 — เชื่อม BigQuery

1. ไปที่ **Customize → Connectors** (หรือ Connectors Directory)
2. ค้นหา **Google Cloud BigQuery** → กด **Connect**
3. ล็อกอินด้วย **บัญชี Google ของบริษัท** (@rabbit.co.th) แล้วกด **Allow**
4. ถ้าหา connector ไม่เจอ แปลว่า admin ยังไม่เปิดให้ทีม — แจ้งทีม BI

## ขั้นตอนที่ 4 — ทดลองใช้

1. เปิดแชตใหม่
2. กดปุ่ม **+** (หรือพิมพ์ `/`) → **Connectors** → ตรวจว่า **Google Cloud BigQuery** เปิดอยู่
3. ลองพิมพ์:
   > ขอยอดขาย Motor เดือนตุลาคม 2026
4. สิ่งที่ควรเกิด: Claude **ถามกลับ** เช่น "ต้องการยอดเงินหรือจำนวนออร์เดอร์? รวมรายการยกเลิกไหม? นับตามวันสร้างออร์เดอร์ วันชำระเงิน หรือวันเริ่มคุ้มครอง?"
   — ถ้า Claude ตอบตัวเลขทันทีโดยไม่ถาม แปลว่า skill ยังไม่ทำงาน ให้กลับไปตรวจขั้นตอนที่ 1–2
5. ตอบคำถามของ Claude แล้วจะได้ตัวเลขพร้อมนิยามและเวลาของข้อมูล

---

## ตัวอย่างคำถามที่ใช้ได้

- "จำนวนออร์เดอร์ Database ไม่รวม cancel ช่วง 1–23 พ.ย."
- "เบี้ยรวมแยกตามบริษัทประกัน นับตามวันที่ประกันอนุมัติ เดือนตุลาคม"
- "อัตรายกเลิกเดือนตุลาคม แยกยกเลิกธรรมดากับ change order"
- "ลีดจาก Facebook เดือนนี้ conversion เท่าไร"
- "ทำไมยอดใน dashboard ไม่ตรงกับยอดค่าคอม" (Claude จะอธิบายสาเหตุที่พบบ่อย)

## สิ่งที่ Skill นี้ **ไม่** ทำ

- คำนวณค่าคอมรายบุคคล → ดูที่ /commission portal
- เช็คสถานะออร์เดอร์รายเดียว → ใช้ CareOS / ทีม Operations
- อนุมัติข้อยกเว้น (อนุโลม) → ส่งอีเมลตามสายอนุมัติ
- ส่งข้อมูลลูกค้ารายบุคคล (ชื่อ เบอร์ ที่อยู่) — ถูกปิดไว้โดยเจตนา

---

## อัปเดต Skill เมื่อทีม BI ออกเวอร์ชันใหม่

1. **Customize → Skills** → คลิก skill เดิม → ลบ (หรือปิดสวิตช์)
2. อัปโหลดไฟล์ zip ใหม่ตามขั้นตอนที่ 2
(ถ้า admin ติดตั้งให้ทั้งบริษัท จะอัปเดตให้อัตโนมัติ ไม่ต้องทำเอง)

## ปัญหาที่พบบ่อย

| อาการ | วิธีแก้ |
|---|---|
| ไม่เห็นเมนู Skills | เปิด Code execution ในขั้นตอนที่ 1 ก่อน / แจ้ง admin ว่าองค์กรเปิด Skills หรือยัง |
| Claude บอกว่าไม่มีสิทธิ์ BigQuery (Access Denied) | ขอสิทธิ์จากทีม BI — ระบุอีเมลบริษัทของคุณ |
| Claude ตอบตัวเลขโดยไม่ถาม | ตรวจว่า skill เปิดอยู่ และ connector เปิดในแชตนั้น |
| ตัวเลขดูแปลก / ไม่ตรงกับ dashboard | ถาม Claude ว่า "ข้อมูลถึงเวลาไหน" และ "ใช้นิยามอะไร" แล้วส่งให้ทีม BI ตรวจ |
| ใช้บนมือถือ | Connector ใช้ได้หลังตั้งค่าบนเว็บ/desktop แล้ว แต่ skill บนมือถือยังไม่ยืนยัน — แนะนำใช้บนเว็บหรือ desktop |

ติดต่อทีม BI: data@rabbit.co.th

---

## สำหรับ Admin (Owner) — ติดตั้งให้ทั้งบริษัท

1. **Organization settings → Plugins & skills → แท็บ Policy** → ตรวจว่า **Cloud code execution and file creation** และ **Skills** เปิดอยู่
2. **Organization settings → Plugins & skills** → **Add** → **Upload a skill** → เลือก `rabbitcare-bi-data.zip` → ทุกคนได้รับทันที (ผู้ใช้ปิดเองได้แต่ลบไม่ได้)
3. **Organization settings → Connectors → Browse connectors** → **Google Cloud BigQuery** → **Add to your team** (แต่ละคนยังต้องล็อกอิน Google เอง)
4. ฝั่ง Google Cloud (ทีม BI/IT): ให้สิทธิ์ผู้ใช้ `roles/bigquery.jobUser` ระดับโปรเจกต์ และ `roles/bigquery.dataViewer` **เฉพาะ dataset ที่อนุญาต** (เช่น `analytics_reports`, `analytics_dimensional_modelling`) และ `roles/mcp.toolUser` ถ้า Google กำหนด — ⚠️ ให้ทีม IT ตรวจรายชื่อ role กับเอกสาร Google ล่าสุดก่อน
5. แนะนำตั้ง BigQuery custom quota ต่อผู้ใช้ เพื่อกันค่าใช้จ่ายเกิน

แหล่งอ้างอิง: support.claude.com — "Use Skills in Claude", "Provision and manage skills for your organization",
"Pre-built connectors for Claude"; claude.com/marketplace/connectors/bigquery
