# Missing scenarios versus live sap_view — root-cause fix map

ตรวจครบ **12 live sap_view definitions** และ output ของทุก view สำหรับ fixed September missing population จาก monthly audit
ข้อมูลต้นทาง: Paid 1,341 charge-item links (1,310 charges) และ cancellation 184 document/placeholder rows
ไม่รวมกลุ่ม REVIEW ของ monthly audit และไม่ใช่การรับรองทุก transaction ของระบบ

## Coverage ที่วัดได้

| ประเภท | มี event identity/status ใน output | ไม่มี event ที่ตรงกัน | ไม่มี CareOS order ให้ route |
| --- | ---: | ---: | ---: |
| Paid | 703 | **203** | **435** |
| Cancellation | 134 | **50** | — |

Paid รวม 1,341; cancellation รวม 184. หน่วยคือ links/documents ไม่ใช่ distinct orders หรือยอดเงิน
การ match ต้องตรง OrderItem + Period + InvoiceNo + Paid/Cancelled; มี item หรือ period เฉย ๆ ไม่นับว่าครบ
**มี output ไม่เท่ากับส่งสำเร็จหรือ payload ถูกต้อง**: ดูข้อผิดพลาด mapping/amount และ duplicate owners ด้านล่าง
Cancellation match ไม่พิสูจน์การจับคู่หนึ่งต่อหนึ่งกับ DocEntry ถ้าหลาย DocEntry ใช้ invoice เดียวกัน

## Paid: 203 แถวที่ไม่อยู่ใน sap_view ใด

| Scenario / primary observed blocker | แถว | Motor/NonMotor | จุดที่ขาดและแนวทางแก้ root cause |
| --- | ---: | --- | --- |
| ออเดอร์ปี 2025 จ่ายเงินในเดือนนี้ | **85** | RCL Motor | `RCL_Motor_process_2_newpayment` กำหนด `OrderDate >= 2026-01-01`; 73 ออเดอร์ปกติ + 12 change-order. Eligibility ควรอิง receipt/payment event ที่ยังไม่อยู่ใน SAP ไม่ผูกกับปีสร้าง order |
| Invoice ใหม่ในงวดที่มี Paid แล้ว | **62** | RCL Motor | 10 ปกติ + 52 change-order; `RCL 05_newpayment` exclude ทั้ง item/period. `RCL 05_paid by period` ยังปิดทั้ง item เมื่อ latest charged period Paid แล้ว (61/62 แถวเข้าเงื่อนไขนี้ด้วย). แก้ทั้งสองชั้นเป็น receipt/invoice identity และตรวจทุก unsent charge ไม่ดูแค่ highest period |
| งวดรับเงินหลัง credit-shell/create ของ NonMotor | **41** | RCL NonMotor | `RCL_HEALTH` ตัด current_human_id ที่เป็น change-order; ส่วน credit-shell wrappers รับเฉพาะ item ที่ยังไม่มีใน SAP. Newpayment จึงไม่มี upstream receipt สำหรับ existing credit-shell item. ต้องเพิ่ม source/route ของ follow-up receipts หลังสร้าง credit-shell โดยตรง |
| Paid ที่ item ถูกยกเลิกแล้ว | **14** | Motor 11 / NonMotor 3, RCL | **เป็น scenario ที่ต้องสืบต่อ ไม่ใช่ single cause ที่ยืนยันแล้ว**. Motor newpayment ตัด cancelled items; 7 แถวในกลุ่มนี้ยังไม่มี SAP item ต้องซ่อม create/upstream ก่อน ส่วนที่มีแล้วต้องจัดลำดับ paid→cancel ตาม SAP state ห้ามเพียงลบ cancel guard |
| ยอดเพิ่มของ RCB item ที่มีใน SAP แล้ว | **1** | RCB Motor | `L78949140-V1`; create และ change views anti-join ระดับ item; ไม่มี existing-item receipt owner ใน 12 views. ต้องมี newpayment/top-up route สำหรับ RCB โดยไม่ส่ง create ซ้ำ |

แต่ละแถวจัดกลุ่มตาม blocker แรกที่ตรวจพบเพื่อไม่ให้นับซ้ำ ไม่ได้หมายความว่ามี blocker เพียงตัวเดียว
เช่น cancelled-item หรือ order-year filter อาจซ้อนกับ paid-period gate. การแก้หนึ่ง predicate ไม่ยืนยันว่าพร้อม export

**435 charges ไม่มี CareOS order link** แยกออกจาก 203 แถวข้างต้น: RCB 290, RCL 145
ไม่มี order_item ให้ sap_view สร้าง payload; จุดแก้อยู่ที่ transaction→order linkage/CareOS ไม่ใช่เพิ่ม UNION ใน sap_view

## Cancellation: 50 แถวที่ไม่มี event ใน output

