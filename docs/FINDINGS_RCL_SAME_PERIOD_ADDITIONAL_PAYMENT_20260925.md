# RCL same-period additional payments — 2026-09-25

Status: diagnosis confirmed against live BigQuery; no production fix, deployment, export, or SAP write.
Scope: Mo's examples L80570054 and L79109956. This is not a full-population impact estimate.

## Finding

The additional payments exist in CarePay. They disappear in the live
`sap_data_engineer.sap_dashboard_carepay_installment` before the current RCL Motor newpayment interface.
A second, independent period-level eligibility gate would still exclude them after the upstream filter is corrected.

| Order / item | Period | Successful first charge (THB) | Successful additional charge (THB) | Additional payment date (ICT) |
|---|---:|---:|---:|---|
| L80570054-V1 | 1 | 1,278.01 | 22.04 | 2026-09-01 15:14:59 |
| L79109956-V1 (order also has M1) | 1 | 1,788.75 | 645.21 | 2026-09-03 18:34:03 |

Source: `careos.carepay_charges` joined through `careos_orders.payment` and
`carepay_transactions`, queried 2026-09-25 15:07:40 UTC / 22:07:40 ICT.
Both orders use RABBIT_CARE_INSTALLMENT; all four charges are SUCCESSFUL / RABBIT_LENDING.
The two additional amounts sum to THB 667.25 at charge-header grain, not a quantified GL loss.

## Exact event evidence

| Order | Additional charge ID | Raw InvoiceNo | Dashboard/SAP-form InvoiceNo |
|---|---|---|---|
| L80570054 | 097864a4-cd1f-4d0a-9e08-9ec775363484 | chrg_68ve8ufva4h1iil7wrn | 2_chrg_68ve8ufva4h1iil7wrn |
| L79109956 | dc98599e-b5bb-44e4-97df-18f9f6c3916a | chrg_68w87npgw0hbvid58ho | 2_chrg_68w87npgw0hbvid58ho |

- Live dashboard, checked 15:08:32 UTC: both first-charge identities present; both additional identities absent.
- Live `sap_view.RCL_Motor_process_2_newpayment`, checked in job listed below: zero rows for these two orders.
- `sap_integration_v2.SAP_LIVE_FULL`, checked 15:10:04 UTC: the first payment rows are marked Paid; neither additional invoice identity occurs for either order, including all queried statuses.
- This is evidence of absence from the current mirror and interface, not a claim that SAP-side JE/import logs were audited. No claim about historical files, queue activity, exact incident onset, or the full affected population is made.

L79109956 allocation: the dashboard and SAP mirror currently show first-charge ActualReceived
1,143.54 on V1 plus 645.21 on M1 = 1,788.75. The missing later 645.21 is a distinct charge.
It must not be confused with the existing M1 allocation merely because the amounts match.

## Root cause and causal probe

Current live definitions were captured from INFORMATION_SCHEMA.VIEWS at 2026-09-25 15:07:04 UTC.

1. The dashboard ranks successful Rabbit Lending charges by
   `ROW_NUMBER() OVER (PARTITION BY transaction_id, installment_number ORDER BY create_time)`.
2. Its voluntary installment branch then filters with
   `AND (charges.charge_rank = 1 OR charges.charge_rank IS NULL)` (captured definition line 346).
   Both missing charges are rank 2 and are discarded.
3. The same live branch already defines ExpectedReceived = 0 and charge-based ActualReceived for
   charge_rank > 1, but the filter makes those additional-payment expressions unreachable.
4. SELECT-only causal probe removed exactly that voluntary predicate from the captured live definition.
   It did not replace any view and left the compulsory charge_rank = 1 predicate unchanged.
   At 15:10:54 UTC the probe recovered exactly the two additional V1 rows:
   L80570054 ActualReceived 22.04 / ExpectedReceived 0;
   L79109956 ActualReceived 645.21 / ExpectedReceived 0.
   Existing period-1 payment rows remained unchanged.
   This isolates the first-charge filter, rather than a missing source charge or snapshot join.

## Independent downstream blockers

The captured live `sap_integration_v2.RCL 05_newpayment` excludes any
(OrderItem, Period) already Paid in SAP, with no InvoiceNo or charge identity comparison.

