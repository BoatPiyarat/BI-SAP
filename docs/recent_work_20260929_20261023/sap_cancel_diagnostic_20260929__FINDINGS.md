# ผลตรวจรายการ cancel สำหรับ SAP — 29 กันยายน 2026

ตรวจ live BigQuery เวลา 09:03–09:13 ICT (02:03–02:13 UTC) ไม่ได้แก้ production หรือส่งไฟล์เข้า SAP

## ข้อสรุป

View เป้าหมาย: pacific-plating-282708.sap_view.RCB_Motor_process_2_cancel_new
อ่าน definition สดเมื่อ 2026-09-29 02:02:26 UTC (live_view.json/sql)
ผลจริง: L80517642-1 แสดง 3 งวด; อีก 11 เลขไม่แสดง ด้วยสาเหตุต่างกัน

| เลขที่แจ้ง | OrderItem ที่ตรวจ | ผลตรวจและการดำเนินการ |
|---|---|---|
| L79601099-V1 | L79601099-V1 | CareOS is_cancelled=false, cancel_time=NULL; ไม่มี SAP predecessor ด้วย ต้องยืนยันการยกเลิกต้นทางก่อน |
| L79680002-V1 | L79680002-V1 | CareOS is_cancelled=false, cancel_time=NULL; ไม่มี SAP predecessor ด้วย ต้องยืนยันการยกเลิกต้นทางก่อน |
| L7903333-1 | ไม่พบ | ไม่พบ exact ID ใน CareOS orders/items และ SAP_LIVE_FULL ต้องยืนยันเลข ห้ามเดาเลขทดแทน |
| L80537618 | L80537618-1 | SAP mirror มี C#L80537618 / Cancelled / DocEntry 2490262 / UpdateDate 2026-09-16 จึงกันส่งซ้ำ |
| L78678708 | L78678708-V1 | SAP mirror มี C#L78678708 / Cancelled / DocEntry 2488619 / UpdateDate 2026-09-16 จึงกันส่งซ้ำ |
| L80358209 | L80358209-V1 | SAP mirror มี C#L80358209 / Cancelled / DocEntry 2489969 / UpdateDate 2026-09-16 จึงกันส่งซ้ำ |
| L78556298 | L78556298-V1 | SAP mirror มี C#L78556298 / Cancelled / DocEntry 2488532 / UpdateDate 2026-09-16 จึงกันส่งซ้ำ |
| L79949677-1 | L79949677-1 | SAP Pending งวด 4 แต่ CarePay SUCCESSFUL; ติด stale_pending_paid_items; newpayment มีงวด 4 แล้ว ต้องตรวจ delivery/import แล้ว refresh mirror ก่อน cancel |
| L80517642-1 | L80517642-1 | แสดงใน live view แล้ว 3 งวด ไม่ต้องแก้ query เพื่อให้ปรากฏ |
| L79180940-1 | L79180940-1 | SAP Pending งวด 5 แต่ CarePay SUCCESSFUL; upstream trigger ตรวจงวดสูงสุด 6 ซึ่ง SAP Paid แล้ว ทำให้งวด 5 ตกหล่น |
| L80824898-1 | L80824898-1 | CareOS cancel แล้ว มี SUCCESSFUL EDC/KRUNGTHAI แต่ไม่พบ predecessor ใน SAP_LIVE_FULL ต้องตรวจเส้นทาง create/payment ก่อน cancel |
| L80824896-1 | L80824896-1 | CareOS cancel แล้ว มี SUCCESSFUL EDC/KRUNGTHAI แต่ไม่พบ predecessor ใน SAP_LIVE_FULL ต้องตรวจเส้นทาง create/payment ก่อน cancel |

## จุดที่ควรปรับ query

### 1. แก้ upstream payment ให้ตรวจช่องว่างรายงวด

Live object: sap_integration_v2.RCL 05-1_paid by period_NonMotor; definition ใน live_paid_trigger.sql
- charges ใช้ ROW_NUMBER() OVER (PARTITION BY transaction_id ORDER BY installment_number DESC) แล้วเลือก rank=1
- JOIN SAP Paid เฉพาะงวดสูงสุด และกรอง sap.U_OrderID IS NULL
- L79180940-1 มี CarePay SUCCESSFUL งวด 1–6 และ SAP Paid งวด 1–4,6 แต่ Pending งวด 5
- งวด 6 จับคู่ SAP Paid ได้ จึงไม่มี trigger ทั้ง order: 08_newpayment_gates.json ยืนยัน trigger_rows=0
- RCL_HEALTH มีงวด 5 เป็น paid พร้อม InvoiceNo chrg_6893rhye87rtfiklprg แต่ RCL_NonMotor_process_2_newpayment ไม่มีรายการนี้เลย (07_payment_route.json)

ข้อเสนอ: ตรวจ SUCCESSFUL charges ทุกงวดด้วย key OrderItem + Period และใช้ NOT EXISTS เทียบ SAP Paid ของงวดเดียวกัน; อย่าตัดเหลือเฉพาะงวดสูงสุด และอย่าใช้ OrderID อย่างเดียวจน sibling จับคู่กันผิด ต้องคงกติกา cancellation, product/flow, historical InvoiceNo และ pre-export validation

### 2. แก้ combine ของ sap_view.RCL_NonMotor_process_2_newpayment ควบคู่กัน

