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

## ARCHITECTURE — ⚠️ มี 2 pipeline คู่ขนาน (clarified 2026-07-16)

**Path A — Interface ขาออก (CareOS → SAP):**
```
CareOS → BigQuery raw → stg_* → Business Logic (per BU×stage) → Validation
→ sap_export_* → CSV → gs://interface-file/<BU>/ → SAP pull รายชั่วโมง (Vendor Aware — ห้ามแตะ)
```

**Path B — ขากลับ (SAP DB → BigQuery เพื่อ recon):** มี 2 รุ่นซ้อนกันอยู่
- **B1 (เก่า, loader-based):** ไฟล์ JSON ใน `gs://sap-bucket-csv` → **loader service**
  (pre-existing, ไม่ใช่ของ BI, schedule ของตัวเอง) → `sap_integration_v2.SAP_LIVE`
  - Loader ต้องการ **ONE JSON array ต่อไฟล์ — NDJSON พัง** ("Extra data: line 2 column 1")
  - Time-coupled กับ extract (เปราะ) → เป็นเหตุ incident 07-14 (ไฟล์เขียนแล้วแต่ SAP_LIVE ไม่อัปเดต)
  - Unresolved: error `position 1866902` ครั้งแรก — สงสัย partial file, ยังไม่ root-cause
- **B2 (ใหม่, Phase 6):** Cloud Run Job `sap-extract-job` → SAP DB (pyodbc ผ่าน WireGuard)
  → NDJSON ลง `gs://rcb-bronze-zone` (audit) → **MERGE ตรงเข้า `raw_sap_live`** (key: DocEntry)
  → watermark ใน `sap_extract_control`
- `⏳ PENDING`: ยืนยันแผน sunset B1 หรือให้ B1/B2 อยู่คู่กัน + ตาราง SAP_LIVE vs raw_sap_live
  ตัวไหนเป็น source ของ recon Layer 6

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

## EXTRACT JOB (Phase 6) — ข้อเท็จจริงยืนยันแล้ว

- SAP DB timezone = Asia/Bangkok (UTC+7); `UpdateTime` format HHMM
- Watermark-based (ไม่ใช่ date window) — scheduler delay ไม่ทำข้อมูลหาย
- Filter: `U_InsuranceGroup <> 'B2B'`
- Deploy env จริง: `GCS_BUCKET=rcb-bronze-zone` (⚠️ PHASE6_DEPLOY.md เขียน bucket คนละชื่อ — doc drift)
- Secrets ต้อง bind ผ่าน `--update-secrets` (`sap-db-username`, `sap-db-password`) —
  code อ่าน env var ตรงๆ ถูกแล้ว, ห้าม deploy ด้วย `--set-env-vars` plaintext อีก
- `sed` corrupt password ที่มี `&`/`\`; loader-side: single JSON array เท่านั้น

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

1. **SAP truth = `raw_sap_live` เท่านั้น** — SAP_LIVE / SAP_LIVE_FULL / SAP_LIVE_2025/2026 (B1)
   เป็น stale mirror (พิสูจน์ 23/07: งวด Paid+invoice โชว์เป็น Pending/ว่าง) ห้ามใช้ตัดสินสถานะ/InvoiceNo
   — ระหว่างเปลี่ยนผ่าน: repoint ชื่อ SAP_LIVE_FULL เป็น view ทับ raw_sap_live ได้
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
6. Design v3 ทั้งชุดอยู่ใน docs/design/ — อ่าน REDESIGN_V3 ก่อนแตะ pipeline ใดๆ
