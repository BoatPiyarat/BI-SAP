# 20_SAP_PROGRESS.md
Last Updated: 2026-07-24 (overwrite ได้ — สถานะปัจจุบันเสมอ)
Overall: ~68% | โหมดปัจจุบัน: **P0 core ทำเสร็จจริงใน BigQuery แล้ว** — stg_sap_state สร้างแล้ว,
A2 fix live ใน 2 production views แล้ว (ผลตรวจแล้ว ไม่มี regression) — เหลือ secret rotation + hard-rule
doc fix + ตัดสินใจเรื่อง 6 views เก่าที่ไม่ใช่ production จริง

---

## 🔥 IN-FLIGHT

1. **Cancel batch 21 items** — ตก 3 รอบ (root cause สุดท้าย: SAP เก็บหลาย doc ต่องวด + InvoiceNo ต้องตรง doc ปัจจุบัน)
   → v4 พร้อม (one-row-per-period, Paid priority) แต่**รอคำตอบ Aware Q3a ก่อนยิง** (spec inferred ส่งแล้ว)
   → ⚠️ business flag: ลูกค้าจ่ายงวดต่อหลัง CareOS cancel — รอ FA confirm intent (cancel+refund?)
2. **RCL new-payment quick fix (27 orders)** — หลักใหม่จาก Boat: **charge-driven full schedule**
   (charge ถึงงวดไหน เติม paid ถึงงวดนั้น, mirror งวดเดิมเป๊ะ InvoiceNo ห้ามแตะ) — query v3 พร้อม รอ sample run
3. **EDC batch 2 (~70 orders จาก list บัญชีชุด 2)** — รอบัญชี confirm channel mapping ธนาคารอื่นนอกจาก KBANK
4. **Secret Manager rebind + password rotation** — ⚠️ ค้างตั้งแต่ 16/07! plaintext ยังอยู่ใน job config
   และ password exposed แล้ว 2 ครั้ง — สถานะ: secret sap-db-password ยังไม่มี version, ขั้นตอนอยู่ใน chat/runbook

## ⏳ WAITING ON OTHERS

- Aware: confirm cancel import spec v0.9 (ส่งแล้ว — โดยเฉพาะ Q3a: หลาย doc ต่องวด อ้าง InvoiceNo ตัวไหน)
- บัญชี: (a) EDC channel matrix (b) Credit Shell = จ่ายครบงวดเดียว OK? (c) intent 21 cancel ที่จ่ายต่อหลังยกเลิก
- IT Leong: Credit Shell ไม่มี installment_details = by design หรือ bug + ขอ direct RCL field (ถามใน group แล้ว)
- Head of Products: COALESCE fix (INCIDENT-001) — ใช้ targeted ไปแล้ว 1 เคส (L80347249-M1 เข้า SAP 22/07)

## ✅ DONE เพิ่มจาก 16/07

- Scheduler self-trigger verified (20:30 ICT, SA sap-bucket-csv@) — Phase 6 automation ครบฝั่ง extract
- เจอ loader B1 = `auto_load_sap_data_in_bucket_to_bigquery` (Pub/Sub 01:00) → อธิบาย incident 07-14
- **ROOT CAUSE ใหญ่: SAP_LIVE/SAP_LIVE_FULL = stale mirror** (mirror comparison 23/07 ยืนยัน INVOICE_DIFF)
  → DECISION: raw_sap_live คือ SAP truth เดียว, sunset B1 (ดู 10_CONTEXT)
- Urgent batches เข้า SAP: 30 EDC + L80347249-M1 + L79189867-1 (self-resolved) + cancel 1 (L80391648-M1)
- EDC gap วินิจฉัยครบ: CREDIT_CARD_INSTALLMENT ไม่มี pipeline เจ้าของ (ตกร่อง 2 flow) — เจอ 2 list รวม ~100 orders
- InvoiceNo convention conflict ยืนยัน: '2_' prefix (BI, กัน collision) vs raw charge id (flow 21/07)
- **Design package v3 ครบ 6 ฉบับ** (REDESIGN / E2E / DATA_PREP / RUNBOOK / DASHBOARD / CANCEL_SPEC) — รอ review/decisions
- Delta-export gap ใน design ถูกจับได้จาก review ของ Boat (new payment Pending→Paid) → amend แล้ว + generalize เป็น charge-driven

