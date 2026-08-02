# V3 cancel/change then credit-shell track

Status: **Class A design/evidence; not deployed; no payload or bucket write authorized**.

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

The 92 are **not cancel-ready under new RULE-21**. RULE-21 requires proof that the replacement Paid
for the same item was accepted by SAP, which requires an approved old-item to new-item mapping.

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
3. `REPLACEMENT_PAID_ACK`: the mapped new item/period is Paid in the refreshed SAP mirror.
4. `CANCEL_SHADOW_READY`: clone all 56 fields from the winning old SAP rows; require exact
   `1..TotalPeriods`, preserve InvoiceNo and every field, change only TransactionStatus.
5. `CANCEL_DELIVERED` then `CANCEL_ACK`: never infer ACK from function/file status.
6. Only after `CANCEL_ACK`, release the mapped replacement into `CREDIT_SHELL_PENDING`.
7. `CREDIT_SHELL_READY`: use approved mapping and SAP-success PaymentMethod/PaymentChannel literals;
   run corrected dedup logic, 56-column validation, amount conservation, and exact delta gate.
8. `CREDIT_SHELL_ACK` closes the chain; rejects remain human-action outcomes.

## Hard boundaries

- Cancel construction does not need CareOS item mapping because it clones the old SAP document;
  cancel **eligibility** does need mapping to prove RULE-21.
- No cancel/change when the mapped replacement Paid has not been acknowledged in SAP.
- No credit-shell payment before cancel ACK.
- INCIDENT-002b and 224 unknown-cause orders remain separate remediation populations.
- Aware still owns explicit-cancel behavior and accepted CreditShell literals; FA/Boat own batch
  approval. No legacy view is modified by this milestone.