Live definition ใน live_nonmotor_newpayment.sql (captured 2026-09-29 02:08:20 UTC)
- newpayment คำนวณ MAX(U_Period) จาก SAP Paid
- combine ใช้ SAP เมื่อ Period <= max และใช้ CareOS เมื่อ Period > max
- หากเพิ่ม trigger ของ L79180940-1 อย่างเดียว max จะเป็น 6 แต่ period 5 ยังอ่าน SAP Pending และถูกตัดด้วย PaymentDate ว่าง
- จึงต้องเลือกต้นทางรายงวด: SAP Paid เดิมคง InvoiceNo/ค่าประวัติเดิม; SAP Pending + CareOS SUCCESSFUL ให้เข้ากระบวนการ update payment งวดนั้น; คง full spine และ quarantine ตามกติกา
- ข้อนี้เป็นข้อเสนอจาก live SQL + หลักฐานรายงวด ยังไม่ได้สร้าง/deploy replacement view หรือทดสอบผลกระทบทั้ง population

### 3. คง safety gate ของ cancel และเพิ่มเหตุผลการ hold

ใน RCB_Motor_process_2_cancel_new: cancelled_items_2026 เป็นด่าน item cancel_time; sap_ranked/is_already_cancelled_flag กับ base_eligible_items กัน cancel ซ้ำ; sap_current ต้องมี predecessor; ready_items ตัด stale_pending_paid_items

ไม่ควรถอด stale_pending_paid_items หรือเติม UNION รายชื่อเพื่อบังคับส่ง cancel เพราะจะข้าม payment ที่ SAP ยังไม่ได้รับ

เพิ่ม diagnostic แยกจาก positional SAP payload เพื่อแสดง SOURCE_ITEM_NOT_CANCELLED, ALREADY_CANCELLED_IN_SAP_MIRROR, SAP_PREDECESSOR_MISSING, PAYMENT_SYNC_REQUIRED_BEFORE_CANCEL และ SOURCE_ID_NOT_FOUND พร้อม period ที่ขาด

ไฟล์ cancel_diagnostic.sql เป็น SELECT ที่รันได้จริงสำหรับชุด 12 รายการ มี explicit mapping จาก OrderID ที่ยืนยันด้วย 02_source.json ไม่ใช่ production replacement และไม่ใช่ interface export

### 4. รายการที่ไม่ต้องแก้ cancel SQL

L79949677-1: upstream trigger=1, max SAP paid=3 และผล newpayment มี paid งวด 4 แล้ว ไม่ได้พิสูจน์ว่า SAP import สำเร็จ ต้องไล่ exact export/import result และ mirror freshness ต่อ

L80824898-1 / L80824896-1: ยืนยันแค่ไม่มี predecessor ใน SAP_LIVE_FULL และ CareOS cancelled + successful charge; ยังไม่ได้ยืนยันเหตุที่ create/payment ไม่เข้าสู่ SAP จึงไม่ควรเดาว่า KRUNGTHAI mapping เป็น root cause การกู้คืนต้องผ่าน create/payment -> successful SAP evidence -> refresh -> cancel

L80517642-1: ผ่าน selection แต่ไม่ได้รับรอง pre-export/import readiness ทั้งหมด; SAP mirror มี Paid period 1 สอง DocEntry และ live ranking เลือกหนึ่ง แยกประเด็นนี้ออกจากอาการไม่แสดง ห้ามถือว่าผล query เท่ากับ import สำเร็จ

## หลักฐานและการตรวจสอบ

- 01_reproduce.sql/json: query view จริงโดยจับทั้ง OrderID และ OrderItem, timestamp 02:03:23 UTC; job bqjob_r36560105d4e89eea_000001a0eae6ff31_1; 7.570 GiB dry run
- 02_source.sql/json: CareOS item cancellation, timestamp 02:04:02 UTC
- 03_gate_trace.sql/json: live CTEs กับ complete history ของ item รวม C# documents
- 04_charges.sql/json: successful charge evidence, timestamp 02:05:39 UTC
- 05_id_check.sql/json: exact unmatched identifier check; result []
- 06_sap_inventory.sql/json: SAP_LIVE_FULL document inventory, including historical Paid + Cancelled
- 07_payment_route.sql/json: RCL_HEALTH vs live nonmotor newpayment, timestamp 02:09:04 UTC
- 08_newpayment_gates.sql/json: trigger/max-period proof, timestamp 02:12:16 UTC
- cancel_diagnostic.sql/json: 12/12 unique requested IDs, timestamp 02:12:47 UTC; dry run 8,154,149,579 bytes; job bqjob_r174b2eeccf7d806e_000001a0eaef9dfe_1
- Offline evidence assertion PASS: every diagnostic READY flag matches actual live output presence across all 12 IDs
- Every data query ran through scripts/bq_safe_query.sh with dry-run first and maximum_bytes_billed=21474836480; no production SQL mutation or GCS export

Cancelled claims above describe observed SAP_LIVE_FULL mirror rows only. Direct SAP JE/import-success evidence was not checked; this report does not certify posting or GL correction. Query output also does not certify export/import success.

| Built | Verified against real data | Still unverified |
|---|---|---|
| Complete diagnostic SQL + evidence | All 12 identifiers; current view output; item flags; SAP predecessor/cancel history; stale payment periods; upstream trigger gap | Correct replacement for L7903333-1; why missing create/payment records never reached SAP; delivery/import outcome; production patch regression |

## Repository handoff

Actual bootstrap path: Phase1.1/agentic_bootstrap/codex_bootstrap. Working tree contains substantial pre-existing changes; git pull --ff-only failed because branches diverged. No merge, reset, commit, push, or edits to that checkout were performed. Artifacts are isolated in the current writable workspace outputs/sap_cancel_diagnostic_20260929. Review status script reported 0 OPEN, with pre-existing historical request warnings. Production patches require the repository review/deploy process; none requested or performed in this investigation.