## 🚧 P0 STATUS (2026-07-24 session — reauth done, verified against live BigQuery)

- ✅ `sap-interface-repo` ตั้งจริงแล้ว (local git, branch `p0/stg-sap-state`) ที่
  `.../02 SAP/Phase1.1/agentic_bootstrap/codex_bootstrap`
- ⚠️ **CORRECTION ใหญ่: `raw_sap_live` ไม่มีอยู่จริง** — Phase 6 B2 extract job ไม่เคย deploy จริงใน
  project นี้ (เป็นแค่แผนใน design docs) — Boat ยืนยัน: **`sap_integration_v2.SAP_LIVE_FULL` คือ SAP
  source จริงที่ใช้อยู่ตอนนี้** ตรงข้ามกับ hard rule เดิมใน AGENTS.md/CLAUDE.md ("SAP truth = raw_sap_live
  ONLY") ที่เขียนไว้ก่อนเช็คจริง — ต้อง**แก้ hard rule นี้ในสองไฟล์นั้นด้วย** (ยังไม่ได้แก้)
- ✅ Verified `SAP_LIVE_FULL` จริง (schema 56 คอลัมน์ ดึงมาแล้ว, ดู view definition ใน
  `sql/production/SAP_LIVE_FULL.sql`): union SAP_LIVE + SAP_LIVE_2024/2025/2026, dedup ด้วย DocEntry
  (ROW_NUMBER by BatchRunDate DESC) — แต่**ยังมี duplicate ที่ (U_OrderItem, U_Period) 328,071 keys
  (687,700/1,649,468 แถว = ~42%)** เพราะ dedup แค่ระดับ DocEntry ไม่ใช่ระดับ period — ตัวอย่างจริง:
  L73340138-V1 period 2 มีทั้งแถว Paid (DocEntry 750141) และ Cancelled (DocEntry 1005571) — ตรงกับ
  CANCEL_IMPORT_SPEC Q3a เป๊ะ
- ✅ TransactionStatus จริง: Paid 1,087,891 / Pending 432,840 / Cancelled 90,489 /
  Cancelled (Change order / Rejected) 38,248 — ตรงกับที่ design assume ไว้พอดี
- ✅ `sql/ddl/002_sp_refresh_sap_state.sql` — **แก้แล้ว** ให้ source จาก `SAP_LIVE_FULL` แทน
  `raw_sap_live`, dedup by (U_OrderItem, U_Period) priority Cancelled>Paid>Pending — ยังไม่รัน
  (ต้อง approve ก่อน — สร้าง dataset+ตารางใหม่ ไม่กระทบของเดิม)
- ✅ `sql/ddl/003_...` — **แผนเดิม (repoint SAP_LIVE_FULL) ตกไป** เพราะ SAP_LIVE_FULL คือ source จริง
  ไม่ใช่ mirror เก่าที่ต้องแทนที่ (ทำแบบเดิมจะ circular) — เช็คจริงแล้วพบว่ามีแค่ 2 consumer ที่แตะ
  SAP_LIVE_FULL (fully_paid's `sap_batchrun`, credit shell's `sap_cancelled`) และทั้งคู่ทำแค่
  `MAX(BatchRunDate)` ต่อ OrderID — **ไม่โดน duplicate bug จริง** (MAX กันซ้ำในตัวอยู่แล้ว) — เป็นแค่
  cleanup ไม่ใช่ live bug
- ✅ **A2 NULL-safe filter bug — ยืนยันจริง, แก้จริง, LIVE ใน BigQuery แล้ว (2026-07-24):**
  พบ `motor_item_type != 'MOTOR_TYPE_COMPULSORY'` แบบไม่กัน NULL ใน **9 views จริง** (ค้นด้วย
  INFORMATION_SCHEMA.VIEWS regex) — เช็ค `sap_view` (12 views, Boat ยืนยันว่านี่คือ production run
  nightly จริง) แยกต่างหาก: **สะอาด** เจอแค่ 1 จุดที่ใช้ `=` (safe) ไม่มี `!=`/`<>` เลย — ไม่ต้องแก้
  9 views ที่เจอบั๊กอยู่ใน `sap_integration_v2`/`sap_data_engineer`: `sap_dashboard_carepay_installment`,
  `RCL 04_new order credit shell` (2 ตัวที่ Boat ชี้ว่า production จริง) + อีก 6 ตัวที่ไม่อยู่ใน list
  (`RCL 02_items_cancel`, `RCL 04_new order credit shell_all`/`new tunning`, `sap_fix_rcl_2025`,
  `sap_fixing_rcl`, `RCL_MOTOR`) — **ยังไม่ตัดสินใจว่าของจริงหรือของทิ้งแล้ว รอถาม Boat**
  ยืนยันด้วยข้อมูลจริง: `careos_order_items.motor_item_type` มี NULL 10,559 แถว ทุกแถวเป็น NonMotor
  → **Applied จริงแล้ว** (`CREATE OR REPLACE VIEW`, ผ่าน bq CLI, location asia-southeast1):
  - `sap_dashboard_carepay_installment`: 631,487 → 665,388 แถว (**+33,901 แถวที่หายไปกลับมา**)
  - `RCL 04_new order credit shell`: 13,894 → 14,379 แถว (**+485 แถว**)
  Sample check แถวที่กลับมา (เช่น L77630866-1 period 3-5/6, health-insurance, paid, ฿13,290) —
  ข้อมูลสมเหตุสมผล ไม่ใช่ garbage. **แถวเพิ่มขึ้นทั้งคู่ ไม่มีลดลง = ไม่มี regression**
- ❌ **Secret rotation** — ยังไม่ทำ (ยังไม่ได้ขอ approve, เป็น action ที่กระทบ job ที่รันจริง)
- ✅ **`sap_integration_v3.stg_sap_state` — สร้างจริงแล้วใน BigQuery** (dataset + `pipeline_run_log`
  ผ่าน `001`, proc `sp_refresh_sap_state` ผ่าน `002`, รันแล้วผ่าน `CALL`)
  → 1,649,468 แถวใน SAP_LIVE_FULL → **1,289,839 แถวหลัง dedup, 0 duplicate key เหลือ** (verified)

## ⬜ NEXT

1. ตัดสินใจเรื่อง 6 views อื่นที่เจอบั๊กเดียวกันแต่ไม่ใช่ production ที่ระบุไว้ (RCL 02_items_cancel ฯลฯ)
   — ของจริงหรือของทิ้งแล้ว? (sap_view ที่เป็น nightly จริงสะอาดแล้ว ไม่ต้องแตะ)
2. แก้ hard rule ใน AGENTS.md/CLAUDE.md: "SAP truth = raw_sap_live" → "SAP_LIVE_FULL" (ผิดจากที่เช็คจริง)
3. Secret Manager rebind + rotation (ค้างตั้งแต่ 16/07)
4. เริ่มใช้ `stg_sap_state` จริงในงานถัดไป (cancel-gen, gap-check, recon) แทนการอ่าน SAP_LIVE_FULL ตรงๆ
5. P1–P4 ตาม migration plan ใน REDESIGN_V3 §4 / E2E §3 (ยังไม่แตะ)

## DECISIONS PENDING (จาก design review)

1. Orchestration: Cloud Workflows? 2. InvoiceNo standard (raw id + rank prefix) — บัญชี ack
3. ProcessingFee 100/103.3 (RCL) vs 100/107 (onetime) — ตัวไหนถูกต่อ flow ไหน (เจอ discrepancy ใหม่)
4. Backfill scope 5. EDC channel matrix 6. Parallel-run กี่วัน (เสนอ 5)
