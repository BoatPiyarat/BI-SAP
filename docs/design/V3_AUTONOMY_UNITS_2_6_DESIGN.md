# V3 unattended daily pipeline — units 2–6 design contract

Status: **source/design only; no deploy, CALL, GCS write, scheduler mutation, or legacy-view
change authorized by this document**. Boat authority: continue non-production work, 2026-08-02.

This document refines `MONTHLY_DELTA_OPERATING_MODEL_V3.md`. Unit 1 makes the SAP mirror fresh;
units 2–6 decide, validate, deliver, acknowledge, reconcile, and report. Every unit is idempotent
at `pipeline_run_id` and fails closed. A failed unit never releases a later unit.

## Shared identity and conservation grain

- Payment event identity: `(order_item, period, charge_id, invoice_no)`; invoice number may be
  empty only before a payment becomes Paid.
- Schedule identity: `(order_item, period)`.
- SAP document identity: `DocEntry`; current business state is the reviewed mirror winner at
  `(order_item, period)`.
- File identity: immutable manifest `(pipeline_run_id, file_role, bu, object_generation, sha256)`.
- SAP result identity: `log_id` plus row-level result sequence/key.

Live-profile correction (2026-08-02): `expected_state` is schedule grain (290,258 rows = 290,258
distinct `(order_item, period)` keys), and only 167,754 rows join a charge. Pending schedules
correctly have no charge. `stg_payment_events` separately contains 1,198,183 unique qualified
charge events. Unit 2 therefore maintains two outputs and two independent conservation equations:

- `PAYMENT_EVENT`: `(order_item, period, charge_id, invoice_no)`; records and amount conserve.
- `SCHEDULE`: `(order_item, period)`; records conserve; amount is NULL/not applicable.

Never coalesce Pending schedule amount to zero and add it to event money. Never deduplicate multiple
successful charges in one period out of the event population. Source implementation is
`sql/ddl/051_v3_unit2_shadow_classifier.sql`.

Every qualified CareOS event must finish the run in exactly one terminal/reportable bucket:

`ACKNOWLEDGED + PENDING_ACK + READY_NOT_DELIVERED + HELD_VALIDATION + EXCLUDED_RULE + REJECTED_BY_SAP`

The sum must equal `QUALIFIED_CAREOS` at both record and amount grain. Categories are mutually
exclusive; NULL/unclassified rows fail the run. Order counts are reported separately and are not
summed as a conservation identity because one order can contain multiple events.

## Unit 2 — current-SAP-state delta classifier

Input requires `UNIT1_COMPLETE` from the same pipeline run and mirror freshness at or after the
Unit 1 loader commitment.

At payment-event grain assign exactly one outcome, in this precedence:

1. `EXCLUDED_RULE` — canonical E1–E3/business exclusions; register row already exists.
2. `HELD_VALIDATION` — qualification/contract/business-rule failure.
3. `REJECTED_BY_SAP` — a prior delivered event has a matched row-level reject and no later ACK.
4. `ACKNOWLEDGED` — SAP mirror/import-success evidence matches immutable identity and status.
5. `PENDING_ACK` — exact manifest delivery exists but no terminal SAP row result yet.
6. `READY_CANCEL_CHANGE` — old SAP document exists as Paid/Pending, full spine exists, and the
   reviewed cancel track says eligible.
7. `READY_CREATE_OR_PAYMENT` — qualified event is absent from current SAP state and has no pending
   identical manifest.
8. Otherwise `HELD_CLASSIFICATION_UNKNOWN`; this is a hard failure, never a silent drop.

Export-archive membership is evidence of delivery only, never evidence that SAP currently needs or
accepted a row. Existing Paid/Cancelled with a different InvoiceNo is human-action hold. Cancel
must ACK before credit-shell release.

### Population-magnitude hard gate

Before accepting Unit 2, compare current vs last successful run by outcome, flow, BU, status,
records, distinct orders, and amount. Gate on an approved absolute/percentage threshold stored in
configuration, not a hardcoded guess. Any threshold breach creates `HELD_MAGNITUDE_REVIEW`, sends
the full distribution to Boat, and emits no file. A zero delta is not assumed correct; reconcile
the complete qualified population.

