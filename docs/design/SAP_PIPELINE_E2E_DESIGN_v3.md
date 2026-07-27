# SAP ⟷ CareOS Pipeline — End-to-End Design v3 (Event-Driven Chain)
Date: 2026-07-23 | Status: DESIGN REVIEW (ก่อนลงมือ P0)
คู่กับ: SAP_INTERFACE_REDESIGN_V3.md (query/logic layer) — ฉบับนี้คือ orchestration + ภาพรวมทั้งระบบ

> ⚠️ **CORRECTION 2026-07-27 — อ่านก่อนเชื่อ `raw_sap_live`/B1 ในเอกสารนี้:** ทั้งสองไม่มีอยู่จริง
> (verified ผ่าน bq/gcloud 2026-07-24 — authoritative source: `docs/knowledge/10_SAP_CONTEXT.md`
> §ARCHITECTURE). ทิศ 2 (SAP → BigQuery) ทำงานจริงตามนี้แทน: `sap-extract-job` เขียน NDJSON
> **ชั่วคราว** ลง `gs://rcb-bronze-zone/SAP/production_database/` → Eventarc trigger
> **`sap-order-payment-initial-phase`** (Cloud Run **service**, ไม่ใช่ Cloud Function) → load เข้า
> `sap_integration_v2.SAP_LIVE` แล้วลบไฟล์ต้นทาง — ทุกจุดด้านล่างที่เขียน "MERGE → raw_sap_live"
> ให้อ่านเป็นขั้นตอนนี้แทน
>
> **"☠ SUNSET B1" ไม่มีความหมายอีกต่อไป** — ไม่เคยมี B1/B2 คู่ขนานจริง มีแค่ path เดียวข้างบน.
> `SAP_LIVE_FULL` (union ของ SAP_LIVE + SAP_LIVE_2024/2025/2026, dedup by DocEntry) คือ SAP source
> เดียวที่มีจริง — ใช้ต่อได้ ไม่ต้อง sunset. ต้องการ 1 แถว/(OrderItem, Period) ใช้
> `sap_integration_v3.stg_sap_state` แทน (SAP_LIVE_FULL เองมี duplicate 328k+ keys ที่ระดับนี้).
>
> **Path B ข้างต้น "event-driven" อยู่แล้ว** (extract → Eventarc → loader — ไม่ต้องสร้างใหม่ตามที่
> เอกสารนี้เสนอ). ของที่ยังขาดจริงคือการ chain **V3 SQL steps** (sap_state → recon → expected_state →
> validate → export) เข้าด้วยกันเป็นเส้นเดียว — ดู `TASK_V3_GAP_CLOSURE_v2.md` PHASE A/B/C.
>
> **Pull cadence แก้ไข**: SAP ดึงไฟล์ทุก 15 นาที (:00/:15/:30/:45) แต่ประมวลผลจริงที่นาที **:30**
> ของทุกชั่วโมง (Boat ยืนยัน 07-25) — ไม่ใช่ "รายชั่วโมง"/"21:00" ตามที่เขียนไว้เดิมด้านล่าง; คำนวณ
> timing claim ใดๆ ใหม่จากจุดนี้ก่อนเชื่อ.
>
> ยังไม่ได้แก้ทั้งฉบับ (โครง orchestration/decision list ด้านล่างยังใช้เป็น reference ได้) — นี่คือ
> pointer เดียวจนกว่าจะรีไรท์เต็ม.

---

## 1. ภาพใหญ่ทั้งสองทิศ

```
┌──────────────────────── ทิศ 1: CareOS → SAP (interface ขาออก) ───────────────────────┐
│                                                                                        │
│  CareOS (BigQuery raw)                                                                 │
│    │  [EVENT CHAIN — ไม่รอเวลา]                                                        │
│    ▼                                                                                   │
│  stg_order_dim / stg_payment_events / stg_schedule  (incremental)                      │
│    ▼                                                                                   │
│  L3 Engine (expected_state, 56 col, payment-type router)                               │
│    ▼                                                                                   │
│  L4 Validation (blocking) ──fail──▶ sap_validation_error                               │
│    ▼ pass                                                                              │
│  L5 Delta Export → gs://interface-file/<BU>/  (_01_create, _02_cancel)                 │
│    ▼                                                                                   │
│  SAP hourly pull + import  (Aware — ห้ามแตะ, จังหวะเดียวที่ "รอเวลา" โดย vendor)        │
└────────────────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────── ทิศ 2: SAP → BigQuery (ขากลับ/ack) ───────────────────────────┐
│                                                                                        │
│  SAP DB (SQL Server ผ่าน WireGuard)                                                    │
│    │  20:30 ICT (จุด anchor เวลาเดียวของทั้งระบบ)                                       │
│    ▼                                                                                   │
│  sap-extract-job (Cloud Run Job, watermark-based)                                      │
│    └─▶ NDJSON ชั่วคราว → gs://rcb-bronze-zone (ลบทิ้งหลัง load)                        │
│    ▼  [Eventarc trigger ต่อทันที — ทำงานจริงอยู่แล้ว ไม่ต้องสร้าง]                     │
│  sap-order-payment-initial-phase (Cloud Run service) → MERGE → SAP_LIVE                │
│    ▼  [EVENT CHAIN ต่อทันที ไม่รอ]                                                     │
│  stg_sap_state (1 แถว/(item,period), priority Cancelled>Paid>Pending)                  │
│    ▼                                                                                   │
│  L6 Recon (expected ⟷ sap_state) → interface_daily_status → Finance ดูเอง             │
│    ▼                                                                                   │
│  [ack] item ที่กลับมาเป็น Paid = official confirmation (v2.1 §6.4)                     │
│                                                                                        │
│  (ไม่มี B1/legacy loader ให้ sunset — SAP_LIVE/SAP_LIVE_FULL/2025/2026 คือ path เดียวจริง)│
└────────────────────────────────────────────────────────────────────────────────────────┘
```

