# SAP Data Preparation Design v3 — CareOS Source → 56-Column Interface
Date: 2026-07-23 | Status: FOR REVIEW (Boat) | คู่กับ: REDESIGN_V3 (why) + E2E_DESIGN (orchestration) + RUNBOOK + DASHBOARD
Scope: ทุก query/stored procedure จาก data source ถึงไฟล์ export — reviewable ทีละ stage

> ⚠️ **CORRECTION 2026-07-27**: `raw_sap_live` (§0, §5 ด้านล่าง) ไม่มีอยู่จริง — verified ผ่าน
> bq/gcloud 2026-07-24, authoritative source: `docs/knowledge/10_SAP_CONTEXT.md` §ARCHITECTURE.
> §5's `stg_sap_state` สร้างจริงแล้วจาก **`sap_integration_v2.SAP_LIVE_FULL`** (ดู
> `sql/ddl/002_sp_refresh_sap_state.sql`), ไม่ใช่ `raw_sap_live` — โค้ดใน §5 เก็บไว้เป็น reference
> เดิม logic เหมือนกันทุกอย่างยกเว้นบรรทัด `FROM`.
>
> **กติกาสองชั้น (two-layer rule), ยืนยันจริงจาก TASK_CLEAN_SAP_MIRROR.md 2026-07-26**: มี 2 ระดับ
> แยกกัน ไม่ใช่ตารางเดียว —
> - **`sap_mirror_doc`** (evidence layer) = 1 แถว/`DocEntry`, **ไม่ dedup ข้าม DocEntry เลย** — ใช้
>   สำหรับ cancel mirroring, invoice lookup, audit (ที่ต้องเห็นทุก doc จริงที่ SAP เก็บ)
> - **`sap_mirror_state`**/`stg_sap_state` (opinion layer) = 1 แถว/(OrderItem, Period), picking rule
>   จุดเดียว (Cancelled > Paid > Pending, non-empty InvoiceNo ชนะ, BatchRunDate ล่าสุดชนะ) — ใช้
>   สำหรับ delta export/recon/dashboard ที่ต้องการคำตอบเดียวต่อ period
>
> **เหตุผลที่ต้องแยก**: 31% ของ (OrderItem, Period) keys มี 2+ candidate documents จริง (328,071 keys)
> — ถ้ายุบเป็นตารางเดียวแบบ opinion-only จะเสีย evidence สำหรับ cancel-mirroring ที่ต้องอ้างอิง
> DocEntry ที่ถูกต้องเป๊ะ; ถ้าเก็บแบบ evidence-only (ไม่ dedup) ทุก consumer ต้องเขียน picking logic
> ซ้ำเอง เสี่ยง logic ไม่ตรงกันข้าม view (บทเรียนจาก duplicate-document forensics 07-26 — ดู
> `docs/FINDINGS_SAP_MIRROR_20260726.md` §9-11). ทุก picking-rule ambiguity ยังรอ Aware ตอบ Q3a
> (`SAP_CANCEL_IMPORT_SPEC_INFERRED_v0.9.md`) — แท็ก `PROVISIONAL_PENDING_AWARE_Q3A` ไว้จนกว่าจะตอบ.

---

## 0. Data Sources & Contracts

| Source | ตาราง | ใช้เป็น | Contract/ข้อควรระวัง |
|---|---|---|---|
| CareOS | careos_orders, careos_order_items, careos_leads | order dimension | `orders.data` = JSON (แพง — parse ครั้งเดียว) |
| CarePay | carepay_transactions, carepay_charges | **payment truth (driver)** | charge SUCCESSFUL = เงินเข้าจริง |
| CarePay | transaction_snapshots (+installment_details, price_summaries) | ยอด/งวด/ดอกเบี้ย | snapshot มีหลายรุ่น → ใช้ latest เท่านั้น; `number_of_installment` ไม่น่าเชื่อถือเดี่ยวๆ |
| CarePay | carepay_follow_ups | due date เท่านั้น | **ห้ามเป็นเงื่อนไขบังคับ** (บทเรียน A3) |
| CareOS | cancelled_change_orders | credit shell chain | recursive ได้หลายชั้น |
| SAP | **`SAP_LIVE_FULL`** (ไม่ใช่ `raw_sap_live` — ไม่มีอยู่จริง, แก้ 07-27) | SAP truth เดียว (doc-grain, ไม่ dedup ข้าม OrderItem/Period) | ต้องการ 1 แถว/(OrderItem,Period) ใช้ `stg_sap_state`/`sap_mirror_state` แทน — ดู two-layer rule ด้านบน |
| Master | sap_accounting_cutoff_dates, insurer master | PaymentDate shift, InsurerCode check | Finance confirm รายเดือน ห้าม hardcode |

