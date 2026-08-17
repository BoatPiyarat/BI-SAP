# TASK — verify and recover the "EDC" missing-from-SAP population
Created 2026-08-17 | Trigger: Puii Somrudee (`somrudeeb@rabbit.co.th`) → Boat, relayed 2026-08-17 |
Owner approval: Boat | Executor: **Codex** (live BigQuery verification, then prepare-only interface
file; single-deployer rule — Claude Code cannot query BigQuery or write `gs://**` this session).

Scope is deliberately narrow: **only** the "EDC" tab's missing-from-SAP population below. The same
workbook has other tabs (`Bank`, `Omise`, `interface order (settle)`, `RCB interface issue_17Aug`,
`RCB Refund`, etc.) — **not read, not in scope**. This is a separate task from
`docs/tasks/TASK_1_15AUG_MISSING_INTERFACE_20260817.md` (different sheet, different owner, RCB/EDC
channel vs. RCL) — do not merge them.

## Why this file exists
Puii asked Boat to import data from the "EDC" tab of her "RCB update sheet." Rather than trust a
tab-name pointer alone, the tab was downloaded and parsed directly to get the exact population and
its data-quality caveats before handing this to Codex.

## Confirmed facts (source-level)
- Sheet: https://docs.google.com/spreadsheets/d/1T4QSlIaTZA2druwhxeJf-CdV9dogt3xo3U9nfEcvZAk
  ("RCB_missing_order", owner `somrudeeb@rabbit.co.th`, last modified 2026-08-17T06:44:32Z).
- Downloaded as `.xlsx`, parsed `xl/workbook.xml` + `xl/worksheets/sheet2.xml` directly (Drive's
  text-export flattens all 12 tabs together with no gid/name boundary — not usable here, same
  limitation hit on the 1-15 Aug task). Confirmed: tab "EDC" = internal `sheetId=2`,
  `state="visible"`, its own `_xlnm._FilterDatabase` range is `$A$1:$AK$853` → **852 data rows**.
- Columns actually populated: `A`=order, `B`=payment date (Excel serial), `C`=a CareOS filter-key
  helper (same `'OrderID',` quoted-string pattern as the RCL sheet), `D`=CareOS status,
  `E`=SAP status, `F`=Progress. No Period column — **this sheet is order-level, not
  order+period like the RCL sheet.**
- Of 852 rows: **495 have `Progress="Done"` / `SAP status="Paid"`** (already resolved, not part of
  this task); **33 carry an explicit Progress note citing a known block** (23 "not yet an order on
  CareOS", 6 "no CareOS order number yet", 3 "no order number", 1 explicit wrong-insurer
  cancellation) — already explained, not silent drops, not part of this task either.
  **324 rows have both `Progress` and `SAP status` blank — genuinely unactioned. This is the
  population.** 322 distinct order IDs after dedup (2 duplicate rows in the sheet itself).
  `495 + 33 + 324 = 852` — accounts for every row.
- Payment-date range for the 324: **2026-07-15 to 2026-08-15** (roughly a month, not a fixed
  half-month window like the RCL sheet).
- **Data-quality note**: column `D` ("CareOS status") is inconsistent — some rows show plausible
  CareOS lead/order statuses, others show what look like unrelated reference tokens (e.g.
  `"1_L78626567-M1"`, `"edc_L79856447-1"`). Not used for classification; flagged so it isn't
  silently trusted if referenced later.
- Per this project's confirmed decision **D11** (Boat 2026-07-30), `CREDIT_CARD_INSTALLMENT` is a
  ONETIME flow (`TotalPeriods=1`) — plausible fit for an "EDC" tab, but **do not assume every row
  here is that exact type without checking.** The verification query below checks "any period has
  a real invoice" rather than specifically period=1, to avoid a false-missing classification if
  that assumption is wrong for some rows.
- This project's **EDC channel matrix is an open, unresolved item** (`docs/INPUTS_NEEDED.md` /
  `AGENT_RULES.md` "Confirmed decisions": only `RCB-EDC-KBANK` confirmed; other banks pending
  Finance). If Phase 2 below needs to assign a channel per order, that gap may block it — flag
  rather than guess a bank.

---

## Phase 1 — Live verification (read-only, mandatory, do first)

**File:** `sql/adhoc/20260817_verify_puii_edc_missing_from_sap.sql` — already written, embeds the
322 distinct order IDs above and classifies each against live `sap_integration_v3`:

- `ALREADY_IN_SAP_NOW` — sheet is stale.
- `LEGITIMATELY_EXCLUDED` — already in `sap_excluded_records`. Not a bug.
- `QUARANTINED_VALIDATION_ERROR` — already in `sap_validation_error`. Known and logged.
- `STILL_MISSING_SILENT_DROP` — the real, actionable population.

Uses the same "real invoice" definition as `sql/ddl/005_recon_all_charges.sql`'s `sap_invoiced`
CTE, at order_item grain (any period, per the no-Period-column caveat above).

**Steps**
1. `scripts/bq_safe_query.sh -f sql/adhoc/20260817_verify_puii_edc_missing_from_sap.sql` —
   dry-run first per `COST_CONTROL.md`.
2. Report the classification breakdown back in `docs/HANDOFF_QUEUE.md`.
3. Rerun with the follow-up query in the file's trailing comment to get the exact order list for
   `STILL_MISSING_SILENT_DROP` — this is the Phase 2 population.
