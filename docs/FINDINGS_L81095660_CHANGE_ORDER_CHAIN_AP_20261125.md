# FINDINGS: L81095660-V1 has no AP; the change-order chain is not reconciled in SAP

Date: 2026-11-25 ICT. Author: Claude Code (read-only). Class A (FA numbers).
Status: **STOPPED: needs FA/Boat decisions.** Nothing has been written to SAP or GCS.

* Request: Boat relayed Ning's report (Teams, 2026-11-23 17:16 ICT), "Order L81095660-V1 ไม่ถูกบันทึก AP",
  and asked to cancel the item and re-import it as V2 correctly.
* Method for this symptom, from Aware via Gift (Teams, 2026-11-10): cancel the item, then re-send
  the file with corrected ActualReceived and ExpectedReceived.

## Evidence
Sources: `sap_integration_v2.SAP_LIVE_FULL` (latest load UpdateDate 2026-11-24) and CareOS
(`careos_orders`, `careos_order_items`, `carepay_charges`, `cancelled_change_orders`, price summaries).

### Change-order chain in CareOS
`L78968613` → `L81069428` → `L81095660`

* All three share the same two charges: `chrg_69c77zaycoo18hbfile` (13,580.00) and
  `chrg_69eypk9sjiaju3h2dcc` (1,455.02). Total cash = 15,035.02.
* L78968613 and L81069428 are `is_cancelled = true` in CareOS.
* No `carepay_refunds` row exists on any of the 3 transactions.

### State in SAP
| item | status in SAP | InvoiceNo | TotalPremium | Expected | Actual | channel | notes |
|---|---|---|---|---|---|---|---|
| L78968613-V1 | **Paid** (not cancelled) | chrg_69c77… | 14,000.00 (disc 420) | 13,580.00 | 13,580.00 | RCB-Omise QR Prompt Pay-BAY | |
| L81069428-V1 | **Paid** (not cancelled) | chrg_69eypk9… | 15,500.02 (disc 465) | 0.00 | 1,455.02 | Credit Shell | RefOrder L78968613 |
| L81095660-V1 | Paid | chrg_69eypk9… (**same invoice**) | 9,900.00 | 0.00 | 1,455.02 | Credit Shell | RefOrder L81069428; ApprovalStatus PENDING; **PolicyNo empty** |

CareOS state of L81095660-V1: `policy_number = 12967-69003/กธ/023077`, `POLICY_UPLOADED`,
insurer 27 (VRY-27), Type 2+, gross 9,900.00, net 9,215.34.

### Probable cause of the missing AP (INFERRED, not confirmed by FA)
V1 entered SAP on 27 Oct with ApprovalStatus PENDING, no PolicyNo, and Expected = 0. The legacy
path never updates a row once it is in SAP. This matches the four 14–16 Nov V2 precedents:

| precedent | pattern |
|---|---|
| L81099721 | V1 = top-up only, PENDING; V2 = one row per charge, POLICY UPLOADED, PaymentDate rolled to 01112026 |
| L81104965 | same |
| L81105450 | same |
| L81135161 | same |

## Money issues (do not fix without FA)
1. **Cash posted more than once.**
   * The 1,455.02 charge is posted as Actual on both L81069428-V1 and L81095660-V1 (same InvoiceNo).
   * The 13,580.00 charge sits on L78968613-V1.
   * Neither earlier item is cancelled in SAP.
2. **Customer overpaid.**
   * Final premium is 9,900.00, against 15,035.02 cash.
   * Difference 5,135.02 = 15,035.02 − 9,900.00 (L81095660 discount = 0 in CareOS).
   * No refund is recorded in CareOS. FA must say whether this is a refund, a credit shell
     balance, or something else.

## Proposed V2 (DRAFT, figures follow the precedent and are NOT confirmed)
* **Cancel L81095660-V1.** InvoiceNo `chrg_69eypk9sjiaju3h2dcc` stays immutable.
* **L81095660-V2**, Credit Shell, RefOrder L81069428, PolicyNo `12967-69003/กธ/023077`,
  POLICY UPLOADED, TotalPremium 9,900.00, PaymentDate 01112026 (October closed):

  | row | InvoiceNo | Expected | Actual | derivation |
  |---|---|---|---|---|
  | 1 | chrg_69c77zaycoo18hbfile | 9,900.00 | 8,444.98 | 9,900.00 − 1,455.02 |
  | 2 | chrg_69eypk9sjiaju3h2dcc | 0.00 | 1,455.02 | the top-up charge |

* This only balances to 9,900.00 if FA treats 5,135.02 separately.
* L78968613-V1 and L81069428-V1 likely also need Cancelled (change order) rows. **FA decision.**

## Execution constraint
* Writing interface files to `gs://interface-file` is not allowed for Claude Code (AGENT_RULES).
  Execution belongs to Codex, or to Boat's manual path as used for the November V2s.
* The file must pass the pre-export gate.

## CORRECTION 2026-11-25 (supersedes "Money issue 1" and the DRAFT split above)

### Earlier items were already cancelled
My earlier filter `U_OrderID = '<id>'` missed SAP cancel records, which are stored with a `C#`
prefix on U_OrderID. Both earlier items **are already cancelled in SAP**:

| item | cancel record | status | BatchRunDate |
|---|---|---|---|
| L78968613-V1 | `C#L78968613` | Cancelled (Change order / Rejected) | 26102026 |
| L81069428-V1 | `C#L81069428` | Cancelled (Change order / Rejected) | 27102026 |

* Only L81095660-V1 is live (Paid).
* There is no double-counted cash.

### Exact precedent: L81135161
| step | what happened |
|---|---|
| chain | L78815384 → L81134119 → L81135161 |
| V1 cancel | `C#L81135161`, TransactionStatus `Cancelled` (plain), all other fields = the V1 row, BatchRunDate 10112026 |
| V2 (16112026) | one row per charge; ActualReceived = that charge's real amount; ExpectedReceived = TotalAmount − Discount on the original-charge row (0 on the top-up row); PolicyNo + POLICY UPLOADED filled; PaymentDate rolled to 01112026 for the closed-month charge; ExpectedDate = charge date; RefOrder unchanged |

### Corrected V2 for L81095660 (replaces the 8,444.98 split)
| row | InvoiceNo | Expected | Actual | PaymentDate | ExpectedDate |
|---|---|---|---|---|---|
| 1 | chrg_69c77zaycoo18hbfile | 9,900.00 | 13,580.00 | 01112026 | 14102026 |
| 2 | chrg_69eypk9sjiaju3h2dcc | 0.00 | 1,455.02 | 01112026 (21 Oct falls in a closed month) | 21102026 |

### Remaining money issue
* Actual 15,035.02 vs Expected 9,900.00 means the customer is over by **5,135.02**.
* No CareOS refund exists. FA must handle the refund. This does not block V2.
* Boat decided on 2026-11-25: cancel the old item and import V2.

## EXECUTED 2026-11-25 ~10:50 ICT: manual CANCEL file for L81095660-V1 (Boat approval in session)

### Method
* The live production view `sap_view.RCB_Motor_process_3_change` already contains the V2-recovery
  rule (FIX 2026-11-10, Boat). That rule re-sends a Credit Shell item as `-V2` once all of these hold:
  * its V1 is `Cancelled` in SAP with BatchRunDate on or after 2026-11-10;
  * its Paid rows have Expected = 0;
  * no later change order exists.
* This rule produced the November V2 precedents. So only the V1 cancel was written by hand; V2
  follows automatically.

### Cancel snapshot
* Snapshot table: `sap_integration_v3.diag_manual_cancel_l81095660_20261125` (expires +14d).
  Built by `sql/adhoc/20261125_manual_cancel_L81095660_V1.sql`, job `job_jPEwc7OcQiztpVG_nkPOc3Mlat8a`.
* The row is the stored SAP row put through the live `RCB_Motor_process_2_cancel_new` transforms:
  * TransactionStatus `Cancelled`;
  * InsurerCode prefix split;
  * `Credit Shell` → `RCB-Credit Shell`;
  * BatchRunDate 25112026.

### Gate
G01–G14 PASS:
* single row;
* 56-column contract match (name, position, type);
* no NULL or "NULL";
* DDMMYYYY dates;
* status vocabulary;
* InvoiceNo = stored SAP value;
* 2-decimal money;
* PolicyNo ≤ 50;
* RCB/Motor only;
* spine 1/1;
* Paid predecessor exists and is not yet cancelled;
* other columns match the SAP row;
* V2-recovery preconditions hold.

### Files written (identical content, SHA-256 of lines `3e95be61a48974faa79d19053de9cdbac3539d2396d9a91e1acf0074394f4366`)
| copy | path | job |
|---|---|---|
| archive | `gs://rcb-bronze-zone/sap-interface-archive/manual/cancel/2026/11/25/MANUALCANCEL-L81095660-20261125/INSURANCE_RCB_02_MANUAL_CANCEL_L81095660_20261125_000000000000.csv` | `job_lFGfjsWSPkU9ZfrrBXUGbed0zPGm` |
| production | `gs://interface-file/RCB_MOTOR/INSURANCE_RCB_02_MANUAL_CANCEL_L81095660_20261125_000000000000.csv` | `job_5NTysRieikV6QZWd0k-byBm9l3sw` |

Read-back of the production file (job `job_Rj90SCFlZ46n3c-GtrwAkKt0q4Wf`): 2 lines, LF, exact
56-name header, 56 fields.

### Expected timeline
| when | what |
|---|---|
| ≤15 min after write | SAP pulls the file |
| 25 Nov 20:30 | SAP extract runs |
| 26 Nov 01:00 | load into the mirror |
| 26 Nov 01:30 | `RCB_Motor_process_3_change` auto-sends L81095660-V2 |
| 27 Nov 01:00 | V2 visible in the mirror |

### Follow-ups
* Scheduled check: 26 Nov 10:41 ICT.
* Still open for FA: the customer overpaid 5,135.02 and no refund exists in CareOS.

## SAP IMPORT LOG 2026-11-25: cancel ACCEPTED
* SAP downloaded the file at 15:15 ICT (DOWNLOAD_GCS_FILE success).
* Import result: Upload **LogID 23778**, status `success`, file
  `RCB_MOTOR_INSURANCE_RCB_02_MANUAL_CANCEL_L81095660_20261125_000000000000.csv`.
* Next: the 25 Nov 20:30 extract, then the 26 Nov 01:00 load, then the 26 Nov 01:30 auto V2.
