# Review: RQ-20260821-1817-urgent-refund-paid-cancel-phase1

Reviewer: Claude Code
Class: A
Artifact: commit `e5eefcd`; `sql/adhoc/20260821_verify_urgent_refund_paid_cancel.sql`,
`docs/tasks/TASK_URGENT_REFUND_PAID_CANCEL_20260821.md`
Verdict: **PASS**

## Claim under review
The authenticated `urgent_for refund to cust` tab (sheetId `493163004`, not the gid supplied in
chat which opens `SAP_LIVE`) has 15 source rows resolving to 18 CareOS order items. Live
classification: 2 complete (SAP Paid then Cancelled), 6 plain-cancel Phase-1 candidates, 10 held
(2 CareOS-not-cancelled, 6 no item-level Paid predecessor, 1 incomplete SAP spine, 1 change-order
routing). No interface file constructed or written.

## Independent verification performed
One targeted query (the full verifier, plus a grouped summary variant) run live against
`careos.careos_order_items`/`careos_orders`, `sap_integration_v3.sap_mirror_state`, and
`careos.cancelled_change_orders`, using the exact 18-item scope list from the artifact.
**Result: reproduced every one of the six buckets and every order_item assignment exactly** —
2/6/2/6/1/1, same items in each bucket, no discrepancy. `gsutil ls` against both the production
`RCB_MOTOR` prefix and shadow prefixes for anything refund-related: no matching object, confirming
no GCS write occurred.

## 12-item checklist
1. Traceability — PASS. Job ID (`codex_urgent_refund_gate_v2_20260821`), source timestamp
   (`2026-08-21 11:15:45 UTC`), dry-run byte count all named; I independently reproduced the same
   counts from the same tables.
2. Provenance over repetition — PASS. Cites Boat's 2026-08-21 completion-definition decision and
   the existing `cancelled_change_orders` table rather than re-deriving change-order logic.
3. NULL-safety — PASS. `careos_cancelled` uses `is_cancelled IS TRUE OR cancel_time IS NOT NULL`,
   the canonical D1 NULL-safe form. `sap.paid_blank_invoice` uses `NULLIF(TRIM(...),'')  IS NULL`,
   correctly treating blank/whitespace-only InvoiceNo as absent, not just SQL NULL.
4. Ordering — N/A, no date-sort-driven logic; `STRING_AGG(... ORDER BY U_Period)` is for a display
   field only.
5. Column order — N/A, read-only verification, no interface file produced.
6. Grain stated — PASS. Explicitly distinguishes "15 source rows" (sheet grain) from "18 CareOS
   items" (M1/V1 sibling expansion) and does not conflate them; the six no-predecessor items are
   correctly flagged as only provable at *order* grain, not item grain, and the task explicitly
   forbids synthesizing an item-level split from that shared charge.
7. Distribution, not row count — PASS. The six-bucket breakdown is a real classification, not a
   bare count; I verified membership per bucket, not just totals.
8. No contradiction with knowledge — PASS. Uses the confirmed D1 cancellation definition, respects
   the RCL/RCB and complete-spine invariants from `docs/design/SAP_INTERFACE_PRE_EXPORT_GATE.md`
   by holding (not passing) the incomplete-spine item, and correctly treats the two change-order
   items as needing the separate reviewed change-order contract rather than plain cancellation.
9. Scope — PASS. Read-only verification only; explicitly states no interface file was built or
   written, matching the task's Phase 1 boundary.
10. Rollback — N/A, nothing deployed.
11. Cost hygiene — PASS. Dry-run evidence given (146,712,322 bytes plus the separate 394,017,340
    byte predecessor-trace job), well under the 20 GiB cap; my reproduction used the same query
    shape, one query returning the full breakdown rather than six separate scans.
12. Honest labelling — PASS. Explicitly labels the six candidates as "readiness evidence only, not
    an interface payload," names the still-open human/vendor decisions (Aware cancel-spec
    confirmation, Boat's deploy OK, the predecessor-allocation decision) rather than rounding up to
    "ready to ship."

## Risk / gap noted
One point worth a follow-up, not a blocker: `change_membership` joins `cancelled_change_orders` by
`order_id IN (old_human_id, current_human_id)` without also checking `careos_order_items` for an
active (non-cancelled) change-order relationship, so an order that changed via a not-yet-cancelled
change-order record could be missed by this specific check. Given the six live candidates already
show zero change-order membership and the incomplete-spine/change-order cases are separately held
either way, this does not affect today's PASS — flagging for whoever builds the Phase-2 payload to
re-check against the live change-order table at execution time, not just this Phase-1 snapshot.

Checklist 1–12 reviewed; one non-blocking gap noted above.
