# FINDINGS — SAP Mirror Gap Discovery (2026-07-26)

Executed against `TASK_CLEAN_SAP_MIRROR.md` STEP 1 (discovery-only, read-only, no approval needed).
All commands run live against `pacific-plating-282708`. **Nothing built yet — this is the report,
per the task's "Stop here and report. Do not build anything yet."**

## 1. Objects found

### `sap_integration_v2` (relevant subset — full list is 50+ objects, mostly ad-hoc analysis views)
| Object | Type | Rows | Distinct DocEntry | Batch date range | Verdict |
|---|---|---|---|---|---|
| `SAP_LIVE` | TABLE | **8,324,155**¹ | not recomputed in this pass | 2026-04-30 → 2026-08-15* | **Append-only incident evidence; heavily amplified** |
| `SAP_LIVE_2024` | TABLE | 538,548 | 538,548 | 2024-01-31 → 2024-12-30 | TRUSTED (historical shard, 1:1) |
| `SAP_LIVE_2025` | TABLE | 681,067 | 681,067 | 2024-12-30 → 2025-12-31 | TRUSTED (historical shard, 1:1) |
| `SAP_LIVE_2026` | TABLE | 573,706 | 386,485 | 2025-12-30 → 2026-06-30 | **Has duplicates too** (1.49 rows/doc) |
| `SAP_LIVE_FULL` | VIEW | 1,652,811 (post-dedup) | 1,652,811 | 2024-01-31 → 2026-08-15* | TRUSTED as a DocEntry-grain mirror, dedup logic is sound |
| `sap_extract_control` | TABLE | 0 | — | — | **DEAD / unused** — real watermark lives in GCS, not here |

*2026-08-15 max is 5 rows only (see §5, minor anomaly, not systemic staleness).

¹ Recomputed from `pacific-plating-282708.sap_integration_v2.SAP_LIVE` at
2026-07-30 13:53:09 UTC. This is a snapshot, not a live invariant, and was already stale after
Boat's later manual run at 21:53 ICT.

`sap_integration_v3` already has the P0–P3 objects built earlier this project (`stg_sap_state`,
`delta_export`, `expected_state`, `sap_validation_error`, `pipeline_run_log`, etc.) — unaffected by
this task, not re-examined here.

`SAP` dataset: legacy carepay reconciliation views/external tables (`IN_SAP_*`, `sap_carepay_view_*`).
Nothing here is a fresher or more complete SAP mirror than `sap_integration_v2.SAP_LIVE_FULL` —
these are all downstream analysis views built on top of it or its predecessors. **Branch A (a
fresher mirror exists elsewhere) does not apply.**

## 2. `SAP_LIVE_FULL` definition (read directly from BigQuery, not the repo)

Unions `SAP_LIVE`, `SAP_LIVE_2024`, `SAP_LIVE_2025`, `SAP_LIVE_2026` (all `sap_integration_v2`),
filters `WHERE U_InsuranceGroup <> 'B2B'` in every branch, then dedups by
`ROW_NUMBER() OVER (PARTITION BY DocEntry ORDER BY BatchRunDate DESC) = 1`. Per its own header
comment, this was already fixed 2026-07-07 to add the DocEntry-based dedup (previously used
`SELECT DISTINCT *`, which silently merged rows that had one differing column and lost data).
No row-dropping date filters beyond the B2B exclusion. **This view's logic is sound as a
DocEntry-grain mirror** — the "missing records" problem is not inside this view's SQL.

All 4 raw tables show **`b2b_rows = 0`** — B2B rows aren't merely filtered at this view, they don't
exist in any raw table today. Cannot confirm from BigQuery alone whether B2B is filtered at extract
(the repo's `main.py` copy) or simply doesn't apply to this business line — **needs Boat/Aware**,
not resolvable by query.

## 3. What the extract job actually does (contradicts the task doc's working assumption)

`sap-extract-job` (Cloud Run Job, watermark-based incremental, VPC connector `sap-connector` to
`172.25.25.3`):
- Writes **one JSON-array file per run** to `gs://rcb-bronze-zone/SAP/production_database/Results_<ts>_<uuid>.json`
- Watermark is tracked in **`gs://rcb-bronze-zone/SAP/_extract_control/_watermark_state.json`**
  (currently `2026-07-26T13:43:53Z`), **not** in the `sap_extract_control` BigQuery table (which is
  empty — dead code/table, safe to ignore or drop later, not urgent).
- Confirmed via live logs: recent runs 07-24 through 07-26 all `success`, `caught_up=True`, 1,593–5,454
  rows each.

## 4. The loader — found and confirmed WORKING (task doc's "Branch B" assumption is wrong)

The task doc assumed "nothing loads \[the GCS files\] reliably" (Branch B, called "most likely").
**This is not what the evidence shows.** The real loader is:

- **Cloud Run service `sap-order-payment-initial-phase`** (not a Cloud Function — a full Cloud Run
  service, `extract_sap_data_to_big_query` handler), triggered via an **Eventarc trigger**
  (`trigger-sap-order-payment-initial-phase`) subscribed to Pub/Sub topic
  `eventarc-asia-southeast1-trigger-sap-order-payment-initial-phase-861`.
- That topic is published to by **Cloud Scheduler job `auto_load_sap_data_in_bucket_to_bigquery`**,
  schedule `0 1 * * *` **Asia/Bangkok** (01:00 ICT nightly).
- Live logs confirm the full chain works: `Successfully loaded to pacific-plating-282708.sap_integration_v2.SAP_LIVE`
  → `Removed file SAP/production_database/Results_*.json`. This is why the GCS output folder is
  currently empty — **the loader deletes source files after a successful load, it isn't losing them.**
- Recent history (last 3 days of logs): loaded successfully every time it found files; logged
  `"No .json files to process"` on runs where the extract hadn't produced anything new (expected,
  not an error).
