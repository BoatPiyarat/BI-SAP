# V3 monthly delta operating model

Status: **design milestone / Class A where implemented / not deployed**. Boat, 2026-08-02.

Google Drive milestone:
`https://docs.google.com/document/d/188igKmt72mCARQFj7W41kuheXl9vxjTLKdIlUsgpTho/edit`

## Goal

After manual July closing is complete, V3 becomes a reusable nightly delta process. It must send
every CareOS-qualified payment exactly once, sequence Paid before cancel/change, respect accounting
period closing, hold unapproved NonMotor InsuranceGroup values, refresh SAP evidence after delivery,
and email a complete conservation report.

## Period state machine

There is exactly one open accounting period at all times. Closing is one controlled transition:

`OPEN(month M) -> close M at closing_at -> OPEN(month M+1)`

Before closing, raw transactions in M keep their real PaymentDate and BatchRunDate is the real run
date within M. At the transition, backlog dated before M+1 is clamped to the first day of M+1;
transactions originating in M+1 keep their real date. This replaces the temporary July-only scope.

The implementation must not infer the open period only from `lock_datetime > CURRENT_TIMESTAMP()`.
It needs an explicit period status/history so the close/open transition is auditable and cannot
leave zero or two active periods.

## Delta classification

At `(OrderItem, Period, payment event)` grain, every qualified CareOS row has exactly one outcome:

- `ACKNOWLEDGED_IN_SAP`
- `PENDING_ACK`
- `READY_CREATE_OR_PAYMENT`
- `READY_CANCEL_CHANGE` (only after SAP Paid/Pending existence proof)
- `HELD_VALIDATION`
- `EXCLUDED_RULE`
- `REJECTED_BY_SAP`

The nightly export contains only READY outcomes. Existing Paid with the same immutable InvoiceNo is
a no-op; existing Paid/Cancelled with a different InvoiceNo is held for human action. This closes
the defect exposed by July Upload LogID 21153, where export-archive membership was incorrectly used
as a substitute for current SAP-state delta classification.

## NonMotor InsuranceGroup gate

For raw PaymentDate >= 2026-08-01, NonMotor is fail-closed until the exact InsuranceGroup value is
present in an explicitly approved mapping. Approval must be traceable to a reviewed SAP-success
source or business owner; non-empty source text is insufficient. Held rows remain in the daily
report and are automatically reconsidered after approval.

## Closed PaymentMethod/PaymentChannel mappings

Canonical values are learned only from reviewed V2 SQL plus successful SAP history. Validate exact
Unicode text, character length, and membership before export. Reject mojibake signatures and values
longer than the SAP contract. Do not repair by truncation because that can map to a different code.

## Nightly completion sequence

The 20:30 ICT SAP extract is the single nightly anchor. One orchestrator owns the dependency chain;
independent clock schedules are not evidence that the chain completed.

1. Execute `sap-extract-job`, wait for the Cloud Run execution to finish, then wait for the exact
   bronze generation to be committed by one loader execution and removed from bronze. HTTP status
   alone is not load evidence.
2. Refresh `sap_mirror_doc` and `sap_mirror_state`; record the extract execution, loader job ID,
   source generation, loaded rows, and mirror freshness.
3. Refresh CareOS-qualified staging and classify the delta against that refreshed SAP mirror.
4. Validate 56-column position, dates, mappings, status completeness, sequencing, period rules,
   and population conservation. No READY population may change by an unexplained magnitude.
5. Archive exact bytes, deliver only READY rows, and retain manifest/hash/generation provenance.
6. Wait for SAP pickup/import evidence with a bounded timeout. Ingest the import result into
   row-level acknowledged/rejected states; a file/function status is not a row ACK.
7. After the SAP import result, execute the SAP extract/load/mirror sequence again so SAP-side
   outcomes from this delivery are visible before reconciliation.
8. Reconcile all qualified CareOS rows and assert exact conservation.
9. Email counts, amounts, exclusions/holds/rejects, new mapping values, freshness, job IDs, and
   missing evidence. Failure to email or reach a human recipient is an alert failure, not pipeline
   success.

## Current automation boundary (verified 2026-08-02)

V3 is not yet an unattended daily pipeline. The deployed 21:00 ICT scheduled procedure refreshes
state/reconciliation objects, but it does not own extract-to-loader dependency, export/delivery,
SAP-result ingestion, the post-import refresh, or the completeness email. The separate 01:00 ICT
loader scheduler precedes the 20:30 extract and is not a same-run dependency guarantee. The
`sap_validation_regression_alert` scheduled query was observed FAILED. Until the Class A increments
below are implemented and one production cycle proves every checkpoint, manual supervision remains
required.

No operator or runbook may describe `wf-sap-pipeline`, `sap-pipeline-trigger`, or a general
`sp_export_delta` as deployed without fresh live metadata evidence.

## Implementation increments requiring Class A review

1. Replace July-specific selection in 048/049 with SAP-state delta classification; preserve the
   historical July artifacts for audit.
2. Extend period-lock storage to explicit OPEN/CLOSED history and an atomic close/open procedure.
3. Add Paid-before-cancel and SAP Paid/Pending existence gates.
4. Add approved InsuranceGroup and PaymentMethod/PaymentChannel mapping registries.
5. Ingest SAP result workbook/log into archive acknowledgement/rejection states.
6. Add post-delivery extract/load/mirror orchestration and daily completeness email.
7. Replace independent-clock execution with one low-cost Cloud Workflows state machine anchored at
   20:30 ICT. Use Cloud Run/BigQuery/Pub/Sub job IDs and bounded polling; do not keep a compute
   service waiting. Persist every transition in `pipeline_run_log` and fail closed with a human
   alert on timeout, duplicate loader commitment, missing import evidence, or conservation failure.

No increment may deploy merely because this design is approved as a milestone; SQL and production
changes retain their separate review and Boat approval gates.
