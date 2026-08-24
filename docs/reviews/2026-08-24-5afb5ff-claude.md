# Review: RQ-20260824-1217 v3-normal-rcl-motor-newpayment

Reviewer: Claude Code
Artifact: `5afb5ff`; `sql/ddl/058_v3_unit5_newpayment_shadow.sql` (lowercase-status mapping + assert),
`sql/adhoc/20260824_qualify_v3_normal_motor_newpayment.sql` (read-only qualifier)
Verdict: **BLOCK**

## Verification performed

Source-only artifact, nothing deployed (DDL 058 `CREATE TABLE` stays gated by its own header
comment: "CREATE is deliberately excluded"). Per protocol, ran one targeted live query
(`sql/adhoc/20260824_review_check_creditshell_join_fanout.sql`, dry-run 631,180 bytes, real run
same) plus free metadata reads (`bq show -j`, `bq head` on the cited job's child job) — not counted
against the one-query budget, same precedent as `2026-08-23-3ac04f6-claude.md`.

- **Lowercase-status mapping (the actual DDL 058 delta) is correct.** The `CASE WHEN 'paid' THEN
  'Paid' WHEN 'pending' THEN 'Pending' ELSE ... END` runs inside the `_candidate` UNION branch that
  carries forward non-target spine periods, and the new `ASSERT ... TransactionStatus NOT IN
  ('Paid','Pending')` runs downstream of that CASE, over the unioned `_candidate` table — so it
  correctly fails closed on any spelling other than the two named ones. Confirmed by direct read of
  `sql/ddl/058_v3_unit5_newpayment_shadow.sql:204-249`.
- **Change-order join fanout — confirmed live, not closed.** The qualifier does:
  `LEFT JOIN cancelled_change_orders c ON c.current_human_id = p.OrderID OR c.old_human_id =
  p.OrderID`, with no grouping or ambiguity guard. The already-PASSed sibling artifact
  `sql/ddl/081_v3_creditshell_flow_router.sql` (`RQ-20260823-2133`) hits the exact same table and
  handles this with `GROUP BY current_human_id, COUNT(*) AS link_count ... HOLD_CHANGE_LINK_
  AMBIGUOUS WHEN link_count!=1` specifically because this table is not 1:1 per order. I ran the
  live check myself: `0` OrderIDs have more than one `cancelled_change_orders` row keyed by
  `current_human_id`, but **`2,225` OrderIDs appear as `current_human_id` in one row and as
  `old_human_id` in a different row** — for any of those, the qualifier's OR-based join returns two
  distinct matched rows for one logical identity, and those two rows get *different* classifications
  (`HOLD_CREDITSHELL_OR_CHANGE_CURRENT` vs `HOLD_CHANGE_PREVIOUS`), silently double-counting and
  misclassifying that identity in the GROUP BY report. This is the review-focus item asked for by
  name ("change-order join fanout") and the artifact does not carry the pattern its own sibling
  artifact was required to adopt one day earlier.
- **Headline counts do not match the cited job's own output.** I re-fetched the cited job
  (`bqjob_r4023e302dbecdf9c_000001a03232c452_1`, found under `location=asia-southeast1`, script with
  3 child jobs) and read the final result table (`bq head` on child job
  `script_job_852d67fe7870f26b7957be7124bfa31c_2`):

  | qualification | identity_rows | order_items |
  |---|---|---|
  | HOLD_CANCELLED | 1 | 1 |
  | HOLD_INCOMPLETE_RCL_SPINE | 2 | 2 |
  | READY_NORMAL_RCL_MOTOR_NEWPAYMENT | 555 | 552 |

  Total `identity_rows` across all three buckets = **558**, not 555. The request text ("555
  identities / 552 items ready, 1 cancelled identity held, and 2 incomplete-spine identities held")
  reads as claiming 555 as the grand total (552+1+2=555), but 555 is actually the READY bucket's own
  `identity_rows`, and the true grand total is 558. Separately, and undisclosed in the request:
  within the READY bucket, `identity_rows` (555) exceeds `order_items` (552) by 3 — three order_items
  each contributed two distinct NEWPAYMENT identity rows (two `charge_id` events) in this one run,
  which is not explained anywhere in the claim. This project's own review protocol exists because of
  exactly this failure class (its own doc cites a prior 419-vs-296 stale-number incident) — the
  discrepancy is small but it is real and it is in Class-A evidence, so it must be corrected and
  explained, not waved through because the qualifier itself is read-only.
- **Job/query text integrity**: the job's stored `configuration.query.query` text matches the
  committed `sql/adhoc/20260824_qualify_v3_normal_motor_newpayment.sql` file verbatim (compared by
  eye against the full stored text) — no drift between what ran and what's in the repo. Real run
  billed 62,914,560 bytes / processed 56,050,306 bytes, run by `data@rabbit.co.th`, `2026-08-24`,
  under the 20 GiB cap, single grouped SELECT (no per-metric repeat queries).

## Required corrections

1. Give the `cancelled_change_orders` join in the qualifier the same fail-closed treatment already
   established and PASSed in `081_v3_creditshell_flow_router.sql`: aggregate to one row per relevant
   key first (or equivalently union the current/old match paths and assert exactly one relationship
   per OrderID), and hold on ambiguity instead of joining an unbounded `OR` condition directly against
   the raw table.
2. Correct the reported figures to the job's actual output — total 558 identities (555 READY +
   1 cancelled + 2 incomplete-spine), 552 READY order_items — and explain the 555-vs-552 gap inside
   the READY bucket (which order_items have two identity rows, and why) before this qualification is
   cited again as evidence for anything.

Neither correction requires new authorization or scope expansion — both are fixes to the read-only
qualifier and its own claim text; DDL 058's actual delta (the lowercase-status mapping) is
independently correct and does not need rework.

## Checklist 1–12

1 traceability BLOCK (headline count doesn't match the cited job's own output — see above); 2
provenance PASS (cites DDL 058 and the prior stale-run context appropriately, doesn't re-derive
settled decisions); 3 NULL-safety PASS (CASE branches use `IFNULL` consistently; the fanout problem
is a join-cardinality bug, not a NULL-handling bug); 4 ordering N/A; 5 column order PASS (DDL 058's
56-column list and ordinal positions are unchanged — only the `TransactionStatus` value expression
changed, confirmed by direct diff read); 6 grain BLOCK (qualifier does not preserve one-row-per-
identity grain through the `cancelled_change_orders` join — confirmed exploitable against live data,
2,225 OrderIDs at risk project-wide); 7 distribution N/A; 8 knowledge PASS (consistent with Boat's
2026-08-24 ADDENDUM on the Motor transport template, doesn't contradict prior confirmed decisions);
9 scope PASS (`sql/ddl/058` is in-scope Unit 5 source, `sql/adhoc/**` is read-only evidence,
`docs/knowledge/**`/`docs/design/**` updates document Boat's decision correctly); 10 rollback N/A
(DDL 058's `CREATE TABLE IF NOT EXISTS` remains uncreated; nothing live to roll back); 11 cost
hygiene PASS (dry-run cited, real run 56 MB processed / well under the 20 GiB cap, one grouped query
for all metrics); 12 honest labelling BLOCK (the "not a production batch count" caveat is present and
correct in spirit, but the count itself is wrong against the job's own stored result, and the
555-vs-552 internal gap is undisclosed).

Summary: DDL 058's actual source delta (lowercase status mapping, fail-closed assert) is correct and
does not need rework. The read-only qualifier has a real, confirmed join-fanout defect on
`cancelled_change_orders` that its own reviewed sibling artifact already had to solve differently,
plus a headline-number mismatch against its own cited job's output. Both are qualifier-only fixes;
resubmit the qualifier (not DDL 058) for a delta review.