- **Loader only writes to `SAP_LIVE`** (the rolling/current table) — never touches the frozen
  `SAP_LIVE_2024/2025/2026` year shards, which is correct/expected (those are historical, one-time).
- **The loader appears to be a plain load-into-table (append), not a MERGE** — evidenced by
  `SAP_LIVE` having 151,024 rows for only 106,873 distinct `DocEntry` (1.41 rows/doc). This matches
  the task doc's predicted "Extract defect #3" (no DELETE/dedup branch) almost exactly, except it's
  in the **loader**, not a BigQuery MERGE step — same effect either way: `SAP_LIVE_FULL`'s
  `ROW_NUMBER()...ORDER BY BatchRunDate DESC` is currently the **only** place dedup happens.

**Verdict: the extract → GCS → load → SAP_LIVE chain is fundamentally working and reasonably fresh
(loaded as recently as today).** This directly contradicts the "stale/broken mirror" framing the
task doc opened with. The missing-records problem is very likely **not** "the mirror isn't being
refreshed" — see §6 for what the evidence actually points to.

## 5. Freshness anomaly (minor, contained — not the root cause)

5 rows in `SAP_LIVE` have `U_BatchRunDate = 2026-08-15` (3 weeks in the future relative to today).
All 5 are `RF*`/`RR*`/`RC*`-prefixed `U_OrderItem` values (refund/reversal/credit-note flows, not
`L`-prefixed motor/nonmotor orders) — looks like a distinct business flow with its own date
semantics, not a systemic clock/watermark bug. Flagging for Boat's awareness; **not blocking**,
doesn't change the branch recommendation below.

## 6. Multi-document grain — this is where the real "wrong decisions" evidence is

```
n_docs per (OrderItem, Period)   item_periods (count)
1                                 964,543
2                                 300,319
3                                  25,241
4                                   2,705
5–13                                   81
45                                      1
496                                     1   <-- one (OrderItem, Period) has 496 DocEntry rows
```

**31% of all (OrderItem, Period) combinations have 2+ DocEntry rows.** A flat DocEntry-grain mirror
(`SAP_LIVE_FULL` as-is) has no way to answer "what's the true state of this OrderItem/Period" when
there are multiple documents for it (change orders, endorsements, cancel-and-rebook, credit-shell
reissues) — a consumer that naively picks "any row" or "first row" for that combination can and will
get a stale/wrong status. **This is very likely the actual root cause of "rows SAP shows as Paid
appear Pending"** — not staleness, but **ambiguous document-to-state resolution** exactly as the
task doc's Step 3 (`sap_mirror_doc` + `sap_mirror_state` two-layer design) anticipated.

Ground-truth spot check (5 known orders, corrected for the real `U_OrderItem` suffix format —
`-V1`/`-M1`, not bare order IDs as originally listed in the task doc) confirms this pattern directly
and confirms the mirror is NOT globally stale at the raw level: e.g. `L80100211-V1` shows Period 2
= Pending and Period 3 = Paid (a later period paid before an earlier one — real, present in the
data, not a staleness artifact), and `L77921401` has separate `-M1` and `-V1` variants both present
for Period 1 with different `DocEntry`s. The raw data has the right facts; a flat single-row-per-doc
mirror just doesn't have a rule for picking among them.

## 7. SAP DB direct reachability (task item 1.8)

Not reachable from this environment — confirmed via `Test-NetConnection 172.25.25.3:1433` →
`TcpTestSucceeded: False`. The SAP DB is only reachable from inside the `sap-connector` VPC that
`sap-extract-job` runs in. **Cannot get true source-side row counts or `null_update_rows`/`b2b_rows`
without Boat running a query from within that job's environment (or granting a path).** Per the
task's own instruction, not guessing this number — marking as needs-Boat.

## 8. Branch decision

