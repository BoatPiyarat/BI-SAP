# SAP V2 Daily Event Assurance — 2026-09-10

Run time: 2026-09-10 17:31–17:46 ICT  
Scope: every CarePay charge whose status is `SUCCESSFUL` and whose effective charge timestamp is in 2026  
Charge grain: `charge_id`  
SAP obligation grain: `(charge_id, OrderItem, Period, obligation_role)`; InvoiceNo/charge identity is checked exactly  
Mode: read-only; no view replacement, interface execution, SAP mutation, or deployment

## Executive result

The SAP-first baseline checked **266,613 distinct successful charges** representing
**THB 1,412,250,098.44** and allocated them into **309,114 SAP obligations**. Amount is counted once
at charge-header grain and is never summed across V1/M1 allocation rows.

Sixty obligations / 52 charges were absent from SAP and required live-view verification. One
previously registered MS-06 obligation was reviewed separately. Exact route-specific checks resolved
57 obligations as present in a live legacy view. The remaining four are:

- three obligations absent from both SAP and their live owner view (two MS-05, one MS-06);
- one bundled-order allocation ambiguity, held rather than called missing.

Because immutable exporter/pickup/import-cycle evidence is unavailable, this report uses
`MISSING_FROM_SAP_AND_LIVE_VIEW`; it does **not** claim `CONFIRMED_MISSING` or delivery failure.

## Transactions absent from SAP and live owner view

| Scenario | OrderItem | Period | InvoiceNo | charge_id | transaction_id | Charge amount | Event time | Root evidence | Next action |
|---|---|---:|---|---|---|---:|---|---|---|
| MS-05 | `L80738381-M1` | 1 | `2_chrg_689hydn4u3coof2wrnz` | `b84c3ff8-7476-4bcf-98ab-acce602d69c1` | `a6a1eaa9-a3bf-4c90-82cd-a401ed55343b` | THB 2,025.92 | 2026-07-07 08:38:33 | Exact 1/1 M1 row exists in `sap_dashboard_carepay_installment`; live `RCL_Motor_process_1_create` drops it | Covered by prepared MS-05 wrapper fix; deploy decision remains human |
| MS-05 | `L80767177-M1` | 1 | `2_chrg_68iihm14piwxqb96ik6` | `a045f8a0-c17d-45d0-8ab0-4f3e3f9b4510` | `184d429b-6198-414e-96bf-ad9c520e1820` | THB 2,085.21 | 2026-07-30 11:37:06 | Exact 1/1 M1 row exists in `sap_dashboard_carepay_installment`; live wrapper drops it | Covered by prepared MS-05 wrapper fix; deploy decision remains human |
| MS-06 | `L80161278-M1` | 1 | `2_chrg_67i5i9355dpxs2imp64` | `32c8435c-047a-4496-8cf6-ce8fe52b77b8` | `5b281a9d-eec8-46f1-a7ff-53bee2d33f63` | THB 645.21 | 2026-04-28 10:43:50 | `FULL_PAYMENT` + successful `RABBIT_LENDING`; absent from installment dashboard and live wrapper | Upstream no-detail compulsory fallback still pending; do not broaden FULL_PAYMENT generally |

For MS-05, the charge amount is the payment-event header, not the M1 allocation amount. The
dashboard M1 payload carries ActualReceived THB 645.21. This is why header amount and allocation
amount must remain separate.

## Held exception — not counted as missing

| OrderItem | Charge/event | Finding | Disposition |
|---|---|---|---|
| `L80830168-M1` | `7dcec9aa-9d3c-4442-b932-0a544a9a399e` / `chrg_68yjco49s3xtzcyje82` | The live RCB view has a paid M1 row, but InvoiceNo is `1_L80830168-M1`; the transaction has two successful charges and two Motor items. The same charge invoice appears on V1. | `QUARANTINE_ITEM_ALLOCATION`; do not call missing or rewrite InvoiceNo until bundled-charge allocation is approved |

## Candidates proven present in a live interface

| Route check | Candidate obligations | Exact in owner view | Exceptions |
|---|---:|---:|---:|
| `RCB_Motor_process_create` | 36 | 34 | 2 |
| `RCB_NonMotor_process_1_create` | 15 | 15 | 0 |
| `RCL_Motor_process_1_create` M1 | 10, including MS-06 | 7 | 3 |
| `RCB_Motor_process_4_creditshell` reroute | 1 | 1 | 0 |

The apparent RCB Motor miss `L80822481-V1` is a change order. It is present exactly in
`RCB_Motor_process_4_creditshell` with InvoiceNo `chrg_68xv0010q7so946clx2`, RefOrder
`L80816744`, and ActualReceived THB 13,500.19; it is not a missing transaction.

## 2026-09-13 addendum — L80570468-1 pre-import route check

`L80570468-1` is not a missing scenario. The current legacy candidate is present as ten rows in
`sap_view.RCL_Motor_process_4_creditshell`; SAP_LIVE_FULL has zero rows for the item. Although the
view name contains `Motor`, this order is a Health/NonMotor full-replacement CreditShell order and
the legacy view intentionally covers it.

At event grain `(OrderItem, Period, InvoiceNo/charge_id)`, Period 1 is the only paid event:

- `charge_id=d3041b01-b51b-4a7f-98f6-53344a0801ec`
- `InvoiceNo=chrg_68frsuoix39jxov3exv`
- raw route `QR_CODE / RABBIT_LENDING`
- `payment_option=RABBIT_CARE_INSTALLMENT`, `RefOrder=L79849357`
- final method/channel `RCL-Credit Shell / RCL-Credit Shell`

