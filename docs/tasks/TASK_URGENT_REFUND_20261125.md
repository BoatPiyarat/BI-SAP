# TASK: urgent refund import (FA/Mo Teams 2026-11-23, tab `urgent_refund to cust`), 2026-11-25

* Owner decision (Boat, 2026-11-25): do it manually, urgent.
* Rules: Aware answers 2026-08-22 in `TASK_URGENT_REFUND_PAID_CANCEL_20260821.md`.
  * Paid and Cancel go in separate files; Cancel only after SAP accepts the Paid file.
  * The cancel covers the full spine 1..TotalPeriods.
  * Never synthesize a Paid row from a shared charge.

## Triage of the 18 orders (22 items)
Sources: SAP_LIVE_FULL (load 2026-11-24) and CareOS, queried 2026-11-25 ~16:30 ICT.

| group | items | state | action |
|---|---|---|---|
| **A. Phase 1 SENT (Paid spine)** | L80731453-V1, L80776827-V1, L80991399-V1, L81017535-V1, L81058304-V1, L81072618-V1, L81131068-V1 | not in SAP; CareOS cancelled; RCL Credit Shell; old order already Cancelled in SAP | Phase 2 = plain `Cancelled` full spine after Phase 1 import is proven |
| B. Complete in SAP (Paid + C#Cancelled) | L78637687-V1, L78773608-V1, L79949677-1, L81085876-V1 | interface done | FA reports no JE. This is a SAP/Aware posting question, not an interface gap |
| C. SAP holds only C#Cancelled, no Paid row | L80568487-M1, L80568487-V1 (DIRECT_PAYMENT, one-time) | cancel without Paid in the mirror | ask Aware whether the Paid document exists; do not resend blindly |
| D. Ready for Phase 2 cancel (Paid in SAP) | L78637687-M1 (CMI, old side of change L80756545) | Paid, CareOS cancelled | `Cancelled (Change order / Rejected)`, goes in the Phase 2 file |
| E. Not in SAP, can join a later Paid file | L81085876-M1 (CMI, Credit Shell from cancelled L81084327-M1) | | Phase 1b |
| F. HOLD: incomplete SAP spine | L77833033-V1 (1/6), L80511750-V1 (1/10), L80513404-V1 (1/10), L80518454-V1 (1/3) | SAP period-1 InvoiceNo `chrg_…`; view now emits `2_chrg_…` | needs the Aware method to add periods 2..N without changing InvoiceNo. These are the nightly 07 "must be end to TotalPeriod" errors |
| G. HOLD: duplicate spine | L81096435-V1 | view returns 20 rows / 10 periods; 2 refunds 8,199.98 > paid 6,444.86 | investigate |
| H. HOLD: CareOS not cancelled | L80992193-M1, L78773608-M1 | SAP Paid; CareOS item active | FA: should CareOS be cancelled first? (CareOS cancellation is definitive) |

## Phase 1 delivery (group A)
* Snapshot: `sap_integration_v3.diag_manual_refund_phase1_20261125`, 57 rows / 7 items, built by
  `sql/adhoc/20261125_manual_refund_phase1_rcl_creditshell.sql`, job `job_3rttlMEHeEySRonadXIyEHEbmzTG`.
* Gate PASS:
  * 56-name contract;
  * spines complete;
  * exactly one Paid row, at period 1;
  * no NULL or "NULL";
  * dates valid (Pending PaymentDate blank);
  * 2-decimal money;
  * RCL-only channels;
  * CareOS cancelled;
  * not in SAP.
* InvoiceNo reuse of the old-order invoice follows the accepted precedent L81085876-V1, which
  reused L81084327's invoice after its cancel.
* Files:
  | copy | path | job |
  |---|---|---|
  | archive | `gs://rcb-bronze-zone/sap-interface-archive/manual/refund/2026/11/25/MANUALREFUND-PAID-20261125/INSURANCE_RCB_05_MANUAL_REFUND_PAID_RCL_20261125_000000000000.csv` | `job_O0junvJOMks4cocrMm50pNohaQ9h` |
  | production | `gs://interface-file/RCB_MOTOR/INSURANCE_RCB_05_MANUAL_REFUND_PAID_RCL_20261125_000000000000.csv` | `job_66hdiAwpXPu4rUj_2XbEMp6T-03q` |
* Read-back: both files 58 lines, identical (sorted-line SHA `973b4034…`).

## Next
1. Read the SAP import email for Phase 1, about 30 minutes after the write.
2. After the 26 Nov 01:00 mirror shows the 7 items Paid: build Phase 2 for groups A + D, gate it,
   then deliver.
   * Group A rows get `Cancelled`.
   * Group D (L78637687-M1) gets `Cancelled (Change order / Rejected)`.
3. Open questions to FA/Aware: groups B, C, F, G, H.

## Boat approval 2026-11-25 (chat "อนุมัติ"), after the triage report
* Approves the plan above: Phase 2 cancel for groups A + D, delivered automatically after the
  mirror proves Phase 1 Paid and the gate PASSes.
* Groups B, C, F, G and H stay on hold. They need FA/Aware answers, which this approval does not
  supply.

## SAP pickup of the Phase 1 file
* 2026-11-25 16:15 ICT: SAP DOWNLOAD_GCS_FILE `success` for
  `RCB_MOTOR/INSURANCE_RCB_05_MANUAL_REFUND_PAID_RCL_20261125_000000000000.csv` (Gmail msg 1a211fcc7333f9c1).
* As of 16:30 ICT the import result email (Upload LogID) has not arrived. Re-check scheduled.

## Phase 1 import RESULT
* Upload **LogID 23787**, status `success` (no error rows), 2026-11-25 16:32 ICT, Gmail msg 1a2120c52da5d7f9.

## Phase 2 CANCEL delivered 2026-11-25 (Boat: "ไม่ต้องรอพรุ่งนี้ค่ะ ทำเลย")
* Proof of Paid = SAP import LogID 23787 success. The mirror refresh was not awaited, on Boat's
  explicit instruction.
* Snapshot: `sap_integration_v3.diag_manual_refund_phase2_20261125`, 58 rows / 8 items, job
  `job_Wa7Zvvg6fkbgFuObN86_Oeml04eS`.
  * 7 Phase-1 items: full spine `Cancelled`, rows identical to Phase 1 except status and BatchRunDate.
  * L78637687-M1: `Cancelled (Change order / Rejected)`; old side of change order L80756545;
    InvoiceNo = SAP Paid.
* Gate G01–G13 PASS:
  * contract;
  * no NULL;
  * full spines;
  * status vocabulary;
  * InvoiceNo equal to SAP;
  * none already cancelled;
  * dates;
  * CareOS cancelled;
  * change-order routing.
* Blank PaymentDate and Method on cancelled Pending periods matches what SAP has accepted
  historically: 7,767 of 10,968 C# rows since 2026-10-01.
* Files:
  | copy | path | job |
  |---|---|---|
  | archive | `gs://rcb-bronze-zone/sap-interface-archive/manual/refund/2026/11/25/MANUALREFUND-CANCEL-20261125/INSURANCE_RCB_07_MANUAL_REFUND_CANCEL_20261125_000000000000.csv` | `job_OZPcT2xVwMkIPT5eK-rWTkZYff4Q` |
  | production | `gs://interface-file/RCB_MOTOR/INSURANCE_RCB_07_MANUAL_REFUND_CANCEL_20261125_000000000000.csv` | `job_QY3oIVAUROiLyqpbt4oQ_ol5vkOp` |
* Read-back (`job_taxASe9IaaY194MBQCJnOR-AVpLj`): both 59 lines, identical (sorted SHA `b436fa11…`).
* Pending: the SAP import email for this file.

## Group F: complete the RCL spine (Boat 2026-11-25: "เรานำเข้าให้ครบงวด")
* Items: L77833033-V1, L80511750-V1, L80513404-V1, L80518454-V1.
* Method: the LogID 21178 fix, i.e. a NEWPAYMENT file with the full 1..N spine.
  * Period 1 is mirrored from SAP: InvoiceNo, PaymentDate, Method, Channel and RefOrder verbatim.
    This avoids `Cannot change InvoiceNo`.
  * Periods 2..N are Pending from `sap_dashboard_carepay_installment`, with financials identical
    to SAP's period 1.
* Snapshot: `sap_integration_v3.diag_manual_rcl_spine_complete_20261125`, 29 rows / 4 items, job
  `job_K776IrauuE5lLFvI24ly-ytg_wVi`.
* Gate PASS:
  * contract;
  * no NULL;
  * spine 1..N with only period 1 Paid;
  * period 1 = SAP (InvoiceNo, PaymentDate, Actual);
  * Pending blanks;
  * dates;
  * no CareOS charge in periods 2..N;
  * ΣExpected = TotalAmount − Discount (L80518454: 22,211.23 − 666.34 = 21,544.89; L77833033 off
    by 0.02 rounding).
* Archive written: `.../manual/refund/2026/11/25/MANUALRCL-SPINE-20261125/INSURANCE_RCB_06_MANUAL_RCL_SPINE_COMPLETE_20261125_000000000000.csv`
  (job `job_VoTDKX3rpnFBjTT3KLBlwPCB1-RD`, 30 lines).
* The production EXPORT was refused with "destination is not empty".
  * `EXPORT DATA overwrite=false` checks the folder, and `RCB_MOTOR/` still held the not-yet-pulled
    `INSURANCE_RCB_07_MANUAL_REFUND_CANCEL_20261125` file.
  * `overwrite=true` was NOT used, because it could delete pending production files.
  * Retry once SAP has pulled the cancel file.
* Next step for these 4 items, after SAP accepts the spine: cancel as
  `Cancelled (Change order / Rejected)`. They are the old side of change orders L80407934,
  L80532206, L80540087 and L80540467.

## Group F cancel prepared (Boat 2026-11-25: "ส่ง file cancel เข้าไปได้เลยค่ะ ด่วนเลย ขอแค่ลำดับชื่อไฟล์ เรียงตามลำดับ paid ก่อนแล้ว cancel")
* Cancel snapshot: `sap_integration_v3.diag_manual_rcl_spine_cancel_20261125`, 29 rows.
  * Rows are identical to the spine snapshot except TransactionStatus
    `Cancelled (Change order / Rejected)` and BatchRunDate.
  * All 4 items are confirmed old side of a change order (L80407934, L80532206, L80540087, L80540467).
  * No NULLs; 0 rows already cancelled in SAP.
* Archive written: `.../MANUALRCL-SPINE-CANCEL-20261125/INSURANCE_RCB_07_MANUAL_RCL_SPINE_CANCEL_20261125_000000000000.csv`
  (job `job_71iSBsVBbuZ0FRilIMU1Qr5eNxO1`).
* Ordering:
  * Names sort `INSURANCE_RCB_06_…SPINE_COMPLETE` before `INSURANCE_RCB_07_…SPINE_CANCEL`.
  * Delivery is also sequential, because EXPORT DATA (overwrite=false) cannot write into a
    non-empty folder and SAP pulls hourly at :15.
  * Planned slots:
    | file | written | SAP pull |
    |---|---|---|
    | spine | ~17:19 | 18:15 |
    | cancel | ~18:18 | 19:15 |

## Group F spine DELIVERED (Boat: "ส่ง ไฟล์ cancel ด่วนค่า ไม่ต้องรอ")
* The folder was empty after SAP's 17:15 pull of the refund cancel file. The spine was written
  immediately:
  `gs://interface-file/RCB_MOTOR/INSURANCE_RCB_06_MANUAL_RCL_SPINE_COMPLETE_20261125_000000000000.csv`
  (job `job_e619kXX7xYnd5oSnMubz9PQoTqPg`).
* Read-back is identical to the archive: 30 lines, sorted SHA `f893a5fc…`
  (job `job_oB7Z5rE56cbgV56bmy2QHWW9MJe6`).
* The cancel was not sent first. SAP rejects a cancel when the spine is incomplete
  (`Cancelled must be end to TotalPeriod`, as in nightly 07 LogID 23765).
* Cancel file scheduled for about 18:18, after SAP's 18:15 pull of the spine.

## Refund cancel REJECTED, then retry (2026-11-25 17:31)
* `INSURANCE_RCB_07_MANUAL_REFUND_CANCEL_20261125`: LogID **23791**, status `error`, whole file:
  `Row#This entry already exists in the following tables (ODBC -2035)`.
* Root cause: L78637687-M1.
  * Its InvoiceNo `chrg_6876a79qa0rpfs9iwd0` and PolicyNo `W19DVF-005-000` are Paid on the active
    item L80756545-M1.
  * This is the same cause Boat explained to Aware on 2026-10-27.
  * Live `RCB_Motor_process_2_cancel_new` excludes such rows (final NOT EXISTS on stg_sap_state).
    The manual files did not apply this guard. **Lesson: always apply the cancel_new
    shared-invoice/policy guard to manual cancels.**
* The same guard also blocks L77833033-V1 (shares invoice and PolicyNo `DW-70-68/018878` with
  Paid L80407934-V1).
* Retry snapshot: `sap_integration_v3.diag_manual_cancel_retry_20261125`, 80 rows / 10 items.
  * 7 refund items: `Cancelled`.
  * L80511750-V1, L80513404-V1, L80518454-V1: `Cancelled (Change order / Rejected)`.
  * Guard hits = 0; full spines.
* Archive: `.../MANUALCANCEL-RETRY-20261125/INSURANCE_RCB_07_MANUAL_CANCEL_RETRY_20261125_000000000000.csv`
  (job `job_9V-PF2dVVSdZPJP_YgjjIHLD398R`).
* Production write is scheduled for ~18:18, after SAP's 18:15 pull of the spine file.
* HOLD for Aware (manual JV, like the 27 Oct advice): L78637687-M1 and L77833033-V1. Each old
  document's charge and policy carry over to an active new order.

## Draft reply to Mo (not sent; Boat sends herself)
โม อัปเดตรายการ urgent_refund to cust ค่ะ

**สรุป:** ส่ง Paid เข้า SAP แล้ว 7 รายการ ส่วน cancel จะเข้ารอบ 19:15 คืนนี้ (รอบแรกโดน SAP reject ทั้งไฟล์ เลยส่งใหม่) และมี 2 รายการที่ต้องให้ Aware ทำ JV แทนค่ะ

**1. Paid เข้า SAP แล้ว (LogID 23787, 16:32) / Cancel เข้ารอบ 19:15**
L80731453, L80776827, L80991399, L81017535, L81058304, L81072618, L81131068

**2. เติมงวดให้ครบแล้วค่อย cancel (ไฟล์ครบงวดเข้ารอบ 18:15 / cancel เข้ารอบ 19:15)**
L80511750, L80513404, L80518454

**3. มีใน SAP ครบอยู่แล้ว (Paid + Cancelled) รบกวนเช็ค JE ฝั่ง SAP/Aware**
L78637687-V1, L78773608-V1, L79949677, L81085876-V1

**4. ต้องให้ Aware ช่วย (ส่ง cancel ผ่าน interface ไม่ได้)**
L78637687-M1 และ L77833033-V1: charge และเลขกรมธรรม์ถูกใช้ต่อใน order ใหม่ที่ยัง active (L80756545-M1, L80407934-V1) SAP เลยขึ้น error ODBC -2035 รบกวนให้ Aware ทำ manual JV เหมือนเคสวันที่ 27 ต.ค. ค่ะ

**5. รอโมยืนยัน**
- L80992193-M1, L78773608-M1: ใน CareOS ยังไม่ได้ยกเลิก ต้องยกเลิกใน CareOS ก่อนไหมคะ
- L80568487 (M1/V1): ใน SAP มีแต่รายการ Cancel ไม่มี Paid รบกวนเช็คกับ Aware
- L81096435-V1: ข้อมูลงวดซ้ำ และยอด refund 8,199.98 มากกว่ายอดที่จ่าย 6,444.86 พี่โบ๊ทกำลังตรวจสอบ
- L81085876-M1: ยังไม่อยู่ใน SAP จะส่งรอบถัดไปค่ะ

ผลทั้งหมดจะเห็นใน SAP หลัง import วันนี้ พรุ่งนี้เช้าพี่โบ๊ทจะยืนยันสถานะอีกครั้งค่ะ

## CANCEL RETRY WRITTEN 2026-11-25 18:18–18:20 ICT (scheduled task trig_01AMZhi897mtE75nsew6QbEA)

* Timing rule (Boat 25 Nov): files must be in place before :15. This file targets the **19:15 ICT pull**;
  the result email is expected around 19:32.
* Pre-check: `gs://interface-file/RCB_MOTOR/` was empty. SAP downloaded the spine file at 18:15
  (DOWNLOAD_GCS_FILE success, email 18:15:05).
* EXPORT DATA (overwrite=false) job `job_D3CtJNhMrgUec6jlvfdkICVXfpqP` wrote
  `gs://interface-file/RCB_MOTOR/INSURANCE_RCB_07_MANUAL_CANCEL_RETRY_20261125_000000000000.csv`.
* Read-back: prod 81 lines = archive 81 lines. Sorted-line SHA-256 for both is
  `f3787506a2f4bfffdb189cd7be67023754dc053d14d751189baffc3705e9991b` (**match**).
* Spine import result (INSURANCE_RCB_06_MANUAL_RCL_SPINE_COMPLETE, pulled 18:15) is **not in yet** as of
  18:20. Because the cancel is written without waiting (Boat), SAP may reject L80511750, L80513404 or
  L80518454 if the spine failed for them.

## V2 Expected=0 rows: Settlement gap (Boat 2026-11-25 ~18:40 "Fix to all same problem")

* Ning reported that L81070149-V2 and L81088877-V2 show in Insurance Search but not in Settlement.
  Aware advises: cancel them, then resend with corrected Actual/Expected (shown in Ning's image, which BI
  has not seen).
* All 24 auto-recovered Credit Shell V2 items (BatchRunDate 14/16 Nov) have 2 invoice rows. One row has
  Expected = the full amount; the other has Expected 0.00 and Actual > 0. Expected and Actual totals
  match for every item.
* **Caveat:** the same "second row Expected 0" layout appears on about 330 other two-row orders in
  Oct–Nov: 184 Credit Shell V1, about 140 DPM and 9 M1. Expected 0 may not be the cause on its own,
  or those orders may be missing from Settlement too. **Needs confirmation from Ning/Aware.**
* Prepared, NOT written: `sap_integration_v3.diag_manual_cancel_v2fix_20261125`.
  * 24 items / 48 rows, cancel_new transforms.
  * Guard hits 0; none already C#-cancelled.
* Blocked on:
  1. The target Expected/Actual per invoice row (Aware's image).
  2. The OrderItem version for the resend: V2 again after the C# cancel, or V3.
  3. Whether the 184 V1 / DPM orders with the same layout are in Settlement.
* The cancel goes out only together with a confirmed resend, so SAP never has no AP for these items.
* The 9 unfixed V1 items (L81064262 etc.) are held. Cancelling them now would make the live view
  generate V2s with the same Expected 0 layout at 01:30.

## Boat decision 2026-11-25 ~18:40: V2 with 2 rows is correct; fix the unfixed items via V2

* Boat ruled that a -V2 with 2 rows whose Actual and Expected totals match is **correct**.
  * Do not cancel it. Do not create a -V3.
  * `diag_manual_cancel_v2fix_20261125` is therefore **not used**.
* Fresh scan (Credit Shell, TotalPeriods 1, all Paid rows Expected 0, -V1, no C#, no -V2):
  * **9 items from Oct–Nov 2026.** Cancel prepared as `diag_manual_cancel_v2recovery_20261125`.
    * 10 rows: L81162612 has 2 invoices.
    * Guard hits 0; no blanks.
    * Archive written: MANUALCANCEL-V2RECOVERY-20261125 (job_uqigclV0_Aa_R_57qzPFBmOguhNZ).
    * Production write is scheduled for 19:18 and targets the **20:15 pull** (trig_01FBu3bUmQ1fwhU1SP5J2r7n).
    * Items: L80984159, L80992862, L81005458, L81036453, L81064262 (Ning's list), L81088939, L81105944, L81130736, L81162612.
  * **L81095660-V1:** cancel accepted today (LogID 23778). V2 follows automatically.
  * **20 items from Jan–Sep 2026, not touched.** These are earlier accounting months. Some are the new
    side of change-order pairs (e.g. L79866100 vs cancelled L79865677). They need Boat's decision.
    * L79422101, L79601154, L79804748, L79866100, L79890839, L80017728, L80137711, L80228034, L80229909,
      L80235140, L80242096, L80255101, L80261098, L80321229, L80328964, L80489722, L80512595, L80561105,
      L80719790, L80961113.
  * **11 items from 2025:** out of scope (2025 = cancel only).
* V2 timing: cancel imported 20:15 → 26 Nov extract/mirror → V2 on the 27 Nov 01:30 run (expected).

## V2-RECOVERY CANCEL WRITTEN 2026-11-25 ~19:19 ICT (trig_01FBu3bUmQ1fwhU1SP5J2r7n)
* Target: the **20:15 ICT pull**. The result email is expected around 20:32.
* Pre-check: the folder was empty (the retry file was pulled at 19:15).
* EXPORT job `job_aGRxpJJ2dttltqTq1oF-mMch6ktC` (overwrite=false) wrote
  `gs://interface-file/RCB_MOTOR/INSURANCE_RCB_08_MANUAL_CANCEL_V2RECOVERY_20261125_000000000000.csv`.
* Read-back: prod 11 lines = archive 11 lines. Sorted-line SHA-256
  `2ba0d6ff170f4a5df41aace68ffd4c22462413e4887abdc1cb4a36fe7a597018` (**match**).

## SAP RESULTS 2026-11-25 (checked 19:36 ICT)
* **Spine:** `INSURANCE_RCB_06_MANUAL_RCL_SPINE_COMPLETE_20261125`
  * Downloaded at 18:15. Upload **LogID 23793 = success** (email 18:31).
  * The full spine is now in SAP for L80511750, L80513404 and L80518454.
* **Cancel retry:** `INSURANCE_RCB_07_MANUAL_CANCEL_RETRY_20261125`
  * Downloaded at 19:15. Upload **LogID 23794 = success** (email 19:32). No rejected rows.
  * The 7 refund items plus L80511750/L80513404/L80518454 are cancelled in SAP.
  * Still held: L78637687-M1 and L77833033-V1 (manual JV by FA/Aware).

## V2-RECOVERY CANCEL RESULT (checked 20:36 ICT)
* `INSURANCE_RCB_08_MANUAL_CANCEL_V2RECOVERY_20261125`: downloaded 20:15, Upload **LogID 23795 = success**
  (email 20:31). No rejected rows.
* All 9 V1 items are cancelled in SAP.
* Expected: V2 is re-sent automatically by the live recovery once the mirror shows the cancels.
  * The import finished around 20:31, close to the 20:30 extract, so the V2 should come on the
    26 Nov 01:30 run or the 27 Nov 01:30 run.
  * The 26 Nov 10:41 check confirms which.

## Manual V2 and view hold (Boat "Deploy ok Granted", ~21:00 ICT)
* The manual V2 for the 9 items stopped before any write. The V2 rows built with the live
  `RCB_Motor_process_3_change` logic (table `diag_manual_v2recovery_paid_20261125`) had matching
  Expected/Actual totals for **only L81162612**.
  * L80984159, L81005458, L81036453, L81064262, L81105944 and L81130736 do not match. Three of them
    differ by exactly the CMI amount.
  * L80992862 and L81088939 produce no rows. They are held or out of scope; cause not checked.
  * Details are in BigQuery. The figures are kept out of this doc.
* **Manual V2 sent: L81162612-V2** (3 rows).
  * Gate: 56 columns, no NULL keys, not in SAP yet, shared-invoice guard 0.
  * Archive `MANUALV2-L81162612-20261125`, then production
    `INSURANCE_RCB_09_MANUAL_V2_L81162612_20261125_000000000000.csv`, written 21:01 for the **21:15 pull**.
  * Read-back: 4 lines; SHA `93e9d758…afca` matches the archive.
* **View hold deployed** on `sap_view.RCB_Motor_process_3_change`:
  * Added `AND base.OrderItem NOT IN (<9 V1 items>)` after the held_items filter.
  * Test copy `sap_integration_v3.diag_view_rcb_motor_p3_hold_test`: 1,198 rows with the same
    fingerprint as live.
  * SHA old `ed56e174…2231` → new `5e4acd5d…c79d`. The deploy was guarded by `newdef = testdef`.
  * Rollback: recreate the view with the HOLD comment and NOT IN line removed. That yields SHA `ed56e174…`.
* **Open:** FA must confirm the correct Actual split for the 8 held items (CMI double count?),
  then they are sent manually and the hold is removed.
* **L81162612-V2 result:** downloaded at 21:15. Upload **LogID 23796 = success** (email 21:31). No rejected rows.