Dataset ใหม่: `sap_integration_v3` (แยกจาก v2 เพื่อรันคู่ขนาน) + ตารางระบบ `pipeline_run_log`

---

## 1. Stage Map (ทุก stored procedure + I/O)

```
sp_refresh_order_dim      : careos_orders(+items,leads) ──▶ stg_order_dim        [incremental]
sp_refresh_payment_events : carepay_charges(+txn)       ──▶ stg_payment_events   [incremental]
sp_refresh_schedule       : snapshots(+details,followup)──▶ stg_schedule         [incremental]
sp_refresh_sap_state      : SAP_LIVE_FULL (ไม่ใช่ raw_sap_live) ──▶ stg_sap_state [full, เร็ว]
sp_build_expected_state   : stg_* ทั้งหมด               ──▶ expected_state       [56 col]
sp_validate               : expected_state + sap_state  ──▶ export_ready / sap_validation_error
sp_export_delta           : export_ready ⊖ sap_state    ──▶ GCS _01_create/_02_cancel + export_archive
ทุก sp เขียน pipeline_run_log (run_id, step, scope, rows_in/out, started, ended, status, error)
```

ทุก sp รับ parameter `run_scope`: `'FULL'` (nightly) หรือ `'ADHOC:<comma-separated order_ids>'` (urgent FA — ดู RUNBOOK §4)

---

## 2. S1 — stg_order_dim (JSON parse ครั้งเดียว)

Grain: 1 แถว/order_item | Refresh: MERGE เฉพาะ order ที่ `update_time > watermark`

```sql
CREATE OR REPLACE PROCEDURE sap_integration_v3.sp_refresh_order_dim(run_scope STRING)
BEGIN
  MERGE sap_integration_v3.stg_order_dim T
  USING (
    SELECT
      o.human_id  AS order_id,
      oi.human_id AS order_item,
      o.id AS order_uid, o.payment, o.lead, o.product AS product_line,
      oi.motor_item_type, oi.is_cancelled, oi.cancel_time,
      oi.insurer, oi.policy_number, oi.policy_start_date,
      oi.net_premium, oi.stamp_duty, oi.vat_amount, oi.gross_premium,
      oi.submission_status, oi.approval_status,
      l.type AS lead_type,
      JSON_VALUE(o.data,'$.oicCode') AS oic_code,
      JSON_VALUE(o.data,'$.chassisNumber') AS chassis_no,
      JSON_VALUE(o.data,'$.carLicensePlate') AS license_plate,
      -- InsuredID / Title / First / Last / BillingAddress: ยก CASE เดิมจาก production มาทั้งก้อน (verified แล้ว)
      ... AS insured_id, ... AS title_raw, ... AS first_name, ... AS last_name,
      ... AS billing_address,
      o.create_time AS order_create_time,
      o.update_time AS src_update_time
    FROM careos_orders o
    JOIN careos_order_items oi ON oi.order_id = o.id
    LEFT JOIN careos_leads l ON CONCAT('leads/', l.id) = o.lead
    WHERE (run_scope = 'FULL' AND o.update_time > (SELECT wm FROM v3_watermarks WHERE tbl='order_dim'))
       OR (run_scope LIKE 'ADHOC:%' AND o.human_id IN UNNEST(SPLIT(SUBSTR(run_scope,7), ',')))
  ) S ON T.order_item = S.order_item
  WHEN MATCHED THEN UPDATE SET ... WHEN NOT MATCHED THEN INSERT ...;
END;
```
Review point: JSON fields ยก logic production เดิมทุกตัว (ไม่แต่งใหม่) — diff ได้ column ต่อ column

## 3. S2 — stg_payment_events (driver ของทั้งระบบ)

Grain: 1 แถว/charge SUCCESSFUL | Partition: DATE(paid_time)

