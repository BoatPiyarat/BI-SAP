# SAP Interface Query Redesign v3 — 56-Column Pipeline
Date: 2026-07-23 | Owner: Boat (BI) | Status: PROPOSAL
Objectives: **(1) CareOS → SAP integration ถูกต้อง** | **(2) ใช้ resource ต่ำ**

> ⚠️ **STATUS UPDATE 2026-07-24 — อ่านก่อนเชื่อ `raw_sap_live` ในเอกสารนี้:** ตรวจสอบจริงผ่าน bq/gcloud
> แล้วพบว่า `raw_sap_live` (B2/Phase 6 target ตลอดเอกสารนี้) **ไม่เคยถูกสร้างขึ้นจริง** และ bucket
> B1 ที่เอกสารเก่าอ้าง **ไม่มีอยู่จริงใน project** — path จริงคือ
> `gs://rcb-bronze-zone/SAP/production_database/`; pipeline คือ `sap-extract-job` → GCS ชั่วคราว →
> `sap-order-payment-initial-phase` → **`sap_integration_v2.SAP_LIVE`** (รายละเอียดเต็มดู
> `docs/knowledge/10_SAP_CONTEXT.md` §ARCHITECTURE + `docs/knowledge/30_SAP_CHANGELOG.md` 2026-07-24).
> P0 ได้ทำจริงแล้วโดยสร้าง `sap_integration_v3.stg_sap_state` จาก **`SAP_LIVE_FULL`** (ไม่ใช่
> `raw_sap_live` ตามที่ § 2.1 ด้านล่างเขียนไว้) — ทุกจุดในเอกสารนี้ที่พูดถึง `raw_sap_live`/B1-sunset
> ให้อ่านเป็น `SAP_LIVE_FULL`/`stg_sap_state` แทน ยังไม่ได้แก้ทั้งฉบับ (ไม่เร่งด่วน) — นี่คือ pointer
> เดียวจนกว่าจะรีไรท์เต็ม

---

## 1. Problem Inventory (รวมทุกอย่างที่เจอ 07/07–23/07)

### A. Coverage gaps — ข้อมูลหายเงียบ (root cause ของ "missing" เกือบทั้งหมด)

| # | ปัญหา | หลักฐาน | Impact |
|---|---|---|---|
| A1 | `CREDIT_CARD_INSTALLMENT` ไม่มี pipeline เจ้าของ — ตกร่องระหว่าง RCL (บังคับ follow_ups) กับ onetime (บังคับ installment=1) | 30 + ~110 orders จาก 2 list บัญชี | สะสมทุกวัน ไม่มีวันเข้าเอง |
| A2 | NonMotor RCL: `motor_item_type != 'MOTOR_TYPE_COMPULSORY'` ตัด NULL ทิ้ง (BigQuery NULL semantics) | L79189867-1 + กลุ่ม 895 rows ใน diagnostic | NonMotor installment ไม่เคยผ่าน filter |
| A3 | `follow_ups` เป็น mandatory ทั้งที่ join เป็น LEFT — งวดไม่มี follow_up หายทั้งแถว | Diagnostic gap check | เงื่อนไขตายเงียบ |
| A4 | Credit Shell ไม่มี installment_details → period NULL → หลุดทุก join (INCIDENT-001) | L80347249-M1, L80440579 | CMI credit shell หายทั้งกลุ่ม |
| A5 | Snapshot ไม่เลือก latest + กรอง `number_of_installment > 1` ที่ field ไม่น่าเชื่อถือ | comment ใน credit shell query ของ Boat เอง | fanout / drop |
| A6 | Credit shell new order ถูกตัดจาก RCL 05 (by design) แต่ flow RCL 04 ไม่ได้รันประจำ | 5 items ใน triage | รอ manual run |
| A7 | RCL flows ไม่มี daily scheduler (มีแต่ RCB `sap-order-payment*`) + production query มี hardcoded list | scheduler list + query 02 | ทั้งสาย RCL เป็น manual |

### B. Correctness bugs — ข้อมูลเข้าแต่ผิด/ชน

