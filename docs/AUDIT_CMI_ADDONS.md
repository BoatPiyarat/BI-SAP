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

Replacement result from `4bbc16f`/`9e6b44d` is **⚠️ SUPERSEDED — DO NOT CITE**: 559
`AMOUNT_VARIANCE` orders (net ฿331,671.78) and 70/71 `MISPOSTING` orders
(gross ฿115,553.58). The population may include rows rejected by SAP and never posted. Source:
`sap_integration_v2.RCL 04_new order credit shell` plus the joins/queries preserved in
`sql/ddl/039_sap_correction_log_and_b1_pilot.sql`; commit timestamp 2026-07-30 08:26:27 ICT.
Do not act on or quote these figures. They require a new posted-only population.

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
- Correction method: **Method 1 adjustment line**.

### MISPOSTING

- Meaning: the total may net to zero, but money is posted to the wrong item/accounting side.
- Tolerance: **none**. The ฿10 buffer applies only to shortage/overage, never to wrong-side posting.
- Formula-test shape: `L80524847` output has M1 `+฿645.21` and V1 `−฿645.21`; order net is zero.
  FA confirmed the file was rejected and no JE exists, so this is **not evidence of a posted
  misposting** and must not be used as a correction known-answer.
- Correction method: **Method 1 adjustment line per affected item**. Offset each item's delta;
  do not Cancel solely because the order nets to zero.

## D14 — correction-method mapping

| Defect/bucket | Treatment | Naming/alias dependency |
|---|---|---|
| Class 1 `AMOUNT_VARIANCE` | Method 1 adjustment line | None |
| Class 2 `MISPOSTING` | Method 1 adjustment line **per item** | None |
| B2 — `ExpectedReceived` itself is wrong | Method 2 Cancel + new Paid | Yes: naming config + alias/recon |
| B3 — SAP already Cancelled | Manual SAP correction by Aware | None in BI pipeline |

D14 removes Method-2 naming, `sap_orderitem_alias`, and Aware Q4 as blockers for Class 2 only.
Those dependencies remain open for B2 because an adjustment line cannot replace an incorrect
Expected baseline.

### Accepted limitation of Method 1

Adjustment lines correct received amounts but do not remove the duplicate SAP document that still
holds a full `ExpectedReceived`. If the duplicate document itself generated a duplicate journal
entry, the JE may remain after the amounts reconcile. This is an accepted, unproven limitation—not
an assumption that GL is fixed.

Prove behavior through the two D15-authoritative pilots and GL verification:

1. Class 1: `L80046687`.
2. Class 2: `L79900064`.

`0a69143`'s pair is **SUPERSEDED**: `L79871659` is too close to the noise floor and has no confirmed
CMI sibling; `L80524847` never posted. The latter is only a rejection-detection known-answer, not a
correction or posted-state known-answer.

After Method 1 is applied, Aware/FA must verify both the interface/SAP amounts and the underlying
GL/JE. No population rollout is allowed from an amount-only success.

## D15 — two generators, authoritative pilots, prevention first

The same permanent defect classes can be produced by at least two distinct generators:

1. **Credit-shell generator:** `sap_integration_v2.RCL 04_new order credit shell` fans out when
   multiple successful charges share `(transaction_id, installment_number)`.
2. **Onetime generator:** `sap_data_engineer.sap_dashboard_carepay_fully_paid` allocates a combined
   payment across M1/V1 incorrectly. Known-answer case: `L78496990`.

FA-facing totals must cover both streams and must not add overlapping orders twice. The second
stream quantification in `3c10215` is under class-A review and includes an unresolved range, so no
single combined number may be reported yet.

Credit-shell B2 drifted from `698 keys / 612 orders` (`73e94e0`) to
`700 keys / 613 orders` (`9e6b44d`). Both queries target the same live view; commit timestamps are
the retained provenance. This is real drift and evidence that the generator remains active.
Therefore prevention order is mandatory: fix the generating bug before sending corrections.

Boat selected **Option A** for the credit-shell generator: fix the v2 view directly because
`sap_view.RCL_Motor_process_4_creditshell` reads it directly; a v3 wrapper alone would not stop new
bad rows. Direction is approved, deploy is not. Before deploy, all three gates must pass:

1. retain the live v2 definition verbatim as rollback;
2. build and compare a shadow view with row/distribution/named-case diff;
3. verify interface column names, positions, and order against `INFORMATION_SCHEMA.COLUMNS`.

## Posted-state population gate

### POSTED_WRONG

Correction population. Requires all three: presence in the SAP mirror, SAP status consistent with
a successful post, and a JE reference tied to a successful import log.

### REJECTED_NEVER_POSTED

Not a correction population. Fix the generating/export bug, then send the normal correct record.
Do not create an adjustment merely because our output or an error XLSX contains a variance.

**Methodology lesson:** SAP error XLSX lists rejected rows. It is evidence of what did **not**
post, not evidence of what exists in SAP. `L80524847` exposed the mistake of using it as a
correction known-answer.

Class 1 also requires `has_CMI_sibling` segmentation. FA confirmed `L79871659` has no CMI sibling,
so the earlier Class-1 population can be over-inclusive for the CMI incident.

## Process lesson

A business taxonomy or decision supplied in chat must be written into its canonical document in
the same session. Chat is not durable project context. Leaving B1/B2/B3 only in conversation forced
commit `73e94e0` to infer B2/B3 from data and propose the wrong pilot bucket.
