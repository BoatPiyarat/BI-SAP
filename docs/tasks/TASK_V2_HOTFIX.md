# TASK-V2-HOTFIX — back-port V3 fixes into the live legacy pipeline
Created 2026-07-29 | Executor: **Claude Code** (SQL/deploy domain) | Owner approval: Boat
Goal: stop the daily "missing / cancel error" bleeding **now**, while V3 Phase B–D is still weeks away.
Scope this file: **H2, H3, H4 only.** H5–H7 are deliberately out of scope (separate approval each).

## Why these three
- **H2** = one-line fix, closes an entire product line (NonMotor RCL installment) that never passes the filter.
- **H3** = one-off recovery of already-quantified backlog; touches no production view at all.
- **H4** = the cancel picking-rule that V3 already proved, applied to the legacy cancel flow that
  currently fails ~100 orders/night.
Bonus: each one field-tests V3 logic on real data before cutover.

## Non-negotiable rules for this task
1. **One view at a time.** Never edit two interface-feeding views in the same deploy.
2. **Column order is a contract.** Before and after every view change, dump
   `INFORMATION_SCHEMA.COLUMNS (ordinal_position, column_name)` and diff. Any movement = abort.
   Never use `SELECT * EXCEPT(col), expr AS col` — use `SELECT * REPLACE(expr AS col)`.
   (Root cause of the 2026-07-26 incident: a moved column broke SAP's positional import for a whole file.)
3. **Keep the previous definition verbatim** in `sql/ddl/` before changing anything → rollback < 5 min.
4. **Shadow diff before production**: build the fixed version as a *separate* view
   (`sap_view_shadow.<name>`), diff against the live one, review, and only then swap.
5. **Deploy gate**: each swap needs Boat's explicit "deploy OK" in that session.
6. Cost rules apply (`docs/COST_CONTROL.md`): dry-run first, `--maximum_bytes_billed`, one query many metrics.
7. Row-count parity is **not** proof. Compare distributions and sample rows.

---

## H2 — NULL-safe item-type filter (NonMotor RCL)

**Bug:** filters written as `motor_item_type != 'MOTOR_TYPE_COMPULSORY'` silently drop rows where the
column is NULL (BigQuery three-valued logic). NonMotor items typically have NULL here → an entire
product line never passes. Confirmed pattern (A2 in the problem inventory); the same shape may exist in
several views.

**Steps**
1. Inventory first (read-only): grep every view/query feeding an interface file for
   `motor_item_type !=`, `<>`, `NOT IN` — list file, view name, line. Report the list before editing.
2. For each hit, the correct predicate is:
   `(motor_item_type != 'MOTOR_TYPE_COMPULSORY' OR motor_item_type IS NULL)`
3. Quantify per view **before** changing anything: how many extra (order_item, period) rows would appear,
   split by year and by `is_cancelled_effective`, and how many already exist in `sap_mirror_state`
   (i.e. would be no-ops). **If the extra population is large, stop and report — do not deploy blind.**
4. Shadow view → diff vs live (row count, distribution, 5 sample rows) → column-order check → swap
   (one view, with approval) → verify next night's file.

**Acceptance:** extra rows appear only where a SUCCESSFUL charge exists; column order unchanged;
no year ≤2024 rows introduced (year scope still applies); next-night import errors do not increase.

---

## H3 — Recovery batch from V3 tables (no production view touched)

Three already-quantified populations:
| Population | Size | Source of truth |
|---|---|---|
| Cancel actionable | **⚠️ superseded sizing: 419 items / ≈฿5.68M**; re-derive before use | session `402904b`; corrected by `fa9b351` |
| EDC / `CREDIT_CARD_INSTALLMENT` backlog | ~70 orders | earlier diagnosis |
| RCL new-payment (Pending→Paid) | 27 order-period pairs | earlier diagnosis |

The corrected provisional diagnostic in `fa9b351` is 296 actionable items / approximately
THB 3.89M before year scope and 41 items / THB 720,307.31 in approved 2025/2026+ scope. Sources:
`careos.careos_order_items`, `careos.careos_orders`, and
`sap_integration_v3.sap_mirror_state`; queried 2026-07-29, exact query timestamp not captured,
evidence committed 2026-07-29 18:46:14 ICT. These are planning inputs only; step 1 still requires
re-derivation from current V3 tables.

**Steps**
1. Re-derive each list **from current V3 tables** (`sap_mirror_state`, `expected_state`,
   `sap_excluded_records`) — do not reuse pasted lists from chat; sizes may have changed.
2. Apply exclusion rules E1–E3 and year scope. Report the final counts per population, split by year.
   For cancel: only items already present in `sap_mirror_state` are eligible.
3. **Per-item-only rule for cancel:** cancel rows must cover exactly the cancelled `order_item`.
   Verify explicitly that **zero active sibling items** appear in the output (98.5% of this population
   has an active sibling — partial cancel-recreate is normal practice, and dragging a sibling in would
   cancel a live policy).
4. Cancel file shape must follow the inferred cancel spec: all periods 1..TotalPeriods, one row per
   period, `InvoiceNo` mirrored verbatim from `sap_mirror_doc`, statuses of other periods Paid/Pending.
5. Write to a **shadow prefix** first. Run the full validation set. Report:
   rows, items, Σ ActualReceived, and any validation blocks with reasons.
6. Then, and only with approval: send **one small pilot batch** (≤50 items) to production, wait for the
   SAP import result, confirm zero errors, and only then release the rest in batches of ≤500.
7. Track every sent row through `export_archive` → `sap_import_result` → recon ack. Anything not acked
   within D+2 gets reported, not silently forgotten.

**Acceptance:** pilot batch imports with zero errors; no active sibling ever appears in a cancel file;
every sent row reaches acked state or has a recorded reason.

⚠️ **Business gate:** the 7 known `PAID_AFTER_CANCEL` cases stay out of this batch — FA must confirm
intent first (payments continued after cancellation).

---

## H4 — Fix the legacy cancel flow using V3's proven picking rule

**Bugs in the legacy cancel query (`02 RCB Motor cancel-new` and its NonMotor twin):**
- the `dup = 1` filter is commented out → multiple documents per (OrderItem, Period) go out → SAP rejects
  the whole order (`Sequence of Period invalid`, `InvoiceNo is duplicated`)
- `ORDER BY BatchRunDate DESC` sorts a `DDMMYYYY` **string** → "31032026" beats "16062026"; this exact
  bug caused stale rows for 44,781 keys in `sap_mirror_doc` before it was fixed there
- no status priority → a Pending document can win over the Paid one for the same period, so the file
  carries an empty `InvoiceNo` where SAP holds a real one → `Cannot change InvoiceNo when status Paid`
- hardcoded `U_OrderID IN (...)` lists left in production queries

**Fix (identical logic to `sap_mirror_state`, which is already validated):**
```sql
ROW_NUMBER() OVER (
  PARTITION BY U_OrderItem, SAFE_CAST(U_Period AS INT64)
  ORDER BY
    CASE WHEN TransactionStatus IN ('Cancelled','Cancelled (Change order / Rejected)') THEN 0
         WHEN TransactionStatus IN ('Paid','paid') THEN 1 ELSE 2 END,
    CASE WHEN IFNULL(U_InvoiceNo,'') != '' THEN 0 ELSE 1 END,
    SAFE.PARSE_DATE('%d%m%Y', BatchRunDate) DESC,
    DocEntry DESC                    -- deterministic final tiebreak
) = 1
```
**Better still:** have the legacy cancel view read `sap_integration_v3.sap_mirror_state` directly instead
of re-implementing the rule. Evaluate both options and recommend one — a single definition is the whole
point, but only if the column set required by the interface file is fully available there.

**Steps**
1. Baseline: last 3 nights of cancel import errors from `sap_import_result`, grouped by error_type
   (this is the number the fix must move).
2. Build the fixed version as a shadow view. Diff vs live: rows, items, and specifically
   **how many (item, period) collapse from N rows to 1**.
3. Column-order check before/after. Remove any hardcoded ID list (report what was in it first).
4. Shadow-generate the cancel file for one night; compare with the file legacy actually produced.
5. With approval: swap one view → watch the next night's import errors → then the second view.

**Acceptance:** exactly one row per (OrderItem, Period) in the cancel output; every `InvoiceNo` matches
`sap_mirror_doc` verbatim; cancel import errors drop materially versus the 3-night baseline; column order
unchanged; no active sibling items included.

---

## Reporting
Write findings to `docs/sessions/2026-07-29-claude.md` (Codex folds them into knowledge).
For each hotfix report: what changed / what was verified against real data / what remains assumed /
rollback command. Anything unverified stays labelled UNVERIFIED.

## Order of work
**H2 inventory + quantify → report → H3 re-derive + shadow → report → H4 baseline + shadow → report.**
No production swap without an explicit "deploy OK" for that specific view.
