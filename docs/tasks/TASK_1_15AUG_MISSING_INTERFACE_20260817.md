# TASK — verify and recover the "1-15 Aug" missing-from-SAP population
Created 2026-08-17 | Trigger: Mo Pawinee (`pawineet@rabbit.co.th`) → Boat, relayed 2026-08-17 |
Owner approval: Boat | Executor: **Codex** (live BigQuery verification, then prepare-only interface
file; single-deployer rule — Claude Code cannot query BigQuery or write `gs://**` this session).

Scope is deliberately narrow: **only** the "1-15 Aug" missing-from-SAP population below. The same
sheet's "urgent_for refund to cust" tab (a refund-routing issue, not a SAP-import gap — see
`docs/INPUTS_NEEDED.md`) and Mo's separate Cancel-import / Changed-order-import asks are explicitly
**out of scope for this task** — tracked elsewhere, do not fold them in here.

## Why this file exists
Mo reported "pending 2,301 Orders" (1–15 Aug 2026, paid to Omise, not yet in SAP, excluding
changed-order-originated new orders) via her "RCL_missing order" Google Sheet. Rather than trust
either her summary count or a lossy text-export of the sheet, the exact population was extracted
from the sheet's own XML and is embedded in a ready-to-run verification query. This task is that
query plus the recovery work it unblocks.

## Confirmed facts (source-level, not just a summary count)
- Sheet: https://docs.google.com/spreadsheets/d/1BVnd49n_kxVQhqHIou70n_GbpRV-hlbXXQjscS5-upA
  ("RCL_missing order", owner `pawineet@rabbit.co.th`, last modified 2026-08-17T03:05:30Z).
- Downloaded as `.xlsx` and parsed `xl/workbook.xml` + `xl/worksheets/sheet6.xml` directly (the
  Drive connector's text-export flattens all 8 tabs in this workbook together with no gid/name
  boundary — not usable for this). Confirmed: tab "1-15 Aug" = internal `sheetId=6`,
  `state="visible"`, its own `_xlnm._FilterDatabase` range is `$A$4:$W$2305`.
- **2301 total data rows (rows 5–2305) — this literally is Mo's 2,301 figure.** Real row count in
  a real, currently-maintained sheet, not a fabricated number.
- **2295 of those rows** have the sheet's own status column (C) marked literally `"not on SAP"` —
  this is the systematic population, embedded verbatim as `(order_item, period)` pairs in
  `sql/adhoc/20260817_verify_mo_1-15aug_missing_from_sap.sql`. No duplicate pairs among the 2295.
  2288 distinct orders (some orders have >1 missing period).
- **6 rows are a different, non-standard shape** — excluded from the systematic 2295, listed here
  in full so they aren't lost: order IDs already carry an item suffix (no separate Period column
  value), 4-of-6 annotated `"paid + cc"` in the sheet's FA-note column — looks like a credit-card
  timing issue on compulsory items, not the same defect class as the rest:
  `L80544270-M1`, `L80519533-M1`, `L80489663-M1`, `L80541540-M1` (appears twice in the sheet — the
  sheet itself has a duplicate here, dedupe before triaging), `L80498125-M1`.
- **1 of the 2295** (`L80416399`, period 1) carries a free-text note suggesting Mo believes it may
  already be resolved ("...เป็น order เรียบร้อยแล้วค่า" — "already became an order"), despite its
  status cell still reading "not on SAP". Left in the 2295 (Phase 1 below will show its true live
  state either way) — don't silently trust the note or the status cell alone.
- The sheet's own tab header states "excl. changed order (Changed Order have to interface from
  CareOS data)" — Mo already tried to exclude changed-order-originated new orders manually. That
  exclusion is self-reported by the sheet, not independently verified by this task.

---

## Phase 1 — Live verification (read-only, mandatory, do first)

