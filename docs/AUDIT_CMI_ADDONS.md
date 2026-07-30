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

### D12/D13 materiality gate

Before classifying B1, aggregate `ActualReceived - ExpectedReceived` across the entire order.
`AMOUNT_VARIANCE` is material when the order-level absolute net difference is at least ฿10.
Do not apply the threshold per row, Period, OrderItem, or SAP document.

The prior B1 result **289 cases / ฿85,106.84** is **⚠️ SUPERSEDED — PRE-THRESHOLD**. It used a
row-level `ABS(delta) > ฿1` floor against
`sap_integration_v2.RCL 04_new order credit shell`; query evidence is in commit `3106719`, exact
query timestamp not retained. Nobody may cite that population or amount. Claude Code must
re-aggregate per order and publish provenance-complete replacement figures.

Replacement result from `4bbc16f` is **⚠️ UNDER CLASS-A REVIEW**: 559
`AMOUNT_VARIANCE` orders (gross ฿350,491.24; net ฿331,671.78) and 70 `MISPOSTING` orders
(gross ฿115,553.58). Source:
`sap_integration_v2.RCL 04_new order credit shell` plus the joins/queries preserved in
`sql/ddl/039_sap_correction_log_and_b1_pilot.sql`; commit timestamp 2026-07-30 08:26:27 ICT.
Do not act on these replacement figures until `REVIEW_QUEUE` clears them.

The five smallest-value pilot cases drafted in `3106719` are **VOID** because each is below the
฿10 order-level materiality buffer. Lesson: selecting a pilot by “smallest amount” before applying
the business threshold selects cases that require no correction. Apply eligibility and
materiality first, then choose a low-risk pilot from the remaining population.

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

## Permanent defect classes

### AMOUNT_VARIANCE

- Meaning: the order is genuinely short or over in net amount.
- Grain: aggregate all relevant rows to the **order** before comparison.
- Tolerance: `ABS(order_net_delta) < ฿10` is within buffer and requires no amount correction;
  `>= ฿10` is material.
- Important blind spot avoided: an order can have every row/Period individually below ฿10 while
  the order total exceeds ฿10. A per-period test would miss it.

### MISPOSTING

- Meaning: the total may net to zero, but money is posted to the wrong item/accounting side.
- Tolerance: **none**. The ฿10 buffer applies only to shortage/overage, never to wrong-side posting.
- Evidence: `L80524847` has M1 `+฿645.21` and V1 `−฿645.21`; order net is zero, but the posting is
  still wrong and must be detected.

## Process lesson

A business taxonomy or decision supplied in chat must be written into its canonical document in
the same session. Chat is not durable project context. Leaving B1/B2/B3 only in conversation forced
commit `73e94e0` to infer B2/B3 from data and propose the wrong pilot bucket.
