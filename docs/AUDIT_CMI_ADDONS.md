# AUDIT_CMI_ADDONS — INCIDENT-002 correction buckets

Canonical bucket taxonomy for the CMI `add_ons` double-deduction audit. Effective 2026-07-30.
These labels are local to `INCIDENT-002`; they are not the historical B1/B2 pipeline labels used
in older architecture documents.

## B1 — Expected correct; Actual needs adjustment

- `ExpectedReceived` is correct.
- `ActualReceived` requires a delta correction.
- The target SAP document is not already Cancelled.
- Treatment: **Method 1**, same Period, `ExpectedReceived=0`,
  `ActualReceived=delta` (negative for over-receipt, positive for short receipt).

This is the pilot bucket because it needs no new OrderItem generation, alias mapping, or naming
convention. Its dependency and blast radius are the smallest.

## B2 — Expected incorrect or negative

- `ExpectedReceived` is incorrect or negative, including an extra row within the same
  `(OrderItem, Period)` retaining nonzero Expected.
- Treatment: **Method 2**, Cancel the existing document and send a new Paid document, as confirmed
  by Aware.
- Method 2 requires a new SAP-facing OrderItem generation because the old Paid/Cancelled key is
  immutable. Naming is governed by D10 and remains undecided.

The `698` diagnostic rows previously associated with this bucket came from
`sap_integration_v2.RCL 04_new order credit shell`, queried for commit `73e94e0`; exact query
timestamp was not retained, so the number remains PROVISIONAL and is not the final incident scope.

## B3 — SAP already Cancelled

- The relevant current SAP state is already `Cancelled` or
  `Cancelled (Change order / Rejected)`.
- Treatment: ask Aware to correct the records manually.
- Do not build alias/naming/remediation infrastructure for this bucket.

There are `2` diagnostic cases in this bucket:
`L79605066` ← `L79289825` and `L79952011` ← `L79917668`. Source:
`sap_integration_v3.sap_mirror_state` joined to
`sap_integration_v2.RCL 04_new order credit shell`, query evidence in commit `73e94e0`; exact
query timestamp was not retained, so the count is PROVISIONAL.

## D10 — replacement naming is configuration, not hardcoded

The replacement-generation naming convention is **not decided**. `M2` cannot be treated as a
revision suffix because `careos.careos_order_items` already contains `1,019` real `-M2` rows.
Source query and result are recorded in `73e94e0`; exact query timestamp was not retained, so this
count is PROVISIONAL.

Any implementation must read a naming template/prefix from configuration. Do not hardcode
`-M1R2`, `M2`, `R{generation}`, or another candidate into SQL. Existing reconciliation history
also shows a `C#` prefix associated with Credit Shell; this is only a clue that SAP-side C# may
already have a prefix convention, not approval to reuse it. Aware must answer Q4 before naming is
implemented.

## D11 — pilot and B3 handling

- Pilot = **one B1 case using Method 1**, not a B3 case.
- Reason: B1 Method 1 has the fewest dependencies and does not require the undecided naming
  convention, `sap_orderitem_alias`, or new-generation reconciliation.
- The two B3 cases go to Aware for manual correction. Do not create infrastructure for two
  already-Cancelled cases.

## Process lesson

A business taxonomy or decision supplied in chat must be written into its canonical document in
the same session. Chat is not durable project context. Leaving B1/B2/B3 only in conversation forced
commit `73e94e0` to infer B2/B3 from data and propose the wrong pilot bucket.

