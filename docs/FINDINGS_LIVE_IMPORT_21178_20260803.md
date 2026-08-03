# LIVE import 21178 — complete rejection caused by incomplete RCL period spine

Status: CONFIRMED 2026-08-03. No PII is recorded here.

The 584-row daily NEWPAYMENT file was delivered exactly, but SAP LIVE LogID 21178 returned status
`error`; every row (584/584) reported `Period: Sequence of Period invalid`. This is a complete
rejection, not partial success. Ledger rows and the single manifest were therefore changed from
DELIVERED to REJECTED by job `codex_mark_21178_rejected_20260803_171858_533`.

The delivered basename also violated the interface contract: it began
`RCB_MOTOR_INSURANCE_RCB_...`. `RCB_MOTOR` is the bucket folder, not part of the filename; the
basename must always begin `INSURANCE_RCB_`. This is independently confirmed and fixed in 060.
Although SAP parsed the file and returned row-level period errors, the filename defect must not be
treated as harmless or repeated.

Direct mirror diagnosis (`codex_diag_21178_20260803_171508_581`) found all 584 target periods and
their predecessors already present in SAP; none of the order items was absent. A period-level
sample also showed a valid existing 1..8 spine with the target period Pending. The defect is the
outbound grain: Unit 5 emitted only the newly Paid event row for each RCL order item. Business rule
7 requires the interface representation to include the complete period spine through
`TotalPeriods`; sending only period N makes the importer reject the sequence even when SAP already
stores its Pending row.

Required correction: build each affected RCL NEWPAYMENT payload from the complete SAP-compatible
56-column period spine, preserving all non-target periods and changing only the target payment
row(s). Re-run balance, identity, 56-position, and sequence-conservation gates against expanded
payload rows. Do not retry the rejected file. Workflow revision `000006-c04` sets production
delivery off by default until this correction passes a controlled test.

## Controlled correction evidence

Run `V3NIGHTLY-2026-08-03T11:24:27-437934f3` produced 559 target events; one balance-held event
removed its entire item spine. The released payload contains 3,857 rows across 555 items, exactly
56 columns, with zero incomplete spines and zero duplicate `(OrderItem,Period,InvoiceNo)` identities
(`codex_verify_full_spine_20260803_183123_559`). Archive-only CALL
`codex_call_060_full_spine_archive_20260803_183256_706` wrote one 2,377,414-byte object with the
correct `INSURANCE_RCB_` basename and 558 event-grain ledger rows. Production delivery remains off;
this archive has not been sent to SAP.
