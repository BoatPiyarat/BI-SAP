# SAP ⟷ CareOS Pipeline — End-to-End Design v3 (Event-Driven Chain)
Date: 2026-07-23 | Status: DESIGN REVIEW (ก่อนลงมือ P0)
คู่กับ: SAP_INTERFACE_REDESIGN_V3.md (query/logic layer) — ฉบับนี้คือ orchestration + ภาพรวมทั้งระบบ

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
│    ├─▶ NDJSON audit → gs://rcb-bronze-zone   (เก็บหลักฐาน)                             │
│    └─▶ MERGE → raw_sap_live                  (SAP truth — B2)                          │
│    ▼  [EVENT CHAIN ต่อทันที ไม่รอ]                                                     │
│  stg_sap_state (1 แถว/(item,period), priority Cancelled>Paid>Pending)                  │
│    ▼                                                                                   │
│  L6 Recon (expected ⟷ sap_state) → interface_daily_status → Finance ดูเอง             │
│    ▼                                                                                   │
│  [ack] item ที่กลับมาเป็น Paid = official confirmation (v2.1 §6.4)                     │
│                                                                                        │
│  ☠ SUNSET: B1 (gs://sap-bucket-csv → loader 01:00 → SAP_LIVE/SAP_LIVE_FULL/2025/2026)  │
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
| `sap-extract-job` + scheduler 20:30 | ✅ มีแล้ว ใช้ต่อ | ค้าง: secret rebind + rotate password (หนี้ P0) |
| `raw_sap_live` | ✅ มีแล้ว | ต้อง backfill ย้อนหลังให้คลุม order เก่า (ก่อน watermark 07-09) |
| `stg_sap_state` | 🆕 สร้าง (P0) | sp_refresh_sap_state |
| `stg_order_dim` / `stg_payment_events` / `stg_schedule` | 🆕 สร้าง (P1) | incremental MERGE by watermark |
| L3 Engine + UDF `fn_invoice_no` | 🆕 สร้าง (P2) | รอ decision InvoiceNo standard |
| `sap_validation_error` + sp_validate | 🆕 สร้าง (P2) | รวม cancel preflight (รอ Aware confirm spec v0.9) |
| sp_export_delta | 🆕 สร้าง (P3) | sequenced _01/_02 |
| `recon_careos_interface` + `interface_daily_status` | 🆕 สร้าง (P4→เลื่อนขึ้น P0-lite ได้) | recon แบบง่ายทำได้ทันทีที่มี sap_state |
| **Cloud Workflow `wf-sap-pipeline`** | 🆕 สร้าง (P3) | แทน schedule แยกทั้งหมด |
| Scheduler `sap-order-payment`, `-non-motor` (01:30) | ♻️ ย้ายเข้า workflow แล้วปิด | ระหว่าง migration รันคู่ได้ |
| **B1 ทั้งเส้น**: `auto_load_sap_data_in_bucket_to_bigquery` (01:00), `gs://sap-bucket-csv`, `SAP_LIVE`, `SAP_LIVE_FULL`, `SAP_LIVE_2025/2026` | ☠ SUNSET (P4) | หลัง consumer ทุกตัวย้ายไป sap_state + backfill ครบ; เก็บ table แบบ freeze อ่านอย่างเดียว 1 เดือนก่อนลบ |
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
| ทั้งวัน | SAP pull `gs://interface-file` รายชั่วโมง (Aware — เดิม) |
| 20:30 | Scheduler ยิง `wf-sap-pipeline` |
| ~20:31–20:40 | extract → raw_sap_live → sap_state → recon |
| ~20:40–20:45 | expected_state → validate → **delta export _01/_02** |
| 21:00 | SAP pull รอบแรกที่เห็นไฟล์ใหม่ → import คืนนั้นเลย |
| D+1 20:30 | รอบถัดไปเห็นผล import → recon ack อัตโนมัติ |
| 22:00 | Dead man's switch ตรวจว่าเส้นวิ่งครบ |

---

## 6. Decisions ก่อนลงมือ (รวมจากทั้ง 2 เอกสาร)

| # | เรื่อง | ตัวเลือก/สถานะ |
|---|---|---|
| 1 | Orchestration | **B (Workflows)** — ขอ confirm |
| 2 | InvoiceNo standard | raw id + rank prefix เฉพาะ additional — รอบัญชี ack |
| 3 | Cancel spec | ส่ง v0.9 ให้ Aware confirm (ร่างพร้อมแล้ว) |
| 4 | raw_sap_live backfill scope | ต้องกำหนดช่วง (ทั้งหมด? 2024+?) — กระทบ storage/รอบแรก |
| 5 | EDC channel matrix | มีแค่ KBANK — ขอ list bank ที่เหลือจากบัญชี |
| 6 | คู่ขนานช่วง migration | รัน pipeline เดิม + ใหม่คู่กัน เทียบ 0-row-diff กี่วันก่อนสลับ (เสนอ 5 วันทำการ) |