```sql
SELECT
  oi.order_item, t.id AS transaction_id, c.id AS charge_id,
  c.third_party_id, c.installment_number,
  ROW_NUMBER() OVER (PARTITION BY t.id, c.installment_number ORDER BY c.create_time, c.id)
    AS charge_rank,                       -- deterministic (เพิ่ม c.id กัน tie — บทเรียน ExpectedReceived)
  t.payment_option,                       -- ROUTER KEY
  c.payment_method, c.service_provider,
  ROUND(c.amount/100, 2) AS amount_thb,
  COALESCE(c.payment_date, c.update_time) AS paid_time
FROM carepay_charges c
JOIN carepay_transactions t ON t.id = c.transaction_id
JOIN stg_order_dim oi ON oi.payment = CONCAT('transactions/', t.id)
WHERE c.status = 'SUCCESSFUL'
```
กติกา: **ทุกแถวในนี้ต้องจบที่ SAP หรือ sap_validation_error เท่านั้น** — นี่คือนิยาม completeness ของโปรเจกต์

## 4. S3 — stg_schedule (spine เต็ม — ฆ่า bug ตระกูล row หาย)

Grain: 1 แถว/(transaction, period 1..TotalPeriods)

```sql
WITH latest_snapshot AS (
  SELECT * FROM (SELECT *, ROW_NUMBER() OVER (PARTITION BY transaction_id
                 ORDER BY update_time DESC, id DESC) rn FROM carepay_transaction_snapshots)
  WHERE rn = 1),
tp AS (   -- TotalPeriods ไม่เชื่อ field เดียว (A5)
  SELECT t.id AS transaction_id,
         GREATEST(COALESCE((SELECT MAX(d.period) FROM ..._installment_details d
                            WHERE d.snapshot_id = s.id), 0),
                  COALESCE(s.number_of_installment, 0),
                  COALESCE(t.installments, 0), 1) AS total_periods,
         s.id AS snapshot_id
  FROM carepay_transactions t LEFT JOIN latest_snapshot s ON s.transaction_id = t.id)
SELECT
  tp.transaction_id, p AS period, tp.total_periods,
  ROUND(d.payment_amount/100,2)   AS expected_amount,
  ROUND(d.add_ons/100,2)          AS addons_amount,      -- CMI ฝังใน V1
  ROUND(d.interest/100,2)         AS interest_eir,
  ROUND(d.principal/100,2)        AS principal_eir,
  ROUND(d.principal_balance/100,2) AS principal_balance,
  COALESCE(fu.due_date,
           DATE_ADD((SELECT MIN(due_date) FROM follow_ups f2 WHERE f2.transaction_id=tp.transaction_id),
                    INTERVAL p-1 MONTH))                  AS expected_date,   -- fallback (A3)
  ROUND(ps.interest_amount/100,2) AS interest_total,
  ... wht/processing/shipment/discount/net_premium จาก price_summaries ...
FROM tp
CROSS JOIN UNNEST(GENERATE_ARRAY(1, tp.total_periods)) p
LEFT JOIN ..._installment_details d ON d.snapshot_id = tp.snapshot_id AND d.period = p
LEFT JOIN follow_ups fu ON fu.transaction_id = tp.transaction_id AND fu.installment = p
LEFT JOIN ..._price_summaries ps ON ps.snapshot_id = tp.snapshot_id
```
- Credit Shell ไม่มี details → spine ยัง gen งวดครบ, expected_amount NULL → engine เติมตามกติกา CS (INCIDENT-001 ตายถาวร)
- follow_ups เป็นแค่ผู้ให้ due_date — ไม่ตัด row ใครอีก

## 5. S4 — stg_sap_state (SAP truth) — โค้ดด้านล่างเป็น reference เดิม, จริงสร้างจาก SAP_LIVE_FULL (ดู banner ด้านบน)