## Unit 3 — closed mapping registries

Two effective-dated registries are required:

### InsuranceGroup registry

Key: `(source_insurance_group, product/BU scope, effective_start, effective_end)`.
Fields include canonical SAP value, approval state, evidence type/reference, approved_by,
approved_at, created_at, retired_at, and reason. Only `APPROVED` mappings release data.

For NonMotor with raw PaymentDate on/after `2026-08-01`, missing, ambiguous, overlapping, expired,
or unapproved mappings produce `HOLD_INSURANCE_GROUP_MAPPING`. No default Motor/NonMotor fallback.
The daily report lists distinct raw values with records/orders/amount and first/last seen.

### PaymentMethod/PaymentChannel registry

Key: `(flow, payment_source_type, payment_method_source, payment_channel_source, effective dates)`.
Output stores exact Unicode SAP-success literals plus evidence/approval fields. Reject mojibake,
truncation, case-normalized invention, overlapping effective windows, and values absent from the
approved registry. Credit-shell literals remain held until SAP-success/Aware evidence exists.

Registry edits are configuration production mutations: Class A review + Boat approval, append a
new effective version, never overwrite history.

## Unit 4 — monthly OPEN/CLOSED state machine

Period history has one row per calendar month with status `PLANNED | OPEN | CLOSED`,
`period_start`, exclusive `period_end`, optional `closing_at`, `closed_at`, `closed_by`, and audit
timestamps. Exactly one row is OPEN.

Atomic transition `close(M, closing_at) -> open(M+1)` must assert:

- M is the single OPEN period and M+1 is PLANNED;
- `period_end(M) = period_start(M+1)`;
- no second active transition/run lock exists;
- closing_at is explicit and not inferred from execution time;
- the transaction commits both state changes or neither.

Date behavior uses **raw PaymentDate**:

- before close: an event inside OPEN M keeps its real PaymentDate; BatchRunDate is the real run
  date capped inside M;
- backlog dated before OPEN M is clamped to `period_start(M)` and marked
  `payment_date_clamped=TRUE`;
- after close/open: previous-month backlog is immediately evaluated against M+1 and clamped to
  `period_start(M+1)`; new M+1 events keep their real date;
- a future-dated event outside OPEN M is held, never backdated silently.

July/August 2026 has a Boat-approved transition override: raw July payments use 2026-07-31 and
raw August payments keep their real dates. The generic previous-month-to-first-day rule must not
turn July into 2026-08-01. `payment_date_clamped=TRUE` still records a July raw date changed to its
month end.

Every derived row stores `source_payment_date`, `effective_payment_date`, `period_id`,
`payment_date_clamped`, and the period-state version used. No last-day/current-date hardcode.

## Unit 5 — exact-byte delivery, SAP result, second refresh

### Archive and delivery

Build only validated READY rows. Assert the canonical 56 columns by ordinal/name/type warning,
date/status rules, BU/role split, exact row/key/amount conservation, and zero held rows in payload.
Create immutable bytes once in a non-production archive, record SHA-256/size/row count/header and
object generation, then promote those exact bytes. Regeneration after approval is prohibited.

`READY_CREATE_OR_PAYMENT` must be split before payload construction. If an OrderItem has no SAP
document, its role is `CREATE` and the file package expands from payment-event grain to the exact
schedule spine `1..TotalPeriods`; Paid rows carry transaction fields and Pending rows retain blank
InvoiceNo, PaymentDate, PaymentMethod, and PaymentChannel. If the OrderItem already has any SAP
document, its role is `NEWPAYMENT` and only the releasable payment event is emitted. A missing,
duplicate, or non-contiguous CREATE spine is a hold. Therefore the Unit 3 releasable event count is
an input conservation total, not an expected CSV row count. The source diagnostic is
`sql/adhoc/20260802_unit5_file_role_population_gate.sql`.

