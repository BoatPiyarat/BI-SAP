# Change-order preflight evidence — 2026-08-02

Status: read-only evidence; no deploy, CALL, export, or production mutation.

## Reviewed run

- Source reviewed at commit `d628ce8`: Claude Code **PASS WITH NOTES** in
  `docs/reviews/2026-08-02-d628ce8-claude.md`.
- Job: `pacific-plating-282708:asia-southeast1.change_order_preflight_20260802_094500`.
- Query timestamp: `2026-08-02 02:41:55 UTC`.
- Start/end epoch milliseconds: `1785638505357` / `1785638517148`.
- Processed: `158,959,442` bytes; billed: `239,075,328` bytes; state `DONE`.
- Result rows: 28,341 linked old/new order pairs.

| preflight_status | pairs |
|---|---:|
| HOLD_OLD_NOT_IN_SAP | 26,541 |
| HOLD_OLD_ALREADY_TERMINAL | 1,367 |
| HOLD_REPLACEMENT_NOT_IN_EXPECTED_STATE | 253 |
| HOLD_SAP_SPINE_INCOMPLETE | 85 |
| READY_FOR_AWARE_FA_REVIEW | 93 |
| HOLD_SAP_PAID_INVOICE_MISSING | 1 |
| HOLD_SAP_PERIOD_INVALID | 1 |

`READY_FOR_AWARE_FA_REVIEW` is not export authority. Aware still owns the explicit-cancel decision
and accepted CreditShell literals; FA/Boat still owns batch approval. Item-level old→new mapping is
also unproven, so no 56-column payload may be generated from these 93 pairs yet.

## Review-note hardening

The next source revision adds two earlier fail-closed gates requested by Claude Code:

- `HOLD_LINK_AMBIGUOUS` when either side participates in more than one distinct link pair.
- `HOLD_SAP_TOTAL_PERIODS_CONFLICT` when SAP rows for a linked pair contain more than one
  `TotalPeriods` value.

The 93-pair result is therefore provisional until the hardened delta is reviewed and rerun. The
completed job is retained as provenance, not silently overwritten.