| Scenario | แถว / items | หลักฐานและจุดแก้ |
| --- | --- | --- |
| หลาย invoice ในงวดเดียว แต่เหลือหนึ่งแถว | **8 / 7** | `RCB_Motor_process_2_cancel_new` ใช้ ROW_NUMBER partition item+period แล้ว `current_doc_rank=1`. ทั้ง 7 items ออกผ่าน view นี้เพียง receipt เดียวใน period1. ต้องเก็บทุก SAP receipt identity/DocEntry ที่ต้อง cancel และแยกการเช็ก period spine ออกจากจำนวน receipt |
| Cancel บาง receipt แล้ว รอบถัดไปไม่รับที่เหลือ | **6 / 6** | ทุก item มี `already_cancelled_flag=1` แล้วถูกตัดออกทั้ง item. ต้องเลือก uncancelled receipt ที่เหลือ และ carry terminal rows ตาม contract โดยไม่ rewrite invoice เดิม |
| CareOS จ่ายแล้ว แต่ SAP ยัง Pending | **26 / 3** | exact live CTE diagnostic: `stale_pending_paid=true`, `ready_item=false`; L78848241-V1 6 แถว, L79587523-1 10 แถว, L79988124-1 10 แถว. เป็น predecessor hold จริง ไม่ควรลบทิ้ง; ต้อง reconcile payment ก่อน cancel. L78848241-V1 ยังไม่มี Paid period1 |
| ไม่มี SAP create document | **10 / 10** | ยังไม่มีเอกสารให้ cancel; แก้ create/payment prerequisite ก่อน แทนการสร้าง cancellation ที่ไม่มีต้นทาง |

8 invoice ที่ตก: L79959262-V1 (1), L80035402-V1 (1), L80236849-V1 (2), L80326899-V1 (1),
L80421949-1 (1), L80489632-V1 (1), **L80517642-1 (1)**. ทั้งหมด period1; มี raw InvoiceNo และ DocEntry ใน CSV

RCL cancel อีก view ยังมี `dup=1` สำหรับ period>1 และ item-level cancelled exclusion จึงต้องแก้ receipt grain ให้สอดคล้องกันด้วย
134 แถวที่มี cancelled event อยู่ใน outputแล้ว อยู่คนละงาน: ตรวจ payload→file→import/error log; ไม่ใช่เพิ่ม route ใหม่

## มี output แต่ยังต้องแก้ payload หรือ ownership

- **88 Paid links / 87 items** มี output จาก `RCB_Motor_process_3_change` เป็น `RCB-EDC-KBANK` ทั้งที่ source payment_method ไม่ใช่ EDC.
  View นี้ hardcode ทั้ง `PaymentMethod='EDC EDC'` และ `PaymentChannel='RCB-EDC-KBANK'`; เงื่อนไข EDC/payment-option ถูก comment และ change-order membership ไม่บังคับ.
  นี่คือ root cause ของ mapping ผิดที่พิสูจน์ได้ใน output; ไม่ใช่ยืนยันว่า 88 แถวถูก SAP รับแล้ว
- **3 Paid links / 2 items** มี matching output ที่ ActualReceived=NULL; 2 links มี ExpectedReceived=NULL ด้วย: L80935037-V1 และ L80941876-V1.
  บาง route อื่นอาจมี payload ใช้ได้ จึงแสดง flags แยกตาม view ห้ามถือ union identity presence ว่า ready
- **135 Paid links + 24 cancellation rows** มี matching event มากกว่าหนึ่ง view.
  ตัวอย่าง create+change ซ้อนกัน, RCL create+newpayment ซ้อนกัน และ RCB/RCL credit-shell wrappers อ่าน source เดียวกัน.
  ต้องกำหนดเจ้าของ scenario และ deduplicate ก่อน export; ตัวเลขนี้ไม่ใช่หลักฐานว่าส่งซ้ำจริง เพราะยังไม่ได้ตรวจ scheduler/export logs

## ชื่อ view กับหน้าที่จริง

| sap_view | หน้าที่ / ข้อจำกัดที่ยืนยันจาก definition |
| --- | --- |
| RCB_Motor_process_create | Motor create เมื่อยังไม่มี item; มี insurer/test/year filters; ไม่รับยอดเพิ่มของ existing item |
| RCB_Motor_process_3_change | Motor create กว้างกว่า change-only; hardcode EDC-KBANK และ overlap create |
| RCB_NonMotor_process_1_create | Health/Travel create; anti-join existing item |
| RCB_NonMotor_process_2_cancel | **Health change-order CREATE** ไม่ใช่ cancel; ไม่รับ cancelled items |
| RCL_Motor_process_1_create | Motor RCL create + compulsory first-period; excludes current change-order และ existing item |
| RCL_Motor_process_2_newpayment | Motor RCL payment; year cutoff + cancelled-item guard + dependent v2 paid gates |
| RCL_NonMotor_process_1_create | RCL Health create เมื่อยังไม่มี item |
| RCL_NonMotor_process_2_newpayment | SAP rows ถึง max Paid period + upstream หลัง max period; ไม่รับ invoice ใหม่ในงวดที่ Paid แล้ว |
| RCB_Motor_process_4_creditshell | อ่าน RCL credit-shell source; รวม Motor/NonMotor และ overlap RCL-named wrapper |
| RCL_Motor_process_4_creditshell | Initial credit-shell create เท่านั้น; excludes existing SAP item |
| RCB_Motor_process_2_cancel_new | Cancel หลาย flow/product ไม่ได้จำกัด Motor/RCB; collapse item/period และมี predecessor gates |
| RCL_Motor_process_3_cancel | RCL multi-period cancellation; item-level exclusion และ later-period dedup |

