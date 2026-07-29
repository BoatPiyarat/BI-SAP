# ADDENDUM 2026-07-29 v2 — EXCLUSION & FORMAT RULES (RESOLVED)
Supersedes: ADDENDUM 2026-07-29 v1 (ข้อที่ tag ⏳ ถูกตอบแล้ว 2026-07-29 โดย Boat)
(แก้วันที่จาก 2026-07-30 → 2026-07-29 ตามที่ Boat ยืนยัน — ห้ามเดาวันที่อีกต่อไป ใช้ `date` command ตรวจก่อนเสมอ)
ให้ append เข้า `docs/knowledge/10_SAP_CONTEXT.md`

## หลักการครอบทั้งหมด: EXCLUDED ≠ DELETED
ทุกแถวที่ถูกกรอง → ลง `sap_integration_v3.sap_excluded_records`
(order_item, period, rule_code, reason, detected_at) + นับใน morning report แยกจาก backlog จริง
ห้ามหายเงียบเด็ดขาด

---

## E1. Year scope — แยกตาม stage (แก้จาก v1 ที่เป็นการตัดทั้งปี)

| ปีของรายการ | Create / Paid / NewPayment | Cancel |
|---|---|---|
| ≤ 2024 | ❌ ไม่แตะเลย | ❌ ไม่แตะเลย |
| 2025 | ❌ **ห้ามนำเข้า paid เพิ่ม** | ✅ **ส่งได้ ตามสถานะ cancel จาก CareOS** |
| 2026+ | ✅ ปกติ | ✅ ปกติ |

**Date basis (confirmed):** ใช้ **`GREATEST(OrderDate, PolicyDate)`** — ยึดวันที่ล่าสุดกว่าของสองตัว
- ถ้าตัวใดเป็น NULL → ใช้ตัวที่มีค่า
- ⏳ CONFIRM: ถ้า **NULL ทั้งคู่** ให้ทำอย่างไร (เสนอ: exclude + rule_code `DATE_BASIS_MISSING`
  แล้วรายงานจำนวนทุกเช้า — ไม่เดาปีเอง)
- ห้ามใช้ `NOT LIKE '%2023%'` string matching อีก → ใช้ `EXTRACT(YEAR FROM ...)`

**⚠️ เงื่อนไขซ่อนของ "2025 cancel ได้" — ต้อง implement ให้ถูก:**
Cancel spec (R4/R5) บังคับว่างวดอื่นต้องเป็น Paid/Pending และงวด 1 ต้อง Paid **อยู่ใน SAP ก่อน**
→ order 2025 ที่ **ไม่เคยถูก interface เข้า SAP เลย** จะ cancel ไม่ได้ (SAP reject ทั้งไฟล์)
และเราก็ห้ามส่ง Paid ย้อนให้มันด้วย (ตามกฎ E1)
**กติกา:** ส่ง cancel ปี 2025 **เฉพาะ order ที่มีอยู่ใน SAP แล้ว** (มีแถวใน sap_mirror_state)
ถ้าไม่มี → `sap_excluded_records` rule_code = `CANCEL_2025_NOT_IN_SAP` (ไม่ใช่ MISSING, ไม่ต้องตามเก็บ)

## E2. Test customer
กรองออกเสมอ — เช็คทั้ง FirstName และ LastName (legacy เช็คแค่ FirstName)
- ⏳ CONFIRM: pattern สุดท้าย เสนอ
  `LOWER(TRIM(FirstName)) IN ('test','test div') OR LOWER(TRIM(LastName)) IN ('test','test div')`
  **ห้ามใช้ `LIKE '%test%'`** (จะโดนชื่อจริง: Testa, Contested)
- rule_code = `TEST_CUSTOMER`

## E3. InsurerCode ไม่มีใน SAP master
กรองออก + ไม่อยู่ใน backlog — แต่ **ต้องนับและโชว์** ทุกเช้า
- rule_code = `INSURER_NOT_IN_MASTER`
- Morning report ต้องมี: "insurer code ที่ถูกกรอง (distinct) = N: `<list>`"
  → code ใหม่โผล่ = สัญญาณต้องขอ Aware เพิ่ม master ไม่ใช่ปัญหาที่จบในตัว
- ⏳ CONFIRM: master list มาจากไหน — เสนอ seed จาก InsurerCode ที่ SAP เคยรับสำเร็จ
  (distinct จาก SAP_LIVE) แล้วขอ list จริงจาก Aware มาแทนภายหลัง

---

## F1. InsuredID ห้ามว่าง
ไม่มีจาก CareOS → ใส่ `-` | ต้องครอบ **ทุก flow** ใน v3 (ไม่ใช่แค่บาง CTE)

## F2. PolicyNo ≤ 50 ตัวอักษร — **BLOCK (confirmed)**
เกิน 50 → **ไม่ส่ง** + validation rule `POLICYNO_TOO_LONG`
**ห้าม truncate** (เลขกรมธรรม์ที่ถูกตัด = ข้อมูลผิดใน SAP ที่แก้ยากกว่า)
Morning report ต้องมีบรรทัด: จำนวนที่ถูก block + ตัวอย่าง order_item 3 ราย → ให้คนแก้ต้นทาง

## F3. Date format = 8 ตัว (DDMMYYYY) — ว่างได้เฉพาะ Pending (confirmed)

| Field | ว่างได้? |
|---|---|
| PaymentDate | ✅ ว่างได้ **เฉพาะแถวที่ status = pending** เท่านั้น |
| OrderDate, PolicyDate, ExpectedDate, BatchRunDate | ❌ ห้ามว่าง ต้อง 8 ตัวเสมอ |

Validation `DATE_FORMAT_INVALID`:
```
-- ทุก date column
LENGTH(col) = 8 AND SAFE.PARSE_DATE('%d%m%Y', col) IS NOT NULL
-- ยกเว้น PaymentDate เมื่อ status = 'pending' → อนุญาต col = ''
```
เช็คทั้งความยาวและ parse ได้จริง (กัน `32072026`) + leading zero (`01072026` ไม่ใช่ `1072026`)

---

## ผลต่อตัวเลข backlog
`MISSING_NO_ROW_IN_SAP = 373,044` จะลดลงมากหลังใช้ E1–E3 → ต้องรายงานตัวเลขใหม่
ห้ามอ้างเลขเก่าต่อ และให้แยกรายงาน: **backlog จริง (2026+, และ cancel 2025 ที่มีใน SAP)**
vs **excluded (แยกตาม rule_code)**
