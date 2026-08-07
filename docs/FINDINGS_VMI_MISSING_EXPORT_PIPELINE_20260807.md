# Findings — missing voluntary (VMI) installment orders: corrects Item 5's root cause, 2026-08-07

**Status: READ-ONLY INVESTIGATION ONLY. Nothing fixed, corrected, exported, or deployed.**
Requested by Piyarat: find the root cause of missing VMI for `L78794968`, `L78583606`,
`L78786429` (the same 3 orders as Item 5 in
`docs/FINDINGS_MOTOR_MISROUTING_AND_MISSING_INTERFACE_20260805.md`), then modify the RCL script.

**This corrects that prior finding.** Item 5 (2026-08-05) blamed a WHERE-clause exclusion in
`rcb_voluntary_installment_details` (`sql/production/RCL_MOTOR.sql:275-279`,
`follow_ups.transaction_id IS NULL`) that stops emitting a period once it reaches
`FOLLOWUP_STATUS_PAID`, with "no other branch to reclaim it." **That claim is false for the
current live view** — verified directly below. Do not apply that finding's proposed fix; it
would not change behavior and would touch code that is not the actual defect.

## Symptom (unchanged, re-confirmed live 2026-08-06/07)

All three orders have a genuine, active `RABBIT_CARE_INSTALLMENT` V1 item (6–8 periods).
Period 1 is `FOLLOWUP_STATUS_PAID` (paid late July: `L78794968` due 27/07, `L78583606` and
`L78786429` due 31/07, all actually paid 01/08). Periods 2+ correctly show
`FOLLOWUP_STATUS_PENDING`, not yet due. **Zero rows for any of the three `-V1` order items exist
in `sap_integration_v2.SAP_LIVE_FULL`, at any period, confirmed today.**

None of the three appear in `sap_integration_v3.sap_excluded_records`,
`sap_validation_error`, or `sap_import_error_detail_v3` — this is not a logged/legitimate
exclusion. Per this project's charge-driven principle, this is a **silent drop**.

## Hypotheses tested

### 1. RCL_MOTOR.sql's `rcb_voluntary_installment_details` drops paid periods — REFUTED

Confirmed the repo copy of `sql/production/RCL_MOTOR.sql` is byte-identical (after line-ending
normalization) to the live `sap_data_engineer.RCL_MOTOR` view (`bq show --view`, checked
2026-08-06/07) — no drift, this really is what's running.

Reproduced `rcl_voluntary_installment_details` (the CTE immediately below it, which requires
`follow_ups.transaction_id IS NOT NULL` — the exact complement of the rcb branch) directly
against these 3 orders: **it returns all periods for all 3 orders**, including the paid period 1.
The two CTEs are complementary by design (`follow_ups IS NULL` vs `IS NOT NULL`); `combine`'s
UNION ALL of both means no period is actually orphaned by this filter split.

Queried the live `sap_data_engineer.RCL_MOTOR` view directly for these 3 order items: **it
returns complete, correct rows for every period**, period 1 `TransactionStatus = 'paid'` with
`InvoiceNo` populated, periods 2+ correctly `'pending'` with blank `InvoiceNo`. The reporting
view is not the problem.

### 2. `sap_dashboard_carepay_installment` / `RCL_Motor_process_1_create` — REFUTED

Also queried the live `sap_data_engineer.sap_dashboard_carepay_installment` view (subject of the
2026-08-06 LEFT-JOIN fix in `FINDINGS_RCL_INSTALLMENT_MISSING_PERIODS_AND_HEALTH_CHANNEL_20260806.md`)
directly for these 3 orders: complete, correct data, all periods present.

