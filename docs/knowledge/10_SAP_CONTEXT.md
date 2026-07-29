# 10_SAP_CONTEXT.md
Version: 3.0 (consolidated 2026-07-16 จาก SAP_CONTEXT v2.1 + Team Context 07-14 + main.py จริง)
กติกา: ไฟล์นี้คือ single source ของ business rules & architecture — แก้เมื่อ rule เปลี่ยนจริงเท่านั้น พร้อมลง CHANGELOG

---

## PROJECT GOAL

ไม่ใช่แค่ export CSV — เป้าหมายคือ integration platform ระหว่าง CareOS ↔ SAP ที่
minimize interface errors / manual adjustments, มี traceability ครบ, maintain ต่อได้โดยทีมรุ่นถัดไป,
และเป็น single source of truth ของ SAP integration knowledge

- **GCP project:** `pacific-plating-282708`
- **Stack:** BigQuery, Cloud Run Jobs, Cloud Scheduler, Secret Manager, VPC Connector,
  WireGuard gateway (VM `sap-wireguard-gateway`), Docker (python:3.12-slim pinned bookworm),
  Looker Studio, draw.io, Confluence, GitHub

---

## ARCHITECTURE — ⚠️ CORRECTED 2026-07-24 (การค้นพบใหญ่ — traced จริงใน BigQuery/gcloud ไม่ใช่เดา)

**กติกาเก่า (07-16) "มี 2 pipeline คู่ขนาน B1(เก่า)/B2(ใหม่, Phase 6→raw_sap_live)" — ผิด**
`raw_sap_live` **ไม่เคยถูกสร้างจริง** และ `gs://sap-bucket-csv` **ไม่มีอยู่จริงใน project นี้เลย**
— ทั้งคู่เป็นแผนใน design docs ที่ไม่เคย deploy จริง ตรวจสอบแล้ว 2026-07-24

**Path A — Interface ขาออก (CareOS → SAP):**
```
CareOS → BigQuery raw → stg_* → Business Logic (per BU×stage) → Validation
→ sap_export_* → CSV → gs://interface-file/{RCB_MOTOR,RCB_NONMOTOR,ADB_MOTOR}/
→ SAP pull (Vendor Aware — ห้ามแตะ): ทุก 15 นาทีจากต้นชั่วโมง (นาทีที่ 0/15/30/45), process จริงที่นาทีที่
30 ของทุกชั่วโมง (ยืนยันจาก Boat 2026-07-25 — แก้ไข "รายชั่วโมง" เดิมที่เป็นการประมาณคร่าวๆ)
```

**Path B — ขากลับ (SAP DB → BigQuery เพื่อ recon): pipeline จริงมีเส้นเดียว (ไม่ใช่ 2 คู่ขนาน)**
```
SAP DB (RCB_LIVE_DB, ผ่าน WireGuard) --[pyodbc]--> sap-extract-job (Cloud Run JOB)
  --[NDJSON]--> gs://rcb-bronze-zone/SAP/production_database/ (ไฟล์ชั่วคราว ลบทันทีหลังโหลด)
  --[Eventarc trigger]--> sap-order-payment-initial-phase (Cloud Run SERVICE)
  --[load]--> sap_integration_v2.SAP_LIVE (ลบไฟล์ต้นฉบับหลังโหลดสำเร็จ)
```
- `sap-extract-job` มีจริง ทำงานจริง (verified: real rows processed, watermark เดินจริง,
  `sap_extract_control`/`_extract_control/_watermark_state.json` ใน bronze zone) — **แต่ไม่เคยเขียนเข้า
  BigQuery เอง** แค่เขียน NDJSON ชั่วคราวแล้วให้ตัวถัดไปกิน
- `sap-order-payment-initial-phase` คือตัวที่ทำ load จริงเข้า `SAP_LIVE` — trigger ผ่าน Eventarc
  (`trigger-sap-order-payment-initial-phase`, service account = default Compute SA ของ project,
  **ไม่ใช่** `sap-bucket-csv@...`)
- `SAP_LIVE` = **SAP truth ที่สดจริง** (14/14 runs SUCCESS นับจาก 07-09, ไม่มี error, watermark
  ปัจจุบันภายใน ~15 นาทีเวลาที่เช็ค) — ไม่ใช่ stale mirror ที่ต้อง sunset ตามที่ ADDENDUM 07-23 สรุปไว้เดิม
