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