| # | ปัญหา | หลักฐาน |
|---|---|---|
| B1 | **InvoiceNo convention ชนกัน 2 flow**: BI ใช้ `CONCAT('2_', id)` (กัน collision) อีก flow ใช้ raw charge id — InvoiceNo immutable → `Cannot change InvoiceNo` | Invoice drift check 21/07 batch |
| B2 | Status mapping ยุบทุกอย่างเหลือ paid/pending — สถานะจริงจาก SAP รู้ได้ทาง D+1 extract เท่านั้น | A_WRONG_STATUS 8,007 rows (ส่วนใหญ่คือภาพลวงจากกระจกเก่า) |
| B3 | Cancel ต้องเป็นไปตาม spec ที่ไม่เคยมีเอกสาร: ครบงวด 1..TotalPeriods, งวดละ 1 แถว, invoice ตรง doc ปัจจุบัน, งวดอื่น Paid/Pending — reverse-engineer จาก error 3 รอบ | import logs 22–23/07 |
| B4 | dup filter ใน production cancel ถูก comment ไว้ + `ORDER BY BatchRunDate` เรียง string DDMMYYYY (ผิด) | query 02 |
| B5 | EIR rounding ปรับ 2 รอบ (finish → finish_2) — ถูกแต่แพงและอ่านยาก | query RCL 05 |

### C. Source-of-truth ผิดตัว (ตัวการใหญ่สุด)

| # | ปัญหา | หลักฐาน |
|---|---|---|
| C1 | **`SAP_LIVE`/`SAP_LIVE_FULL` (B1 loader path) เป็นกระจกล้าสมัย** — งวดที่ SAP Paid+มี invoice ยังโชว์ Pending/ว่าง; ต้นเหตุ cancel ตก ~100 orders/คืน และ gap count เกินจริง (6,515 → จริง ~1.4 พัน) | Mirror comparison 23/07: INVOICE_DIFF ยืนยัน |
| C2 | Gap check เดิมเช็ค output กับ output ตัวเอง (`RCL 05_*` vs ตัวเอง) — มองไม่เห็นสิ่งที่ query gen ไม่ออก | Query 1 ของชุด gap check |
| C3 | ไม่มี recon layer — Finance ไล่หา gap เองเป็น list ส่งมาให้แก้เป็นงวดๆ | ทั้ง 3 รอบที่ผ่านมา |

### D. Resource waste

| # | ปัญหา |
|---|---|
| D1 | ทุก query full-scan ตาราง careos ทั้งประวัติศาสตร์ทุกครั้งที่รัน (ไม่มี partition filter / incremental) |
| D2 | `JSON_VALUE(orders.data, ...)` ×15 fields × ทุก order × ทุก run — CPU หนักสุดใน pipeline |
| D3 | `SELECT DISTINCT *` บนตารางกว้าง (SAP_LIVE_FULL rebuild, raw scan) |
| D4 | 5-pass pipeline (combine → transformation → arrange → finish → arrange_again → finish_2) |
| D5 | Batch แบบ full-regenerate แล้วให้ SAP ปัด duplicated เอง แทน delta-only |

---

## 2. Target Architecture — "One Engine, Data-Driven Routing, Delta Export"

หลักคิด: เลิกมี 4-5 query แยกตาม flow ที่แต่ละตัวถือกติกาคนละชุด → เหลือ **engine เดียว** ที่ route ตาม payment_option ในข้อมูลจริง, สร้าง full schedule จาก spine, และ export เฉพาะ delta เทียบกับสถานะจริงใน SAP

```
CareOS raw ──▶ [L2 Staging: incremental, JSON parse ครั้งเดียว]
                 stg_payment_events   (partition by charge date)
                 stg_schedule         (latest snapshot + spine 1..N)
                 stg_order_dim        (JSON parsed, materialized)
raw_sap_live ─▶  stg_sap_state        (1 แถว/(item,period), Paid-priority) ★ SAP truth เดียว
                        │
                        ▼
              [L3 Engine: expected_state]
                 route: payment_option → flow rules
                 InvoiceNo: กติกาเดียว (UDF กลาง)
                        │
                        ▼
              [L4 Validation — blocking]
                 PK dup / sequence / balance / master / cancel-preflight
                 fail → sap_validation_error (ห้าม drop เงียบ)
                        │
                        ▼
              [L5 Delta Export]
                 expected_state ⊖ stg_sap_state → _01_create / _02_cancel
                        │
                        ▼
              [L6 Recon] expected vs sap_state รายวัน → interface_daily_status
```

