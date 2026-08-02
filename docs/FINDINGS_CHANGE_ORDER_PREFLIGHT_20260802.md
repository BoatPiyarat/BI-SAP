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

## Hardened rerun and RULE-21 impact

The reviewed hardened rerun is job `change_order_preflight_hardened_20260802_103000`, timestamp
`2026-08-02 04:00:45 UTC`, processed 160,050,800 bytes and billed 249,561,088 bytes. It produced
28,341 pairs: 7,457 link-ambiguous; 19,123 old-not-in-SAP; 1,332 already-terminal; 245 replacement
missing from expected state; 85 incomplete spine; 5 TotalPeriods conflicts; one Paid InvoiceNo
missing; one invalid period; and 92 order-level READY.

RULE-21/22 require the old item being cancelled to have a Paid/Pending SAP winner. They do not
require replacement Paid. The 92 therefore need a new old-status gate before cancel shadow work.
Job `change_order_item_mapping_20260802_110300` remains relevant to the later credit-shell stage:
no tested CareOS strategy is both unique and complete, so replacement mapping cannot be automatic.

The follow-up source added the old-status gate, but the 92 remain non-citable until it is rerun.
That rerun must also report the distinct winning `TransactionStatus` inventory: the current source
accepts `Paid`, `paid`, and `Pending`; any other spelling/case, including a possible lowercase
`pending`, is deliberately held until evidenced. For the change-order payload the only permitted
target cancellation literal is `Cancelled (Change order / Rejected)`.

Plain cancellation is out of this diagnostic by construction because its population has no
`cancelled_change_orders` link. Its future target literal is `Cancelled`, with no replacement map
or credit-shell transition. Cross-routing between these populations is prohibited.
