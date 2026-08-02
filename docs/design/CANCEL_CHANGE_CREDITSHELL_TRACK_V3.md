# V3 cancel/change then credit-shell track

Status: **Class A design/evidence; not deployed; no payload or bucket write authorized**.

## Population boundary and SAP status literals

This document covers **change-order only**: a row enters only through a link in
`careos.cancelled_change_orders`. Its cancel payload must use the exact SAP-success literal
`Cancelled (Change order / Rejected)`. A linked pair must never be routed to plain cancellation.

Plain cancellation is a separate future track. Its population is
`stg_order_dim.is_cancelled_effective=TRUE` with no membership in `cancelled_change_orders`. It uses
the exact target literal `Cancelled`, has no replacement mapping, no replacement semantics, and no
credit-shell stage. An unlinked cancellation must never enter this change-order/credit-shell state
machine. Legacy cancel views predate RULE-21/22 and are not readiness evidence for either track.

## Existing-track inventory

Legacy objects exist for RCB cancel-new/change and RCL cancel, plus RCB/RCL credit-shell views.
They are not a V3-safe track: the cancel views predate RULE-21/22, and the credit-shell generator
has a confirmed duplicate-generation defect. Their existence is not readiness evidence.

## Hardened cancel/change evidence

Reviewed preflight source: `sql/adhoc/20260802_change_order_preflight.sql` at/after `233ad5f`.
Execution: `change_order_preflight_hardened_20260802_103000`; query timestamp
`2026-08-02 04:00:45 UTC`; processed 160,050,800 bytes; billed 249,561,088 bytes; state DONE.

| status | linked order pairs |
|---|---:|
| HOLD_LINK_AMBIGUOUS | 7,457 |
| HOLD_OLD_NOT_IN_SAP | 19,123 |
| HOLD_OLD_ALREADY_TERMINAL | 1,332 |
| HOLD_REPLACEMENT_NOT_IN_EXPECTED_STATE | 245 |
| HOLD_SAP_SPINE_INCOMPLETE | 85 |
| HOLD_SAP_TOTAL_PERIODS_CONFLICT | 5 |
| HOLD_SAP_PAID_INVOICE_MISSING | 1 |
| HOLD_SAP_PERIOD_INVALID | 1 |
| READY_FOR_AWARE_FA_REVIEW under the old order-level gate | 92 |

The 92 are order-level candidates, not yet cancel-ready. RULE-21/22 require every winning old SAP
row being cancelled to be Paid or Pending. The next preflight revision adds that missing status
gate. It does **not** require replacement Paid: “its own” means the old SAP item being cancelled.

## Item-map evidence

Job `change_order_item_mapping_20260802_110300` (dry-run upper bound 175,041,125 bytes) measured 482
old SAP items from unambiguous order links:

| provisional strategy | no match | unique | ambiguous | unique and replacement Paid in SAP |
|---|---:|---:|---:|---:|
| suffix only | 216 | 174 | 92 | 146 |
| suffix + motor type + product + insurer | 263 | 151 | 68 | 127 |
| motor type + product + insurer + package | 427 | 51 | 4 | 44 |

No strategy has sufficient coverage and uniqueness to become an automatic business key. Suffix is
a clue, not authority. Auto-cancel from these inferred matches is prohibited.

## Required V3 state machine

1. `ITEM_MAP_PENDING`: emit old/new candidates to a human queue; no payload.
2. `ITEM_MAP_APPROVED`: retain approver, timestamp, method, old/new item, and link provenance.
3. `OLD_PAID_OR_PENDING_ACK`: every winning old item/period exists in refreshed SAP as Paid/Pending.
4. `CANCEL_SHADOW_READY`: clone all 56 fields from those winning old SAP rows; require exact
   `1..TotalPeriods`, preserve InvoiceNo and every field, change only TransactionStatus to the
   exact literal `Cancelled (Change order / Rejected)`.
5. `CANCEL_DELIVERED` then `CANCEL_ACK`: never infer ACK from function/file status.
6. Only after `CANCEL_ACK`, use the approved old→new map to release the replacement into
   `CREDIT_SHELL_PENDING`.
7. `CREDIT_SHELL_READY`: use approved mapping and SAP-success PaymentMethod/PaymentChannel literals;
   run corrected dedup logic, 56-column validation, amount conservation, and exact delta gate.
8. `CREDIT_SHELL_ACK` closes the chain; rejects remain human-action outcomes.

## Hard boundaries

- Cancel construction and eligibility do not need a replacement map: they clone the old SAP
  document and prove that same old item is Paid/Pending. Mapping is required for credit-shell.
- No cancel/change when the old SAP item has no Paid/Pending winner.
- No credit-shell payment before cancel ACK.
- Never cross-route: linked change-order pairs cannot enter plain cancel; unlinked plain cancels
  cannot enter change-order or credit-shell.
- INCIDENT-002b and 224 unknown-cause orders remain separate remediation populations.
- Aware still owns explicit-cancel behavior and accepted CreditShell literals; FA/Boat own batch
  approval. No legacy view is modified by this milestone.