**Completed 2026-08-17:** all 2,295 pairs classified `STILL_MISSING_SILENT_DROP` (2,283 distinct
orders), job `bqjob_r1b11ba652f44370b_000001a00f046414_1`, dry-run 108,547,143 bytes. The flagged
order and five distinct non-standard `-M1` items were checked separately in
`sql/adhoc/20260817_spotcheck_mo_1-15aug_flagged_rows.sql`; see `docs/HANDOFF_QUEUE.md` for results
and job evidence. Phase 2 may use the 2,295 systematic pairs, but must expand accepted RCL items to
their full-period spines and pass the canonical pre-export gate; the non-standard `-M1` items remain
outside that population.

**File:** `sql/adhoc/20260817_verify_mo_1-15aug_missing_from_sap.sql` — already written, embeds
the 2295 `(order_item, period)` pairs above and classifies each against live `sap_integration_v3`:

- `ALREADY_IN_SAP_NOW` — sheet is stale (imported since the sheet's 03:05 ICT snapshot, or its
  status was already wrong).
- `LEGITIMATELY_EXCLUDED` — already in `sap_excluded_records` with a `rule_code`. EXCLUDED ≠
  DELETED; not a bug.
- `QUARANTINED_VALIDATION_ERROR` — already in `sap_validation_error`, known and logged.
- `STILL_MISSING_SILENT_DROP` — the real, actionable population. Per this project's charge-driven
  principle, every successful charge must end in SAP or in one of the two tables above; anything
  left in this bucket is a genuine silent drop.

Uses the same "real invoice" definition as `sql/ddl/005_recon_all_charges.sql`'s `sap_invoiced` CTE
(a period counts as in SAP only with a real `U_InvoiceNo`, not just any row/status).

