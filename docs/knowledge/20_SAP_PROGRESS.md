# 20_SAP_PROGRESS.md
Last Updated: 2026-07-24 (overwrite ได้ — สถานะปัจจุบันเสมอ)
Overall: ~65% | โหมดปัจจุบัน: repo ตั้งแล้ว, เริ่ม P0 (stg_sap_state ร่างแล้ว รอรัน) — บล็อกที่ gcloud/bq auth

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

## 🚧 P0 STATUS (2026-07-24 session)

- ✅ `sap-interface-repo` ตั้งจริงแล้ว (local git, branch `p0/stg-sap-state`) ที่
  `.../02 SAP/Phase1.1/agentic_bootstrap/codex_bootstrap` — baseline commit = design package v3 ทั้งชุด
- ✅ `sql/ddl/001_create_sap_integration_v3.sql` — dataset + `pipeline_run_log` DDL, เขียนเสร็จ ยังไม่ได้รัน
- ✅ `sql/ddl/002_sp_refresh_sap_state.sql` — `sp_refresh_sap_state` proc เขียนเสร็จ ยังไม่ได้รัน
  → ⚠️ พบ **design conflict**: REDESIGN_V3 §2.1 บอกให้เก็บ `SELECT r.*` (ชื่อ column ดิบทั้งหมด) แต่
  DATA_PREP_DESIGN §5 เขียนแบบ rename เป็น subset (`order_item`,`sap_status`,`sap_invoice_no`,...) ที่มี
  "..." ค้างไว้ (ไม่ครบ ต้องเทียบ Data Dictionary) — ไฟล์นี้เลือกแบบ REDESIGN_V3 (เก็บ raw ทั้งหมด) เพราะ
  ปลอดภัยกว่าต่อกติกา "mirror stored values exactly"; รอ confirm ก่อน merge
- ✅ `sql/ddl/003_PROPOSED_repoint_sap_live_full.sql` — ร่าง 2 ทางเลือก (A: view→raw_sap_live ตรงตาม
  ADDENDUM #1, B: view→stg_sap_state ที่ dedup แล้ว) **ยังไม่รัน** ต้องเลือกทางก่อน + ยังไม่ diff กับ
  schema จริงของ SAP_LIVE_FULL ปัจจุบัน
- ❌ **NULL-safe filter fix (A2)** — ยังทำไม่ได้ ไม่มีไฟล์ query production จริงอยู่ใน repo เลย
  (`sql/production/` มีแค่ README stub — ไม่มี `rcl_installment.sql` ฯลฯ ตัวจริง) ต้องขอไฟล์จริงจาก Boat
  หรือดึงจาก BigQuery (scheduled query/saved view) ก่อนถึงจะแก้แบบไม่เดา
- ❌ **Secret rotation** — ยังทำไม่ได้ `gcloud`/`bq` auth หมดอายุใน session นี้ (`gcloud auth login`
  ต้อง interactive/browser ทำเองไม่ได้จาก agent) + เป็น action ที่กระทบ job ที่รันจริง ต้อง propose ก่อน
- ยังไม่ได้ verify อะไรกับ BigQuery จริงในรอบนี้ (schema ของ `raw_sap_live`/`SAP_LIVE_FULL`, ว่า
  `sap_integration_v3` มีของค้างอยู่แล้วหรือยัง) — ทำได้ทันทีที่ reauth

## ⬜ NEXT (หลัง decisions)

1. Reauth `gcloud`/`bq` (ผู้ใช้ต้องรัน `gcloud auth login` เอง) → verify schema จริง, รัน 001/002 ผ่าน bq
2. เลือก A/B ใน `003_PROPOSED_repoint_sap_live_full.sql` + diff กับ SAP_LIVE_FULL เดิม ก่อน merge
3. ส่งไฟล์ query production จริง (`rcl_installment.sql`, `rcb_onetime_fully_paid.sql`,
   `rcb_cancel_new.sql`, `credit_shell_recursive.sql`) เข้า repo เพื่อแก้ NULL-safe filter ได้จริง
4. Secret Manager rebind + rotation (ค้างตั้งแต่ 16/07) — ทำหลัง reauth
5. P1–P4 ตาม migration plan ใน REDESIGN_V3 §4 / E2E §3
6. Quantify EDC backlog ทั้งประวัติศาสตร์ (ไม่ scope list บัญชี)
7. raw_sap_live backfill scope (decision #4)

## DECISIONS PENDING (จาก design review)

1. Orchestration: Cloud Workflows? 2. InvoiceNo standard (raw id + rank prefix) — บัญชี ack
3. ProcessingFee 100/103.3 (RCL) vs 100/107 (onetime) — ตัวไหนถูกต่อ flow ไหน (เจอ discrepancy ใหม่)
4. Backfill scope 5. EDC channel matrix 6. Parallel-run กี่วัน (เสนอ 5)