**None of Branch A/B/C as literally described fit.** The evidence says:
- The extract and load chain **is** working and reasonably fresh (contra Branch B's core assumption).
- No fresher/more-complete mirror exists elsewhere (contra Branch A).
- The data is not globally untrustworthy (contra Branch C).

**Recommended target: proceed straight to STEP 3 (build `sap_mirror_doc` + `sap_mirror_state` in
`sap_integration_v3`), skipping the Branch B "build our own loader" work** — the existing legacy
loader doesn't need replacing, it needs a proper two-layer mirror built **on top of** its output
(`SAP_LIVE_FULL`), because the actual defect is at the **resolution layer** (many DocEntry rows per
OrderItem/Period, no consistent priority rule), not at the **ingestion layer**. This is a narrower,
lower-risk task than Branch B/C implied — no need to touch the extract job, the loader, or build a
new external table/backfill pipeline.

Two things worth fixing opportunistically while building `sap_mirror_doc`/`sap_mirror_state` (both
cheap, both already anticipated by the task doc's "Extract defects to verify" section):
1. Confirm with Boat/Aware whether B2B should ever appear (currently 0 rows everywhere, at both
   extract and view level) — low priority, no evidence it's actively causing the reported problem.
2. Note for Boat: the append-only `SAP_LIVE` table (1.41 rows/DocEntry and growing forever) is a
   storage/cost concern longer-term, not correctness (since `SAP_LIVE_FULL` already dedups
   correctly) — no action needed now.

**Stopping here per the task's instruction. Not building `sap_mirror_doc`/`sap_mirror_state` yet —
want your confirmation on the branch call above before I start, since it changes scope from what the
task doc originally laid out.**

---

## ADDENDUM (2026-07-26, after go-ahead) — pre-build forensics + build result

Boat approved STEP 3 conditional on two additional checks before building the state layer. Both
done, both reported below, then `sap_mirror_doc`/`sap_mirror_state` were built and validated.

### 9. Duplicate-document forensics

Full distribution of DocEntry count per `(U_OrderItem, U_Period)`:

| n_docs | (item,period) keys | | n_docs | (item,period) keys |
|---|---|---|---|---|
| 1 | 964,543 | | 8 | 5 |
| 2 | 300,319 | | 9 | 2 |
| 3 | 25,241 | | 11 | 1 |
| 4 | 2,705 | | 13 | 5 |
| 5 | 37 | | 45 | 1 |
| 6 | 25 | | 496 | 1 |
| 7 | 11 | | | |

**The two largest buckets (496 and 45 docs) are data-quality artifacts, not real orders**:
`U_OrderItem = 'Invoice'` (496 rows, all `Period=1`, `BatchRunDate` 02–29 Apr 2024, mixed
Paid/Cancelled) and `U_OrderItem = 'SaleOrder'` (45 rows, all `Period=1`, all Paid, **NULL**
`BatchRunDate`) are SAP object-type labels that leaked into the OrderItem column — not real order
IDs. Excluded at the state layer (see §11).

The remaining genuine high-duplicate items (`L76956324-V1`, `L76915860-V1`, `L74212597-V1`, 6
`(item,period)` keys with 11–13 docs each) were inspected row-by-row. Pattern: **same
`GrossPremium`/`TotalPremium` across every duplicate, mostly identical `TransactionStatus =
Pending`, no `U_InvoiceNo`, and DocEntry values clustered tightly (often within a few hundred of
each other) on a small number of specific `BatchRunDate`s** (e.g. 10 distinct DocEntry rows for
`L76956324-V1` period 3, all dated `21032024`) — **not** one new row appearing every subsequent
night. This is not "real distinct SAP postings" in any obvious business sense (10 legitimate
separate documents for the same still-unpaid installment, same date, same amount, no invoice, is
not a plausible real-world SAP workflow) — it looks much more like **an extract-query fan-out
artifact, or genuine duplicate schedule rows that already exist in the source table itself**.
Cannot fully distinguish the two without SAP DB/Aware input — **flagged for Aware, not resolved
here.**

### 10. Completeness evidence without SAP DB access

**DocEntry gap analysis** (the strongest available signal): sorted all distinct `DocEntry` values
in `SAP_LIVE_FULL` and measured consecutive-pair gaps. **98.2% (1,622,566 of 1,652,810) of
consecutive pairs are perfectly contiguous (gap = 1).** Only 389 gaps exceed 100, only 45 exceed
1,000, biggest single gap 24,919. Since the extract's source is a single SAP table
(`[RCB_LIVE_DB].[dbo].[@INSURANCE]`), near-total contiguity is a strong completeness signal — the
existing gaps are consistent with the confirmed B2B exclusion (0 B2B rows in any table today) and
other non-installment row types the extract's own source query never selects, not with a systemic
hole.

**Concrete missing-DocEntry number** (re-run 2026-07-27, per Boat's A5 ask — closing the open
"add the number" item): summing every gap (`DocEntry - previous_DocEntry - 1`) across all
1,656,763 distinct `DocEntry` values in `SAP_LIVE_FULL` today (range 367,560 → 2,398,293) gives
**373,971 DocEntry values absent from the mirror** — 29,931 of 1,656,762 consecutive pairs
(1.8%) have any gap at all, one single gap accounts for 24,918 of that total (see below). This is
a **ceiling, not an estimate of real loss**: `DocEntry` is very likely a shared auto-increment
across SAP's whole `@INSURANCE`-adjacent table set, not an insurance-installment-only sequence, so
most of this gap is plausibly other business-object types the extract's own source query never
selects (confirmed intentional: the B2B exclusion alone is 0 rows today, not the explanation) —
not confirmable further without SAP DB access. Logged as an open item in `docs/INPUTS_NEEDED.md`
(a 2-minute query for Boat/Aware to run at source: total `@INSURANCE` row count and a breakdown by
row type, to convert this ceiling into a real number).

**Log-based reconciliation**: only possible since **~2026-07-20** — earlier executions (07-12
through 07-16) produced no structured row-count logging at all (an older code revision; the
`secrets-fixed: 20260720` label marks when this changed). Since 07-20, every successful execution
reported `caught_up=True`, including the run that absorbed a 3.75-day apparent outage
(2026-07-16 13:30 → 2026-07-20 09:13) in one 4-chunk, 47,888-row catch-up with no sign of loss. The
watermark file only advances on success (confirmed: 7 of ~20 lifetime executions failed, clustered
around initial deploy 07-12 and the 07-20 fix, and none of them advanced the watermark) — an
idempotent, retry-safe design that doesn't silently skip a failed window.

**Both checks point the same direction: ingestion completeness is not the problem.** This
reinforces the STEP 1 conclusion — the gap Boat is seeing is a resolution-layer problem
(§6/§9), not a missing-data problem.

### 11. Built: `sap_mirror_doc` + `sap_mirror_state`

- **`sap_mirror_doc`** (`sql/ddl/024_sap_mirror_doc.sql`, `sp_refresh_sap_mirror_doc`): same 4
  source tables and same per-DocEntry resolution as `SAP_LIVE_FULL`, but **no B2B filter** in any
  branch — "เก็บครบ, ห้าม dedup ข้าม DocEntry" as instructed. Deployed and run live:
  **1,652,811 rows = 1,652,811 distinct DocEntry** (matches `SAP_LIVE_FULL` exactly today, since
  B2B is still 0 everywhere — this table just won't silently start dropping them if that changes).
- **`sap_mirror_state`** (`sql/ddl/025_sap_mirror_state.sql`, `sp_refresh_sap_mirror_state`): one
  row per `(U_OrderItem, U_Period)`, built on `sap_mirror_doc`. The picking rule is isolated in a
  single, clearly-marked `ORDER BY` block (reused verbatim from `stg_sap_state`'s already-validated
  logic: Cancelled > Paid > Pending, non-empty InvoiceNo wins ties, latest BatchRunDate wins
  remaining ties) — the comment marks it as the one place to change when Aware answers Q3a. Every
  row carries `docs_considered` (fan-out count) and `resolution_confidence`
  (`UNAMBIGUOUS` when only one candidate existed, `PROVISIONAL_PENDING_AWARE_Q3A` when the picking
  rule actually had to choose among 2+). `'Invoice'`/`'SaleOrder'` junk rows excluded before ranking.
  Deployed and run live: **1,292,894 rows** (964,543 `UNAMBIGUOUS` + 328,351
  `PROVISIONAL_PENDING_AWARE_Q3A`, i.e. 25% of the state layer is a provisional pick pending Aware).
  Confirmed 0 rows with `U_OrderItem IN ('Invoice','SaleOrder')` made it through.

**Not done yet, deliberately**: neither table is wired into the nightly refresh chain
(`sp_nightly_state_and_recon_refresh`) or read by any consumer — that's a cutover decision (task
doc STEP 5), separate from building them, and needs its own explicit go-ahead.

---

## ADDENDUM 2 (2026-07-27) — §12: definitive forensics on the >10-doc cases (per Boat's ask, before touching stg_sap_state)

Boat asked for a hard answer — real SAP posting or artifact — on the 496-doc case and every
`(OrderItem, Period)` key with >10 documents, checked on three specific signals: does amount
repeat, does `BatchRunDate` progress nightly like a re-export, are `DocEntry` values genuinely
different. Queried `sap_mirror_doc` directly (live, 2026-07-27). All 8 keys with `n_docs > 10`:

| U_OrderItem | Period | n_docs | distinct DocEntry | distinct amount | distinct BatchRunDate | date range | statuses |
|---|---|---|---|---|---|---|---|
| `Invoice` (junk) | 1 | 496 | 496 | 374 | 21 | 2024-03-06 → 2024-05-08 | Cancelled, Paid |
| `SaleOrder` (junk) | 1 | 45 | 45 | 40 | 0 (all NULL) | — | Paid |
| `L76956324-V1` | 4 | 13 | 13 | **1** | 4 | 2024-03-19 → 2024-04-06 | Pending only |
| `L76956324-V1` | 5 | 13 | 13 | **1** | 4 | 2024-03-19 → 2024-04-06 | Pending only |
| `L76956324-V1` | 6 | 13 | 13 | **1** | 4 | 2024-03-19 → 2024-04-06 | Pending only |
| `L76915860-V1` | 3 | 13 | 13 | **1** | 4 | 2024-03-19 → 2024-04-02 | Pending, Paid |
| `L74212597-V1` | 6 | 11 | 11 | **1** | 3 | 2024-03-19 → 2024-04-04 | Pending only |

**Answering the 3 questions directly:**
1. **Amount duplicated?** Yes, for the 5 real-order keys — every single duplicate row within a key
   shares one identical `U_TotalAmount` (18,523.82 / 7,516.16 / 9,570.64×3). Not true for the 2 junk
   keys (374 and 40 distinct amounts across 496/45 rows — see below, different phenomenon).
2. **Does BatchRunDate progress nightly (re-export pattern)?** No. Row-level detail (pulled for all
   5 real-order keys) shows every duplicate clusters into **3-4 distinct dates total**, all inside a
   single ~2.5-week window (**2024-03-19 → 2024-04-06**), and **nothing recurs after that window** —
   not one new duplicate since. A true nightly re-export would show ~1 distinct date per doc,
   continuing to the present; this is the opposite — a closed, one-time historical cluster.
3. **Are DocEntry genuinely different?** Yes, every row (all 8 keys) has a distinct real `DocEntry` —
   this is not the same document appearing twice under different keys.

**The smoking gun (`L76915860-V1` period 3, row-level)**: 12 of its 13 rows are `Pending`,
`U_ActualReceived = 0`, `U_InvoiceNo = NULL` — dead placeholders that were never paid or invoiced,
ever. Exactly **one** row (`DocEntry 867756`) is `Paid`, carries a real `U_InvoiceNo`
(`P670231006408`) and a real `PaymentDate` (2024-03-29) — same amount as all the others. This is
the clearest possible evidence: one real posting, N inert duplicate placeholders. The other 4 keys
(all-Pending, zero ever invoiced/paid) are the same pattern minus the one real event — i.e. these
installments simply never got paid, and whatever process generated the schedule rows generated
10-13 duplicates of the not-yet-existing invoice instead of one.

**Verdict: artifact, not real repeated SAP postings.** None of this meets the "real distinct
business postings" bar that would require stopping and escalating to Finance — no case shows more
than one row per key ever carrying real money (`ActualReceived > 0` + real `InvoiceNo`), amounts
never differ within a key (real adjustments/endorsements would differ), and the entire phenomenon
is contained to a single ~2.5-week window over 2 years ago with zero recurrence since. Most likely
cause: a batch/schedule-generation defect (extract-side or SAP-side) active only during that
2024-03-19 → 2024-04-06 window — not confirmable further without SAP DB/Aware access, but not an
active or ongoing risk either way. `sap_mirror_state`'s picking rule (Paid > Pending, non-empty
InvoiceNo wins ties) already resolves every one of these keys correctly today — confirmed
`L76915860-V1`/period 3 picks `DocEntry 867756` (the real Paid+invoiced row), not one of the 12
dead Pending duplicates.

**Separate, smaller finding on the 2 junk keys** (`Invoice`/`SaleOrder`): these are NOT duplicate
postings of one order — `n_distinct_docentry = n_docs` (496=496, 45=45) and amounts vary widely
(374 distinct values across 496 rows), spread over weeks (`Invoice`) or with no BatchRunDate at all
(`SaleOrder`). This means **541 real, distinct SAP documents lost their true `U_OrderItem` value to
a literal type-label string** — a genuine (if old, 2024-03 to 2024-05, non-recurring) data-quality
defect, different in kind from the duplicate-schedule-row issue above. Already correctly excluded
from `sap_mirror_state` (§11); not re-opening this investigation further without SAP DB/Aware
access to trace why the real OrderItem was lost — noted in `docs/INPUTS_NEEDED.md`.

---

## ADDENDUM 3 (2026-07-27) — §13: reopened verdict on the 496 case + a real double-counting risk found elsewhere

Boat asked to reopen §12's verdict before trusting it: re-confirm the 496 case is really distinct
DocEntry, check whether it's a nightly re-export pattern, and — separately — check whether any
existing view/report `SUM`s over `SAP_LIVE(_FULL)` in a way that would multiply a total by however
many documents exist per period. If real documents genuinely exist in SAP, escalate regardless of
whether our own mirror already dedups correctly.

**1. Re-confirmed distinctness (`Invoice`, period 1, 496 rows)**: `COUNT(DISTINCT DocEntry) = 496`
— every row is still a genuinely separate document, not the same DocEntry counted twice. Unchanged
from §12.

**2. Re-checked the re-export-pattern question with a finer breakdown — found something §12 missed**:
grouping by `BatchRunDate` shows **442 of the 496 rows (89%) have a NULL `BatchRunDate`**, not
spread across the "21 distinct dates" §12 reported (that figure only counted the non-null 54 rows —
`COUNT(DISTINCT x)` silently excludes NULLs, and this wasn't caught before). The 442 NULL-date rows
still show wide amount variance (345 distinct amounts, min 108.07 to max 2,936,480.82) — the
opposite of what a single-document re-export would look like (which would show one narrow amount
repeating). Per-date breakdown of the remaining 54 non-null rows: 1-10 rows per date, scattered
across 21 dates from 2024-03-06 to 2024-05-08, with 1-8 distinct amounts per date (not 1) — still
consistent with **many different real transactions**, not one thing re-exported nightly. Verdict
from §12 stands: this is 496 genuinely distinct real transactions with a corrupted `OrderItem`
field, not duplicate postings of one order. (Correction noted for the record: the NULL-BatchRunDate
majority should have been called out in §12 and wasn't — fixed here.)

**3. The real finding: searched the repo + live BigQuery for any `SUM(...)` reading `SAP_LIVE`/
`SAP_LIVE_FULL` directly.** Found **`sap_integration_v2.sap_integrety_2025_RCL`** (a live, queryable
view, 301,188 rows) doing exactly the risky pattern Boat asked about:
```sql
sap_raw AS (
  SELECT REGEXP_REPLACE(U_OrderId, r'^C#', '') AS OrderID, U_OrderItem AS OrderItem,
         SAFE_CAST(U_Period AS INT64) AS Period,
         ROUND(SAFE_CAST(U_TotalAmount AS FLOAT64), 2) * CASE WHEN U_OrderId LIKE 'C#%' THEN -1 ELSE 1 END AS NetAmount
  FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
),
sap_net AS (
  SELECT OrderID, OrderItem, Period, SUM(NetAmount) AS SAP_NetAmount, ...
  FROM sap_raw GROUP BY OrderID, OrderItem, Period
)
```
This reads `SAP_LIVE_FULL` with **no per-(OrderItem,Period) dedup at all** before summing — every
extra document for a period adds its full amount into the total. Quantified live: of 1,508,026
(OrderID, OrderItem, Period) groups this logic produces, **144,013 (9.55%) have more than one
document contributing to the sum, and in 142,381 of those the summed total is measurably different
from what a single-document pick would give** — i.e. this view is producing a wrong total for
~142K real groups *right now*, independent of anything in `sap_integration_v3`. Related views found
by the same search, not yet individually re-verified: `sap_integrety_2025`, `sap_integrety_2025_Q1`,
`audit_010_careos_missing_in_sap_detail`, `int_01_careos_missing_in_sap_summary`,
`int_020_careos_cancelled_missing_summary`, `reconcile_revenue 202508_booking` (all in
`sap_integration_v2`/`sap_data_engineer`, all matched `SUM(...)` + `SAP_LIVE` in the same search).

**This is a real, confirmed, currently-live double-counting exposure — separate from and more
concrete than the 496/>10-doc "artifact" question.** Recommending Boat loop in whoever owns/consumes
`sap_integrety_2025_RCL` (name suggests a Finance-facing integrity/reconciliation report) before
trusting any total it has ever produced. Not modifying this view myself — it's outside
`sap_integration_v3` and outside this task's scope, and per the standing "propose first" rule this
needs Boat's call on both the fix and who else needs to know. Logged in `docs/INPUTS_NEEDED.md`.

---

## ADDENDUM 4 (2026-07-27) — §14: sap_integrety_2025_RCL consumers, THB impact, and the 6 related views (one table, per Boat's ask)

**⚠️ Kept strictly internal per Boat's instruction: not modifying any of these views, not
notifying anyone outside the team, holding for Boat's return 2026-07-30.**

**90-day consumer check** (`region-asia-southeast1.INFORMATION_SCHEMA.JOBS_BY_PROJECT`, exact
view-name text match, not memory):

| View | Real external consumers, last 90 days | Verdict |
|---|---|---|
| `sap_integrety_2025_RCL` | **None** — only 5 hits, all `data@rabbit.co.th` today (2026-07-27), all from this investigation itself | Structurally buggy but **dormant** — nobody has queried it directly in 90 days |
| `sap_integrety_2025_Q1` | **None** — same pattern, 1 hit today from this investigation | Dormant |
| `audit_010_careos_missing_in_sap_detail` | **Yes** — `piyaratt@rabbit.co.th` on 2026-05-06, 2026-05-29 (×2), 2026-06-05 — genuine, if infrequent, real usage | **Live** — this is the one that actually matters if it shares the bug |
| `int_01_careos_missing_in_sap_summary` | None found in the same search window | Appears dormant (not exhaustively re-verified) |
| `int_020_careos_cancelled_missing_summary` | None found | Appears dormant (not exhaustively re-verified) |
| `sap_integrety_2025` | None found | Appears dormant (not exhaustively re-verified) |
| `reconcile_revenue 202508_booking` | Not re-located during this pass (name suggests `sap_data_engineer` but wasn't found there under this exact search - **UNVERIFIED**, needs a proper re-check, not confirmed either way) | Unknown |

**All 5 of the other `sap_integrety_2025*`/`int_0*` views also `SUM()` an amount field with no
visible per-DocEntry/per-period dedup** (checked via `INFORMATION_SCHEMA.VIEWS` regex for
`ROW_NUMBER`/`QUALIFY`/`DISTINCT DocEntry` — none present in any of the 5). **Structurally the same
risk as `sap_integrety_2025_RCL`, not individually quantified** (time-boxed this investigation to
the one confirmed-consumed view plus the one with the largest name-recognition; a full per-view
THB quantification is a reasonable next step but wasn't done here).

**THB delta by year × business unit for `sap_integrety_2025_RCL` specifically** (summed amount
minus a single-document pick, for every (OrderID, OrderItem, Period) group where they differ;
junk `Invoice`/`SaleOrder` OrderItem values excluded; grouped by `U_InsuranceGroup` and the batch
year of the contributing documents):

| Year | Business Unit | Affected groups | THB delta (summed − single-doc) |
|---|---|---|---|
| 2024 | Motor | 48,065 | +231,279,163.14 |
| 2024 | Health | 4 | +93,691.56 |
| 2024 | Corporate | 4 | +778.96 |
| 2025 | Motor | 54,564 | +165,218,368.46 |
| 2025 | Corporate | 63 | +13,986,701.70 |
| 2025 | Health | 1,708 | +11,975,938.62 |
| 2025 | Motorbike | 6 | +17,978.73 |
| 2026 | Health | 7,531 | −14,710,900.18 |
| 2026 | Motor | 30,435 | −10,383,320.68 |
| 2026 | Inter | 2 | +36,712.00 |

**Read this carefully before treating it as "double-counted money"**: this is the raw arithmetic
difference between what this view's `SUM(NetAmount) GROUP BY (OrderID, OrderItem, Period)` produces
today vs. what a single-authoritative-document pick would produce, for every group where they
differ. It is **not** confirmed that all of it is erroneous overstatement — some portion is very
plausibly genuine (real endorsements/adjustments producing multiple real documents with
legitimately different amounts for the same period, which arguably *should* net together in some
cases). What **is** confirmed: the view has no defined rule for when summing vs. picking-one is
correct, so today's totals are unreliable by construction, in either direction (note 2026 shows
**negative** deltas — summed-lower-than-single-doc — the opposite direction, consistent with
inconsistent/undefined behavior rather than one-directional inflation). Given `sap_integrety_2025_RCL`
itself is dormant (no real consumer in 90 days), there's no evidence anyone has acted on a wrong
number from it recently — but `audit_010_careos_missing_in_sap_detail` **is** actively used and
has not been checked for the same pattern in this pass (time-boxed) — that's the one to check
first when this is picked back up.

---

## ADDENDUM 2026-07-30 — daily loader amplification and distinct-DocEntry loss check

**Read-only only; no loader change and no cleanup.** `SAP_LIVE` remains append-only audit history
until the incident closes.

Sources:

- BigQuery: `pacific-plating-282708.sap_integration_v2.SAP_LIVE`.
- SAP SQL Server: `[RCB_LIVE_DB].[dbo].[@INSURANCE]`, grouped by `U_BatchRunDate`; result supplied
  by Boat on 2026-07-30. Original SQL execution timestamp was **not captured**, so it must not be
  invented.
- Comparison query: executed through `scripts/bq_safe_query.sh` at
  **2026-07-30 09:10:41 UTC / 16:10:41 ICT**. Dry-run estimate:
  **133,186,480 bytes (0.124 GiB)**. It joined Boat's supplied daily SQL counts to BigQuery
  `COUNT(*)` and `COUNT(DISTINCT DocEntry)` by `DATE(U_BatchRunDate)`.

| Batch date | SQL `[@INSURANCE]` rows | BQ rows | BQ distinct DocEntry | Distinct − source | BQ/source rows |
|---|---:|---:|---:|---:|---:|
| 2026-08-15 | 5 | 5 | 5 | 0 | 1.000× |
| 2026-07-29 | 27 | 27 | 27 | 0 | 1.000× |
| 2026-07-28 | 58,619 | 1,465,475 | 58,619 | 0 | **25.000×** |
| 2026-07-27 | 2,076 | 4,226,950 | 60,385 | +58,309 | **2,036.103×** |
| 2026-07-26 | 8,578 | 2,484,385 | 66,952 | +58,374 | **289.623×** |
| 2026-07-25 | 817 | 1,584 | 1,584 | +767 | 1.939× |
| 2026-07-24 | 4,476 | 11,900 | 11,846 | +7,370 | 2.659× |
| 2026-07-23 | 851 | 1,578 | 1,578 | +727 | 1.854× |
| 2026-07-22 | 997 | 1,494 | 1,494 | +497 | 1.498× |
| 2026-07-21 | 1,791 | 3,011 | 3,011 | +1,220 | 1.681× |

`U_BatchRunDate=2026-08-15` is a value present in both supplied/current datasets; it is not the
query execution date.

### Real-loss conclusion

There is **no count-level evidence of real loss** for the ten supplied dates: BigQuery distinct
DocEntry is never below the SQL Server row count, and is exactly equal on 2026-07-28, 2026-07-29,
and 2026-08-15. This is not yet proof of zero loss. The SQL result supplied only daily row counts,
not the source DocEntry set or source distinct-DocEntry count; equal/greater counts cannot prove
set inclusion. Closing real loss requires an anti-join of the extracted/source DocEntry list
against `SAP_LIVE`, or equivalent source-side distinct IDs. Until then: **REAL LOSS NOT OBSERVED
BY COUNT, SET-LEVEL VERIFICATION OPEN**.

---

## ADDENDUM 2026-07-30 — corrected overwrite gate and root-cause retractions

Incident `INCIDENT-SAP-MIRROR-20260726` remains **OPEN** for storage/cost, prevention and
set-level loss verification. The accounting-overwrite gate is **CLEARED**.

### Corrected STEP A methodology

Source: `pacific-plating-282708.sap_integration_v2.SAP_LIVE`. Query timestamp:
**2026-07-30 14:27:28 UTC**.

The earlier comparison used earliest-versus-latest state across the whole lifecycle. That method
mixed legitimate issuance/payment progression into the overwrite test and is retracted.

- 63,757 DocEntries were in the target population.
- **54,055 WITH_BEFORE** had a last observation before 26/07 and were compared with the first
  observation in 26–28/07.
- **9,702 NO_BASELINE** had no pre-26/07 observation and were excluded; absence of evidence was
  not treated as a default value or POPULATION.

| Field | POPULATION | MUTATION A→B | A→default |
|---|---:|---:|---:|
| `U_ActualReceived` | 0 | 0 | 0 |
| `U_ExpectedReceived` | 0 | 0 | 0 |
| `U_TotalPremiumAmt` | 0 | 0 | 0 |
| `U_GrossPremiumAmt` | 0 | 0 | 0 |
| `U_VATAmt` | 0 | 0 | 0 |
| `U_StampDutyAmt` | 0 | 0 | 0 |
| `U_RefundAmt` | 0 | 0 | 0 |
| `U_RefundAmountAfterFee` | 0 | 0 | 0 |
| `U_InvoiceNo` | 822 | 0 | 0 |
| `U_PaymentDate` | 657 | 165 | 7,152 |
| `U_PaymentStatus` | 0 | 190 | 0 |
| `U_PolicyNo` | 9,911 | **39** | 0 |
| `U_PolicyStatus` | 0 | 822 | 0 |
| `U_ApprovalStatus` | 0 | 9,963 | 0 |
| `U_SubmissionStatus` | 0 | 2,124 | 0 |
| `U_Period` / `U_TotalPeriods` | 0 | 0 | 0 |

All monetary fields are zero in both change classes. `U_PolicyNo` non-empty→non-empty mutations
are 39/54,055 (0.072%) and collapse into a small number of repeated policy corrections, including
punctuation fixes and policy issuance alongside `PENDING → POLICY UPLOADED`; they are negligible
relative to 9,911 default→real policy populations.

**Verdict: CLEARED.** No evidence of a mass monetary overwrite. This is still a **LOWER BOUND**:
states written between extract runs but never observed by BigQuery cannot be recovered.

### `DocEntry 2345730` — WAITING HUMAN

This DocEntry has no observation before 26/07 and is outside WITH_BEFORE.

| Batch | UpdateDate/Time | PolicyStatus | Actual | Expected | Payment evidence |
|---|---|---|---:|---:|---|
| 07-26 | 07-27 03:41 | Pending | 2,200.00 | 2,200.00 | no invoice/date/method |
| 07-27 | 07-28 04:13 | Pending | 2,200.00 | 2,200.00 | no invoice/date/method |
| 07-28 | 07-29 03:54 | Paid | 1,554.79 | 2,200.00 | invoice + PaymentDate 07-28 + method/channel |

Invoice, PaymentDate and payment method appearing together is consistent with a partial-payment
event. `U_Discount=0`, so the evidence does not support a discount. The previous ฿645.21
accounting stop was caused by the wrong lifecycle boundary and is not evidence of mass overwrite.

Status: **WAITING HUMAN — Boat will verify with FA in the SAP UI.** Remaining question: why is
PolicyStatus `Paid` when Actual 1,554.79 is below Expected 2,200.00 by 645.21?

### Root-cause record

The following hypotheses are retracted:

1. **Loader crash-loop/full-bucket reread as primary cause.** The supported structural mechanism is
   BI interface import updating SAP-owned `UpdateDate`/`UpdateTime`, followed by correct watermark
   re-extraction and a plain-append loader.
2. **Watermark reset/deletion/failure-to-advance.** Fourteen generations advance continuously with
   no reset, gap or failed advance. Declining 60,404→60,385→58,619 counts do not fit replay from
   the default watermark.
3. **Unidentified SAP writer.** Boat confirmed BI interface import. The narrowed pathway observed
   in the writer window is schedulers `sap-order-payment` / `sap-order-payment-non-motor` at
   2026-07-26 18:30 ICT → `rcb-motor-order-payment-sap-bucket-1` /
   `rcb-nonmotor-order-payment-sap-bucket-1` → external SAP importer.
4. **Old aggregate amplification shorthand.** Use daily BQ/source ratios: 289.623× on 07-26,
   **2,036.103× peak on 07-27**, and 25.000× on 07-28.

### Separate open finding — normal-day baseline duplication

Days 21–25/07 are not 1:1: BQ/source ratios are 1.681×, 1.498×, 1.854×, 2.659× and 1.939×
(approximately 2.19× average). This baseline behavior had not previously been isolated. It is
separate from the acute 26–28/07 amplification and remains **OPEN**.

---

## ADDENDUM 2026-08-01 — UpdateDate comparison supplied by Boat

Boat supplied current counts grouped by `UpdateDate` from BigQuery `SAP_LIVE` and SAP SQL Server
`[RCB_LIVE_DB].[dbo].[@INSURANCE]`. The source-query execution timestamp and query text were not
supplied, so they must not be invented. BigQuery is `COUNT(DISTINCT DocEntry)`; the SAP result's
unnamed count column is treated as source rows, expected to be one row per DocEntry but not proven
distinct by the supplied output.

| UpdateDate | BQ distinct DocEntry | SAP source rows | BQ − source |
|---|---:|---:|---:|
| 2026-08-01 | 60,118 | 60,118 | 0 |
| 2026-07-31 | 59,280 | 2,261 | +57,019 |
| 2026-07-30 | 1,880 | 966 | +914 |
| 2026-07-29 | 58,619 | 725 | +57,894 |
| 2026-07-28 | 60,385 | 2,067 | +58,318 |
| 2026-07-27 | 62,081 | 3,871 | +58,210 |
| 2026-07-26 | 6,850 | 5,071 | +1,779 |
| 2026-07-25 | 1,832 | 923 | +909 |
| 2026-07-24 | 10,813 | 4,288 | +6,525 |
| 2026-07-23 | 1,603 | 1,097 | +506 |
| 2026-07-22 | 2,336 | 1,115 | +1,221 |
| 2026-07-21 | 1,832 | 1,814 | +18 |
| 2026-07-20 | 6,873 | 1,196 | +5,677 |
| 2026-07-19 | 8,657 | 1,097 | +7,560 |
| 2026-07-18 | 339 | 339 | 0 |
| 2026-07-17 | 32,033 | 13,936 | +18,097 |
| 2026-07-16 | 1,422 | 1,413 | +9 |
| 2026-07-15 | 1,009 | 1,004 | +5 |
| 2026-07-14 | 796 | 796 | 0 |
| 2026-07-13 | 77 | 77 | 0 |
| 2026-07-12 | 118 | 118 | 0 |
| 2026-07-11 | 899 | 897 | +2 |
| 2026-07-10 | 475 | 475 | 0 |
| 2026-07-09 | 1,190 | 1,090 | +100 |
| 2026-07-08 | 596 | 596 | 0 |
| 2026-07-07 | 981 | 1,045 | **−64** |
| 2026-07-06 | 2 | 42 | **−40** |
| 2026-07-05 | 652 | 505 | +147 |
| 2026-07-04 | 2,025 | 949 | +1,076 |
| 2026-07-03 | 2,587 | 1,396 | +1,191 |
| 2026-07-02 | 7,839 | 6,310 | +1,529 |
| 2026-07-01 | 15,836 | 6,527 | +9,309 |
| 2026-06-30 | 5,135 | not supplied | not comparable |

Interpretation:

- 01-Aug is an exact count match at 60,118, strong current-batch evidence but not proof of identical
  DocEntry membership. A source-ID anti-join is still required for set completeness.
- BigQuery is append-only snapshot history. The same DocEntry can remain under an older UpdateDate
  observation after SAP's current row advances, so positive BQ−source deltas do not mean SAP lost
  rows and cannot establish completeness.
- 06-Jul and 07-Jul are the only supplied comparable dates where BigQuery is lower, by 40 and 64.
  This is a new **count-level historical gap signal** requiring source distinct-DocEntry lists (or
  anti-join output) before assigning exact missing IDs. It does not establish that 104 unique
  documents are missing overall because date-bucket membership can change when a source row is
  updated.
- This UpdateDate comparison is different from the earlier BatchRunDate comparison and does not
  replace it. Mixing those date bases would create a false reconciliation.
