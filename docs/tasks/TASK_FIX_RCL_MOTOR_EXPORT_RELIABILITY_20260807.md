# TASK — fix `rcb-motor-order-payment-sap-bucket-1` reliability + recover missing VMI
Created 2026-08-07 | Trigger: missing VMI for `L78794968`, `L78583606`, `L78786429`
(`docs/FINDINGS_VMI_MISSING_EXPORT_PIPELINE_20260807.md`) | Owner approval: Boat
Executor: **Boat/IT** for A/B/C (Cloud Function source + secret — outside this repo, outside
Claude Code's/Codex's access); **Claude Code (prepare) → Codex (deploy)** for D (BigQuery-side
recovery, per this project's single-deployer rule).

## Why this file exists
The SQL views (`RCL_MOTOR.sql`, `sap_dashboard_carepay_installment.sql`,
`RCL_Motor_process_1_create.sql`) are verified correct — see the corrected Item 5 finding. The
defect is in the Cloud Function that actually produces and drops the Motor interface CSVs. Pulled
its deployed source (`gs://gcf-sources-919786098205-asia-southeast1/rcb-motor-order-payment-sap-bucket-1-.../version-443/function-source.zip`,
read-only) to confirm the exact code, not just logs.

## Confirmed facts (source-level, not just log-level)
- `main.py` loops over 8 SQL files (`01`..`08`, including `05_RCL_Motor_process_1_create.sql` and
  `06_RCL_Motor_process_2_newpayment.sql`), writes each result straight to
  `gs://interface-file/RCB_MOTOR/INSURANCE_RCB_<process>_<yesterday's-date>.csv` — this **is**
  the production interface path SAP polls every 15 minutes; nothing downstream re-promotes it.
- After all 8 writes, `main.py:154` calls `send_email(...)` completely unguarded (no
  try/except). `mailer.py` requires `SMTP_USER`/`SMTP_PASS` env vars and does a real
  `smtplib.SMTP(...).login(...)` — any failure here is an **uncaught exception that crashes the
  whole Pub/Sub-triggered invocation**, even though all 8 CSVs were already written successfully
  moments earlier.
- Confirmed in logs: this exact crash happened 2026-07-31 (`535 Username and Password not
  accepted` — the Gmail app-password is invalid/expired) and the function also hit its hard 540s
  timeout on 2026-08-06 (1st-gen Cloud Functions cap at 540s — there is no higher ceiling to raise
  on this platform; `availableMemoryMb: 512`, `runtime: python312`, confirmed via
  `gcloud functions describe`).
- **Not fully closed:** in both incidents checked, steps 05/06 (the ones relevant to VMI) logged
  successful writes *before* the failure. This means the crash/timeout are confirmed, real,
  currently-live defects, but proving they are *specifically* why these 3 orders never reached SAP
  (vs. e.g. a SAP-side import rejection after a correctly-delivered file) needs the verification
  step below — do not assume without it. `sap_import_result_header_v3` returned zero rows for
  either process's filename pattern across the whole window, so it does not currently answer this
  either (that table looks like it tracks a different, email/XLSX-based ingestion path, not this
  CSV drop).

---

## A — Make the notification step non-fatal (blocking any other fix)

**Bug:** `main.py:149-154` — `send_email` call has no error handling; any SMTP failure kills a
Pub/Sub invocation whose actual data work (all 8 CSVs) already succeeded.

**Fix (prepare as a diff to hand to whoever has deploy access to this function — not in this
repo today):**
```python
try:
    send_email("suphakornh@rabbit.co.th", subject, body)
except Exception:
    logger.error("Completion email failed; export itself already succeeded.", exc_info=True)
```
**Steps**
1. Confirm with Boat/IT who owns deploy access for `rcb-motor-order-payment-sap-bucket-1` (not
   confirmed reachable from `data@rabbit.co.th`/`piyaratt@rabbit.co.th` per this project's
   existing IAM findings — same accounts already known not to be Cloud Run/Functions admins).
2. Apply the try/except, redeploy, confirm next night's log shows `Success` even if email still
   fails (until B below is also fixed).
3. Baseline-capture this function's source into this repo once redeployed (there is currently no
   `main.py`/`mailer.py`/`06_RCL_Motor_process_2_newpayment.sql` tracked here at all — the sixth
   query file is a real gap in `sql/sap_view/`).

