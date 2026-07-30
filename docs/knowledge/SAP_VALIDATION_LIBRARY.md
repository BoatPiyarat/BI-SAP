# SAP VALIDATION LIBRARY

Canonical validation rules for the SAP interface. Updated 2026-07-29 from the legacy Drive
library; this version closes the former “รอคำตอบ Aware” correction-method question.

---

## Actual-received correction — confirmed 2026-07-29

Source: Aware and Sarawut/Boyd operational confirmation.

1. **Adjustment line:** retain the Period, set `ExpectedReceived=0`, and set
   `ActualReceived` to the delta. A negative delta corrects an over-receipt; a positive delta
   corrects a short receipt. Confirmed test cases: `L79899055`, `L79965977`.
2. **Cancel + Paid replacement:** cancel the existing document and send a new Paid document.
   Confirmed test cases: `L79899088`, `L79965966`.
3. **Mandatory selection:** when `ExpectedReceived` is incorrect or negative, use method 2.
   Aware explicitly recommended this selection rule. The former question “cancel+re-import vs
   manual SAP correction — รอคำตอบ Aware” is therefore **RESOLVED**.

### Reconciliation control

An adjustment line with a positive delta is structurally indistinguishable from the existing
additional-payment rule: same Period, `ExpectedReceived=0`, `ActualReceived>0`. A structural
query alone cannot classify the row. Reconciliation by transaction type remains untrustworthy
until the source/export carries a durable marker distinguishing `CORRECTION` from
`ADDITIONAL_PAYMENT`.

### Required validations

- `EXTRA_ROW_EXPECTED_NONZERO`: within one `(OrderItem, Period)`, every row after the first must
  have `ExpectedReceived=0`.
- `ADD_ONS_DEDUCTED_MORE_THAN_ONCE`: `add_ons` may be deducted once per
  `(OrderItem, Period)`, never once per charge row.
- `CORRECTION_MARKER_MISSING`: do not classify an adjustment-shaped row as correction versus
  additional payment without an explicit marker.
- CMI identification must use
  `careos.careos_order_items.motor_item_type = 'MOTOR_TYPE_COMPULSORY'`; `packageType` is not a
  valid CMI identifier.

### D12/D13 — money materiality and defect classification

- `AMOUNT_VARIANCE`: aggregate by order first. Treat
  `ABS(order_net_delta) < 10.00 THB` as within tolerance; values `>= ฿10` are material.
  Never apply this threshold independently per row, Period, OrderItem, or SAP
  document.
- `MISPOSTING`: no tolerance. A zero-net order can still be wrong when equal amounts are posted to
  opposite items/accounting sides. `L80524847` proves this shape: M1 `+฿645.21`, V1 `−฿645.21`,
  net zero but materially wrong.
- Validation must run both checks. Passing `AMOUNT_VARIANCE` must never suppress `MISPOSTING`.
- An order whose individual rows are each within ฿10 but whose aggregated variance exceeds ฿10
  must fail `AMOUNT_VARIANCE`; this is why the comparison grain is the order.

### D14 correction routing and GL acceptance

- `AMOUNT_VARIANCE` → Method 1 adjustment line.
- `MISPOSTING` → Method 1 adjustment line per affected item.
- B2 where `ExpectedReceived` itself is wrong → Method 2; naming/alias dependencies remain.
- B3 already Cancelled in SAP → manual SAP correction by Aware.

Method 1 amount reconciliation is not sufficient acceptance evidence. It does not delete a
duplicate full-Expected document, so a journal entry created by that document may remain. Pilot
acceptance requires Aware/FA to verify GL/JE for both one Class-1 and one Class-2 case.

Implementation and live validation belong to Claude Code's SQL lane and are queued in
`docs/HANDOFF_QUEUE.md`; these rules do not assert that the corresponding SQL checks are deployed.