The captured live `sap_integration_v2.RCL 05_paid by period` also excludes an item when its selected
latest installment number is already Paid. Both target V1 items currently have only period-1
successful charges and a Paid period-1 mirror row, so they fail this eligibility gate.

The current wrapper `sap_view.RCL_Motor_process_2_newpayment`:
- unions RCL 05_paid with RCL 05_newpayment;
- requires an item to pass RCL 05_paid by period;
- has additional-payment-aware deduplication (ExpectedReceived = 0, ActualReceived > 0, InvoiceNo key).

Thus fixing only wrapper deduplication or rerunning the unchanged interface cannot restore these
events. The new rows are already missing before that deduplication stage.

The create wrapper is not a recovery path for these existing items: its live definition excludes
items already in SAP_LIVE_FULL.

## Alternate upstream caution

Live `sap_data_engineer.RCL_MOTOR` does retain both raw invoice identities, but its ActualReceived
for these V1 rows is the installment amount, repeated per charge: 1,300.05 for L80570054 and
1,788.75 for L79109956. L79109956 also has two M1 identities each showing 645.21.
Those rows are not a safe substitute for the missing charge-level dashboard payload.
This is a view-output observation, not an assertion that those alternate rows were posted.

## Required correction scope (not implemented)

- Preserve distinct successful same-period payment events in the voluntary dashboard branch.
- Make RCL newpayment and item eligibility compare event/invoice identity as well as item/period;
  retain historical first payments and the complete required schedule.
- Preserve zero ExpectedReceived for additional rows and exact incremental ActualReceived.
- Keep compulsory M1 allocation separate; do not remove its first-charge rule indiscriminately.
- Verify invoice immutability, rerun idempotency, no duplicate M1 or first payment, and multi-charge
  same-period regression cases before proposing a deployment/backfill.
- Check all affected events before recovery. These two examples alone do not quantify the population.
- Establish first deployment time of the offending predicate from change/audit history if an onset
  date is required. Header comments are not deployment evidence.

## Reproduction and evidence

Queries: `sql/adhoc/20260925_trace_rcl_same_period_{source,dashboard,motor,newpayment,sap}.sql`.
Causal probe: `sql/adhoc/20260925_probe_rcl_same_period_rank_filter.sql`.
Local snapshot checks: `python scripts/verify_rcl_same_period_evidence_20260925.py`.

All successful non-metadata queries used scripts/bq_safe_query.sh, with dry-run and
maximum_bytes_billed=21474836480. Initial source query failed dry-run due to an unsupported correlated
subquery; it was corrected to a grouped item inventory join before any live execution.

| Stage | Query timestamp UTC | Job ID | Dry-run bytes |
|---|---|---|---:|
| Source | 15:07:40 | bqjob_r3ae9aa94a742ee39_000001a0d91b9c3a_1 | 444008750 |
| Dashboard | 15:08:32 | bqjob_r722a7e202678b719_000001a0d91c628c_1 | 834721586 |
| RCL_MOTOR | 15:08:45 | bqjob_r54629e81e6f855e1_000001a0d91c9680_1 | 839769928 |
| Newpayment | See job metadata | bqjob_r60aa2d023b2c04dc_000001a0d91cd332_1 | 9788803014 |
| SAP mirror | 15:10:04 | bqjob_r16ee2ec7b31761c5_000001a0d91dca94_1 | 7905478460 |
| Rank-filter probe | 15:10:54 | bqjob_r2c370f15f94a02c0_000001a0d91e9168_1 | 824370975 |

Snapshots and exact live definitions are retained under
`docs/evidence/rcl_same_period_20260925/`.

| Built | Verified against real data | Still unverified |
|---|---|---|
| Read-only traces, causal probe, evidence checks, this finding | Both missing source events; dashboard filter; current mirror and wrapper absence; probe recovery | Historical onset, all-orders impact, SAP JE/import acknowledgements, production correction |

Repository state: existing unrelated uncommitted work was preserved. git pull --ff-only failed due
to diverging branches. No merge/rebase, commit, or push was performed for this investigation.
Review gate at investigation start: 0 OPEN. This live production finding requires Class A review;
no deployment readiness is claimed.