### 2.1 stg_sap_state — SAP truth เดียว (แก้ C1, B3)

> ✅ **สร้างจริงแล้ว 2026-07-24** — ดู `sql/ddl/002_sp_refresh_sap_state.sql` ใน repo (source จริงคือ
> `SAP_LIVE_FULL` ไม่ใช่ `raw_sap_live` ด้านล่าง ซึ่งไม่มีอยู่จริง — โค้ดข้างล่างเก็บไว้เป็น reference
> เดิม logic เหมือนกันทุกอย่างยกเว้นบรรทัด FROM)

```sql
CREATE OR REPLACE TABLE `...sap_integration_v3.stg_sap_state`
CLUSTER BY U_OrderItem AS
SELECT * EXCEPT(rn) FROM (
  SELECT r.*,
    ROW_NUMBER() OVER (
      PARTITION BY U_OrderItem, SAFE_CAST(U_Period AS INT64)
      ORDER BY
        CASE WHEN TransactionStatus IN ('Cancelled','Cancelled (Change order / Rejected)') THEN 0
             WHEN TransactionStatus IN ('Paid','paid') THEN 1 ELSE 2 END,
        CASE WHEN IFNULL(U_InvoiceNo,'') != '' THEN 0 ELSE 1 END
    ) AS rn
  FROM `...sap_integration_v2.SAP_LIVE_FULL` r  -- (เดิมเขียน raw_sap_live — ไม่มีอยู่จริง, แก้ 07-24)
) WHERE rn = 1;
```
- Source: **raw_sap_live เท่านั้น** — SAP_LIVE* ใช้ได้เฉพาะ historical fallback ชั่วคราวระหว่าง backfill raw ให้ครบ แล้ว sunset
- Refresh: ต่อท้าย extract 20:30 (job เดียวกัน chain กัน — ไม่พึ่ง loader ตี 1 อีก)
- ทุก consumer (gap check, cancel gen, recon, dashboard) อ่านตารางนี้ตัวเดียว

### 2.2 stg_order_dim — JSON parse ครั้งเดียว (แก้ D2)

Materialize InsuredID/Title/Name/Chassis/LicensePlate/BillingAddress/oicCode จาก `orders.data` ครั้งเดียวต่อ order, MERGE เฉพาะ order ที่ `update_time` เปลี่ยน — งานที่เคยจ่ายทุก run ทุก query เหลือจ่ายครั้งเดียว

### 2.3 stg_payment_events + stg_schedule — population driver ใหม่ (แก้ A1–A5, C2)

**หลักการกลับด้าน: ขับจาก "เงินเข้า" (charges SUCCESSFUL) ไม่ใช่ขับจาก follow_ups/snapshot** — เงินเข้าแล้วต้องมีทางไป SAP เสมอ ไม่มี filter ไหนตัดทิ้งเงียบได้อีก

```sql
-- stg_schedule: spine เต็มทุก order ที่มีเงินเข้า
WITH latest_snapshot AS (
  SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY transaction_id
                                 ORDER BY update_time DESC, id DESC) rn
    FROM carepay_transaction_snapshots) WHERE rn = 1
),
total_periods AS (          -- ไม่เชื่อ number_of_installment ตัวเดียว (A5)
  SELECT t.id AS transaction_id,
         GREATEST(COALESCE(MAX(d.period), 0),
                  COALESCE(s.number_of_installment, 0),
                  COALESCE(t.installments, 0), 1) AS total_periods
  FROM carepay_transactions t
  LEFT JOIN latest_snapshot s ON s.transaction_id = t.id
  LEFT JOIN ..._installment_details d ON d.snapshot_id = s.id
  GROUP BY t.id, s.number_of_installment, t.installments
)
SELECT t.transaction_id, p AS period, tp.total_periods
FROM total_periods tp, UNNEST(GENERATE_ARRAY(1, tp.total_periods)) p
```
- ทุกงวดเกิดจาก spine → **ไม่มีเงื่อนไข "ต้องมี follow_ups / ต้องมี details" อีก** (A3, A4 ตายถาวร — COALESCE ไม่จำเป็นเพราะไม่ join แบบบังคับแล้ว)
- `ExpectedDate = COALESCE(follow_ups.due_date, DATE_ADD(first_due, INTERVAL p-1 MONTH))`
- Incremental: process เฉพาะ transaction ที่มี charge ใหม่ตั้งแต่ watermark ล่าสุด (D1)