```sql
CREATE OR REPLACE TABLE stg_sap_state CLUSTER BY order_item AS
SELECT * EXCEPT(rn) FROM (
  SELECT U_OrderID order_id, U_OrderItem order_item,
         SAFE_CAST(U_Period AS INT64) period, SAFE_CAST(TotalPeriods AS INT64) total_periods,
         TransactionStatus sap_status, U_InvoiceNo sap_invoice_no,
         U_ActualReceived, ExpectedReceived, PaymentDate, PaymentMethod, PaymentChannel,
         ...(ทุก column ที่ cancel ต้อง mirror)...,
         ROW_NUMBER() OVER (PARTITION BY U_OrderItem, SAFE_CAST(U_Period AS INT64)
           ORDER BY CASE WHEN TransactionStatus IN ('Cancelled','Cancelled (Change order / Rejected)') THEN 0
                         WHEN TransactionStatus IN ('Paid','paid') THEN 1 ELSE 2 END,
                    CASE WHEN IFNULL(U_InvoiceNo,'') != '' THEN 0 ELSE 1 END) rn
  FROM SAP_LIVE_FULL) WHERE rn = 1;  -- แก้ 07-27: raw_sap_live ไม่มีอยู่จริง, source จริงคือ SAP_LIVE_FULL
```
⏳ รอ Aware Q3a — ถ้าคำตอบชี้ doc อื่น ปรับ ORDER BY จุดเดียว (จุดเดียวกับที่ `sap_mirror_state`'s
picking rule ใช้ — ดู `sql/ddl/025_sap_mirror_state.sql`, ไม่ใช่จุดที่สอง/สาม)

## 6. S5 — sp_build_expected_state (หัวใจ: router + 56 columns)

### 6.1 Router (แทน WHERE กระจาย 4 query)
```sql
CASE
  WHEN d.is_cancelled AND ss.order_item IS NULL AND pe.order_item IS NULL THEN 'SKIP_CANCELLED_NEVER_PAID'
  WHEN d.motor_item_type = 'MOTOR_TYPE_COMPULSORY'
       AND pe.service_provider = 'RABBIT_LENDING'                          THEN 'RCL_CMI'
  WHEN pe.payment_option = 'RABBIT_CARE_INSTALLMENT'                       THEN 'RCL_INSTALLMENT'
  WHEN pe.payment_option = 'CREDIT_CARD_INSTALLMENT'                       THEN 'EDC_ONETIME'      -- A1 ปิดถาวร
  WHEN cs.chain_root IS NOT NULL                                           THEN 'CREDIT_SHELL'     -- A6
  WHEN pe.payment_option IS NOT NULL                                       THEN 'ONETIME'
  ELSE 'UNROUTED'                                                           -- ลง validation_error เสมอ
END AS flow
```
NULL-safe ทุก filter (A2) | `cs` = recursive chain จาก cancelled_change_orders + invoice pool (query ของ Boat — ยกเข้ามาทั้ง logic)

### 6.2 กติกาต่อ flow

| Flow | Population | Period/TotalPeriods | เงิน | Channel |
|---|---|---|---|---|
| ONETIME | charge SUCCESSFUL | 1/1 | สูตร fully_paid เดิม (compu_detail split M/V) | matrix RCB เดิม |
| EDC_ONETIME | charge SUCCESSFUL | 1/1 (bank จ่ายเต็ม) | เหมือน ONETIME แต่ปลด snapshot=1 filter | `EDC EDC`/`RCB-EDC-<bank>` ⏳รอ matrix ครบ |
| RCL_INSTALLMENT | **spine ทุกงวด** join payment | p/N | สูตร RCL เดิม + additional payment rule (rank≠1→Expected 0) | matrix RCL เดิม |
| RCL_CMI | period 1 เท่านั้น | 1/1 | gross_premium ตรง, fee=0 | RCL-CMI-channel |
| CREDIT_SHELL | spine + carried invoice pool | p/N | ตาม recursive query | RCL-Credit Shell |

### 6.3 InvoiceNo — UDF เดียว (B1) ⏳ รอบัญชี ack
```sql
CREATE OR REPLACE FUNCTION fn_invoice_no(third_party_id STRING, charge_rank INT64,
                                         order_item STRING, is_paid BOOL) AS (
  CASE WHEN NOT is_paid THEN ''                                   -- งวดยังไม่จ่าย
       WHEN third_party_id IS NULL THEN order_item                -- ไม่มี id จาก gateway
       WHEN charge_rank > 1 THEN CONCAT(charge_rank,'_',third_party_id)  -- กัน collision เฉพาะ additional
       ELSE third_party_id END);                                  -- มาตรฐาน = raw id (ตามที่ SAP ถือจริง)
```

### 6.4 56-Column Assembly (source ต่อกลุ่ม)