Reproduced `sql/sap_view/RCL_Motor_process_1_create.sql` verbatim (the "new order, never yet in
SAP" export selector — applies here since these order items have literally never posted) against
these 3 orders: **it selects all 20 period-rows correctly** (none excluded by the
`OrderItem NOT IN (...SAP_LIVE_FULL...)`, cancelled-change-order, hardcoded-OrderID, or
year-string filters). This view's SELECT is not the problem either.

### 3. The actual interface-file producer is unreliable — CONFIRMED, this is the real cause

Per `docs/SAP_SCHEDULER_INVENTORY.md` row 7, the Cloud Function `rcb-motor-order-payment-sap-bucket-1`
(region `asia-southeast1`) is **"the real Motor interface file producer"** — it runs
`sql/sap_view/{01..08}_*.sql` in sequence (including `05_RCL_Motor_process_1_create.sql` and
`06_RCL_Motor_process_2_newpayment.sql`) and writes each result as a CSV to
`gs://interface-file/RCB_MOTOR/...`, which SAP's own 15-minute pull picks up. That inventory
already flagged this function as timing out at its (then 300s, later raised to 540s) ceiling for
"5+ consecutive days" as of 2026-07-26, with the fix status "UNVERIFIED."

Checked its logs directly (`gcloud functions logs read`, region `asia-southeast1`):

- **2026-07-31 18:30–18:38 UTC** (the exact day `L78583606` and `L78786429`'s period 1 became
  due/paid): all 8 steps wrote their CSVs successfully, then the **entire function crashed** with
  an uncaught `smtplib.SMTPAuthenticationError` (`535 Username and Password not accepted` — the
  Gmail app-password used for a post-run completion email is invalid) while executing
  `send_email(...)` in `mailer.py`. This is an unhandled exception on a Pub/Sub push endpoint —
  the invocation ends in failure from Pub/Sub's perspective regardless of the CSVs already
  written.
- **2026-08-06 18:30–18:39 UTC** (yesterday): all 8 steps again wrote their CSVs, then the
  function hit its hard **540-second timeout** (`Function execution took 538582 ms, finished
  with status: 'timeout'`) right after the last step. Same shape of failure, different proximate
  cause — the fix noted in the inventory (300s→540s) has not resolved it; the workload now
  exceeds the raised ceiling too.
- Confirmed the current deployed timeout is 540s, last updated 2026-08-06T18:31:36Z — so this is
  not stale config, it is actively still failing today.

Current `gcloud functions describe rcb-motor-order-payment-sap-bucket-1` timeout: `540s`.

**This is a known, still-open, dated defect** (`SAP_SCHEDULER_INVENTORY.md` row 7, opened
2026-07-26), not a newly discovered SQL bug. It fully explains a silent, sporadic drop pattern —
CSVs can be written and then the delivery/notification wrapper still fails, and Pub/Sub push
retry semantics on a crash/timeout mean any given calendar day's export for any given order is
not reliably guaranteed to land, with no entry in `sap_excluded_records` because nothing in the
pipeline ever explicitly rejected these rows — they just never made a clean end-to-end run to
completion. It also matches Piyarat's own observation that these gaps get "swept up" during
month-end batch reprocessing (a backfill re-running the same, already-correct queries would
recover anything the flaky daily function missed).

## What this means for "modify the current script of RCL"

The RCL BigQuery views (`RCL_MOTOR.sql`, `sap_dashboard_carepay_installment.sql`,
`RCL_Motor_process_1_create.sql`) are **not shown to be the defect for this population** — their
current logic is correct and was directly verified against live data. Editing
`RCL_MOTOR.sql`'s `follow_ups` filter per the old Item 5 write-up would be a no-op change to code
that isn't broken (against this project's surgical-changes rule) and would leave the real cause
untouched.

The actual fix surface is the Cloud Function `rcb-motor-order-payment-sap-bucket-1`'s Python
source (not held in this repo — only its `sql/sap_view/*.sql` query files are baseline-captured
here): (a) the `send_email` call needs to not be able to crash the whole export after the CSVs
are already written (wrap in try/except, or move notification out of the critical path), and
(b) the recurring timeout needs an actual fix (parallelize the 8 sequential queries, split the
batch, or raise memory/CPU so the underlying BigQuery calls return faster) rather than another
ceiling bump, since 300s→540s already didn't hold.

This has direct accounting/customer-money impact (paid installment premiums not reaching SAP) —
per this project's standing rule, stopping here to report rather than pushing a source change to
production infrastructure that isn't in this repo and that only Codex is authorized to deploy.

## Addendum — pulled the actual function source, one attribution gap remains open

Downloaded the deployed source (`gcloud functions describe` → Cloud Build → GCS source zip,
read-only) rather than relying on logs alone. Confirmed at code level: `main.py` writes each of
the 8 CSVs straight to `gs://interface-file/RCB_MOTOR/...` (the real path SAP polls, no
intermediate promotion step) inside its loop, and only calls the unguarded `send_email(...)`
*after* the loop finishes. In both incidents checked (07-31 SMTP crash, 08-06 timeout), the log
shows steps 05/06 (the ones relevant to VMI) had already logged a successful GCS write before the
failure. **This means the crash/timeout are confirmed, real, currently-live bugs, but are not yet
proven to be why these specific 3 orders' files never reached SAP** — that requires checking the
SAP-side import log for the actual filenames on the actual dates, which nothing on the BigQuery
side can answer (`sap_import_result_header_v3` returned 0 rows for either process's filename
pattern — it appears to track a different, email/XLSX-based ingestion path, not this CSV drop).
Full task plan, including this verification step, is in
`docs/tasks/TASK_FIX_RCL_MOTOR_EXPORT_RELIABILITY_20260807.md`.

## Next steps (not done here)

1. Boat/IT: rotate or fix the Gmail app-password used by `mailer.py` in
   `rcb-motor-order-payment-sap-bucket-1`, and make that email step non-fatal to the export.
2. Boat/IT: address the function's recurring 540s timeout (see options above) — needs someone
   with `cloudfunctions.functions.update`/source access; this repo does not hold that function's
   source.
3. Re-scope Item 5's "541 voluntary order items" population: that count was derived only from
   "paid per follow_ups but absent from `SAP_LIVE_FULL`," which is equally consistent with this
   pipeline-reliability cause. It should not be assumed to require a `RCL_MOTOR.sql` fix without
   re-checking against the corrected mechanism here.
4. Once (1)/(2) land, these 3 orders and any others caught in the same window should self-resolve
   on the next successful nightly run — no manual backfill of `RCL_MOTOR.sql`-derived data should
   be needed if the export function itself starts completing cleanly.
