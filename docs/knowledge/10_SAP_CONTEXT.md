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

**Interface filename contract (confirmed from SAP email evidence 2026-07-27):**
- ทุกไฟล์ใต้ `gs://interface-file/<BU>/` ต้องขึ้นต้นด้วย `INSURANCE_RCB_`
  (`Type_Company_`).
- ห้ามใส่ชื่อ BU ซ้ำใน filename; path `<BU>/` เป็นตัวกำหนด BU และ SAP import log จะเติม BU
  prefix เองตอนรายงาน.
- ชื่อผิด contract ถูก SAP ปฏิเสธในขั้น download ก่อนถึง import จึงเสีย pull cycle โดยไม่ได้
  validation/import ใด ๆ.

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

**Path C — SAP result evidence (revised 2026-07-29):**
- Gmail body = header metadata; error text อยู่ใน TXT/XLSX attachment.
- Apps Script ใช้ `getAttachments()` แล้วเก็บไฟล์ที่
  `gs://rcb-bronze-zone/sap_import_logs/<LogID>/`.
- Import-result email ที่มี LogID เข้า `sap_import_result` โดย `log_id` เป็น logical key; parse TXT
  ชั้นที่สองเข้า `sap_import_error_detail` ที่ grain `(log_id, detail_seq)` เป็น `STRUCTURAL`
  หรือ `ROW_LEVEL` พร้อม `error_message`/`row_ref`.
- Gmail label `ingested` กันประมวลผลซ้ำหลัง persist สำเร็จ.
- `DOWNLOAD_GCS_FILE` ไม่มี LogID และต้องเข้า `sap_file_pickup` แยกต่างหาก: เป็นหลักฐานว่า SAP
  ดึงไฟล์ ไม่ใช่หลักฐานว่า import rows สำเร็จ.

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
- **CMI add-on deduction grain:** หัก `add_ons` ได้ครั้งเดียวต่อ `(OrderItem, Period)` เท่านั้น
  ห้ามหักซ้ำต่อ charge row. กฎนี้ป้องกัน `INCIDENT-002` ใน credit-shell path.
- **RCL installment:** ทุก payment ต้อง export ครบทุก period (full schedule)
- **PaymentDate:** ใช้วันจ่ายจริง; ถ้าตกงวดบัญชีที่ปิดแล้ว → เลื่อนเป็นวันแรกของงวดเปิดถัดไป
  (cutoff จาก `sap_accounting_cutoff_dates` — Finance confirm รายเดือน, ห้าม hardcode)
- **Immutable keys:** OrderItem + InvoiceNo แก้ไม่ได้หลัง post — แก้ = Cancel+Re-import หรือ manual SAP
- **Additional payment:** Period เดิม, ExpectedReceived=0, ActualReceived>0 → ไม่ใช่ duplicate
  PK = OrderItem + Period + ChargeID + InvoiceNo
- **Repeated-row expected amount:** เมื่อมีหลายแถวใน `(OrderItem, Period)` เดียวกัน แถวที่ 2
  เป็นต้นไปต้องมี `ExpectedReceived = 0` เสมอ.
- **Actual-received correction (Aware + Sarawut/Boyd confirmed 2026-07-29):**
  - Method 1 — adjustment line: ใช้ Period เดิม, `ExpectedReceived=0`, และ
    `ActualReceived=ส่วนต่าง` (ค่าลบเมื่อรับเกิน / ค่าบวกเมื่อรับขาด). ทดสอบกับ
    `L79899055`, `L79965977`.
  - Method 2 — Cancel เอกสารเดิมแล้วส่ง Paid ใหม่. ทดสอบกับ `L79899088`, `L79965966`.
  - **Selection rule:** ถ้า `ExpectedReceived` ผิดหรือติดลบ ต้องใช้ Method 2 ตามคำแนะนำของ
    Aware; ห้ามแก้ด้วย adjustment line.
  - ⚠️ **Recon ambiguity:** Method 1 มีรูปทรงเดียวกับ additional payment
    `(Period เดิม, ExpectedReceived=0, ActualReceived>0)`. ห้ามสรุปจากโครงสร้างแถวเพียงอย่างเดียว
    และห้ามเชื่อยอด recon แยกประเภทจนมี durable marker ระบุ `CORRECTION` หรือ
    `ADDITIONAL_PAYMENT`.