4. For that population, confirm each order's actual `TotalPeriods`/payment-option — do not assume
   ONETIME/period=1 for all of them without checking (see D11 caveat above).

**Acceptance:** a reported classification breakdown that sums to 322, sourced from a live BigQuery
query with dry-run evidence, not from the sheet.

## Phase 2 — Prepare (NOT deploy) the interface file

Scope: **only** the `STILL_MISSING_SILENT_DROP` population confirmed in Phase 1.

### Mandatory interface invariants (mirrors Boat's 2026-08-17 gates on the sibling RCL task,
adapted for RCB/EDC — see `TASK_1_15AUG_MISSING_INTERFACE_20260817.md` for the RCL original)

These are hard, fail-closed acceptance gates. A candidate that violates any gate must be
quarantined with its reason and must not enter the shadow file.

1. **RCL and RCB must never mix.** Classify every candidate from canonical source attributes before
   projection. Every order_item in this task must resolve to **RCB** (this is the EDC/RCB task, the
   inverse of the sibling RCL task). Reject a candidate if RCL/RCB indicators conflict, if the flow
   is unknown/NULL, or if one order_item spans both flows. Produce an explicit pre-export assertion
   proving zero mixed/unknown/RCL-classified candidates; do not infer the flow from the destination
   filename or from the "EDC" tab name alone.
2. **RCB interfaces the full period spine.** Do not assume `TotalPeriods=1` for every row just
   because this looks like an EDC/ONETIME tab (see the D11 caveat in Confirmed facts above) —
   determine the real `TotalPeriods` per order_item from source data. For each included order_item
   with `TotalPeriods = N`, emit exactly one row for every integer period `1..N`, including
   already-paid and not-yet-paid periods. Paid periods remain `Paid`; unpaid periods remain
   `Pending`.
3. **No NULL interface values.** Before export, assert zero SQL NULLs and zero literal `"NULL"`
   values in every required interface column, including period, TotalPeriods, status, flow/channel,
   identifiers, dates, and amounts. The one canonical exception: `PaymentDate` may be the empty
   string only on a `Pending` row, per `docs/AGENT_RULES.md`; it must never be SQL NULL or the
   literal `"NULL"`. Any other empty required value is a validation failure.
4. **Required proof per order_item.** Assert `MIN(period)=1`, `MAX(period)=TotalPeriods`,
   `COUNT(*)=TotalPeriods`, `COUNT(DISTINCT period)=TotalPeriods`, every period is in `1..N`, and
   every status is exactly `Paid` or `Pending`. Also assert one canonical flow (RCB) per order_item
   and reconcile the candidate row count to `SUM(TotalPeriods)` across the accepted order_items.

**Steps**
1. Determine routing (legacy `sap_view.RCL_MOTOR`/equivalent RCB path, or V3 `delta_export` — V3
   Phase B/C is currently **ON HOLD**; flag rather than silently build on top of it). If any order
   needs a channel assignment (`RCB-EDC-<bank>`) and the bank isn't KBANK, stop and route to
   `docs/INPUTS_NEEDED.md` — the channel matrix gap is a human decision, not something to guess.
2. Exact positional column order (`INFORMATION_SCHEMA.COLUMNS`, `SELECT * REPLACE(...)` never
   `SELECT * EXCEPT(...)`), `DDMMYYYY` dates, satang/100 amounts rounded 2dp, `InvoiceNo` via
   `fn_invoice_no` only (immutable if ever Paid/Cancelled), through the validation stage — never
   bypassed, including urgent work. Apply and retain evidence for all four invariants above before
   writing the shadow candidate.
3. **Write only to a shadow `gs://` prefix.** Never `gs://interface-file/**`.
4. Stop. Present dry-run evidence + a one-paragraph change summary in `docs/HANDOFF_QUEUE.md`.
   **Do not write to `gs://interface-file/**` without Boat's explicit "deploy OK"** — this task
   file is not that approval.

**Acceptance:** a shadow-written, validated RCB-only candidate interface file covering exactly the
accepted Phase-1-confirmed `STILL_MISSING_SILENT_DROP` order_items at their complete `1..N` period
spines, with Paid/Pending status per period, no prohibited NULL/`"NULL"` values, invariant-query
results, dry-run evidence, and a change summary ready for Boat's review — no production write.

---

## Order of work
**Phase 1 (verify live) → report breakdown → Phase 2 (prepare + shadow-write only) → Boat's
explicit deploy OK → production write (separate, later, not part of this task).**
No BigQuery mutation or `gs://**` write beyond the shadow prefix without that explicit approval.

## Known blocker (as of 2026-08-17T15:30+07:00)
Codex's attempt at the sibling `TASK_1_15AUG_MISSING_INTERFACE_20260817.md` Phase 1 failed before
execution: mandatory `scripts/bq_safe_query.sh` dry-run hit `ReauthUnattendedError` on legacy
`bq 2.0.92` (see `docs/HANDOFF_QUEUE.md` and `docs/INPUTS_NEEDED.md` "bq CLI reauth" entry, open
since 2026-08-10). This task will hit the identical blocker until that's resolved — don't
re-diagnose it here, it's the same root cause, already tracked.
