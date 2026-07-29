# FINDINGS — Credit-shell (OrderItem, Period) duplication, money-adjacent, 2026-07-29

**Status: READ-ONLY INVESTIGATION ONLY. Nothing fixed. Not notified outside the team.**
Per Boat's explicit instruction and this project's own hard rule (money/accounting impact →
document + stop). Awaiting Boat's decision after Codex arithmetic-verifies this report
(`REVIEW_QUEUE.md`, class A).

## Mechanism (confirmed live, not inferred)

Live view: `pacific-plating-282708.sap_integration_v2.\`RCL 04_new order credit shell\`` (the
non-suffixed one — distinct from the `... new tunning` and `..._all` variants, which are separate
objects with different behavior; only this exact view was checked).

The view builds its period spine from the **new** (replacement) order's own transaction only
(`new_order_txn`/`period_spine` in `sql/production/RCL_04_new_order_credit_shell_new_tunning.sql`,
same shape). Separately, `credit_shell_link` matches old-order and new-order charges that share an
`invoice_no`. Root cause confirmed empirically (not from reading the SQL alone): for a credit-shell
pair, **the old order and the new order each independently contribute a charge/row that lands on
the same (OrderItem, Period) key in the view's output** — both rows are treated as if each were the
authoritative period-1 row, so the `add_ons` deduction (`payment_amount - add_ons` on Period 1 for
non-Compulsory items) fires once per row instead of once per (OrderItem, Period). `ExpectedReceived`
is computed identically on both rows (not divided or zeroed for the extra row), so it is duplicated
too, not just `ActualReceived`.

## Confirmed example: L80524847 (new order) / L78675328 (old order, superseded per `cancelled_change_orders`)

| OrderItem | Period | ExpectedReceived | ActualReceived |
|---|---:|---:|---:|
| L80524847-M1 | 1 | 645.21 | 645.21 |
| L80524847-M1 | 1 | 645.21 | 645.21 |
| L80524847-V1 | 1 | 1603.27 | 1523.12 |
| L80524847-V1 | 1 | 1603.27 | **-565.06** |

M1 (Compulsory) is a clean double-receipt (645.21 counted twice). V1 (Voluntary) shows the same
`ExpectedReceived` on both rows and two different, both-wrong `ActualReceived` values — one row
even goes **negative** (a real accounting-impossible value: `1603.27 - 2168.33 = -565.06`, i.e. the
full Compulsory premium was subtracted from the Voluntary side's Period-1 receipt on one of the two
duplicate rows). Two more confirmed examples from a broader sample (read-only, not exhaustive):
`L79411145-M1` (645.21/645.21 exact duplicate) and `L79411345-V1` (ExpectedReceived 2683.67 on both
rows, ActualReceived 2663.82 and 1519.85 — summed 4183.67 vs the true 2683.67, over-received by
1500.00 in this specific case, positive-value version of the same bug).

## Quantified scope (single query, one BigQuery job, `--maximum_bytes_billed=21474836480`, 7.5 GB billed)

Query scope: every `(OrderItem, Period)` key in the live view with ≥2 rows.