- `SAP_LIVE_FULL` (view, `sap_integration_v2`) = UNION ของ SAP_LIVE + SAP_LIVE_2024/2025/2026,
  dedup ด้วย DocEntry (ROW_NUMBER by BatchRunDate DESC) — **แต่ยังมี duplicate ที่ระดับ
  (OrderItem, Period)** (328,071 keys ยืนยันจริง 07-24, เช่น doc Pending + doc Cancelled/Paid
  ของงวดเดียวกันอยู่พร้อมกัน) → ใช้ `sap_integration_v3.stg_sap_state` แทนถ้าต้องการ 1 แถว/(item,period)
- **`sap-extract-schedule` (Cloud Scheduler, 20:30 ICT) ล่มอยู่ตอนนี้** — 401 UNAUTHENTICATED,
  IAM binding (`run.invoker` สำหรับ `sap-bucket-csv@...` บน `sap-extract-job`) น่าจะไม่เคย apply
  สำเร็จเลย (audit log ไม่เจอ SetIamPolicy ที่ granted=true บน resource นี้) ไม่ใช่ "หลุดไป" — ดู
  30_SAP_CHANGELOG.md 2026-07-24 (cont'd 6) รอ Attila แก้ (ต้อง IAM Admin เท่านั้น)
- Dead-man's-switch (`sap_integration_v3.vw_dead_mans_switch` / scheduled query "SAP Data Freshness
  Monitor") เฝ้าดูความสดของ `SAP_LIVE` แทนที่จะรอเจอปัญหาเอง — deploy แล้ว 2026-07-24

**6-Layer Standard (v2.1):** Extraction → Staging → Business Logic → Validation → Export →
Reconciliation & Monitoring (Layer 6 อ่านอย่างเดียว ไม่ mutate)

---

## DESIGN PRINCIPLES

- Control-first: ห้าม export ตรงจาก business SQL — ต้องผ่าน raw → stg → int → val → sap_export
- Validate BEFORE export, never after SAP; ทุก failure ลง `sap_validation_error` ห้าม drop เงียบ
- ทุก layer idempotent (re-run ได้ผลเดิม ไม่ duplicate side effect)
- ทุก query change = branch + PR + validation template + 0-row-diff proof ก่อน merge

---

## RCB / RCL CLASSIFICATION — ⚠️ CORRECTED 2026-07-14 (accounting-critical)

**กฎเก่า "RCL = PaymentMethod/PaymentChannel prefix RCL" — ผิด** prefix นั้นคือ OUTPUT ที่ BI
generate ไม่ใช่ signal จากต้นทาง (Data Dictionary/Validation Library ฉบับ cold tier ยังเขียนแบบเก่า — ห้ามใช้)

**Logic จริง (⚠️ PROVISIONAL รอ IT confirm — ถาม IT ผ่าน Slack 07-14 เรื่องเพิ่ม direct RCL field ใน CareOS):**
- **Voluntary RCL:** (`transaction_snapshot_installment_details.id IS NOT NULL` OR `transactions.installments > 1`)
  AND `follow_ups.transaction_id IS NOT NULL` AND `transaction_snapshots.number_of_installment > 1`
- **Compulsory/CMI RCL:** `motor_item_type = 'MOTOR_TYPE_COMPULSORY'` AND `service_provider = 'RABBIT_LENDING'`

หลักคงเดิม: RCB = one-time / RCL = installment, ห้ามปนกัน; ห้ามใช้ CompanyDB (ค่าคงที่ 'RCB' เสมอ)

---

## BUSINESS RULES (คงเดิมจาก v2.1)

- **Product separation:** Motor / Non-Motor / Compulsory — SQL, validation, export แยกอิสระ
- **Compulsory ID:** `motor_item_type = 'MOTOR_TYPE_COMPULSORY'` เท่านั้น — ห้ามใช้ packageType
  (ต้นเหตุ 263-transaction mismatch)
- **RCL installment:** ทุก payment ต้อง export ครบทุก period (full schedule)
- **PaymentDate:** ใช้วันจ่ายจริง; ถ้าตกงวดบัญชีที่ปิดแล้ว → เลื่อนเป็นวันแรกของงวดเปิดถัดไป
  (cutoff จาก `sap_accounting_cutoff_dates` — Finance confirm รายเดือน, ห้าม hardcode)
- **Immutable keys:** OrderItem + InvoiceNo แก้ไม่ได้หลัง post — แก้ = Cancel+Re-import หรือ manual SAP
- **Additional payment:** Period เดิม, ExpectedReceived=0, ActualReceived>0 → ไม่ใช่ duplicate
  PK = OrderItem + Period + ChargeID + InvoiceNo
- **Cancel/Recreate:** partial (M-only/V-only) เป็น normal practice; matching ต้อง item-level
  ⚠️ ChassisNo มี human error + ไม่มีใน Non-Motor — ใช้เป็น key ไม่ได้ (INCIDENT-001 Hypothesis 2)
- **Credit Shell:** ไม่มี `transaction_snapshot_installment_details` เป็นเรื่องปกติ →
  fallback `COALESCE(period, 1) = 1` (fix รอ Head of Products confirm — INCIDENT-001)
- **Cancel sequencing (confirmed 07-14):** Paid+Cancel วันเดียวกัน → ส่ง batch เดียวกันเป็นไฟล์
  เรียงลำดับ `<YYYYMMDD>_01_create.csv`, `_02_cancel.csv` — ไม่รอ SAP round-trip;
  hold เฉพาะเมื่อ Paid ต้นทาง BLOCKED/MISSING
- **SAP ack convention:** การกลับมาปรากฏใน SAP_LIVE (D+1 extract) = official confirmation
- **NonMotor error root cause:** sequencing violation (Cancel ส่งโดยไม่มี Paid นำ)

---

## EXTRACT JOB (Phase 6) — ข้อเท็จจริงยืนยันแล้ว (แก้ 2026-07-24: ตัด reference ถึง raw_sap_live/B1 ทิ้ง)

- SAP DB timezone = Asia/Bangkok (UTC+7); `UpdateTime` format HHMM
- Watermark-based (ไม่ใช่ date window) — scheduler delay ไม่ทำข้อมูลหาย; state จริงอยู่ที่
  `gs://rcb-bronze-zone/SAP/_extract_control/_watermark_state.json` (ไม่ใช่แค่ `sap_extract_control`
  ใน BigQuery)
- Filter: `U_InsuranceGroup <> 'B2B'`
- Deploy env จริง (verified 07-24): `SAP_DB_HOST=172.25.25.3`, `SAP_DB_NAME=RCB_LIVE_DB`,
  `GCS_BUCKET=rcb-bronze-zone`, `GCS_PREFIX=SAP/production_database` — เขียน NDJSON ที่นี่ **ชั่วคราว
  เท่านั้น** ตัวถัดไป (`sap-order-payment-initial-phase`, Cloud Run service แยกต่างหาก) กินไฟล์แล้วลบทิ้ง
  หลังโหลดเข้า `SAP_LIVE` สำเร็จ — งานนี้เอง**ไม่ได้เขียนเข้า BigQuery โดยตรง** (ผิดจากที่เข้าใจเดิม)
- Secrets ต้อง bind ผ่าน `--update-secrets` (`sap-db-username`, `sap-db-password`) —
  code อ่าน env var ตรงๆ ถูกแล้ว, ห้าม deploy ด้วย `--set-env-vars` plaintext อีก
- `sed` corrupt password ที่มี `&`/`\`
- **`sap-extract-schedule` ล่มอยู่** (401, IAM binding ไม่เคย apply สำเร็จ) — ดู ARCHITECTURE ด้านบน

---

## SAP ERROR → COLUMN (ย่อ — เต็มดู Data Dictionary)

duplicated→TransactionStatus | must be Paid before→sequencing | InsurerCode not found→master gap |
InvoiceNo cannot change→invoice drift | Not balance→TotalPremium/TotalAmount |
Posting Periods Unlocked→PaymentDate | invalid date→ต้อง DDMMYYYY

---

## GOVERNANCE & AI WORKING STYLE

- เปลี่ยน business logic/field/schema/reference data → แจ้ง BI ก่อน deploy เสมอ
- AI: study first, เข้าใจ business logic ก่อนเขียน SQL; ข้อมูลยังมาไม่ครบ → รอ ไม่วิเคราะห์บางส่วน
- Data privacy: ข้อมูล customer จาก connector → mask by default
- Security: credential เคยหลุดในแชท ≥2 ครั้ง — rotate เป็นระยะ, ห้าม paste plaintext,
  ห้าม echo password ใน shell (ตัว `&` ใน password ทำ bash แตก background job)


---

## ⚠️ ADDENDUM 2026-07-23 — กติกาใหม่ที่สำคัญที่สุด (override ส่วนที่ขัดกันด้านบน)

1. **⚠️ แก้ 2026-07-24 (ของเดิมผิด — `raw_sap_live` ไม่มีอยู่จริง, verified ผ่าน bq/gcloud ไม่ใช่เดา):**
   **SAP truth = `sap_integration_v2.SAP_LIVE_FULL`** (ดู ARCHITECTURE ด้านบนสำหรับ pipeline จริงที่ป้อนมัน)
   — ใช้ `sap_integration_v3.stg_sap_state` แทนเมื่อต้องการ 1 แถว/(OrderItem, Period) แบบ dedup แล้ว
   (SAP_LIVE_FULL เองยังมี duplicate 328k+ keys ที่ระดับนี้ — dedup แค่ระดับ DocEntry) ห้ามใช้
   SAP_LIVE_2024/2025/2026 หรือ SAP_LIVE ตรงๆแยกกัน (เป็นแค่ shard ดิบที่ SAP_LIVE_FULL union รวม)
2. **Cancel import spec (inferred, รอ Aware confirm — SPEC_INFERRED_v0.9):** ครบงวด 1..TotalPeriods,
   งวดละ 1 แถวเท่านั้น, InvoiceNo ต้องตรง doc ปัจจุบันใน SAP เป๊ะ, งวดอื่นต้อง Paid/Pending,
   order ที่ cancelled แล้วห้ามส่งซ้ำ — SAP validate ทั้ง order เป็นชุด พังหนึ่งพังหมด
3. **Charge-driven principle (Boat 23/07):** population ขับจาก charge SUCCESSFUL —
   จ่ายถึงงวดไหน interface ถึงงวดนั้น; งวดที่ SAP ถืออยู่แล้ว mirror เป๊ะทุก column (InvoiceNo ห้ามแตะ)
4. **InvoiceNo convention conflict (เปิดอยู่):** BI ใช้ CONCAT('2_', third_party_id) กัน collision /
   flow อื่นใช้ raw id — SAP ปัจจุบันถือ raw id; มาตรฐานเดียวรอตัดสินใจ (เสนอ: raw id + rank prefix
   เฉพาะ additional payment) ห้าม gen invoice โดยไม่ผ่านกติกากลาง
5. **CREDIT_CARD_INSTALLMENT = ONETIME flow** (ธนาคารจ่ายเต็ม): TotalPeriods=1, status paid,
   channel RCB-EDC-<bank> (KBANK confirmed; bank อื่นรอบัญชี)

## ⚠️ ADDENDUM 2026-07-29 v2 — EXCLUSION & FORMAT RULES (RESOLVED) — supersedes v1
(แก้วันที่ 2026-07-30 → 2026-07-29 — ยืนยันจริงด้วย `date`, ไม่เดาอีกต่อไป)

**หลักการครอบทั้งหมด: EXCLUDED ≠ DELETED.** ทุกแถวที่ถูกกรองโดยกติกาข้างล่าง → ลง
`sap_integration_v3.sap_excluded_records` (order_item, period, rule_code, reason, detected_at) —
นับใน morning report แยกจาก backlog จริง ห้ามหายเงียบเด็ดขาด. Implement ที่ **staging/engine**
(`sp_refresh_expected_state`) ไม่ใช่ export layer — excluded rows ไม่เข้า `expected_state` เลย
ดังนั้น `delta_export`/`interface_daily_status` จะไม่นับเป็น `MISSING` โดยอัตโนมัติ.

**E1. Year scope — แยกตาม stage** (แก้จาก v1 ที่ตัดทั้งปีแบบเหมารวม):

| ปีของรายการ (date basis) | Create/Paid/NewPayment | Cancel |
|---|---|---|
| ≤ 2024 | ❌ ไม่แตะเลย (`OLD_YEAR_NO_TOUCH`) | ❌ ไม่แตะเลย (`OLD_YEAR_NO_TOUCH`) |
| 2025 | ❌ ห้ามนำเข้า paid เพิ่ม (`NO_NEW_PAID_2025`) | ✅ เฉพาะ order ที่มีอยู่ใน `sap_mirror_state` แล้ว — ถ้าไม่มี → `CANCEL_2025_NOT_IN_SAP` |
| 2026+ | ✅ ปกติ | ✅ ปกติ |

Date basis = `GREATEST(OrderDate, PolicyDate)` (NULL ตัวใดใช้ตัวที่มีค่า); **NULL ทั้งคู่ →
exclude, rule_code `DATE_BASIS_MISSING`**, รายงานจำนวนทุกเช้า ไม่เดาปีเอง. ห้ามใช้
`NOT LIKE '%2023%'` string matching อีกต่อไป — ใช้ `EXTRACT(YEAR FROM ...)` เท่านั้น.
เหตุผลของ "2025 cancel ได้เฉพาะที่มีใน SAP แล้ว": cancel spec (R4/R5) บังคับงวด 1 ต้อง Paid ใน SAP
ก่อน — order ที่ไม่เคยเข้า SAP เลยจะ cancel ไม่ได้ (SAP reject ทั้งไฟล์) และห้ามส่ง Paid ย้อนให้ตาม E1
อยู่แล้ว จึงต้อง exclude แยกเป็น `CANCEL_2025_NOT_IN_SAP` (ไม่ใช่ MISSING, ไม่ต้องตามเก็บ).

**E2. Test customer** (final, resolved 2026-07-29, exact match เท่านั้น):
- `TEST_CUSTOMER_NAME`: `LOWER(TRIM(FirstName))='test' OR LOWER(TRIM(LastName))='test'` — **exact
  match เท่านั้น ห้าม `LIKE '%test%'`** (จะโดนชื่อจริง เช่น Testa, Contested) และ **ตัด `'test div'`
  ออกจากลิสต์** ตามที่ Boat ยืนยัน 07-29 (ใช้แค่ `'test'`)
- `TEST_CUSTOMER_PHONE`: เบอร์ (normalize ตัด space/-/() แล้วแปลง `+66xxxxxxxxx`→`0xxxxxxxxx`) `=
  '0999999999'` — **REPORT-ONLY รอบแรก**, ยังไม่ตัดออกจาก interface. ตรวจจริง 2026-07-29: 252
  order_items ตรง, 72 รายชื่อไม่ใช่ 'test', ΣActualReceived (ที่มีใน SAP แล้ว) = ฿670,312.54 — **ไม่ใช่
  0 และไม่ใช่ test ทั้งหมด** จึงยังไม่เปิดเป็น hard filter ตามเงื่อนไขที่ Boat วางไว้เอง (ปรับได้ที่
  config table ไม่ต้อง deploy เมื่อ Boat สั่ง)

**E3. InsurerCode ไม่มีใน SAP master**: กรองออก + ไม่อยู่ใน backlog แต่ต้องนับ/โชว์ distinct list
ทุกเช้า (`INSURER_NOT_IN_MASTER`) — code ใหม่โผล่ = สัญญาณขอ Aware เพิ่ม master ไม่ใช่ปัญหาจบในตัว.
Master seed จาก distinct `InsurerCode` ที่ SAP เคยรับสำเร็จจริง (`SAP_LIVE_FULL`) — รอ list จริงจาก
Aware มาแทนภายหลัง.

**F1. InsuredID ห้ามว่าง** — ไม่มีจาก CareOS → ใส่ `-`, ครอบทุก flow (fix ที่ `stg_order_dim` ต้นทาง
ไม่ใช่แค่บาง CTE).

**F2. PolicyNo >50 ตัวอักษร = BLOCK (confirmed)** — ห้าม truncate (เลขกรมธรรม์ที่ถูกตัด = ข้อมูลผิดใน
SAP ที่แก้ยากกว่าไม่ส่ง) → validation rule `POLICYNO_TOO_LONG` + morning report ต้องมีจำนวน + ตัวอย่าง
order_item 3 ราย.

**F3. Date format = 8 ตัว (DDMMYYYY)** — ว่างได้เฉพาะ `PaymentDate` เมื่อ `status=pending` เท่านั้น
(`OrderDate`/`PolicyDate`/`ExpectedDate`/`BatchRunDate` ห้ามว่าง). เช็คทั้งความยาว+parse ได้จริง (กัน
`32072026`) และ leading zero (`01072026` ไม่ใช่ `1072026`). **UNVERIFIED/ไม่ยังไม่ wire จริง**: ยังไม่มี
คอลัมน์ export ที่ format เป็น DDMMYYYY string ใน `expected_state` วันนี้ (รอ PHASE B 56-column
rebuild) — logic พร้อมใช้เมื่อ column เหล่านั้นมีจริง.

**ผลต่อ backlog**: `MISSING_NO_ROW_IN_SAP` เลขเก่า (373,044 ณ 07-27) ใช้ต่อไม่ได้ — ต้องแยกรายงาน
**backlog จริง** (2026+ และ cancel 2025 ที่มีใน SAP) vs **excluded** (แยกตาม rule_code) ทุกครั้ง.
ดู `sql/ddl/032-036` และ `docs/knowledge/30_SAP_CHANGELOG.md` 2026-07-29 สำหรับตัวเลขจริง.
6. Design v3 ทั้งชุดอยู่ใน docs/design/ — อ่าน REDESIGN_V3 ก่อนแตะ pipeline ใดๆ