- **Cancel/Recreate:** partial (M-only/V-only) เป็น normal practice; matching ต้อง item-level
  ⚠️ ChassisNo มี human error + ไม่มีใน Non-Motor — ใช้เป็น key ไม่ได้ (INCIDENT-001 Hypothesis 2)
  Cancel output must be emitted per `order_item`; an order-level signal must never pull active
  sibling items into the cancel file.
- **Canonical cancellation definition (revised D1, Boat 2026-07-29):**
  `stg_order_dim.is_cancelled_effective =
  (careos.careos_order_items.is_cancelled IS TRUE) OR
  (careos.careos_order_items.cancel_time IS NOT NULL)`. Source field ทั้งสองมาจาก
  `careos.careos_order_items`; ให้คำนวณครั้งเดียวใน `stg_order_dim`
  และทุก downstream query ใช้ field นี้เท่านั้น
  **ห้าม re-derive cancellation เอง**. นิยามนี้ตรงกับ legacy cancel-new logic ที่ใช้ OR condition
  เดียวกันมาก่อน และปิดช่องว่างที่ v3 เห็น cancelled น้อยกว่า legacy.
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

## ADDENDUM 2026-07-30 — D10/D11 CMI correction execution

- Canonical B1/B2/B3 definitions live in `docs/AUDIT_CMI_ADDONS.md`; these are
  `INCIDENT-002` buckets, not historical pipeline labels.
- **D10:** Method-2 replacement naming is not decided. `M2` is already used by real CareOS items,
  so the naming template/prefix must be a configuration parameter, never a hardcoded suffix.
  The `C#` prefix seen around Credit Shell is only an SAP-side clue pending Aware Q4.
- **D11:** the pilot must be a B1 case using Method 1, not B3, because this path has the fewest
  dependencies and does not require a new OrderItem generation or naming infrastructure.
  The two B3 cases already Cancelled in SAP go to Aware for manual correction; do not build
  infrastructure for them.
- Process rule: definitions supplied in chat must be written into canonical knowledge in the same
  session. Agents must not infer an undocumented taxonomy.

### D12/D13 — materiality and posting correctness

- Amount shortage/overage uses a ±฿10 tolerance **per order**. Aggregate all relevant rows before
  comparison; do not apply the buffer per row, Period, OrderItem, or SAP document.
- `AMOUNT_VARIANCE` and `MISPOSTING` are permanent separate defect classes.
- `MISPOSTING` has no buffer: net zero can still be wrong when amounts land on opposite accounting
  sides. `L80524847` is only an output-shape example; FA confirmed its file was rejected and no JE
  exists, so it is not evidence of a posted misposting.
- An order may have every constituent row below ฿10 but exceed ฿10 after aggregation. This is a
  required validation case and the reason order grain is canonical.

### D14 — correction routing

- Class 1 `AMOUNT_VARIANCE` → Method 1 adjustment line.
- Class 2 `MISPOSTING` → Method 1 adjustment line per affected item; no Cancel required.
- B2 (`ExpectedReceived` itself wrong) → Method 2; naming config, alias mapping, and Aware Q4 still
  apply to this group only.
- B3 (SAP already Cancelled) → manual SAP correction by Aware.
- Accepted limitation: Method 1 corrects amounts but does not delete the duplicate full-Expected
  document. A duplicate JE created by the document may remain. Require GL verification after one
  Class-1 and one Class-2 pilot before rollout.

### D15 — authoritative pilots and two defect generators

- Authoritative pilots: Class 1 `L80046687` + Class 2 `L79900064`.
  `0a69143` is superseded: `L79871659` is too close to the noise floor and has no confirmed CMI
  sibling; `L80524847` was rejected and has no JE. It is a rejection-detection test only.
- Defect classes have two known generators: credit-shell
  (`sap_integration_v2.RCL 04_new order credit shell`) and onetime
  (`sap_data_engineer.sap_dashboard_carepay_fully_paid`, known-answer `L78496990`).
- FA totals must include both streams with order-level overlap removed; no combined point estimate
  is approved while `3c10215` remains under review/range ambiguity.
- Credit-shell drift `698→700 keys`, `612→613 orders` proves the generator remains active. Fix the
  generator before correction.
- Option A selected: fix the v2 credit-shell view because the real
  `sap_view.RCL_Motor_process_4_creditshell` consumer reads it directly. Deploy still requires
  verbatim backup, shadow diff, and column-order verification.
- Permanent population split: `POSTED_WRONG` requires mirror + successful status + JE reference
  from a successful import log and is correction-eligible. `REJECTED_NEVER_POSTED` requires a bug
  fix and normal resend, not correction. Error XLSX proves rejection, never posting.
