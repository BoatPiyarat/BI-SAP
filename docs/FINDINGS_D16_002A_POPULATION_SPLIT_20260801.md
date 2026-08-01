# D16 INCIDENT-002a population split — 2026-08-01

Status: **OPEN / Class A review required / not stakeholder-citable**. Read-only analysis; no view,
table, procedure, export, backfill, or production object was changed.

## Scope and grain

This work separates the historical CMI arithmetic match into mutually exclusive shapes. It does
not re-scope or quantify INCIDENT-002b and does not touch the 224 unknown-cause orders.

- INCIDENT-002a candidate grain: one current non-CMI `(OrderItem, Period=1)` SAP key per order,
  with `Paid`, real `DocEntry`, positive Expected, and `(Actual-Expected) = CMI gross premium`.
- `INCIDENT_002A_PURE`: the CMI sibling is independently Paid and its own Actual equals Expected.
- `SHARED_FULL_PAYMENT_OTHER_FINDING`: CMI and non-CMI siblings carry the same Actual and Invoice;
  this is the separate onetime/shared-full-payment shape, not INCIDENT-002a or 002b.
- `UNCLASSIFIED_REQUIRES_HUMAN_REVIEW`: arithmetic matches, but SAP evidence does not prove either
  of the two shapes above.
- `credit_shell_boundary`: membership in either side of `cancelled_change_orders`. This is only a
  boundary alarm. It is not an INCIDENT-002b population definition or count.

The executable source is
`sql/adhoc/20260801_d16_incident_002a_population_split.sql`. Live metadata was inspected before
writing it. The live `sap_mirror_doc` has no UpdateDate/UpdateTime yet, so current-state selection
uses the existing status, non-empty InvoiceNo, parsed BatchRunDate, DocEntry order. This limitation
must be removed after reviewed 024 is deployed; no source-only future schema was assumed live.

## Direct-file conflation inventory

Inspection before editing found:

1. `docs/FINDINGS_CREDITSHELL_DUPLICATE_20260729.md` D16 Item 1 contains the historical
   `401 orders / ฿267,775.28` derivation and itself admits that the arithmetic filter mixes pure
   V1-side CMI non-deduction with the shared-full-payment shape.
2. That file also sits under a credit-shell title while discussing INCIDENT-002a, increasing the
   risk of treating 002a and 002b as one population. Its earlier ambiguous `INCIDENT-002` labels
   are historical pre-D16 text.
3. `sql/ddl/039_sap_correction_log_and_b1_pilot.sql` and
   `sql/ddl/040_generating_bug_option_a_dedup_charges.sql` use the old unsuffixed
   `INCIDENT-002` label. 039 is a pre-D16 symptom/pilot artifact and cannot define either incident;
   040 is specifically the credit-shell generator and therefore belongs to 002b only.
4. No deployed view and no separate SQL file was found that derives the 401 result. The only
   derivation retained was prose in the D16 addendum. Review and canonical files repeat the blocked
   result but do not contain another executable derivation.

## Historical 401 traceability gap

The original `401 orders / ฿267,775.28` result has **no recoverable BigQuery job ID and no captured
query timestamp**. Commit `84df583` retains prose and was committed at 2026-07-30 12:32:39 ICT,
but a commit timestamp is not a query timestamp and must not be substituted for one. Therefore the
historical number remains blocked and cannot be made reproducible retroactively by attaching a
different job.

The `263 transactions` phrase is a stakeholder-supplied operational incident label, not a measured
row count from the 401 query. It also has no BigQuery job provenance and must remain labelled as
such.

## Fresh read-only remeasurement

The first diagnostic job, `d16_002a_split_20260801_111315`, returned zero rows because it joined
CareOS internal `order_id` directly to SAP human `U_OrderID`. That failed diagnostic is not evidence
about population size. The committed query fixes the grain by mapping
`careos_orders.id -> careos_orders.human_id` first.

Authoritative job metadata for the corrected run:

- Job ID: `d16_002a_split_20260801_111420`
- Created: `2026-08-01 04:14:25.294 UTC`
- Started: `2026-08-01 04:14:25.381 UTC`
- Ended: `2026-08-01 04:14:29.261 UTC`
- Location: `asia-southeast1`
- Dry-run upper bound: `258,022,275` bytes
- Processed: `258,022,275` bytes
- Billed: `258,998,272` bytes
- Ceiling: `21,474,836,480` bytes
- Sources: `careos_orders`, `careos_order_items`, `cancelled_change_orders`, `sap_mirror_doc`

| shape | credit-shell boundary | records | orders | excess amount (THB) |
|---|---:|---:|---:|---:|
| INCIDENT_002A_PURE | false | 65 | 65 | 42,904.86 |
| INCIDENT_002A_PURE | true | 2 | 2 | 1,290.42 |
| SHARED_FULL_PAYMENT_OTHER_FINDING | false | 86 | 86 | 57,420.48 |
| SHARED_FULL_PAYMENT_OTHER_FINDING | true | 7 | 7 | 4,516.47 |
| UNCLASSIFIED_REQUIRES_HUMAN_REVIEW | false | 30 | 30 | 20,000.44 |
| UNCLASSIFIED_REQUIRES_HUMAN_REVIEW | true | 1 | 1 | 645.21 |

Interpretation: the current stricter, reproducible query does **not** reproduce 401. It finds 191
mutually classified current candidates, of which only 67 satisfy the proposed pure-002a rule and
10 trip the credit-shell boundary alarm. These are diagnostic results pending Class A review, not
approved incident or correction populations. No number in this table replaces the 002b 244-order
diagnostic population or assigns the boundary rows to 002b.

## Pilot candidate L77828566

`L77828566` remains an **unconfirmed candidate**, not an approved pilot. Existing mirror arithmetic
and invoice-collision observations are insufficient. Missing evidence is:

1. FA/Aware confirmation of the intended incident and correction decision at
   `(OrderItem, Period)` grain;
2. SAP DocEntry and current SAP status confirmed by the evidence owner;
3. JE reference tied to a successful import LogID and success evidence;
4. verifier identity, evidence timestamp, and controlled source reference suitable for insertion
   through `sp_record_fa_verification` after 042 is reviewed and deployed;
5. explicit FA/GL verification plan for any eventual pilot outcome.

FA/Aware own the SAP/JE/import evidence. Boat owns coordination and the decision to authorize any
pilot. Until that evidence is captured in `sap_fa_verification`, no correction row, shadow approval,
export, or status advancement is permitted.
