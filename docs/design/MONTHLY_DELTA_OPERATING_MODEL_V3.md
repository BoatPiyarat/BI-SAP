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

1. Refresh CareOS-qualified staging and classify the delta against the latest SAP mirror.
2. Validate 56-column position, dates, mappings, status completeness, sequencing, and period rules.
3. Archive exact bytes, deliver only READY rows, and retain manifest provenance.
4. Ingest import result into row-level acknowledged/rejected states.
5. Run `sap-extract-job`; wait for loader success; refresh `sap_mirror_doc` and
   `sap_mirror_state`.
6. Reconcile all qualified CareOS rows and assert exact conservation.
7. Email counts, amounts, exclusions/holds/rejects, new mapping values, freshness, job IDs, and
   missing evidence. Failure to email is an alert failure, not pipeline success.

## Implementation increments requiring Class A review

1. Replace July-specific selection in 048/049 with SAP-state delta classification; preserve the
   historical July artifacts for audit.
2. Extend period-lock storage to explicit OPEN/CLOSED history and an atomic close/open procedure.
3. Add Paid-before-cancel and SAP Paid/Pending existence gates.
4. Add approved InsuranceGroup and PaymentMethod/PaymentChannel mapping registries.
5. Ingest SAP result workbook/log into archive acknowledgement/rejection states.
6. Add post-delivery extract/load/mirror orchestration and daily completeness email.

No increment may deploy merely because this design is approved as a milestone; SQL and production
changes retain their separate review and Boat approval gates.