CREATE does not collapse a legitimate top-up into its schedule row. The first Paid row for a
period carries that period's ExpectedReceived; each additional successful event for the same
`(OrderItem,Period)` is a separate row with ExpectedReceived=0 and its own immutable InvoiceNo and
ActualReceived. Thus CREATE payload rows equal schedule-spine rows plus `SUM(event_count-1)` over
multi-event item-periods.

Before materializing 56 columns, each target identity must match exactly one source-contract
variant. The match is `(OrderItem,Period,InvoiceNo)` for Paid rows and
`(OrderItem,Period,Pending-with-blank-InvoiceNo)` for Pending rows. Missing and ambiguous variants
are holds; Unit 5 must not replace them with a schedule-level winner or invent financial fields.
The coverage query is `sql/adhoc/20260802_unit5_payload_source_coverage.sql`.

Delivery states:

`SHADOW_READY -> ARCHIVED -> DELIVERED -> PICKED_UP -> ACKNOWLEDGED | PARTIAL_REJECT | REJECTED | TIMEOUT`

No state is inferred from a Cloud Function/workflow HTTP result. Delivery requires production GCS
generation evidence; pickup email is not ACK; import header status is not row-level success.

### Result ingestion

Ingest email metadata and attachments idempotently by `log_id`. Store raw diagnostic text only in
BigQuery access-controlled columns and sanitized templates in docs/reporting. Match each exported
row to ACK or reject evidence; unmatched rows remain `PENDING_ACK`. LogID 21153 is an audit/regression
fixture and must not be replayed.

The nightly poll is deliberately bounded to message-level Gmail results from the preceding 60
minutes and production markers `[LIVE]` + `RCB_LIVE_DB`. It must additionally match the exact
current delivery-manifest filename. UAT2 is excluded; zero matches remains pending; multiple
distinct LogIDs fail as ambiguous rather than choosing the newest message. This time boundary
limits stale-result capture but does not replace the exact filename and environment gates.

After a terminal import result, run the complete Unit 1 extract/load/mirror sequence again with a
new child execution linked to the delivery run. Reconciliation waits for this second mirror. A
bounded timeout ends as `TIMEOUT/HUMAN_ACTION`, not success.

## Unit 6 — daily completeness report and human alert

One immutable report snapshot per pipeline run contains:

- source/mirror freshness timestamps and every upstream execution/job ID;
- qualified records/orders/amount;
- each mutually exclusive outcome at records/orders/amount;
- exclusions by rule code, with report-only rules separated from hard exclusions;
- validation holds by rule, new InsuranceGroup/payment mapping values, cancel/plain-cancel/
  credit-shell states, and SAP reject templates;
- every file manifest/hash/generation, LogID/status, ACK/reject/unmatched counts;
- conservation residuals, threshold decisions, and prior-run deltas.

Run success requires record and amount residuals exactly zero and all required evidence present.
The report is sent to a channel proven to reach Boat; `data@rabbit.co.th` alone is insufficient.
Email/publish failure changes the pipeline terminal state to `ALERT_FAILED` and pages the fallback
channel. A log-only failure is silent failure and is prohibited.

Repair `sap_validation_regression_alert` as a separate Class A unit. Its acceptance requires a
synthetic failing validation that reaches the human recipient and a healthy run that does not
alert.

## Release dependency and stop gates

1. Unit 1 Class A PASS plus pinned control object/schema and alert channel evidence.
2. Unit 2 measured shadow run and explained population distribution.
3. Unit 3 approved registries; NonMotor remains held until then.
4. Unit 4 transition rehearsal on non-production state with rollback proof.
5. Unit 5 exact-byte/UAT and row-level ACK rehearsal; no production replay of July.
6. Unit 6 conservation snapshot and end-to-end human alert test.
7. Only then may Codex request/consume Boat's scoped deploy/cutover approval. Scheduler pause/enable,
   mutating CALL, IAM, GCS production write, and workflow deployment remain production stops.

Rollback is unit-local until cutover. Full cutover is one controlled change: enable the reviewed
workflow trigger and pause overlapping independent schedules. Rollback pauses the workflow trigger
and restores the prior schedules; it never deletes audit tables, manifests, or SAP_LIVE history.
