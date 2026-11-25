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