### 2.4 L3 Engine — payment-type router (แก้ A1, A2, A6, A7)

ตารางกติกาเดียว แทน WHERE กระจาย 4 query:

| payment_option / เงื่อนไข | Flow | TotalPeriods | Channel matrix |
|---|---|---|---|
| `FULL_PAYMENT` (+ อื่นๆ default) | ONETIME | 1 | RCB-* ตาม method+provider |
| `CREDIT_CARD_INSTALLMENT` | **ONETIME** (ธนาคารจ่ายเต็ม) | 1 | `EDC EDC` / `RCB-EDC-KBANK` (+เพิ่ม bank อื่นใน matrix) |
| `RABBIT_CARE_INSTALLMENT` + voluntary | RCL full schedule | spine | RCL-* matrix |
| COMPULSORY + `RABBIT_LENDING` | RCL-CMI period 1 | 1 | RCL-CMI-channel |
| order ∈ cancelled_change_orders chain | CREDIT_SHELL (recursive pool) | spine | RCL-Credit Shell |

- Filter NULL-safe ทุกจุด: `(motor_item_type != 'MOTor_TYPE_COMPULSORY' OR motor_item_type IS NULL)` (A2)
- Credit shell รวมเข้า engine เดียว ใช้ recursive chain + invoice pool ของ Boat (A6)
- **Unknown payment_option → route เข้า `sap_validation_error` เป็น UNROUTED** — payment type ใหม่ในอนาคตจะ "มองเห็น" ตั้งแต่วันแรก ไม่หายเงียบแบบ A1 อีก

### 2.5 InvoiceNo — กติกาเดียวทั้งระบบ (แก้ B1) ⚠️ ต้องตัดสินใจ

ข้อเท็จจริง: SAP ตอนนี้ถือ **raw charge id** (จาก flow 21/07) และ InvoiceNo แก้ไม่ได้
ข้อเสนอ (ให้ Boat/บัญชี confirm): มาตรฐาน = **raw `third_party_id`**; กัน collision ด้วย prefix **เฉพาะ charge ซ้ำในงวดเดียว** (additional payment): `charge_rank > 1 → CONCAT(rank,'_',id)` — ตรงกับ pattern ฝั่ง onetime อยู่แล้ว และเลิก `2_` บนงวด 1 ปกติ
Implement เป็น UDF กลาง `fn_invoice_no(third_party_id, charge_rank, order_item, status)` — ทุก flow เรียกตัวเดียวกัน แก้ที่เดียว

### 2.6 L4 Validation — blocking ก่อน export (แก้ B3, B4)

Checks (ทั้งหมดจาก VALIDATION_LIBRARY เดิม + ที่ reverse-engineer ใหม่):
1. PK dup: (OrderItem, Period, ChargeID, InvoiceNo) unique
2. Schedule integrity: install order ต้องมีงวด 1..TotalPeriods ครบ งวดละ 1 แถว
3. Balance: TotalAmount = Premium+EIR+SBT+fees; Σ Actual per period = Expected แถวแรก
4. **Cancel preflight** (spec ใหม่): ทุกงวดใน stg_sap_state เป็น Paid/Pending, ไฟล์ cancel ครบ 1..TotalPeriods งวดละ 1 แถว, InvoiceNo = ค่าใน stg_sap_state เป๊ะ, ไม่มี item ที่ cancelled แล้ว
5. Master: InsurerCode มีใน master / PaymentDate ตาม cutoff calendar
- Fail → `sap_validation_error` พร้อม reason — Layer 5 export เฉพาะที่ผ่าน

