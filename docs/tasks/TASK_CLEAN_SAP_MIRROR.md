# TASK-CLEAN — Close the SAP mirror gap (discovery-first)
Created: 2026-07-26 by design review (chat) | Executor: **Claude Code** | Owner approval: Boat
Supersedes: METHOD_CLEAN_SAP_LIVE_FULL.md (that doc assumed `sap_integration_v2.raw_sap_live` exists — **it does not**)

## Problem statement (confirmed by Boat)
`SAP_LIVE_FULL` is missing a large number of records, so interface files (create / newpayment / cancel)
make wrong decisions — rows that SAP already has appear missing, and rows SAP shows as Paid appear Pending.

## Ground rules for this task
- **Do not assume any table/view/job exists. Verify everything with read-only commands first.**
  Known-wrong assumptions already burned us: `raw_sap_live` (does not exist), and the repo copy of
  `main.py` (deployed env vars have no `BQ_DATASET`/`RAW_TABLE`/`GCP_PROJECT`, and do have
  `GCS_PREFIX=SAP/production_database` — so the deployed extract very likely writes **files to GCS**,
  not a BigQuery MERGE. Verify from the deployed job, not from the repo file.)
- DDL only in `sap_integration_v3`. Never CREATE/ALTER/DROP in `sap_integration_v2`, `SAP`, or `careos`.
- Replacing anything existing consumers read (incl. `SAP_LIVE_FULL`) needs Boat's explicit "deploy OK".
- Report findings in a table before proposing the fix. If discovery contradicts this spec, say so and stop.

---

## STEP 1 — DISCOVERY (read-only, no approval needed, do all of it)

**1.1 What SAP-side objects actually exist**
```bash
bq ls --max_results=200 pacific-plating-282708:sap_integration_v2
bq ls --max_results=200 pacific-plating-282708:SAP
bq ls --max_results=200 pacific-plating-282708:sap_integration_v3
```
For every table/view whose name suggests SAP mirror data (`SAP_LIVE*`, `raw*`, `stg_sap*`, `IN_SAP*`):
`bq show --format=prettyjson <ref>` → record: type (TABLE/VIEW/EXTERNAL), row count, size,
last modified, partitioning/clustering. For VIEWs, capture the definition.

**1.2 How `SAP_LIVE_FULL` is currently defined** (this is the object that is wrong — read it first)
```bash
bq show --view --format=prettyjson pacific-plating-282708:sap_integration_v2.SAP_LIVE_FULL
```
Write down: which base tables it unions, how it dedups, any date/group filters that silently drop rows
(e.g. `PolicyDate NOT LIKE '%2023%'`, `U_InsuranceGroup NOT IN (...)`, `SELECT DISTINCT *`).

**1.3 What the extract job really does**
```bash
gcloud run jobs describe sap-extract-job --region=asia-southeast1 --format=yaml
gcloud logging read 'resource.labels.job_name="sap-extract-job"' --limit=80 --freshness=3d
gsutil ls -l "gs://rcb-bronze-zone/SAP/production_database/**" | tail -20
gsutil ls -l "gs://rcb-bronze-zone/SAP/_extract_control/**" | tail -5
```
Answer explicitly: does the extract write **GCS files**, a **BigQuery table**, or both? What is the
newest object/row it produced, and is that consistent with a nightly 20:30 ICT run?

**1.4 What loads GCS → BigQuery (the B1 path)**
```bash
gcloud scheduler jobs describe auto_load_sap_data_in_bucket_to_bigquery --location=asia-southeast1
gcloud functions list --project=pacific-plating-282708 --gen2
gcloud functions list --project=pacific-plating-282708
```
Then, for whichever function/service is the loader: which bucket/prefix does it read, which table does
it write, on what schedule, and did it succeed last night? Check its logs.

**1.5 Freshness & completeness of the current mirror** (adapt table names to what 1.1 found)
```sql
-- per source table: coverage & freshness
SELECT COUNT(*) rows_, COUNT(DISTINCT DocEntry) docs,
       MIN(SAFE.PARSE_DATE('%d%m%Y', BatchRunDate)) min_batch,
       MAX(SAFE.PARSE_DATE('%d%m%Y', BatchRunDate)) max_batch,
       COUNTIF(DocEntry IS NULL) null_docentry,
       COUNTIF(U_InsuranceGroup = 'B2B') b2b_rows
FROM `pacific-plating-282708.sap_integration_v2.<TABLE>`;
```
Run for every base table behind SAP_LIVE_FULL. **A max_batch older than yesterday = the mirror is stale
and that alone explains wrong interface decisions.**

**1.6 Multi-document grain** (decides the target design; also answers review item C5)
```sql
SELECT n_docs, COUNT(*) item_periods FROM (
  SELECT U_OrderItem, U_Period, COUNT(DISTINCT DocEntry) n_docs
  FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL` GROUP BY 1,2)
GROUP BY n_docs ORDER BY n_docs;
```

**1.7 Ground truth spot-check (5 known orders)** — `L77921401`, `L78034906`, `L78222896`, `L80100211`, `L77616707`:
per (OrderItem, Period) list status + InvoiceNo from the current mirror. These are known from earlier
investigation to have later-paid periods; if the mirror shows Pending/blank where SAP has Paid+invoice,
staleness is confirmed at row level.

**1.8 If SAP DB is reachable** (via the extract job's tunnel — do not open new network paths):
count rows at source and, critically:
```sql
SELECT COUNT(*) total_rows,
       SUM(CASE WHEN UpdateDate IS NULL OR UpdateTime IS NULL THEN 1 ELSE 0 END) null_update_rows,
       SUM(CASE WHEN U_InsuranceGroup = 'B2B' THEN 1 ELSE 0 END) b2b_rows
