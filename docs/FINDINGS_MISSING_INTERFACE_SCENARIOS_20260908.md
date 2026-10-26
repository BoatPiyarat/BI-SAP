# Missing SAP interface scenarios — V2 legacy

Status: INVENTORY ACTIVE. MS-01 has a full source-only legacy reuse query; no DDL, deployment,
SAP mutation, or interface execution.

Point-in-time: 2026-09-08 22:10 ICT.

## Status legend

- **CONFIRMED MISSING** — source event exists, current item is absent from SAP, and no legacy
  interface view contains it.
- **SOURCE FIX READY** — missing in live behavior, but a full validated source-only query exists.
- **HUMAN INVESTIGATION** — intentionally excluded until the underlying business timestamp/state
  is confirmed.
- **NOT A MISSING SCENARIO** — intentionally ignored, historical backlog, or no successful payment
  event exists.

## Missing-scenario list

| ID | Scenario | Route/product | Current evidence | Status | Proposed reuse target |
|---|---|---|---|---|---|
| MS-01 | New active order item created from Change/CreditShell predecessor; new order has successful RCB payment but the generic Health create upstream excludes every `cancelled_change_orders.current_human_id` | RCB / NonMotor Health / Change-new-order | 3 items; predecessor is in SAP for all 3; current item is in 0/12 interface views | **QUERY READY** | Reuse `RCB_NonMotor_process_2_cancel`; full SELECT-only query validated |
| MS-02 | Bank `CREDIT_CARD_INSTALLMENT` paid in full to Rabbit Care but excluded by `RCB_HEALTH` because the customer snapshot says 3/6/10 installments | RCB / NonMotor Health / ONETIME create | 23 active items with successful charges; 0 in SAP; 0/12 interface views | **SOURCE FIX READY** | Existing `RCB_NonMotor_process_1_create` via upstream `RCB_HEALTH` fix |
| MS-03 | Item is marked `is_cancelled=true` with Change-completed accounting status, but `cancel_time` is NULL | RCB / NonMotor Health / Change-cancel | 1 item: `L77754975-1` | **HUMAN INVESTIGATION** | Do not assign to a view until the missing timestamp/state is resolved |
| MS-04 | Cancellation occurred in 2026 but original order date is 2023/2024 | RCB / Motor + NonMotor / Cancel | 6 example items representing one general scenario | **SOURCE FIX READY** | Universal `RCB_Motor_process_2_cancel_new` proposal |
| MS-05 | Active compulsory M1 on an RCL Motor installment order has a successful Rabbit Lending charge, but the wrapper requires more than one row and TotalPeriods greater than one even though compulsory M1 is intentionally a one-row 1/1 payload | RCL / Motor compulsory / Create | 249 M1 items / 267 successful charges in the discovery snapshot; 2026-09-10 event assurance reconfirmed exact residuals `L80738381-M1` and `L80767177-M1` upstream but absent from SAP/live wrapper | **SOURCE FIX READY — GREEN** | Fix existing `RCL_Motor_process_1_create`: admit valid M1 1/1 and only charge-proven RCL V1 with a complete schedule |
| MS-06 | Active compulsory M1 has a successful Rabbit Lending charge, but transaction is `FULL_PAYMENT` and the snapshot has no installment detail/follow-up, leaving it outside both RCB fully-paid and RCL installment upstreams | RCL-funded / Motor compulsory / Create | 1 item: `L80161278-M1`; absent from SAP, both dashboards, and all 12 interfaces | **ABSENT FROM SAP/LIVE VIEW; QUERY NEXT** | Root fix `sap_dashboard_carepay_installment` no-detail compulsory 1/1 branch, then widen the prepared create-wrapper route proof to successful Rabbit Lending |

## MS-01 — first confirmed scenario for view reuse

Affected current items:

| Current OrderItem | Current OrderID | SAP predecessor (`RefOrder`) | Payment |
|---|---|---|---|
| `L80720286-1` | `L80720286` | `L80552394` | FULL_PAYMENT; 2 successful DIRECT_PAYMENT charges |
| `L80797823-1` | `L80797823` | `L79287978` | FULL_PAYMENT; 2 successful DIRECT_PAYMENT charges |
| `L80799909-1` | `L80799909` | `L80317736` | FULL_PAYMENT; 1 successful EDC/KRUNGSRI charge |

All three new items have `is_cancelled=false` and `cancel_time=NULL`. They are not cancel payloads.
They are paid replacement/new-order items whose predecessors exist in SAP. The current
`RCB_HEALTH` upstream excludes them solely because their OrderID appears as
`cancelled_change_orders.current_human_id`.