**หลักการ event-driven ตามแผนเดิม — ขยายผล:** แผนเดิมคือ "extract เสร็จ → trigger loader ทันที" เพื่อฆ่า gap 4.5 ชม. ตอนนี้ B2 MERGE ตรงเข้า BigQuery อยู่แล้ว (loader หมดหน้าที่) หลักการเดียวกันจึงยกไปใช้ทั้งเส้น: **ทุก step downstream ต่อกันเป็น chain ทันทีที่ step ก่อนสำเร็จ — เวลานัดหมายมีจุดเดียวคือ 20:30**

---

## 2. Orchestration — 3 ทางเลือก

| | A. Monolith job | **B. Cloud Workflows (แนะนำ)** | C. Pub/Sub events |
|---|---|---|---|
| รูปแบบ | ยัดทุก step ต่อท้าย main.py | Workflow เรียกทีละ step: Run Job → BQ procedures → แจ้งผล | แต่ละ step publish topic ให้ตัวถัดไป subscribe |
| ข้อดี | ง่ายสุด ไม่มี component ใหม่ | เห็น flow เป็น graph, retry/branch ต่อ step, แยก concern, ค่าใช้จ่าย ~ศูนย์ | หลวมสุด ขยายง่าย |
| ข้อเสีย | extract code ปนกับ SQL orchestration, fail ครึ่งทาง re-run ทั้งก้อน, ทดสอบยาก | มี component ใหม่ 1 ตัวต้องเรียนรู้ (YAML) | ชิ้นส่วนเยอะ, debug ยาก, dead-letter ต้องดูแล — เกินความจำเป็นของ chain เส้นตรง |
| Resource | ต่ำ | **ต่ำ (pay-per-step, พันครั้ง/เดือนยังฟรี)** | ต่ำแต่ overhead คนดูแลสูง |

**แนะนำ B**: Scheduler 20:30 → Workflow เดียวเดินทั้งเส้น ทุก step เป็น BigQuery **stored procedure** (deploy/version ใน repo ได้, ทดสอบแยกได้):

```yaml
# wf-sap-pipeline (ตรรกะย่อ)
1. run sap-extract-job (Cloud Run Jobs API, wait จน SUCCESS)     # ทิศ 2
2. CALL sp_refresh_sap_state()                                    # ≤1 นาทีหลัง extract
3. CALL sp_run_recon()                                            # ack + daily status
4. CALL sp_build_expected_state()                                 # ทิศ 1 (ใช้ ack ล่าสุด)
5. CALL sp_validate()            → ถ้ามี blocking error: หยุด + alert (ไฟล์ไม่ออก)
6. CALL sp_export_delta()        → เขียน _01/_02 ลง gs://interface-file
7. publish สรุป (Slack webhook / email): rows exported, validation fails, recon status
on_error ทุก step → alert พร้อมชื่อ step   # dead man's switch ในตัว
```

ผลลัพธ์เวลา: จากเดิม extract 20:30 → (loader 01:00) → คนมาเช็คเช้า = **~12 ชม.** เหลือ **20:30 → ~20:45 ทั้งเส้นจบ ไฟล์ export พร้อมให้ SAP pull รอบ 21:00** — ข้อมูลที่ SAP เห็นสดขึ้นทั้งคืน และ cancel ที่ gen ใช้ sap_state อายุ <15 นาที (ฆ่าปัญหา stale mirror ที่ระดับ design)

---

## 3. Component Inventory (อะไรมีแล้ว/แก้/สร้างใหม่/เลิก)