| Metric | Count | THB |
|---|---:|---:|
| **(OrderItem, Period) pairs with ≥2 rows (the duplication itself)** | **1,247** | — |
| ...of which have a CMI (Compulsory) sibling item on the same order | 612 | — |
| ...where `SUM(ActualReceived)` ≠ first row's `ExpectedReceived` (amount doesn't reconcile) | 441 | — |
| ...with at least one row `ActualReceived < 0` | **65** | — |
| **...where a 2nd+ row still holds a nonzero `ExpectedReceived`** (should be 0 — widest single bug, per Boat's own prediction) | **698** | — |
| Σ (Σactual − expected) across all 1,247 pairs, net | — | 246,584.15 |
| Σ absolute mismatch (`|Σactual − expected|`) across all 1,247 pairs | — | 369,914.01 |
| **...already present in `sap_integration_v3.sap_mirror_state`** (i.e. already sent to/reflected in real SAP — retroactive fix required, not just a forward-looking one) | **1,243 of 1,247 (99.7%)** | — |
| Year split (`PolicyDate`, DDMMYYYY string, parsed) | ≤2024: 0 · 2025: 9 · 2026+: 1,238 | — |
| BU split | 100% classified `InsuranceGroup` = `Motor`/`products/health-insurance` (no NonMotor value exists in this view) | — |

**BU/scope caveat, stated plainly**: this view is the Motor-lane credit-shell object. **Whether an
equivalent NonMotor credit-shell view has the same bug has NOT been checked** — do not read the
"0 NonMotor" line as "NonMotor is clean." It means "not yet looked at," a different thing.

**Almost all of this (99.7%) is already in SAP** — this is not a pipeline output that can simply be
corrected before sending; the wrong numbers likely already exist in `RCB_LIVE_DB`.

## Exact quantification query (single job, dry-run first, `--maximum_bytes_billed=21474836480`)

Dry-run: 7,506,882,355 bytes upper bound. Actual job ran successfully within the cap.

```sql
WITH base AS (
  SELECT OrderItem, Period, OrderID, InsuranceType, InsuranceGroup, PolicyDate, OrderDate,
    ExpectedReceived, ActualReceived,
    ROW_NUMBER() OVER (PARTITION BY OrderItem, Period ORDER BY ActualReceived DESC) AS rn,
    COUNT(*) OVER (PARTITION BY OrderItem, Period) AS n_rows
  FROM `pacific-plating-282708.sap_integration_v2.RCL 04_new order credit shell`
),
dup AS (
  SELECT * FROM base WHERE n_rows >= 2
),
agg AS (
  SELECT
    OrderItem, Period, ANY_VALUE(OrderID) AS OrderID,
    ANY_VALUE(InsuranceType) AS InsuranceType, ANY_VALUE(InsuranceGroup) AS InsuranceGroup,
    ANY_VALUE(PolicyDate) AS PolicyDate, ANY_VALUE(OrderDate) AS OrderDate,
    MAX(n_rows) AS n_rows,
    SUM(ActualReceived) AS sum_actual_received,
    ARRAY_AGG(ExpectedReceived ORDER BY rn)[OFFSET(0)] AS first_expected_received,
    ARRAY_AGG(ExpectedReceived ORDER BY rn)[SAFE_OFFSET(1)] AS second_expected_received,
    COUNTIF(ActualReceived < 0) AS n_rows_negative,
    COUNTIF(rn > 1 AND ExpectedReceived != 0) AS extra_rows_with_nonzero_expected
  FROM dup
  GROUP BY OrderItem, Period
),
order_has_cmi AS (
  SELECT DISTINCT OrderID
  FROM `pacific-plating-282708.sap_integration_v2.RCL 04_new order credit shell`
  WHERE InsuranceType = 'MOTOR_TYPE_COMPULSORY'
),
mirror_check AS (
  SELECT DISTINCT U_OrderItem FROM `pacific-plating-282708.sap_integration_v3.sap_mirror_state`
)
SELECT
  COUNT(*) AS duplicated_orderitem_period_pairs,
  COUNTIF(a.OrderID IN (SELECT OrderID FROM order_has_cmi)) AS pairs_with_cmi_sibling,
  COUNTIF(ROUND(a.sum_actual_received,2) != ROUND(a.first_expected_received,2)) AS pairs_sum_actual_ne_expected,
  COUNTIF(a.n_rows_negative > 0) AS pairs_with_negative_actual,
  COUNTIF(a.extra_rows_with_nonzero_expected > 0) AS pairs_extra_row_nonzero_expected,
  ROUND(SUM(a.sum_actual_received - a.first_expected_received),2) AS sum_delta_actual_minus_expected_thb,
  ROUND(SUM(IF(a.sum_actual_received != a.first_expected_received, ABS(a.sum_actual_received - a.first_expected_received), 0)),2) AS sum_abs_mismatch_thb,
  COUNTIF(a.OrderItem IN (SELECT U_OrderItem FROM mirror_check)) AS pairs_already_in_sap,
  COUNTIF(EXTRACT(YEAR FROM SAFE.PARSE_DATE('%d%m%Y', a.PolicyDate)) <= 2024) AS yr_le_2024,
  COUNTIF(EXTRACT(YEAR FROM SAFE.PARSE_DATE('%d%m%Y', a.PolicyDate)) = 2025) AS yr_2025,
  COUNTIF(EXTRACT(YEAR FROM SAFE.PARSE_DATE('%d%m%Y', a.PolicyDate)) >= 2026) AS yr_2026_plus,
  COUNTIF(a.InsuranceGroup LIKE '%non-motor%' OR a.InsuranceGroup LIKE '%nonmotor%') AS bu_nonmotor,
  COUNTIF(a.InsuranceGroup NOT LIKE '%non-motor%' AND a.InsuranceGroup NOT LIKE '%nonmotor%') AS bu_motor_or_other
FROM agg a
```

Note on `pairs_with_cmi_sibling`: joins on `OrderID` matching any row in the view with
`InsuranceType = 'MOTOR_TYPE_COMPULSORY'` anywhere (not scoped to the duplicated subset) — i.e.
"does this order have a Compulsory item at all," matching Boat's "CMI sibling" framing.
`InsuranceGroup` distinct values in this view, checked directly: only `Motor` (13,858 rows) and
`products/health-insurance` (644 rows) — no `NonMotor` value exists here, hence the BU-split caveat
above.

## Relation to INCIDENT-002 / the “263-transaction” incident

Boat's subsequent evidence on 2026-07-29 identifies the CMI credit-shell double-deduction as
`INCIDENT-002` and refers to it operationally as the 263-transaction incident. That supersedes this
finding's earlier inference that the two were unrelated. The broad duplicate-pair diagnostic in
this file is not automatically the authoritative incident population: it came from a different
query grain and its exact query timestamp was not retained. Claude Code is quantifying the
transaction list, amount impact, and overlap. Until that result is recorded, do not merge or cite
these counts as final `INCIDENT-002` scope.

## Fix method (per Boat/Aware, already recorded — NOT actioned)

Aware and Sarawut/Boyd confirmed two methods: adjustment line
(`ExpectedReceived=0`, `ActualReceived=delta`) and Cancel + fresh Paid. The mandatory selection
rule is: if `ExpectedReceived` is wrong or negative, use **Cancel + fresh Paid (Method 2)**.
Not attempted here; scope, review, and approval are still required.

## What was NOT done (by design, per instruction)

- No fix, no view edit, no SQL change to any credit-shell object.
- No notification outside the team.
- No attempt to identify which specific 1,247 pairs need Cancel+Paid vs another treatment — that is
  the next step only after Boat decides on this report.

---

# ADDENDUM 2026-07-30 — D9 remediation design (Boat's Method 2 decision)

Boat decided (D9): Method 2 requires a **new OrderItem generation** (a Paid+Cancelled item is
immutable in SAP) and confirmed **InvoiceNo uniqueness scope = per order** (closes Q8a).
`ADJ{n}_{OrderItem}` naming approved. Still source-only / design-only below — nothing deployed,
nothing sent, per instruction.

## 1. Precondition check (done first, as instructed): does `-M2` collide with real meaning?

**Yes — cannot reuse `M2` as a revision-generation suffix.** Verified live:
`SELECT REGEXP_EXTRACT(human_id, r'-([A-Z]*\d+)$') AS suffix, COUNT(*) FROM careos_order_items GROUP BY 1`
→ V1: 478,955 · M1: 175,346 · `1`: 77,340 · `2`: 23,455 · **M2: 1,019** (real, live data).
Sampled 5 `-M2` rows: every one is `motor_item_type = MOTOR_TYPE_COMPULSORY`, each on an order with
exactly 2 items (an M2 + a V1, **no M1 present** in the sampled cases) — a genuinely different real
item, not "M1 revision 2." `V2` and `M3` have 0 rows today, but "not observed" ≠ "reserved safe."

**Proposed alternative** (matches Boat's own suggested shape): append `R{generation}` to the
*original* suffix, never renumber the base digit — e.g. `L80524847-M1` (generation 1) →
`L80524847-M1R2` for the Method-2 replacement. Verified unused: `SELECT COUNT(*) FROM
careos_order_items WHERE REGEXP_CONTAINS(human_id, r'R\d+$')` → **0 rows**.
**⚠️ Proposal only — waiting on Boat's explicit confirmation of this exact string format before
anything downstream depends on it.**

## 2. `sap_orderitem_alias` (source-only, `sql/ddl/038_orderitem_alias_and_adj_invoice_minting.sql`)

Columns exactly as specified: `careos_order_item, sap_order_item, generation, reason,
audit_case_id, created_at`. Every join between a CareOS order_item and SAP-facing tables
(`sap_mirror_state`, `SAP_LIVE_FULL`, `stg_sap_state`) must resolve through this table once Method 2
exists — otherwise `-M1R2` is an orphan in recon and `-M1` reads as permanent false MISSING.
**Blast radius, not yet touched**: `sp_refresh_expected_state` (034/037), `sp_refresh_delta_export`
(018), `sp_refresh_interface_daily_status` (030) would each need this resolution added — each its
own separate, deploy-gated change once the table and naming are both confirmed.

## 3. Path C balance-test criterion: must be alias-group, not per-order_item

**Design principle** (no existing balance-test SQL was found to "fix" — recorded here as the
requirement any future balance-test implementation must satisfy, since none exists yet in this
repo): once a case is remediated, the OLD generation (`-M1`) will *permanently* show a Cancelled,
imbalanced state at SAP (that's what Cancel does), while the NEW generation (`-M1R2`) holds the
correct Paid, balanced state. **A balance check keyed on a single `sap_order_item` value would see
`-M1`'s Cancelled-imbalance forever and report the case as still broken**, even after a correct fix.
Correct check: `GROUP BY careos_order_item` (via `sap_orderitem_alias`, i.e. all generations of one
logical item together), summing/reconciling across every `sap_order_item` in that alias group before
judging balanced vs not.

## 4. B1/B2/B3 bucket definitions — corrected by Boat 2026-07-30

The inference below was necessary only because the original taxonomy remained in chat. It is now
superseded by the canonical definitions in `docs/AUDIT_CMI_ADDONS.md`:

- B1: Expected correct, Actual needs delta adjustment, SAP not already Cancelled → Method 1.
- B2: Expected incorrect or negative → Method 2.
- B3: SAP already Cancelled → Aware manual correction; no new infrastructure.

Read "B2 (Expected ผิด)" as the 698-pair `extra_rows_with_nonzero_expected` bucket already
quantified above, and "B3 (SAP cancelled แล้ว)" as duplicate pairs whose current
`sap_mirror_state.TransactionStatus` is already `Cancelled`/`Cancelled (Change order / Rejected)`.
Quantified (same live view, one additional query, joined to `sap_mirror_state`):

| Bucket | Count | Overlap with the other bucket |
|---|---:|---:|
| B2 — extra row still holds nonzero ExpectedReceived | 698 | 0 |
| B3 — already `Cancelled`/`Cancelled (Change order / Rejected)` in SAP | **2** | 0 |

B3 is small — only 2 of 1,247 pairs are already Cancelled in SAP today. Both are genuine
credit-shell pairs (`L79605066` ← `L79289825`; `L79952011` ← `L79917668`, both confirmed in
`cancelled_change_orders`). Both show `NULL` Expected/Actual on the *duplicate view rows*
themselves (these are unpaid/placeholder periods caught in the duplication, not the money-bearing
rows) while SAP's own mirror already shows a real historical `U_ActualReceived` (19,500.14 and
3,604.00 respectively) under `TransactionStatus = Cancelled`.

**Pilot correction (D11):** do not use either B3 case as a pilot. The pilot must be one B1 case
using Method 1 because it has the fewest dependencies and does not require a new OrderItem,
`sap_orderitem_alias`, or unresolved replacement naming. Ask Aware to correct the two B3 cases
manually.

## 5/6. `fn_mint_adj_invoice` + prior-ADJ-invoice check — done, source-only

`sql/ddl/038_orderitem_alias_and_adj_invoice_minting.sql`: scalar SQL function, scoped per
`U_OrderID` (matches Q8a), scans `sap_mirror_doc` for existing `ADJ\d+_` invoices under that order,
picks `MAX(n)+1`. `fn_invoice_no` itself is unchanged (still `third_party_id` identity) — this is a
new, separate function, since identity has no way to consult existing invoices.

3 unit-test cases run (regex/aggregate logic directly, function not deployed):
- Case A (no prior ADJ invoice) → extracts `1` correctly.
- Case B (non-contiguous prior `ADJ1_`/`ADJ3_`, simulated via a 3-row scratch table) → **4**
  (`MAX+1`, not gap-fill; unrelated `ADJUSTMENT_...` row correctly ignored).
- Case C (`ADJUSTMENT_...` look-alike) → `REGEXP_EXTRACT` returns `NULL`, no false match.

**Item 6 (retroactive check)**: `SELECT COUNT(*) FROM SAP_LIVE_FULL WHERE U_InvoiceNo LIKE 'ADJ%'`
→ **0 rows**. No existing `ADJ`-prefixed invoice anywhere in SAP today — no collision risk from
prior use.

## Still open / needs Boat's decision before any further build or send

1. Aware Q4: confirm the SAP-facing replacement naming/prefix. D10 requires configuration and
   forbids hardcoding the proposed `-M1R2` form.
2. Select and approve one B1 + Method-1 pilot case.
3. Ask Aware to correct the two B3 cases manually.
4. Do not deploy `sap_orderitem_alias` or `fn_mint_adj_invoice` unless a future approved B2
   remediation requires them; both remain source-only today.