This is the valid RCL CreditShell override for both Motor and NonMotor; the normal Health QR label
`RCL-Omise QR Prompt Pay-Health` applies only when the event is not classified as carried-over
CreditShell. Periods 2–10 are pending and correctly have blank InvoiceNo, PaymentDate,
PaymentMethod, and PaymentChannel. Pre-import disposition: `PASS`; no query change is required.
If an operational interface list still omits this item, investigate the list/export snapshot or
its selected view set, not the current BigQuery candidate logic.

## 2026-09-13 addendum — split Motor/NonMotor CreditShell payment routing

`L80700230-1` reproduced a second-period Health routing defect in
`sap_view.RCL_Motor_process_4_creditshell`. Period 1 is a valid carried-over payment and correctly
uses `RCL-Credit Shell`; Period 2 is a new successful QR/RABBIT_LENDING event but the legacy
upstream labelled it `RCL-Omise QR Prompt Pay-BAY`. The correct NonMotor label is
`RCL-Omise QR Prompt Pay-Health`.

The same reproduction also confirmed both paid dates were before the current month:
`13072026` and `30082026`. Under the approved posting-date rule, both become `01092026`; pending
Periods 3–10 keep PaymentDate, PaymentMethod, and PaymentChannel blank.

A full SELECT-only legacy wrapper proposal now branches by InsuranceGroup: Motor is preserved,
Health/TA paid OME QR rows receive the Health channel, and unknown labels are preserved without
guessing. The population regression kept 94/94 rows, changed no Motor non-date payload, left zero
bad NonMotor QR channels, zero old paid dates, and zero populated pending payment fields. No live
view replacement or interface execution was performed.

## Evidence jobs

| Purpose | BigQuery job | Result |
|---|---|---|
| SAP-first 2026 event baseline | `bqjob_r7c6046823feb0ffb_000001a08adedb07_1` | PASS; 266,613 charges, 60 SAP-absent candidate obligations |
| RCB Motor owner-view check | `bqjob_r19ffc17afb2c9563_000001a08ae4f25e_1` | 34 exact / 2 exceptions |
| RCB NonMotor owner-view check | `bqjob_r29e960e66d4b7cfd_000001a08ae5080c_1` | 15 exact / 0 exceptions |
| RCL Motor M1 owner-view check | `bqjob_r4dba73d0f7b1a5e6_000001a08ae4f4fd_1` | 7 exact / 3 missing |
| RCB exception root trace | `bqjob_r436dd58b7621e38a_000001a08ae98308_1` | Change route + bundled-charge ambiguity proven |
| RCL M1 root trace | `bqjob_r301bda4e766dc9e9_000001a08ae98593_1` | MS-05 upstream rows and MS-06 upstream absence proven |
| Change/CreditShell exact check | `bqjob_r1e0238214f036e65_000001a08aeb317a_1` | `L80822481-V1` exact in CreditShell |
| L80570468 route and full-spine trace | `bqjob_r16648ac5e08c6e04_000001a099948e98_1` | PASS; 1 paid CreditShell event + 9 pending rows, periods 1–10 complete |
| L80700230 RED reproduction | `bqjob_r15e5dd0cac4475d1_000001a099a5172d_1` | RED; Period 2 wrong BAY channel, Periods 1–2 old PaymentDate |
| Motor/NonMotor candidate regression | `bqjob_r9475c9e5dd7fa3e_000001a099a9d611_1` | PASS; 94/94 rows, target Periods 1–2 green, zero contract violations |

An attempted all-12-view monolith, `bqjob_r15a39831e027f1ee_000001a08ad72966_1`, was stopped by
the 20 GiB billing cap before returning a result. Daily execution is therefore intentionally split
into SAP-first plus route-specific checks.

## Daily operating format

Publish these blocks every day:

1. Charge conservation: successful charge count and amount, counted once by `charge_id`.
2. Obligation conservation: count by owner/BU/role at `(charge_id, OrderItem, Period, obligation_role)`.
3. `IN_SAP_EXACT` and `SAP_TERMINAL_CANCELLED` summary.
4. SAP-absent candidates, then exact owner-view verification by InvoiceNo/charge identity.
5. `MISSING_FROM_SAP_AND_LIVE_VIEW` list with charge_id, transaction_id, OrderItem, Period,
   InvoiceNo, charge amount/time, scenario, owner, and next action.
6. Quarantine list for source identity, route, bundled allocation, payload, cancellation, or SAP
   identity conflict. Never mix quarantine into missing.
7. Delivery caveat: upgrade to `CONFIRMED_MISSING` only when an immutable completed export ->
   pickup/import -> post-import SAP-extract cycle is available and fresh.

## Progress checklist

- ✅ Event-level assurance contract documented
- ✅ Every 2026 SUCCESSFUL charge checked at `charge_id` grain
- ✅ SAP obligations allocated at charge + item + period + role grain
- ✅ SAP exact InvoiceNo/status check completed
- ✅ SAP-absent candidates checked against their live owner views
- ✅ Change/CreditShell false positive removed
- ✅ Bundled-charge ambiguity held fail-closed
- ✅ Daily missing-transaction format prepared
- ✅ `L80570468-1` Health/NonMotor CreditShell route checked before import
- ✅ Motor/NonMotor CreditShell routing split prepared and regression-tested
- ✅ First-of-current-month PaymentDate rule added to the proposal
- ⏳ MS-05 live deployment decision
- ⏳ MS-06 full upstream legacy fix query
- ⏳ Immutable delivery/pickup/import evidence for true `CONFIRMED_MISSING`
- ⏸ MS-03 NULL `cancel_time` human investigation
