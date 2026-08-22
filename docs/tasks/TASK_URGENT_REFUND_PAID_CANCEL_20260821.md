# Task — urgent refund: SAP Paid then Cancelled

Status: PHASE 1 VERIFIED; production construction blocked by listed gates  
Owner decision: Boat, 2026-08-21 — CareOS item cancellation is definitive. A row is complete only
when SAP has the transaction Paid and subsequently Cancelled.

## Authoritative population

Source workbook: `RCL_missing order`, tab `urgent_for refund to cust`, Google sheetId `493163004`.
The URL supplied in chat used gid `235486908`, which opens `SAP_LIVE`; the tab title was resolved
from workbook metadata and read directly. The visible populated range contains 15 source rows
(rows 3–17), resolving to 18 CareOS order items because three unsuffixed order IDs have M1/V1
siblings. The sheet is input scope only; current CareOS item status controls eligibility.

## Live Phase 1 result

Canonical query: `sql/adhoc/20260821_verify_urgent_refund_paid_cancel.sql`  
Corrected job: `codex_urgent_refund_gate_v2_20260821`  
Source timestamp: `2026-08-21 11:15:45 UTC`  
Dry-run estimate: 146,712,322 bytes

| Decision | Items | Order items |
|---|---:|---|
| Complete in SAP | 2 | `L79966351-M1`, `L80489663-V1` |
| Plain-cancel Phase-1 candidates | 6 | `L78551615-V1`, `L80451154-V1`, `L80482628-V1`, `L80545799-V1`, `L80546987-V1`, `L80562453-V1` |
| Hold — CareOS item not cancelled | 2 | `L79883067-1`, `L80482628-M1` |
| Hold — no item-level SAP Paid predecessor | 6 | `L78753528-M1`, `L78753528-V1`, `L79328887-V1`, `L80489663-M1`, `L80569525-M1`, `L80569525-V1` |
| Hold — incomplete SAP spine | 1 | `L77833033-V1` (only period 1 of 6 exists; old change-order side) |
| Hold — change-order routing | 1 | `L80503747-V1` (old change-order side) |

The six plain-cancel candidates each have a complete `1..TotalPeriods` SAP spine, exactly one Paid
period, a nonblank immutable Paid InvoiceNo, and a Pending tail. This is readiness evidence only,
not an interface payload.

The six no-predecessor items belong to four orders with successful order-level charges, but the
charge is shared across M1/V1 on three orders. That does not prove an item-level SAP Paid
predecessor and must not be used to synthesize one. Read-only trace job
`codex_refund_missing_predecessor_trace_20260821` (2026-08-21 11:12:16 UTC; dry-run 394,017,340
bytes) records the ambiguity.

## Required path to completion

1. Keep the two completed items out of any retry.
2. Keep both non-cancelled CareOS items out unless their item-level CareOS state changes.
3. Resolve the two change-order/old-order cases through the reviewed change-order contract, not
   the plain-cancel flow.
4. Resolve the six missing item-level Paid predecessors through a separately reviewed allocation /
   create-or-payment task. Never manufacture M1/V1 allocation from the shared order charge.
5. For the six plain-cancel candidates, capture the current live 56-column cancel source contract,
   construct an immutable full-spine candidate, enforce the canonical pre-export gate, dry-run,
   and obtain Class-A PASS.
6. Obtain Boat's explicit scoped `deploy OK` in the execution session before any production GCS
   write. Refresh SAP immediately before execution and re-check CareOS status, predecessor state,
   InvoiceNo, prior cancellation, complete spine, candidate hash, and schema hash.

No interface file was built or written by Phase 1.

## Aware answers received

- 2026-08-22 — Pending-period `InvoiceNo`: preserve the existing SAP value exactly; when the
  existing SAP value is blank, leave it blank. Never generate or substitute it.

## Phase 2 — shadow candidate built (source only, not executed), 2026-08-22

`sql/ddl/080_urgent_refund_cancel_candidate.sql` implements step 5 above for the 6 plain-cancel
candidates: full-spine rows mirrored verbatim from `sap_mirror_state` (no recompute — deliberately
avoids the unsafe legacy `sql/production/RCL_02_items_cancel.sql` wide-source view), forward-fills
`PaymentMethod`/`PaymentChannel` from the item's one confirmed non-blank value (all 6 items
verified live to have exactly one distinct value each — job against `sap_mirror_state`, live
2026-08-22), sets `TransactionStatus='Cancelled'` for the full spine per inferred rule R1, and
item-level-quarantines anything that fails re-derived eligibility (CareOS not cancelled, SAP
already shows a Cancelled period, invalid spine, ambiguous/missing payment channel) rather than
trusting the Phase-1 snapshot's freshness. Dry-run passed at 0 bytes.

**This script has not been executed.** It builds no table, holds no manifest, and is not eligible
for export until it separately receives Class-A PASS.

**Known likely blocker, disclosed in the script itself**: all 6 candidates propose `Cancelled`
status on periods that were always `Pending` (never paid), which under the current mirror-verbatim
rule leaves `PaymentDate=''` on a `Cancelled` row. The canonical gate
(`docs/design/SAP_INTERFACE_PRE_EXPORT_GATE.md` item 5) only confirms blank `PaymentDate` as an
exception for `status='Pending'`; extending it to `Cancelled` is the still-open Q11 in
`SAP_CANCEL_IMPORT_SPEC_INFERRED_v0.9.md`. The script computes `gate_status` honestly rather than
assume the extension — expect `BLOCK_OPEN_VENDOR_QUESTION` unless Aware confirms Q11 first. That is
a correct outcome to report, not a defect to silently work around.

**Next steps**: (1) Class-A review of `080_urgent_refund_cancel_candidate.sql` by Codex — logged
`RQ-20260822-1147-urgent-refund-cancel-candidate`. (2) Independently of the review, Aware needs to
confirm Q11 before this can ever reach `PASS`. (3) Only after both: execute the script (Codex, per
the single-deployer rule), inspect the resulting gate manifest, and if `PASS`, bring it to Boat for
the separate explicit scoped `deploy OK` before any `gs://interface-file/**` write.