**Acceptance:** a future SMTP failure logs a warning and the function still returns `200`.

## B — Fix or rotate the Gmail app-password

**Bug:** `535 Username and Password not accepted` — the credential in `SMTP_PASS` (env var on
the function) is invalid or expired.

**Steps**
1. Boat/IT: regenerate the Gmail App Password for whatever account `SMTP_USER` currently points
   to (or confirm 2FA/security settings didn't revoke it), update the Cloud Function's environment
   variable, redeploy.
2. Trigger a manual invocation, confirm the completion email actually arrives.

**Acceptance:** next nightly run's log shows `✅ Email sent to ...` with no exception.

## C — Fix the recurring 540s timeout for real

**Bug:** 1st-gen Cloud Functions cap at 540s; this function is already at that ceiling and still
times out — there is no further ceiling to raise on this platform (confirmed via
`gcloud functions describe`: no `serviceConfig.*` fields, i.e. genuinely 1st-gen).

**Options (evaluate, pick one, get Boat's sign-off — this is a platform-level change, not a
one-line fix):**
1. Migrate to a 2nd-gen Cloud Function or Cloud Run job (both support up to 3600s) — smallest
   conceptual change, same trigger/code shape.
2. Parallelize the 8 sequential `bigquery_client.query(query)` calls (they're independent) instead
   of running them one at a time in a `for` loop — likely the biggest single win for a shared
   540s budget.
3. Split into two functions (e.g. RCB steps 1-4 / RCL steps 5-8) triggered off the same Pub/Sub
   message, each with its own 540s budget.
Note: 2026-07-25's changelog already worked around this exact ceiling once, using `EXPORT DATA`
directly instead of this Cloud Function for a one-off backfill — that's a precedent, not a
standing replacement.

**Acceptance:** three consecutive nightly runs complete in comfortably under the function's
timeout with `status: 'ok'` (not `'timeout'`).

## D — Verify whether files actually reached SAP, then recover these 3 (and any siblings)

Do this **after** A lands (so re-running doesn't risk another crash), and treat it as its own
step — don't assume A/B/C retroactively fixed history.

**Steps**
1. Ask Aware/Boat to check the SAP-side import log for
   `INSURANCE_RCB_05_RCL_MOTOR_PROCESS_1_CREATE_20260727.csv` /
   `..._20260731.csv` / `..._20260801.csv` (and the `06_..._NEWPAYMENT` equivalents) — did SAP
   ever receive/attempt-import these files, and with what result? This is the one check that can
   actually confirm or refute the export-vs-import attribution above; nothing on the BigQuery
   side can answer it.
2. Re-derive the population, don't reuse the old "541 voluntary order items" figure from the
   superseded Item 5 finding — it was computed from the same "paid per follow_ups, absent from
   `SAP_LIVE_FULL`" signal this task now explains differently. Recompute date-bounded to the
   window this Cloud Function has been unreliable (2026-07-26 onward, per
   `SAP_SCHEDULER_INVENTORY.md` row 7).
3. Follow the same shadow → dry-run → pilot-batch pattern as `TASK_V2_HOTFIX.md` H3 (this repo's
   already-established, Boat-approved pattern for a recovery batch): shadow-materialize the
   missing set from `RCL_MOTOR`/`sap_dashboard_carepay_installment` (already proven correct),
   diff row-for-row against what these 3 orders' expected periods should look like, get explicit
   "deploy OK", then let Codex execute the actual write per the single-deployer rule.
4. Confirm these 3 named orders specifically land and reconcile before closing this task.

**Acceptance:** `L78794968-V1`, `L78583606-V1`, `L78786429-V1` all appear correctly in
`SAP_LIVE_FULL`; the re-derived population (not the stale 541 figure) is fully accounted for,
either recovered or explicitly still-pending-and-tracked.

---

## Order of work
**A (unblock) → B (fix credential) → C (fix timeout, needs its own approval) → verify next 3
nightly runs are clean → D (confirm SAP-side truth, then recover the backlog).**
No production Cloud Function redeploy or BigQuery write without Boat's explicit "deploy OK" for
that specific step, per this project's standing deploy gate.