**Steps**
1. `scripts/bq_safe_query.sh -f sql/adhoc/20260817_verify_mo_1-15aug_missing_from_sap.sql` —
   dry-run first per `COST_CONTROL.md` (should be cheap: ~2300 small literal rows joined against
   clustered/partitioned tables, but don't skip the check).
2. Report the classification breakdown (counts + distinct-order counts per bucket) back in
   `docs/HANDOFF_QUEUE.md`.
3. Rerun with the follow-up query in the file's trailing comment to get the exact
   `(order_item, period)` list for `STILL_MISSING_SILENT_DROP` — this is the Phase 2 population.
4. Separately spot-check `L80416399` period 1's live state given its note (see Confirmed facts).
5. Triage the 6 non-standard `-M1` rows separately — confirm whether "paid + cc" indicates a real
   credit-card-timing defect or an already-known/handled case; don't fold them into Phase 2 without
   this check.

**Acceptance:** a reported classification breakdown that sums to 2295, sourced from a live BigQuery
query with dry-run evidence, not from the sheet.

## Phase 2 — Prepare (NOT deploy) the interface file

Scope: **only** the `STILL_MISSING_SILENT_DROP` population confirmed in Phase 1 (re-excluding
`L80416399` if Phase 1 shows it's actually already resolved).

### Boat's mandatory interface invariants (2026-08-17)

These are hard, fail-closed acceptance gates. A candidate that violates any gate must be
quarantined with its reason and must not enter the shadow file.

1. **RCL and RCB must never mix.** Classify every candidate from canonical source attributes before
   projection. Each `(order_item, period)` must resolve to exactly one flow, and every order_item in
   this task must resolve to RCL. Reject a candidate if RCL/RCB indicators conflict, if the flow is
   unknown/NULL, or if one order_item spans both flows. Produce an explicit pre-export assertion
   proving zero mixed/unknown candidates; do not infer the flow from the destination filename.
2. **RCL always interfaces the full period spine.** For each included order_item with
   `TotalPeriods = N`, emit exactly one row for every integer period `1..N`, including already-paid
   periods and not-yet-paid periods. A partial subset such as only period 6 of 6 is prohibited.
   Paid periods remain `Paid`; unpaid periods remain `Pending`.
3. **No NULL interface values.** Before export, assert zero SQL NULLs and zero literal `"NULL"`
   values in every required interface column, including period, TotalPeriods, status, flow/channel,
   identifiers, dates, and amounts. The one canonical exception is representation, not data loss:
   `PaymentDate` may be the empty string only on a `Pending` row, as already defined in
   `docs/AGENT_RULES.md`; it must never be SQL NULL or the literal `"NULL"`. Any other empty required
   value is a validation failure.
4. **Required proof per order_item.** Assert `MIN(period)=1`, `MAX(period)=TotalPeriods`,
   `COUNT(*)=TotalPeriods`, `COUNT(DISTINCT period)=TotalPeriods`, every period is in `1..N`, and
   every status is exactly `Paid` or `Pending`. Also assert one canonical flow per order_item and
   reconcile the candidate row count to `SUM(TotalPeriods)` across the accepted order_items.

**Steps**
1. Determine routing: this likely overlaps either the existing V3 export effort (`delta_export`,
   Phase B/C — currently **ON HOLD** per `docs/knowledge/20_SAP_PROGRESS.md`, "V3 produces no
   interface file yet") or the legacy `sap_view.RCL_MOTOR` path (the only thing that actually
   produces real interface files today). Use judgment on which one this should route through
   rather than inventing a third path; if routing through V3 means touching something on hold,
   flag that explicitly and get Boat's call before proceeding.
2. Build the file per existing production conventions:
   - Exact positional column order — verify via `INFORMATION_SCHEMA.COLUMNS` before deploying any
     interface-feeding view; never `SELECT * EXCEPT(col), expr AS col` (moves the column to the
     end), use `SELECT * REPLACE(expr AS col)`.
   - Interface dates as `DDMMYYYY` strings; CarePay amounts in satang → `/100`, `ROUND(...,2)`.
   - `InvoiceNo` via `fn_invoice_no` only — never invented, and immutable (mirror verbatim) for any
     row that was ever Paid/Cancelled.
   - Through the validation stage — **never bypass validation before export, including urgent
     work.** Anything that fails validation goes to `sap_validation_error`/`sap_excluded_records`
     with its reason, not silently dropped or silently included.
   - Apply and retain evidence for all four mandatory interface invariants above before writing the
     shadow candidate.
   - Apply the complete canonical contract in
     `docs/design/SAP_INTERFACE_PRE_EXPORT_GATE.md`; the task-specific four invariants strengthen
     that contract and do not replace its universal or RCL checks.
3. **Write only to a shadow `gs://` prefix.** Never `gs://interface-file/**` — that is production,
   SAP pulls it every 15 minutes.
4. Stop. Present dry-run evidence + a one-paragraph change summary in `docs/HANDOFF_QUEUE.md`.
   **Do not write to `gs://interface-file/**` without Boat's explicit "deploy OK" in that session**
   — this task file is not that approval.

**Acceptance:** a shadow-written, validated RCL-only candidate interface file covering exactly the
accepted Phase-1-confirmed `STILL_MISSING_SILENT_DROP` order_items at their complete `1..N` period
spines, with Paid/Pending status per period, no prohibited NULL/`"NULL"` values, invariant-query
results, dry-run evidence, and a change summary ready for Boat's review — no production write.

**Phase-2 gate result, 2026-08-17: BLOCKED.** Order-to-item mapping yielded 1,873 distinct
unambiguous RCL items, but their canonical installment-source candidate failed the mandatory gate:
160 incomplete spines, 3,894 non-Paid/Pending rows, and 9,396 required-field SQL NULL rows. See
`docs/HANDOFF_QUEUE.md` for job IDs and byte evidence. No GCS object was written.

---

## Order of work
**Phase 1 (verify live) → report breakdown → Phase 2 (prepare + shadow-write only) → Boat's
explicit deploy OK → production write (separate, later, not part of this task).**
No BigQuery mutation or `gs://**` write beyond the shadow prefix without that explicit approval.