| Component | สถานะ | หมายเหตุ |
|---|---|---|
| `sap-extract-job` + scheduler 20:30 | ⚠️ กำลังล่ม (401 IAM, รอ Attila) | ค้าง: secret rebind + rotate password (หนี้ P0) |
| `sap-order-payment-initial-phase` → `SAP_LIVE`/`SAP_LIVE_FULL` | ✅ มีแล้ว จริง ใช้ต่อ (ไม่ใช่ `raw_sap_live` — ไม่มีอยู่จริง) | Eventarc-triggered, ไม่ต้อง backfill แยก — เป็น source เดียวที่มี |
| `stg_sap_state` | ✅ มีแล้ว (P0, `sql/ddl/002`) | sp_refresh_sap_state, source = SAP_LIVE_FULL |
| `stg_order_dim` / `stg_payment_events` / `stg_schedule` | 🆕 สร้าง (P1) | incremental MERGE by watermark |
| L3 Engine + UDF `fn_invoice_no` | 🆕 สร้าง (P2) | รอ decision InvoiceNo standard |
| `sap_validation_error` + sp_validate | 🆕 สร้าง (P2) | รวม cancel preflight (รอ Aware confirm spec v0.9) |
| sp_export_delta | 🆕 สร้าง (P3) | sequenced _01/_02 |
| `recon_careos_interface` + `interface_daily_status` | 🆕 สร้าง (P4→เลื่อนขึ้น P0-lite ได้) | recon แบบง่ายทำได้ทันทีที่มี sap_state |
| **Cloud Workflow `wf-sap-pipeline`** | 🆕 สร้าง (P3) | แทน schedule แยกทั้งหมด |
| Scheduler `sap-order-payment`, `-non-motor` (01:30) | ♻️ ย้ายเข้า workflow แล้วปิด | ระหว่าง migration รันคู่ได้ |
| ~~B1 ทั้งเส้น~~ | ไม่มีอยู่จริง (`gs://sap-bucket-csv`/`auto_load_sap_data_in_bucket_to_bigquery` ไม่มี B1 คู่ขนาน — ลบแผน sunset นี้ทิ้ง) | `SAP_LIVE`/`SAP_LIVE_FULL`/`SAP_LIVE_2025/2026` ใช้ต่อถาวร ไม่ sunset |
| RCL manual queries (05_paid, 05_newpayment, 04 credit shell, 02 cancel-new) | ♻️ ยุบเข้า Engine | หมด hardcoded list |

---

## 4. Failure Handling & Observability

1. **ทุก step fail → Workflow ส่ง alert ระบุ step + หยุดเส้น** — ไม่มี partial export (validation คุมไว้ก่อน export เสมอ)
2. **Dead man's switch**: ถ้า `interface_daily_status` ไม่มี row ของวันนี้ภายใน 22:00 → scheduled query ยิง alert (จับเคส workflow ไม่ถูก trigger เลย)
3. **Extract fail กลางคืน**: watermark ไม่ขยับ → รันคืนถัดไปเก็บครบเอง (design เดิมของ Phase 6 — คงไว้)
4. **SAP import error (จาก Aware log)**: เก็บ log file เข้า `sap_import_result` (parse import txt) → recon เห็น MISSING พร้อม reason — ปิด loop สุดท้ายที่วันนี้ยังเป็นคนอ่าน log มือ
5. Audit: NDJSON ใน bronze zone + append-only export archive = replay ได้ทุกวัน

---

## 5. Timeline รายวัน (หลัง migrate ครบ)

| เวลา (ICT) | เหตุการณ์ |
|---|---|
| ทั้งวัน | SAP pull `gs://interface-file` ทุก 15 นาที (:00/:15/:30/:45), ประมวลผลจริงที่นาที :30 ของทุกชั่วโมง (Aware — แก้ 07-25, ไม่ใช่ "รายชั่วโมง"/"21:00" เดิม) |
| 20:30 | Scheduler ยิง `wf-sap-pipeline` |
| ~20:31–20:40 | extract → SAP_LIVE (ผ่าน Eventarc, ทำงานอยู่แล้ว) → sap_state → recon |
| ~20:40–20:45 | expected_state → validate → **delta export _01/_02** |
| :30 ถัดไป | SAP pull รอบแรกที่เห็นไฟล์ใหม่ → import รอบนั้นเลย (คำนวณใหม่จาก cadence จริง ไม่ใช่ 21:00 คงที่) |
| D+1 20:30 | รอบถัดไปเห็นผล import → recon ack อัตโนมัติ |
| 22:00 | Dead man's switch ตรวจว่าเส้นวิ่งครบ |

---

## 6. Decisions ก่อนลงมือ (รวมจากทั้ง 2 เอกสาร)

| # | เรื่อง | ตัวเลือก/สถานะ |
|---|---|---|
| 1 | Orchestration | **B (Workflows)** — ขอ confirm |
| 2 | InvoiceNo standard | raw id + rank prefix เฉพาะ additional — รอบัญชี ack |
| 3 | Cancel spec | ส่ง v0.9 ให้ Aware confirm (ร่างพร้อมแล้ว) |
| 4 | ~~raw_sap_live backfill scope~~ | **moot — raw_sap_live ไม่มีอยู่จริง, ไม่มี backfill ต้องทำ.** ของจริงที่ยังค้างคือ chain V3 SQL steps (sap_state→recon→expected_state→validate→export) — ดู TASK_V3_GAP_CLOSURE_v2.md PHASE A/B/C |
| 5 | EDC channel matrix | มีแค่ KBANK — ขอ list bank ที่เหลือจากบัญชี |
| 6 | คู่ขนานช่วง migration | รัน pipeline เดิม + ใหม่คู่กัน เทียบ 0-row-diff กี่วันก่อนสลับ (เสนอ 5 วันทำการ) |
