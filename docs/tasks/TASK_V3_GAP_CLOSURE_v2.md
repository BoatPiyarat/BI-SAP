# TASK-V3-GAP v2 — Make the daily interface reliable
Created: 2026-07-26 | Supersedes: TASK_V3_GAP_CLOSURE.md (v1 was built on the pre-07-24 architecture)
Executor: **Claude Code** | Owner: Boat
Authoritative context: `docs/knowledge/10_SAP_CONTEXT.md` (v3.0 + ARCHITECTURE corrected 2026-07-24)
**If any design doc contradicts 10_SAP_CONTEXT, 10_SAP_CONTEXT wins. Report the contradiction, don't act on it.**

---

## Verified status
- **V3 produces no interface file.** Every file SAP receives is still produced by the legacy v2 path
  (`sap_view.*` + its own functions/schedulers). V3 = staging + `expected_state` (~12 cols) +
  2 validation checks + `delta_export` + dead-man's switch. Risk of a wrong/missing daily interface is
  therefore **unchanged by V3 so far**.
- `SAP_LIVE` is genuinely fresh (14/14 successful loads since 07-09). The earlier "stale mirror"
  diagnosis was **wrong**; the real defect is **multiple documents per (OrderItem, Period)** —
  328,071 keys — with no agreed picking rule.
- **`sap-extract-schedule` is currently failing (401 UNAUTHENTICATED)** — IAM binding never applied.
  Until Attila fixes it, SAP-side freshness depends on manual/other triggers. This is a live risk to
  every recon/ack decision downstream.

---

## PHASE 0 — Fix the documentation before writing any more code (do this first, it's cheap)
Stale design docs actively mislead future sessions. Correct, don't delete — keep the history visible.

**0.1 `docs/design/SAP_PIPELINE_E2E_DESIGN_v3.md`** — add a correction banner at the top and fix inline:
- ❌ "MERGE → raw_sap_live (SAP truth — B2)" → ✅ extract writes **temporary NDJSON** to
  `gs://rcb-bronze-zone/SAP/production_database/`, then **`sap-order-payment-initial-phase`
  (Cloud Run service, Eventarc-triggered)** loads it into `sap_integration_v2.SAP_LIVE` and deletes the file.
- ❌ "SUNSET B1 / gs://sap-bucket-csv / auto_load_sap_data_in_bucket_to_bigquery" → ✅ **there is no B1.**
  `gs://sap-bucket-csv` and `raw_sap_live` never existed. Remove the sunset plan entirely.
- ❌ "event chain must be built" → ✅ Path B **is already event-driven** (extract → Eventarc → loader).
  What's missing is chaining the **V3 SQL steps** (sap_state → recon → expected_state → validate → export).
- ❌ "SAP pull hourly, file ready for the 21:00 pull" → ✅ pull every 15 min (:00/:15/:30/:45), **processed
  at :30 each hour** (Boat, 07-25). Any export timing claim must be recomputed against this.

**0.2 `docs/design/SAP_DASHBOARD_DESIGN_v1.md`** — Page 4 freshness must read from `SAP_LIVE` /
`sap_extract_control` / `_watermark_state.json`, not `raw_sap_live.extracted_at`. Also add a widget for
**extract-scheduler health** (the 401 failure would have been invisible on the current design).

**0.3 `docs/design/SAP_DATA_PREP_DESIGN_v3.md`** — §5 `stg_sap_state` sources `raw_sap_live`; repoint to
`SAP_LIVE_FULL` and state the two-layer rule (doc-level evidence vs state-level opinion) explicitly.

**0.4** Grep the whole repo for `raw_sap_live`, `sap-bucket-csv`, `auto_load_sap_data_in_bucket_to_bigquery`,
`B1` and fix or annotate every hit. Then append one CHANGELOG entry recording that these were never real.

Acceptance: a fresh session reading only `docs/` cannot conclude that `raw_sap_live` exists.

---

## PHASE A — Safety net over the LEGACY pipeline (highest value; changes no file generation)

**A0. Unblock extract scheduling** — draft the exact ask for Attila (resource, role, member, and the
`gcloud` command he needs to run) and put it in `docs/INPUTS_NEEDED.md`. Do not attempt IAM changes.
Meanwhile document how extract is currently being triggered, so freshness isn't a mystery.

**A1. Column-contract guard** ← direct fix for the 2026-07-26 positional-import incident
Store the authoritative 56-column contract (name, ordinal, type) as a table in `sap_integration_v3`,
seeded from the real SAP destination schema. Nightly (before/right after the legacy export runs), compare
`INFORMATION_SCHEMA.COLUMNS` (ordinal_position, column_name) of **every** `sap_view.*` interface view
against it; any drift → `sap_validation_error` + Slack alert.
Acceptance: reordering a column in a scratch copy of a view triggers the alert.

**A2. Daily recon + alert on legacy output**
Expected (charge-driven, from `stg_payment_events`) vs actual (`stg_sap_state`) per (order_item, period)
for yesterday's business date → `recon_daily` + `interface_daily_status` with statuses
`OK / PENDING_ACK(≤D+2) / MISSING(>D+2) / STATUS_CONFLICT / PAID_AFTER_CANCEL / UNROUTED`.
Alert on MISSING/STATUS_CONFLICT, and if no status row exists by 07:30 ICT.
Acceptance: the known RCL new-payment cases and the EDC backlog appear automatically — no pasted lists.

