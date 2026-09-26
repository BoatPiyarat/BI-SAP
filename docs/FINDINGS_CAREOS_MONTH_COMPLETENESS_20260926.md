# September CareOS versus SAP — monthly completeness audit

**ยังไม่ครบ ณ 26 September 2026 เวลา 23:06:06 ICT** (snapshot time 16:06:06 UTC).
ช่วงตรวจ: 1 September ถึงเวลารัน; query ใช้ขอบเขตเดือน `[2026-09-01, 2026-10-01)` และตัดเหตุการณ์อนาคตด้วย as_of.
ไม่ได้หมายความว่าได้ตรวจวันที่ 27–30 September ซึ่งยังมาไม่ถึง

## ผลรวม

- SUCCESSFUL charges ในเดือน: **26,290 charges / 143,502,388.42 บาท** นับเงินหนึ่งครั้งต่อ charge ไม่คูณตามจำนวน order items
- Paid ยังไม่พบ terminal SAP receipt ที่ตรงกัน: **1,310 distinct charges / 1,341 charge-item links**; เกี่ยวข้องกับยอดรับดิบ **5,972,569.50 บาท**
- ยอดดังกล่าวเป็นจำนวนเงินของ charges ที่ต้องตรวจ ไม่ใช่ยอด GL ขาด: มีหลาย item ต่อ charge และ allocation ยังไม่ได้ reconcile
- Paid อีก **3,961 charges / 5,110 links** เป็น REVIEW เช่น invoice สำรอง, identity ซ้ำ, หลาย SAP documents หรือยอด allocation ต่างกัน ไม่รวมเป็น missing ที่ยืนยันแล้ว
- Cancellation ยังไม่มีหลักฐานยกเลิกตรงกัน: **184 แถว / 46 order items** รวม 10 item ที่ยังไม่มี SAP document
- Cancellation อีก **4,759 แถวในเดือน** เป็นสถานะเอกสารขัดกัน และ **1 รายการไม่มี cancel_time** แยกไว้นอกยอดเดือน
- Paid ที่ใช้ update_time แทน payment_date: 2 charges; มี paid_date_source ให้ตรวจได้

ฐานเปรียบเทียบคือ `sap_integration_v2.SAP_LIVE_FULL` ณเวลารัน ไม่ใช่ SAP import acknowledgement โดยตรง
view นี้ไม่รวม B2B และ deduplicate ตาม DocEntry ข้าม CompanyDB; ผลจึงเป็น completeness ภายใต้ขอบเขต mirror นี้
ไม่ใช่การรับรอง B2B, GL หรือทุกบริษัทใน SAP ทั้งระบบ

## Query และไฟล์ผลลัพธ์

- Query ใช้ซ้ำ: `sql/operator/careos_current_month_sap_completeness.sql`
- `month_start` เริ่มต้นเป็น `DATE_TRUNC(CURRENT_DATE('Asia/Bangkok'), MONTH)`; เปลี่ยนเป็นวันที่ 1 ของเดือนที่ต้องการเพื่อตรวจย้อนหลัง
- `only_exceptions=TRUE` คืนเฉพาะรายการต้องตรวจ; เปลี่ยน FALSE เพื่อรวม matched และ not-applicable ด้วย
- `include_undated_cancellations=TRUE` แสดงรายการยกเลิกที่ไม่มีวันในกลุ่มแยก ไม่ยัดเข้าเดือนปัจจุบัน
- ผล 3 ชุด: summary, distinct-charge money/control totals, รายละเอียดรายรายการ
- ผลของการรันครั้งนี้: `docs/evidence/careos_month_audit_20260926/paid_missing.csv`, `cancellation_missing.csv`, `exceptions.csv`, `summary.csv`
- CSV มี order_id, order_item, transaction_id, charge_id, installment_period, Motor/NonMotor, RCL/RCB,
  payment_mode, paid_date, cancellation_date, amount, raw/candidate/SAP InvoiceNo, DocEntry, source status,
  reconciliation_status, reason_code, cause_confidence และผลตรวจ upstream/process ประกอบ
- BANK_INSTALLMENT แยกจาก RCL INSTALLMENT เพราะการผ่อนกับธนาคารเป็น onetime ใน SAP; careos_total_installments ยังแสดงเทอมลูกค้า
- cancellation: charge_amount_thb เป็น NULL; ใช้ sap_matched_actual ของเอกสารนั้น ส่วน paid_at เป็น last-paid ของ transaction เพื่อ context

รันผ่าน safe wrapper (read only, ใช้เฉพาะ temporary tables):