- Class 1 must be segmented by `has_CMI_sibling`; FA confirmed `L79871659` has no CMI sibling.


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
ไม่ใช่แค่บาง CTE). Source committed in `033_extend_stg_order_dim_exclusion_fields.sql`
(`fa8d8cc`).

**F2. PolicyNo >50 ตัวอักษร = BLOCK (confirmed)** — ห้าม truncate (เลขกรมธรรม์ที่ถูกตัด = ข้อมูลผิดใน
SAP ที่แก้ยากกว่าไม่ส่ง) → validation rule `POLICYNO_TOO_LONG` + morning report ต้องมีจำนวน + ตัวอย่าง
order_item 3 ราย. **NOT YET EVIDENCED AS DEPLOYED**: commit `9825e97` restores source for the live
E1–E3 procedure but its `034` file does not implement F2; tracked for Claude Code in
`docs/HANDOFF_QUEUE.md`.

**F3. Date format = 8 ตัว (DDMMYYYY)** — ว่างได้เฉพาะ `PaymentDate` เมื่อ `status=pending` เท่านั้น
(`OrderDate`/`PolicyDate`/`ExpectedDate`/`BatchRunDate` ห้ามว่าง). เช็คทั้งความยาว+parse ได้จริง (กัน
`32072026`) และ leading zero (`01072026` ไม่ใช่ `1072026`). **OPEN — Boat-confirmed, not
deferred:** ยังไม่พบหลักฐานว่า validation นี้ wire จริง และไม่มีหลักฐานว่า Boat ตัดสินใจเลื่อน.
ข้อสังเกตว่า current `expected_state` มีเพียง 12 columns และใช้ DATE type เป็น technical constraint
ที่ Claude Code ต้องเลือก validation layer ให้ถูกต้องหรือส่ง blocker evidence กลับมา ไม่ใช่เหตุผล
ให้ postpone rule เอง. ติดตามใน `docs/HANDOFF_QUEUE.md`.

**ผลต่อ backlog**: `MISSING_NO_ROW_IN_SAP` เลขเก่า (373,044 ณ 07-27) ใช้ต่อไม่ได้ — ต้องแยกรายงาน
**backlog จริง** (2026+ และ cancel 2025 ที่มีใน SAP) vs **excluded** (แยกตาม rule_code) ทุกครั้ง.
**⚠️ PROVISIONAL — UNDER VERIFICATION; DO NOT CITE until Claude Code reports passing 0A/0B and
STATUS_CONFLICT decreases in line with D1 acceptance.**
Live refresh after E1–E3 filtering completed 2026-07-29 14:01:28 ICT:
`interface_daily_status`: MISSING 576, STATUS_CONFLICT 34,758, PENDING_ACK 514, OK 257,340.
STATUS_CONFLICT's unexplained jump has not passed regression testing. Return Triage's 340,051 was
measured before filtering and must not be reused. `DATE_BASIS_MISSING = 0` is consistent with a direct check finding zero
candidate rows where both date inputs are NULL. See `sql/ddl/032-034`, commits `fa8d8cc` /
`9825e97`, and `30_SAP_CHANGELOG.md`.
6. Design v3 ทั้งชุดอยู่ใน docs/design/ — อ่าน REDESIGN_V3 ก่อนแตะ pipeline ใดๆ

## ⚠️ ADDENDUM 2026-07-29 v3 — DESIGN DECISIONS D1–D5

This addendum overrides any earlier text that conflicts with D1–D5.

**D1 revised by Boat 2026-07-29 — one cancellation definition.**
`is_cancelled_effective = (careos.careos_order_items.is_cancelled IS TRUE) OR
(careos.careos_order_items.cancel_time IS NOT NULL)`. Both fields come only from
`careos.careos_order_items`. Compute this exactly once as
`stg_order_dim.is_cancelled_effective`; all downstream logic must use
that field and must not re-derive the OR. This matches the legacy cancel-new condition and closes
the gap where v3 recognized fewer cancellations than legacy.

**Why not `careos.careos_orders.is_cancelled`:** the design review initially estimated that the
order-level flag added only approximately one item beyond the two item-level fields. The subsequent
reverse cross-check found **0 rows** where the order flag was true while both item fields were
false. Source object: proposed `v_order_cancelled_item_not_monitor`; queried 2026-07-29, exact query
time not captured, evidence commit `988e901` at 18:59:27 ICT. Regardless of population, the
order-level field introduces a grain mismatch that can mark active siblings cancelled, violating
the confirmed per-`order_item` constraint. Excluding it also keeps D1 aligned with legacy
cancel-new. This design review is closed; do not reopen it without a new Boat decision backed by
row-level evidence.