**A3. Import-log ingestion — revised attachment-first spec**:
- Apps Script reads Gmail metadata, calls `getAttachments()`, and stores TXT/XLSX under
  `gs://rcb-bronze-zone/sap_import_logs/<LogID>/`.
- `sap_import_result` header schema: `log_id` (logical key), `file_name`, `status`, `import_type`,
  `company_db`, `email_date`, `txt_gcs_uri`, `xlsx_gcs_uri`, `ingested_at`.
- Second-stage TXT parse writes `sap_import_error_detail` at `(log_id, detail_seq)` grain with
  `error_class` (`STRUCTURAL`/`ROW_LEVEL`), `error_message`, `row_ref`.
- Apply Gmail label `ingested` only after persistence; it is the mailbox duplicate guard.
- `DOWNLOAD_GCS_FILE` messages have no LogID and go to separate `sap_file_pickup`; they prove file
  pickup/download only, not successful row import.
Acceptance: last night's attachments are durable in GCS; header/detail errors are queryable by
LogID and class; re-running ingestion creates no duplicate; file pickup is never conflated with
import success; Dashboard Page 3 can be built on the result tables.

**A4. Multi-document resolution (the real root cause)**
- `sap_mirror_doc` — every DocEntry, **no dedup** (evidence layer: cancel mirroring, InvoiceNo lookups, audit).
- `sap_mirror_state` — 1 row per (order_item, period); picking rule in **one place**, tagged
  `⚠️ PROVISIONAL` pending Aware's Q3a. Reconcile with the existing `stg_sap_state` — do not create a
  third competing definition; if `stg_sap_state` already fills this role, extend it instead and say so.
- Forensics before trusting any rule: distribution of docs per (item, period); characterise the extreme
  cases (one key had 496 docs) — are they **real repeated SAP postings** or mirror artifacts?
  **If real repeated postings → stop and escalate to Finance the same day. That outranks all pipeline work.**

**A5. Completeness evidence without SAP DB access** (item 1.8 is unreachable from the agent environment)
DocEntry gap/continuity analysis over time + cross-check against rows that import logs show as accepted.
Anything still unprovable → list in `INPUTS_NEEDED.md` as a 2-minute query for Boat to run at source.

**Exit criteria:** 5 consecutive days where the morning status is produced automatically and every gap
Finance would have reported by hand is already on the dashboard.

---

## PHASE B — Make `expected_state` interface-complete (still no file writing)
Extend to the full 56 columns **in contract order**, per flow (ONETIME / EDC_ONETIME / RCL_INSTALLMENT /
RCL_CMI / CREDIT_SHELL), sourced from `stg_order_dim` + `stg_schedule` + channel/payment mappings.
Non-negotiables: ProcessingFee RCL = /103.3 (confirmed) — **onetime stays /107 until Boat confirms**;
InvoiceNo only via `fn_invoice_no`, and already-posted rows mirror SAP's stored value verbatim;
additional-payment rule (rank>1 → Expected 0, Σ Actual = first row's Expected); dates `DDMMYYYY`;
PaymentDate clamped by `sap_accounting_cutoff_dates`; include Credit Shell (currently excluded).

**Acceptance = golden-file test:** take 3 files SAP accepted cleanly (create / newpayment / cancel),
regenerate the same population from `expected_state`, diff cell-by-cell. 0 diffs, or every diff explained
and approved in writing before continuing.

---

## PHASE C — Export layer in SHADOW MODE (writes files SAP never sees)
- Delta rule: export when a successful charge exists and `sap_mirror_state` for that (item, period) is not
  already in the target status — covers create, Pending→Paid, additional payment, cancel-needed; must not
  resend rows already exported and awaiting ack (`export_archive`).
- Cancel branch: CareOS cancelled + SAP active → full-schedule mirror per the inferred cancel spec
  (all periods 1..TotalPeriods, one row per period, InvoiceNo verbatim from SAP).
- Validation blocks before any write. **Policy decision needed from Boat: item-level quarantine vs
  run-level atomic (review item C2). Ask; do not choose silently.**
- Write to a shadow prefix SAP does not pull. **Never write to `gs://interface-file/**` in this phase.**
- Timing: recompute the chain so files land before a :30 processing window, not "21:00".
- Diff shadow vs the real legacy file nightly for ≥5 business days.

## PHASE D — Cutover, one file type at a time (each needs explicit "deploy OK")
Order: newpayment → create → cancel (cancel last: highest blast radius, Q3a may still be open).
Per type: 5 clean shadow days → switch producer → watch import errors 3 nights → next.
Keep the previous definition verbatim in `sql/ddl/` first; rollback must be < 5 minutes.

---

## Housekeeping
- Renumber duplicate `019_*.sql`; check `ls sql/ddl/` before naming.
- Propose moving the repo off the OneDrive path (spaces + CRLF churn + sync risk) — ask before moving.
- Orchestrate V3 SQL steps into one nightly chain (Cloud Workflows per corrected E2E) with
  `pipeline_run_log` written by every step and per-step failure alerts.
- Keep `docs/INPUTS_NEEDED.md` current: Q3a (Aware); onetime ProcessingFee, C2 policy, B2B (0 rows
  everywhere — confirm intentional), EDC channel matrix for non-KBANK banks (Finance); SAP source counts (Boat);
  IAM fix (Attila).

## Reporting rule
After each item: append `30_SAP_CHANGELOG.md`, update `20_SAP_PROGRESS.md`, and report a table of
built / verified-against-real-data / still-assumed. Unverified stays labelled unverified.