The reserved ownership is now `sap_view.RCB_NonMotor_process_2_cancel`. The full source-only query
is `sql/production/RCB_NonMotor_process_2_cancel_change_create_rootfix_20260908.sql`.

Source-detail job `bqjob_r7b4046b8778a7716_000001a07f9f27e0_1` proved that the three items contain
five distinct successful charges. The two repeated Period 1 cases are legitimate additional
payments: amounts and payment timestamps differ. The candidate therefore keeps all five payment
rows, assigns stable rank-based fallback InvoiceNo values, and sets ExpectedReceived to zero only
on the later charge.

Final shadow job `bqjob_r7611af1cebb05526_000001a07fac1ce9_1` returned exactly five rows:

- `L80720286-1`: 2 Direct Payment rows; ExpectedReceived `10716.00`, then `0.00`;
- `L80797823-1`: 2 Direct Payment rows; ExpectedReceived `11952.00`, then `0.00`;
- `L80799909-1`: 1 EDC/KRUNGSRI row mapped to `RCB-EDC-BAY`.

`L80799909-1` requires a human pre-deployment check: its successful source charge is `3600.00`
while its current TotalAmount is `2160.00`. The query does not rewrite source ActualReceived;
ExpectedReceived remains `2160.00`, preserving the difference for explicit business review.

The query retains the target's exact 56-column order and data types. Its dry-run estimate was
1,730,971,666 bytes. No deployment was performed.

All-view proof job `bqjob_r10e0c16ddf9b93c9_000001a07f285b5a_1` ran from
2026-09-08 10:55:47 to 10:57:32 ICT and processed 11,925,813,141 bytes:

- scoped items: 3;
- NonMotor items: 3;
- successful transaction items: 3;
- items with successful charge: 3;
- current items already in SAP: 0;
- items whose predecessor is in SAP: 3;
- items present in any of the 12 legacy interface views: 0.

Because the first two items have two successful charges, any reused view must preserve distinct
payment identities and apply the confirmed repeated-period rule: only the first scheduled row may
carry ExpectedReceived; a later additional payment at the same period must carry
ExpectedReceived = 0.

Evidence query:
`sql/adhoc/20260908_trace_RCB_NonMotor_change_creditshell_gap.sql`

## Source-ready scenarios not yet live

### MS-02 — RCB Health card installment as ONETIME

Full validated upstream query:
`sql/production/RCB_HEALTH_credit_card_installment_rootfix_20260907.sql`

Final GREEN job: `bqjob_r622445d20c2c7dad_000001a07cd6cd4b_1`. The proposed next interface grows
from 17 to 40 items and includes all 23 missing items exactly once.

### MS-04 — current cancellation with historical OrderDate

Full validated universal-cancel query:
`sql/production/RCB_Motor_process_2_cancel_new_current_cancel_scope_fix_20260907.sql`

Final GREEN job: `bqjob_rcfea64538e1671_000001a07c7fe6ef_1`. The rule is general
`cancel_time >= 2026-01-01`; it is not a six-item allow-list.

## MS-05 — RCL Motor compulsory M1 removed by installment-wrapper cardinality gate

MS-05 is a separate create scenario, not a cancellation and not a new-payment period gap. The
current CareOS order is active, uses `RABBIT_CARE_INSTALLMENT`, and has at least one successful
`RABBIT_LENDING` charge. Its compulsory `MOTOR_TYPE_COMPULSORY` item should be a one-row Period 1 / 
TotalPeriods 1 payload alongside the voluntary installment schedule.

The live upstream `sap_data_engineer.sap_dashboard_carepay_installment` already produces that M1
row. The live wrapper `sap_view.RCL_Motor_process_1_create` then removes it with both conditions:

```sql
QUALIFY
  COUNT(*) OVER (PARTITION BY OrderItem) > 1
  AND TotalPeriods > 1
```

The 2026-09-10 event-level rerun checked exact `(charge_id, OrderItem, Period, InvoiceNo)` identity
and reconfirmed two current residual examples: `L80738381-M1` and `L80767177-M1`. Both have their
exact paid 1/1 row in the dashboard and neither has the row in SAP or the live wrapper. See
`docs/DAILY_EVENT_ASSURANCE_20260910.md`. They are covered by the already-prepared general MS-05
query and do not form a new scenario.

Focused job `bqjob_r7d506e63a5f6a80a_000001a08190eb4a_1` processed 9,391,343,552 bytes and confirmed:

- 249 active, non-Test, 2026-scope compulsory M1 items absent from SAP;
- 267 distinct successful Rabbit Lending charges across those items;
- all 249 have exactly one upstream dashboard row;
- all upstream M1 rows are Period/TotalPeriods 1/1;
- zero of the 249 survive `RCL_Motor_process_1_create`;
- every M1 has a voluntary V1 sibling;
- 216 V1 siblings are already in SAP;
- the other 33 V1 siblings are present in the current create interface.

This rules out ordinary pipeline timing: the voluntary half of every order is covered while the M1
half is systematically filtered. Boat then selected the root-fix direction: retain the existing
`RCL_Motor_process_1_create` ownership and make its final cardinality gate type-aware. Compulsory
M1 is allowed only when Period/TotalPeriods is 1/1; voluntary V1 continues to require multiple rows
and TotalPeriods greater than one. `RCL_Motor_process_3_cancel` therefore remains reserved for a
later missing scenario.

Full source-only wrapper query:
`sql/production/RCL_Motor_process_1_create_compulsory_M1_rootfix_20260909.sql`

Read-only shadow validation:
`sql/adhoc/20260909_validate_RCL_Motor_process_1_create_compulsory_M1_rootfix.sql`

After authentication, the first regression exposed a second root cause upstream: bank
`CREDIT_CARD_INSTALLMENT` transactions without installment details, follow-ups, or a successful
Rabbit Lending charge were expanded into pending V1 rows from the snapshot installment count.
Those rows correctly had blank pending payment identity fields, but ExpectedReceived and
ExpectedDate were NULL.

The wrapper proposal now requires RCL ownership from source facts: payment option must be
`RABBIT_CARE_INSTALLMENT` and the transaction must have at least one `SUCCESSFUL`
`RABBIT_LENDING` charge. A voluntary V1 item is emitted only when its full 1..TotalPeriods spine is
present with a single TotalPeriods value and no NULL ExpectedReceived/ActualReceived or blank
ExpectedDate. No amount or invoice is invented for a missing source row.

Regression job `bqjob_r4daddc19c596ecaa_000001a082c7a673_1` returned PASS. Full candidate job
`bqjob_r23e4a7e5aaa62eb1_000001a082cd32d3_1` returned 260 rows / 251 items, including 250 M1 rows,
with zero incomplete V1, invalid M1, NULL Expected/Actual, blank ExpectedDate, or invalid Pending
payment fields. No deployment was attempted.

Discovery queries:

- `sql/adhoc/20260908_discover_MS05_charge_driven_uncovered.sql`
- `sql/adhoc/20260908_confirm_MS05_RCL_motor_compulsory_wrapper_gap.sql`

## Explicitly not counted as missing

- Two underwriting-rejected Health items without `is_cancelled/cancel_time`: intentionally ignored
  by Boat's decision.
- 1,010 cancellations before 2026: historical backlog outside current scope.
- 29 `RCB_TRAVEL` rows: old PENDING transactions with zero charges and zero successful charges.
- `L80511755-V1`: cancelled CreditShell item intentionally excluded from the active-item source.
- Wrong status/channel/payload defects that still produce an interface row are tracked in their
  root-cause reports; they are not mixed into this missing-row inventory.

## Progress

- ✅ Review scope closed at 10/10
- ✅ Two remaining views reserved for reuse
- ✅ MS-01 confirmed against SAP, CareOS, and all 12 interface views
- ✅ MS-01 assigned to `RCB_NonMotor_process_2_cancel`
- ✅ MS-01 full legacy SELECT query dry-run and shadow validation
- ⏸ MS-01 `L80799909-1` ActualReceived `3600.00` vs TotalAmount `2160.00` — human pre-deploy review
- ✅ MS-02 full source fix ready and validated
- ⏸ MS-03 pending human investigation
- ✅ MS-04 full source fix ready and validated
- ✅ MS-05 confirmed: RCL Motor compulsory M1 wrapper gap
- ✅ MS-05 root-fix owner: existing `RCL_Motor_process_1_create`
- ✅ MS-05 full legacy query and validation query prepared
- ✅ MS-05 BigQuery regression and full candidate validation GREEN
- ✅ MS-06 confirmed: `L80161278-M1` RCL-funded compulsory/FULL_PAYMENT/no-detail gap
- ⏳ MS-06 full upstream legacy query — next work item
- ⏭ `RCL_Motor_process_3_cancel` remains reserved for a later scenario
- ⏳ Deploy MS-01 only after human review/approval
- ⏳ Continue listing MS-06 after MS-05 query work
