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