ช่องว่างเชิงโครงสร้างที่ควรมี regression test แม้ไม่มีเคสยืนยันเพิ่มจาก missing population รอบนี้:
RCB NonMotor existing-item top-up, RCL NonMotor same-paid-period extra, และ credit-shell follow-up หลัง initial create
อย่านำจำนวน REVIEW ที่ยังไม่ยืนยันมาใส่เป็น affected cases ของช่องว่างเหล่านี้

## ลำดับชุดแก้ที่เตรียมได้

1. **Payment mapping/ownership:** แยกหน้าที่ `RCB_Motor_process_3_change`, เลิก hardcode EDC-KBANK, ยืนยัน source-based mapping และหนึ่งเจ้าของต่อ event ก่อน export
2. **Receipt grain:** แก้ RCL v2 newpayment+gate (62 missing links); cancellation เก็บทุก invoice และ partial retry (8+6 missing rows)
3. **Order-year scope:** แก้ eligibility ของ RCL Motor newpayment อิง payment event แทนปีสร้าง order (85 links)
4. **Scenario coverage:** เพิ่ม NonMotor credit-shell follow-up source/route (41 links) และ RCB existing-item payment route (1 confirmed link)
5. **Lifecycle/predecessor repair:** ทำ paid/create→cancel recovery สำหรับ cancelled-item payments และ stale SAP Pending; รักษา validation gates และแยก no-order linkage ไป CareOS
6. **Delivery investigation:** สำหรับ 703 Paid + 134 cancellation identity matches ตรวจ payload/file/import log หลังแก้ risk flags; อย่าส่งซ้ำจากผล audit เพียงอย่างเดียว

Regression acceptance: charge ใหม่หลายรายการในงวดเดียวไม่หาย; SAP invoice เดิมไม่ถูก rewrite; Expected ไม่เพิ่มซ้ำ;
full schedule spine ครบโดยไม่ลดจำนวน receipts; partial cancel retry เหลือเฉพาะ unresolved event;
old-order/current-payment ผ่าน; source non-EDC ไม่กลายเป็น EDC; ไม่มี Paid amount NULL; ไม่มี multiple active route owner ที่ export event ซ้ำ

## Artifacts / provenance / limits

- รายการที่ไม่มี event ใน sap_view: `docs/evidence/careos_scenario_routes_20260926/absent_from_sap_view.csv` — 253 rows = 203 Paid + 50 cancellation
- รายการทั้งหมดพร้อม scenario/primary blocker/view owners/payload flags: `scenario_details.csv` — 1,525 rows
- สรุป: `scenario_summary.csv`; mapping/NULL/owner review: `output_payload_review.csv`
- Offline reproducible analysis: `python scripts/analyze_month_scenario_routes_20260926.py`; มี assertions ของ population และ coverage
- 10 live paid/create/change/credit-shell probes สำเร็จ; cancellation outputs reuse จากก่อนหน้า เพราะ 12 definitions ตรวจใหม่แล้วไม่ drift
- `successful_jobs_and_bindings.json` ผูก SQL กับ 13 successful jobs; `execution_status.json` เก็บเวลาตรวจแต่ละ route
- Cancellation cache มี timestamp เดิมจาก monthly audit; definition ไม่เปลี่ยนไม่ได้แปลว่า output ไม่เปลี่ยน. ไม่อ้าง atomic same-time snapshot ของทุก view
- ขอบเขตเฉพาะ 12 live sap_view ที่พบ ไม่รวม route ภายนอก dataset, manual files หรือ import program. Source population เป็น September ถึง 23:06 ICT ตามรายงานก่อนหน้า
- ใช้ SAP_LIVE_FULL mirror ตามกติกาเดิม: ไม่รวม B2B; identity match ไม่รับรอง GL/การกระจายเงินระหว่าง item
- **เตรียม root-cause fix plan เท่านั้น ยังไม่ได้แก้หรือ deploy views, scheduler, SAP หรือ interface files; V3 ยัง hold**