`expected_status` supports `Cancelled`; precedence is `Cancelled > Paid > Pending`.
`PAID_AFTER_CANCEL` remains a separate anomaly classification and must not be hidden by ordinary
Cancelled precedence. Add `CANCEL_TIME_MISSING` to the status vocabulary when
`is_cancelled_effective` is true from item-level `is_cancelled` but item `cancel_time` is NULL, so the
timing comparison needed for PAID_AFTER_CANCEL cannot be made. Canonical vocabulary:
`OK`, `PENDING_ACK`, `MISSING`, `STATUS_CONFLICT`, `PAID_AFTER_CANCEL`,
`CANCEL_TIME_MISSING`, `UNROUTED`.

Acceptance requires the post-change
STATUS_CONFLICT population to decrease as expected and Claude Code regression checks 0A/0B to
pass. Until then, the 14:01 ICT status-count set remains **⚠️ PROVISIONAL — UNDER VERIFICATION**.

Evidence context for D1: the cancel-path analysis used `sap_integration_v3.stg_order_dim`,
`sap_integration_v3.interface_daily_status`, and SAP mirror state; evidence was captured in commit
`19d9452` at 2026-07-29 17:58:53 ICT. The exact underlying query timestamps were not captured, so
all associated counts remain provisional under D5.

**S1–S6 constraint/evidence folded from `402904b`:**
- Partial cancel-recreate is normal practice, not a CareOS bug. In the diagnostic population,
  **⚠️ PROVISIONAL 98.5%** had an active sibling on the same order. Sources:
  `careos.careos_order_items` joined to `careos.careos_orders`; queried 2026-07-29, exact query
  timestamp not retained, evidence committed at 2026-07-29 18:35:27 ICT.
- Cancel status/files are strictly per `order_item`. Never fan an order-level cancellation signal
  out to active sibling items.
- A later row-level correction in `fa9b351` recognized both SAP cancelled variants
  (`Cancelled` and `Cancelled (Change order / Rejected)`). Latest **⚠️ PROVISIONAL** result:
  296 actionable order_items / approximately THB 3.89M before year scope; 41 items /
  THB 720,307.31 are inside approved 2025/2026+ scope and are the first-round FA population.
  Sources: `careos.careos_order_items`, `careos.careos_orders`, and
  `sap_integration_v3.sap_mirror_state`; queried 2026-07-29, exact query timestamp not retained,
  evidence committed at 2026-07-29 18:46:14 ICT. The intermediate 419 / THB 5.68M and broad
  2,254 / THB 30M figures are superseded and must not be cited.

The three-field formula written inside the diagnostic session note and source-only commit
`8a28710` is superseded by Boat's later two-item-field revised-D1 definition above; it must not be
copied into implementation.

**D2 — change-order supersession is not Q3a.** Never send a Cancelled batch for superseded old
orders until all three required change-order preflight checks are documented and passed, Aware
answers whether an explicit Cancelled document is required, and FA explicitly approves the batch.
Q3a only resolves which existing SAP document/status is authoritative when multiple documents
already exist; it does not answer supersession behavior.

The current candidate figure, **⚠️ PROVISIONAL 9,625 order_items**, came from
`careos.cancelled_change_orders`, `careos.careos_orders`, `careos.carepay_transactions`,
`sap_integration_v3.stg_order_dim`, and SAP mirror logic; evidence capture is commit `19d9452`,
2026-07-29 17:58:53 ICT, while exact query timestamps were not retained. Do not treat it as an
approved batch size.

**D3 — DDL 035 deploy approved.** Boat explicitly approved deployment of
`035_policyno_too_long_validation.sql` in this session. Claude Code owns deploy and verification.
Approval is scoped to 035's replacement of `sp_run_validation`; any other existing-consumer
replacement still follows its own deploy gate.

**D4 — phone filtering stays report-only.** `0999999999` must not become a hard filter yet.
Wait for a provenance-complete result set and a separate decision before changing
`enforce_hard_filter=false`. Earlier phone counts without table + query timestamp are not
decision-ready under D5.

**D5 — numerical provenance is mandatory.** Every reported number must state the source
table/object and source timestamp. Bare numbers are prohibited. If an exact query timestamp was
not captured, state that limitation and mark the number **PROVISIONAL**; a commit timestamp proves
when evidence was recorded, not when the source snapshot was measured.