### 2.7 L5 Delta Export (แก้ D5, ลบ duplicated error)

```sql
-- create: expected ที่ SAP ยังไม่มี
SELECT e.* FROM expected_state e
LEFT JOIN stg_sap_state s USING (order_item, period)
WHERE s.order_item IS NULL AND e.target_status = 'paid'
-- cancel: SAP ยัง active แต่ CareOS cancel แล้ว → mirror จาก stg_sap_state
```
- ส่งเฉพาะส่วนต่าง → ไฟล์เล็ก, ไม่มี `duplicated` noise, SAP ประมวลเร็ว
- Sequenced `_01_create` / `_02_cancel` ตาม v2.1 §6.2 เสมอ

### 2.8 L6 Recon (แก้ C3)

`recon_careos_interface` รายวัน (หลัง extract): expected_state ⟷ stg_sap_state ต่อ (item, period) → `OK / MISSING(>D+2) / PENDING_ACK(≤D+2) / STATUS_CONFLICT / UNROUTED` + `interface_daily_status` สรุปให้ Finance ดูเอง — **จบยุครับ list จากบัญชีเป็นงวดๆ**

**D12/D13 money recon:** คำนวณ `AMOUNT_VARIANCE` โดย aggregate ทั้ง order ก่อน แล้วใช้ tolerance
±฿10 ต่อ order; ห้ามเทียบ threshold ต่อ row/period/item/document. แยก `MISPOSTING` เป็นคนละ defect
class และไม่มี tolerance เพราะยอด order อาจ net 0 ทั้งที่ลงผิดฝั่ง.

---

## 3. Resource Budget เทียบก่อน/หลัง

| รายการ | เดิม | ใหม่ |
|---|---|---|
| Scan ต่อ run | full history ทุกตาราง ทุก query | incremental จาก watermark + partition pruning |
| JSON parse | ทุก field × ทุก run × ทุก query | ครั้งเดียวใน stg_order_dim |
| จำนวน pass | 5–6 pass (finish_2) | 2 pass (engine → validate) — EIR adjust ใช้ window ครั้งเดียว |
| Export | full regenerate | delta-only |
| Scheduled jobs | RCB 2 jobs + RCL manual | 1 chain: extract → sap_state → engine → validate → export → recon |
| กระจก SAP | B1 loader + SAP_LIVE ×3 ตาราง + FULL rebuild | raw_sap_live + stg_sap_state (B1 sunset) |

---

## 4. Migration Plan

| Phase | งาน | ปิด gap |
|---|---|---|
| **P0 (สัปดาห์นี้ — quick wins ไม่แตะโครง)** | สร้าง stg_sap_state จาก raw_sap_live; ชี้ cancel-gen + gap check ทุกตัวมาที่นี่; แก้ NULL-safe filter + snapshot latest ใน query production เดิม; ตัดสินใจ InvoiceNo standard | C1, C2, A2, A5, B1 |
| **P1** | stg_order_dim + stg_payment_events + spine (incremental) | D1, D2, A3, A4 |
| **P2** | Engine + router + UDF invoice + validation blocking | A1, A6, B2-B5, D4 |
| **P3** | Delta export + scheduler chain เดียว (เลิก manual RCL) | A7, D5 |
| **P4** | Recon L6 + daily status + sunset B1/SAP_LIVE* | C3 |

---

## 5. Decisions ที่ต้องการจาก Boat / stakeholders

1. **InvoiceNo standard** (§2.5) — raw id + rank prefix เฉพาะ additional? (บัญชีต้อง ack เพราะกระทบเลขบนเอกสาร)
2. Cancel spec — ยืนยันกับ Aware/SAP ให้เป็นลายลักษณ์อักษร (เลิก reverse-engineer)
3. CREDIT_CARD_INSTALLMENT channel matrix ครบทุก bank (ตอนนี้ confirm แค่ KBANK)
4. Backfill scope ของ raw_sap_live ย้อนหลัง (ให้ stg_sap_state ครอบ order เก่าครบก่อน sunset SAP_LIVE*)
5. Ownership + schedule ของ chain ใหม่ (เสนอ: ต่อท้าย extract 20:30 ทั้งเส้น)