FROM [RCB_LIVE_DB].[dbo].[@INSURANCE];
```
If not reachable from your environment, say so and mark this as needing Boat — do not guess the number.

### Deliverable of STEP 1 → `docs/FINDINGS_SAP_MIRROR_20260726.md`
A table of: object → type → rows → freshness → who writes it → verdict (TRUSTED / STALE / UNKNOWN),
plus a short "why records are missing" section citing the evidence above, and which branch below applies.
**Stop here and report. Do not build anything yet.**

---

## STEP 2 — BRANCH (pick from STEP 1 evidence, state which and why)

**Branch A — a fresh BigQuery mirror exists under another name** (e.g. something in `SAP` or `v3`)
→ Target: build `sap_integration_v3.sap_mirror_doc` on top of it (dedup by DocEntry, newest batch via
`SAFE.PARSE_DATE`, no row-dropping filters), then Step 3.

**Branch B — the extract only produces GCS files; nothing loads them reliably** (most likely, per 1.3/1.4)
→ Target: build the load ourselves in v3, so we stop depending on the legacy loader:
1. Point a BigQuery **external table** at the extract output (fastest, no copy):
   `sap_integration_v3.ext_sap_extract` over `gs://rcb-bronze-zone/SAP/production_database/*`
   (detect the real format first — NDJSON vs single JSON array vs CSV — from 1.3; the legacy loader is
   known to require ONE JSON array per file, so files may be array-formatted, which external NDJSON
   tables cannot read. If so, load via a BigQuery load job with the right `source_format` instead.)
2. `sap_integration_v3.sap_mirror_doc` = MERGE from that external/staging into a real table, key `DocEntry`,
   newest-batch wins. Idempotent, re-runnable.
3. Backfill history: if the extract is watermark-based, seed the control record back to an early date and
   run the job once per year-slice (respect `--task-timeout`); if the extract is full-dump, one run suffices.

**Branch C — nothing trustworthy exists anywhere** → re-extract from SAP DB is the only source of truth.
Fix the extract first (see "Extract defects to verify" below), then run the historical backfill, then Step 3.

---

## Extract defects to verify before any backfill (from the repo copy of main.py — confirm against deployed code)
1. `AND U_InsuranceGroup <> 'B2B'` → B2B rows may never be extracted at all. Check 1.8's `b2b_rows` and
   whether the current mirror contains B2B. If business needs them, filter at **export**, never at extract.
2. Watermark predicate `DATEADD(...UpdateTime..., UpdateDate) > ?` yields NULL when either field is NULL
   → those rows are **permanently invisible** to an incremental extract. Fix:
   `... > ? OR UpdateDate IS NULL OR UpdateTime IS NULL`. Check 1.8's `null_update_rows` for the size.
3. MERGE has no DELETE branch → rows deleted in SAP linger forever (over-count, not under-count).
   Decide and document: keep (with a `seen_at` column) or hard-delete on full refresh.

---

## STEP 3 — TARGET DESIGN (build in v3; do not touch v2 yet)

Two layers — one flat mirror is what caused the cancel failures:
- **`sap_mirror_doc`** — one row per `DocEntry`, nothing dropped. Use for: cancel-file mirroring, invoice
  lookups (InvoiceNo is immutable — must match what SAP actually stores), audit.
- **`sap_mirror_state`** — one row per (OrderItem, Period): priority `Cancelled > Paid > Pending`,
  non-empty InvoiceNo wins. Use for: delta export, recon, dashboards.
Both clustered by `U_OrderItem`. Write row counts + freshness into `pipeline_run_log` on every refresh.

## STEP 4 — VALIDATE (all must pass; report as a table)
| Check | Pass criterion |
|---|---|
| No regression | Every `DocEntry` present in the legacy union is present in `sap_mirror_doc` (0 missing) |
| Coverage vs source | `COUNT(DISTINCT DocEntry)` ≈ source total from 1.8 (explain any gap) |
| Row-level truth | The 5 spot-check orders from 1.7 now match SAP's real status/InvoiceNo per period |
| Interface impact | Re-run delta/gap logic on old vs new mirror; every disappearing "MISSING" must be explainable as a stale-mirror false positive |
| Freshness | mirror max batch = last night |

## STEP 5 — CUTOVER (needs Boat's explicit approval, one step at a time)
1. Snapshot first: `CREATE TABLE sap_integration_v3.archive_<name>_20260726 AS SELECT * FROM <legacy>` for
   every legacy base table (rollback insurance — do this before anything else).
2. Repoint `sap_integration_v2.SAP_LIVE_FULL` → view over `sap_mirror_doc` (same column names/order/types
   as today; verify with `INFORMATION_SCHEMA.COLUMNS` — **column ORDER matters, SAP import is positional**).
3. Parallel-run 5 business days: compare generated interface files old vs new; import error rate must drop.
4. Then pause the legacy loader schedule; freeze legacy tables read-only for 1 month before deletion.
5. Update `10_SAP_CONTEXT.md` + `30_SAP_CHANGELOG.md` with the new truth and the two-layer rule.

**Rollback:** restore the previous `SAP_LIVE_FULL` view definition (keep it verbatim in
`sql/ddl/` before changing it) and re-enable the loader schedule. Must be < 5 minutes.
