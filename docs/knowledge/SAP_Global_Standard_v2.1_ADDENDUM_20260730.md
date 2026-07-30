# SAP Global Standard v2.1 — §6.1.1 addendum

Repository correction dated 2026-07-30. The full `SAP_Global_Standard_v2.1` source is not present
in this repository; Google Drive is backup-only and must not be used as a reading source. This
addendum is therefore the repository-canonical replacement for the pending wording in §6.1.1
until the full standard is imported.

## §6.1.1 Materiality / tolerance — RESOLVED by D12/D13

Replace “proposed ±฿0.01 per document” with:

> **Amount-variance tolerance is ±฿10 per order. Aggregate the full order before comparison.**

- `AMOUNT_VARIANCE`: `|order net delta| < ฿10` is immaterial; `>= ฿10` is material.
- `MISPOSTING`: no tolerance; net zero does not prove correct accounting-side allocation.
- Do not evaluate the buffer per row, Period, OrderItem, or SAP document.
- Orders may have every constituent row below ฿10 while the order aggregate exceeds ฿10; these
  must be detected by the order-level check.

Decision provenance: Boat, 2026-07-29 (“มี buffer 10 THB”); order-grain clarification D13,
2026-07-30.