| กลุ่ม column | Source | Transformation |
|---|---|---|
| Identity (CompanyDB, OrderID, OrderItem, InvoiceNo) | dim + fn_invoice_no | CompanyDB='RCB' คงที่ |
| Customer (InsuredID, Title, First/Last, BillingAddress) | stg_order_dim | Title map คุณ/นาย/นาง/นางสาว (เดิม) |
| Product (Insurer/Group/Type/Product, PolicyType, PolicyNo/Date, Chassis, Plate) | dim | + **Health/TA map (FIX C — ของใหม่)**; MotorBike จาก oic 610/620/630 |
| Money (Gross..TotalAmount, Discount) | stg_schedule + dim | สูตรเดิม verified; TotalAmount = Σ components (บังคับใน validation) |
| EIR block (TotalEIR/SBT, Interest*/Principle*) | schedule | สูตร 3.3/103.3 เดิม; **rounding spread ปรับงวดสุดท้าย ครั้งเดียวด้วย window** (แทน finish/finish_2):
`InterestEIR += (TotalEIR − SUM(InterestEIR) OVER item) เฉพาะ period = TotalPeriods` |
| Status (Transaction/Submission/Approval/Payment) | pe + dim | map เดิม; target_status = paid/pending ตาม charge จริง |
| Payment (Expected/Actual, PaymentDate, Method, Channel, Expected Date) | pe + schedule + router | additional rule (rank), PaymentDate cutoff shift (calendar), DDMMYYYY |
| Meta (Period, TotalPeriods, PendingPayment, RefOrder, Refund*, BatchRunDate) | schedule + cs | PendingPayment สูตรเดิม |

⚠️ **Open review Q-A (เจอระหว่าง consolidate):** ProcessingFee ใช้ตัวหาร **100/103.3 ในสาย RCL** แต่ **100/107 ในสาย onetime** — สูตรใดถูกต้องต่อ flow ไหน (VAT 7% vs SBT 3.3%?) รบกวน Boat/บัญชี confirm ก่อน P2 — ถ้าอันหนึ่งผิด แปลว่ามี drift ในเงินอยู่แล้ววันนี้

## 7. S6 — sp_validate (blocking)

| Rule | เงื่อนไข | Severity |
|---|---|---|
| V1 PK unique | (OrderItem, Period, ChargeID, InvoiceNo) ซ้ำ | BLOCK item |
| V2 Schedule integrity | installment: งวด 1..N ครบ งวดละ 1 แถว | BLOCK item |
| V3 Balance | TotalAmount = Σ comps; Σ Actual/period = Expected แถวแรก | BLOCK item |
| V4 Cancel preflight | ทุกงวดใน sap_state ∈ (Paid,Pending); ไฟล์ครบ 1..N; invoice = sap_invoice_no; ไม่ cancelled ซ้ำ | BLOCK item |
| V5 Master | InsurerCode ใน master; PaymentDate ตาม cutoff | BLOCK item |
| V6 UNROUTED / no-charge | flow แปลก | REPORT (ไม่ export) |
ผลลง `sap_validation_error(run_id, order_item, period, rule, detail)` — dashboard อ่านตรงนี้

## 8. S7 — sp_export_delta

```sql
-- CREATE: expected paid ที่ SAP ไม่มี  → _01_create
-- CANCEL: CareOS cancelled + SAP ยัง active → mirror จาก stg_sap_state ทุก column → _02_cancel
EXPORT DATA OPTIONS(uri='gs://interface-file/<BU>/<YYYYMMDD>_01_create_*.csv', format='CSV', header=true)
AS SELECT ... FROM export_ready WHERE batch_type='CREATE';
```
+ INSERT ทุกแถวเข้า `export_archive` (append-only, มี run_id) — replay/audit ได้ตลอด

## 9. Parallel-Run Acceptance (ก่อนสลับ production)

รัน v2 (เดิม) + v3 คู่กัน N วัน (เสนอ 5): เทียบรายวัน
1. row diff ต่อ flow = 0 หรืออธิบายได้ทุกแถว (ส่วนที่ v3 เก็บเพิ่ม = gap ที่ v2 ทำหาย — ต้องตรงกับ inventory A1–A7)
2. เงินทุก column: ผลรวมต่อ item ต่างกัน = 0.00 (ยกเว้น ProcessingFee ระหว่างรอ Q-A)
3. import error rate ของไฟล์ v3 < v2
ผ่านครบ → สลับ + freeze v2 อ่านอย่างเดียว 1 เดือน