```bash
bash scripts/bq_safe_query.sh --project pacific-plating-282708   -f sql/operator/careos_current_month_sap_completeness.sql --   --format=json --max_rows=100000 --location=asia-southeast1
```

## Paid: กลุ่มที่ไม่พบ terminal receipt

จำนวนในตารางเป็น charge-item links; ห้ามบวกยอดเงินต่อ link เพราะเงินอาจถูกกระจายหลาย item

| กลุ่ม | Links | สิ่งที่ตรวจพบ / สาเหตุที่ยืนยันได้ |
| --- | ---: | --- |
| SAP ยัง Pending | 528 | ทั้ง 528 มี InvoiceNo ใน upstream และใน RCL 05_newpayment แล้ว ช่องว่างอยู่หลังขั้นนี้ ต้องดู gate/export/import log เพื่อแยกสาเหตุสุดท้าย |
| ไม่มี CareOS order ผูก transaction | 435 | ไม่มี order link จึงยังไม่มี order item ให้ส่ง SAP; upstream ที่ตรวจไม่พบทั้งหมด เป็นปัญหาการเชื่อมข้อมูลก่อน interface |
| Change-order ใหม่ | 155 | 100 มีใบรับเงินใน upstream (44 อยู่ใน Motor RCL newpayment, 56 ไม่อยู่); อีก 55 ไม่อยู่ใน 5 upstream ที่ตรวจ ต้องใช้เส้นทาง change-order แยก ห้ามสรุปเป็น import error ทั้งกลุ่ม |
| ไม่มี SAP item | 138 | 131 มี invoice ใน upstream; อีก 7 ไม่มี invoice ตรงกัน (5 มี period แต่ invoice ไม่ตรง, 2 ไม่มี period) แยก upstream identity/routing กับ create/export/import ที่ยังไม่ยืนยัน |
| Lead ไม่ใช่ PURCHASED | 64 | เป็นลักษณะข้อมูล ไม่ใช่สาเหตุที่พิสูจน์แล้ว: ทั้ง 64 ยังมี invoice ใน upstream จริง ต้องตรวจ process ถัดไป |
| จ่ายเพิ่มในงวด Paid แล้ว | 10 | ทั้ง 10 อยู่ใน dashboard แต่ไม่อยู่ใน RCL newpayment; live predicate exclude ทั้ง order_item+period ที่ Paid โดยไม่แยก InvoiceNo จึงยืนยันตัวกรองที่ขวางยอดเพิ่ม |
| ไม่มี SAP period | 5 | ทั้ง 5 มี invoice ใน upstream และ RCL newpayment แล้ว ต้องตรวจการส่ง full period spine และ import log |
| Item ยกเลิก แต่ charge ไม่พบ | 5 | 4 มี invoice upstream; 1 ไม่มี ต้อง reconcile ลำดับรับเงิน/ยกเลิก ไม่สร้าง receipt ซ้ำอัตโนมัติ |
| SAP Paid ด้วย invoice อื่น | 1 | มี upstream invoice แต่ไม่ตรงใบที่อยู่ใน SAP ต้องตรวจ identity/import history |

คำว่า MISSING_TERMINAL_SAP_EVIDENCE หมายถึง query ไม่พบหลักฐาน terminal receipt ภายใต้กติกา matching
ไม่ใช่ยืนยันว่า SAP reject แล้ว; การ reject, ยังไม่ได้ส่ง, อยู่ระหว่าง import ต้องอาศัย import/error log

## Cancellation: กลุ่มที่ไม่พบสถานะยกเลิก

| กลุ่มตามข้อมูล | แถว | Order items (อาจซ้ำข้ามกลุ่ม) |
| --- | ---: | ---: |
| สถานะยังไม่ Cancelled | 128 | 17 |
| Change-order เดิมยังไม่ยกเลิก | 25 | 13 |
| หลาย receipt ในงวดเดียวกัน | 15 | 7 |
| ยกเลิกเพียงบาง receipt | 6 | 6 |
| ไม่มี SAP create document | 10 | 10 |

เทียบทุกแถวกับ output จริงของ `RCB_Motor_process_2_cancel_new` และ `RCL_Motor_process_3_cancel`:

- **134 แถว** มี invoice/period ใน cancellation output แล้ว แต่ SAP mirror ยังไม่เป็น Cancelled — ต้องตรวจ export/import/error log
- **8 แถว / 7 items**: item อยู่ใน output แต่ InvoiceNo บางบรรทัดหาย ยืนยันว่า query ส่ง cancellation ไม่ครบ receipt
- **32 แถว**: ไม่มี item ใน cancellation output ที่ตรวจ (20 status-not-applied, 6 change-order, 6 partial cancellation)
- **10 items**: ไม่มี SAP document ให้ยกเลิก ต้องตรวจ create/payment ก่อน

8 แถวที่ cancellation output ขาด invoice:

| Order item | Period | จำนวนแถวที่ขาด |
| --- | ---: | ---: |
| L79959262-V1 | 1 | 1 |
| L80035402-V1 | 1 | 1 |
| L80236849-V1 | 1 | 2 |
| L80326899-V1 | 1 | 1 |
| L80421949-1 | 1 | 1 |
| L80489632-V1 | 1 | 1 |
| **L80517642-1** | **1** | **1** |

ทั้ง 7 items ออกผ่าน `RCB_Motor_process_2_cancel_new` เพียงใบเดียวใน period 1 (`cancel_omitted_examples.json`)
live query นี้มีการลดหลาย DocEntry เหลือหนึ่งแถวต่อ item/period และมี item-level already-cancelled exclusion
จึงต้องรักษาทุก invoice ของ SAP เมื่อแก้ cancellation ไม่ใช่เพียงให้ period ครบ
สำหรับ 6 partial-cancel rows ไม่มี output และมี cancelled sibling ภายใน item จึงสอดคล้องกับตัวกรอง already-cancelled ระดับ item

ชื่อ process ไม่รับประกันหน้าที่: `RCB_NonMotor_process_2_cancel` live ปัจจุบันเป็น Health change-order CREATE
ไม่ใช่ cancel อย่างที่ชื่อบอก แต่ไม่ได้แปลว่า NonMotor ทั้งหมดไม่มีเส้นทาง cancel: การตรวจพบ output ของสอง cancel views ข้างต้นรวม NonMotor ด้วย

## กลุ่ม REVIEW ที่ไม่ควรนับเป็น missing อัตโนมัติ

| Paid REVIEW | Links |
| --- | ---: |
| พบ SAP ผ่าน invoice สำรอง | 4,488 |
| หลาย SAP documents ตรง receipt เดียวกัน | 423 |
| ไม่มี invoice ต้นทาง | 103 |
| Source identity ซ้ำ/กำกวม | 92 |
| ยอด raw charge ต่างจาก SAP ต้องตรวจ allocation | 4 |

Cancellation REVIEW: 1,789 เอกสาร Paid/สถานะอื่นมี cancelled counterpart ที่ invoice เดียวกัน;
2,970 blank Pending documents มี cancelled document ใน period เดียวกัน
ทั้งหมดคง DocEntry และ counterpart_cancelled_docentries ให้ตรวจ ไม่ถือว่าเอกสารเหล่านี้ถูก supersede หรือยกเลิกสำเร็จเพียงเพราะอีกแถว Cancelled
รายการไม่มีวันยกเลิกอีก 1 แถวถูกแยก `UNDATED_NOT_ASSIGNED_TO_MONTH`

## Verification และข้อจำกัด

- Source boundary checks: September cancelled items without a linked order = 0; successful charges without payment_date and update_time = 0 (`source_coverage.json`).
- Exact current-month query job: `codex_careos_month_audit_final_20260926`; assertions ผ่านทั้ง charge population conservation, charge-item grain และ cancellation-document grain
- `query_sha256.json` ผูก SQL กับผล; `final_jobs.json` เก็บสถานะและ bytes ของ query สำเร็จ
- Independent static review: PASS WITH NOTES; matching เป็น receipt identity ไม่ใช่ GL/การกระจายเงินระหว่าง compulsory/voluntary
- Captured live view definitions และ source schemas เก็บใน evidence directory; metadata SAP_LIVE ล่าสุดที่อ่านไม่ได้แปลว่าไม่มี extract lag
- `audit_result.json.gz` เป็นผลรอบแรกที่ยังมี false positives; `audit_corrected.json.gz` เป็นรอบแก้บน cached snapshot; ใช้ **audit_final.json.gz** และ CSV สุดท้ายเป็นผลอ้างอิง
- Diagnostic snapshots รันหลัง audit; อาจเกิดข้อมูลขยับเล็กน้อย ผล membership คือ ณเวลาตรวจ route ไม่ใช่หลักฐานว่ามีการส่งไฟล์ ณ audit time
- ไม่มีการแก้ production view, scheduler, SAP หรือเขียน interface file ในงาน audit นี้; V3 ยังคง hold
