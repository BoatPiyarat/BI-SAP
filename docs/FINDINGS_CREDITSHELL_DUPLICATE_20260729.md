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

---

# ADDENDUM 2026-07-30 (cont'd) — B1 quantified, pilot drafted, generating-bug fix INCOMPLETE (auth blocker)

## Item 1 — ⚠️ SUPERSEDED: B1 pre-threshold result, do not cite

**D12/D13 supersedes this entire B1 population and amount.** The `289 / ฿85,106.84` result below
used a per-row `ABS(delta) > ฿1` floor before Boat's ±฿10 per-order buffer was documented. It is
pre-threshold and must not be cited. Replacement figures are in `4bbc16f` and remain under
class-A review; do not act on them yet.

The methodology history remains below only to explain why the result changed.

First attempt scoped B1 as "not-B2, not-B3" **within the 1,247 duplicated-pairs population**
(the same set the 698/2 counts came from) — that gives 547 candidate pairs, but sampling 5 of them
showed **all 10 rows were NULL/NULL** (both duplicate rows are unpaid-future-period placeholders
with zero real money). Verified this holds for the full 547, not just the sample: restricting to
pairs with at least one non-NULL `ExpectedReceived` inside that population returns **0 rows**. So
**B1 has zero real cases inside the duplicated-pairs set** — every money-bearing duplicate falls
into B2 or B3, none into "duplicated but Expected still correct."

**B1's real population is a different, previously unexamined slice**: single-row
(`n_rows = 1`, i.e. NOT part of a duplicate pair at all) records in the same live view where
`ExpectedReceived`/`ActualReceived` are both real and differ. First pass here caught trivial ±0.01
THB satang-rounding noise (sampled the smallest deltas directly, confirmed) — added an
`ABS(delta) > 1.00 THB` floor. Cross-checked every remaining row against
`careos.cancelled_change_orders` (either side) to rule out an unrelated mismatch source:
**100% (289 of 289) are genuinely credit-shell related.**

**B1 (verified, live, single query, dry-run 7,470,424,864 bytes upper bound)**:

| Metric | Value |
|---|---:|
| Real B1 cases (single-row, credit-shell related, |delta| > ฿1.00, not already Cancelled) | **289** |
| ≤2024 | 0 |
| 2025 | 5 |
| 2026+ | 284 |
| Overlap with B3 | 0 of 289 |
| Σ net delta (Actual − Expected) | **+฿85,106.84** |
| min / max \|delta\| | ฿1.07 / ฿4,316.42 |

Exact queries (blast-radius sample, rounding-noise sample, credit-shell cross-check, year/B3-overlap
aggregate) are in `sql/ddl/039_sap_correction_log_and_b1_pilot.sql`.

## Item 2 — VOID: five-case B1 pilot was below the materiality buffer

`sql/ddl/039_sap_correction_log_and_b1_pilot.sql`: `sap_correction_log` table designed (source-only)
plus the 5-row draft (table in that file). All 5 are over-received (`ActualReceived > Expected`),
so all 5 corrections are negative. Invoice-collision check done directly against `sap_mirror_doc`
for all 5 real orders: none have any prior `ADJ`-prefixed invoice, so `ADJ1_<OrderItem>` is
collision-free for all 5 (matches unit-test Case A from `038`).

**Gap found, flagged, not silently filled**: `sap_accounting_cutoff_dates` does not exist anywhere
in this project (checked `sap_integration_v3`, `sap_integration_v2`, `sap_data_engineer`, `SAP`) —
`10_SAP_CONTEXT.md` references it as if built, but it isn't. Used the existing rollover pattern
already live in `sap_dashboard_carepay_fully_paid.sql`'s `PaymentDate` logic as a stand-in for the
draft, explicitly marked as a placeholder pending Finance/Boat confirmation — same open question
already on record, not a new one.

Pilot is **drafted only** — validation, shadow, and `REVIEW_QUEUE` submission still pending per
Boat's own sequencing, and per D9/D11 nothing sends without explicit deploy OK.

**D13 disposition:** all five drafted cases are below the ฿10 per-order buffer, so the pilot is
void and must not be validated, submitted, or sent. Selecting “the smallest amounts” before
applying materiality chose records that require no correction. Future pilot selection must first
apply the order-level threshold and preserve the separate no-buffer `MISPOSTING` test.

## Item 3 — generating-bug fix: INCOMPLETE, blocked mid-investigation by a BigQuery auth failure

Pulled the live view's actual deployed SQL (`sap_integration_v2.\`RCL 04_new order credit shell\``,
via `bq show`) rather than reasoning from the legacy captured copies in `sql/production/`, since
those are explicitly different objects. Began a bisection to isolate exactly which join fans one
(new_order, Period) row into two: checked `careos_order_items` for a genuine duplicate row on
`L80524847-V1` (**none — exactly 1 row**), checked `cancelled_change_orders`/`all_links` for
multiple link candidates on `L80524847` (**none — exactly 1**). **BigQuery access failed
mid-bisection** (`gcloud`/`bq` token reauthentication required, cannot be completed non-interactively
from here) before reaching the `ancestors`/`new_order_old_invoice_pool`/`spine_with_payment` stages,
which is where the fan-out most likely lives (the recursive ancestor walk and its `LEFT JOIN` into
`channel_resolved` on `(new_order_id, invoice_no)` are the remaining unverified candidates).

**Ruled out** (verified, not assumed): the duplication is NOT a source-table data-quality issue
(`careos_order_items`, `cancelled_change_orders` are both clean for this case) — it is a
join/CTE-logic defect somewhere in the view itself, most likely in the `ancestors`/invoice-pool/
`channel_resolved` chain. **Not yet pinpointed to a specific line**, so no fix is proposed yet —
proposing one without finishing the bisection would risk fixing the wrong join or picking the wrong
row to keep in a money-critical view.

**Needed to continue**: `data@rabbit.co.th`'s GCP credentials need interactive re-authentication
(`gcloud auth login`) on this machine — something only a human can complete. Once restored, the
bisection resumes from `ancestors`/`new_order_old_invoice_pool` for the same `L80524847` case.

**Consequence Boat flagged is still live**: until this fix lands, the nightly credit-shell run keeps
generating new duplicate rows on top of whatever gets corrected via the B1 pilot — the pilot corrects
past rows, it does not stop new ones.

## Item 4 — no new action

`sap_orderitem_alias` / `fn_mint_adj_invoice` remain source-only, undeployed, per D10/D11 (naming
undecided, B2 remediation not yet approved).

## Item 5 — 🔴 git remote: proposal only, not created on Boat's behalf

Confirmed: `git remote -v` is empty, 108 commits since 2026-07-24 (6 days), only `master` and
`p0/stg-sap-state` branches, everything local to this one machine. `gh` CLI is not installed here,
so there's no path for me to create a remote even if it were appropriate to — and per instruction,
it isn't: repo creation/ownership is Boat's call, not something to do on Boat's behalf.

**Proposed steps for Boat to run** (or hand back to me once the empty repo exists and its URL is
known — I can run the `git remote add`/`push` half, not the repo-creation half):

1. Create a **private** repository (GitHub web UI, since `gh` isn't available locally):
   `https://github.com/new` → name it (e.g. `rabbitcare-sap-integration`) → Visibility: **Private**
   → do NOT initialize with a README/license/gitignore (this repo already has its own history).
2. Once created, note the remote URL (SSH or HTTPS) and either run these two commands directly, or
   send me the URL to run them:
   ```bash
   git remote add origin <URL>
   git push -u origin p0/stg-sap-state
   git push origin master
   ```
3. Confirm who else needs access (Codex's environment, if it pushes/pulls from a different path than
   this local checkout, needs the same remote configured on its side too — separate step, not done
   here).

Not run — waiting for the repo to exist and for explicit confirmation before pushing 108 commits of
this project's history anywhere.

---

# ADDENDUM 2026-07-29 (session, D13) — buffer ฿10/order, Class 1/2 split, root cause found, pilot re-selected

Boat confirmed 4 items same session: (1) `gcloud auth login` done, item 3 unblocked; (2) repo
`https://github.com/BoatPiyarat/BI-SAP`; (3) materiality buffer ฿10, **per order, not per
row/period** (D13); (4) `sap_accounting_cutoff_dates` still pending Finance, placeholder stays
flagged.

## Item A — push to remote: BLOCKED by the permission classifier, not by me choosing to withhold it

`git remote add origin https://github.com/BoatPiyarat/BI-SAP.git` was **blocked by the Claude Code
auto-mode permission classifier** — adding a remote and pushing 108 commits to a brand-new external
repo is exactly the class of hard-to-reverse, externally-visible action the classifier gates,
regardless of the explicit written instruction. This is not something I can route around with a
different tool - per the classifier's own guidance, stopping and explaining is the correct response,
not finding a workaround. **Needs an explicit interactive approval from Boat in the session, or Boat
running the two commands directly.** Nothing pushed. Branch check before attempting: only `master`
and `p0/stg-sap-state` exist in this local checkout - the fuller branch list Boat mentioned
(`feat/v3-sql`, `chore/docs-governance`) is not present here, likely in Codex's separate checkout -
flagging so the push doesn't get reported as "complete" when only 2 of the expected branches exist
locally to push in the first place.

## Item B — Class 1 / Class 2 re-quantified at ORDER level: ⚠️ caught and fixed a real formula bug via the known-answer test

First attempt computed delta **per raw output row** (`ActualReceived - ExpectedReceived`), summed
across an order. For a duplicated `(OrderItem, Period)` key this is wrong: `ExpectedReceived` is
itself duplicated identically on both rows (the underlying bug), so comparing each duplicate row
against its own (already-wrong) Expected masks the real over/under pattern entirely. Result:
**`L80524847` landed in Class 1, not Class 2 - failing Boat's own known-answer test outright**,
exactly the check it was designed to catch.

**Fixed**: compute delta at the `(OrderItem, Period)` **key** grain first — `SUM(ActualReceived)`
across every row sharing that key, minus the **single** true `ExpectedReceived` (not summed) — the
same formula already validated for B1/B2. Then sum that per-key delta up to the order level.
Re-ran the known-answer test: `L80524847` → **Class 2, net_delta = 0.00** (M1 key delta = +645.21,
V1 key delta = −645.21, netting to zero) — **passes**, matches Boat's own worked example exactly.

**Corrected order-level quantification** (single query, dry-run 7,470,446,905 bytes upper bound):

| Class 1 — AMOUNT_VARIANCE (`|net_delta| ≥ ฿10`) | |
|---|---:|
| Orders | **559** |
| Σ gross (Σ\|key_delta\| per order, summed) | ฿350,491.24 |
| Σ net (Σ key_delta per order, summed) | ฿331,671.78 |
| ≤2024 / 2025 / 2026+ | 0 / 9 / 550 |
| Histogram ฿10–100 / ฿100–1,000 / >฿1,000 | 102 / 393 / 64 |
| Orders where every individual key was <฿10 but the order sum wasn't (order-level catches something key-level would miss) | **0** — verified, not assumed: in every Class-1 order at least one individual key already had \|delta\| ≥ ฿10, so key-level checking would have caught these too |

| Class 2 — MISPOSTING (`|net_delta| < ฿10` AND sign-flip within the order) | |
|---|---:|
| Orders | **70** |
| Σ gross (Σ\|key_delta\| per order — the real money moved, even though net ≈ 0) | ฿115,553.58 |
| ≤2024 / 2025 / 2026+ | 0 / 0 / 70 |

Sanity: 3,457 total orders in the view; 664 have any nonzero key_delta at all; 559 + 70 = 629,
leaving 35 orders with a small net delta (<฿10) and no sign-flip — genuinely immaterial, no action.

## Item C — Global Standard v2.1 §6.1.1: text drafted, NOT applied to the source document

`Global Standard v2.1` lives on Google Drive as a `.drawio` file (`90_TEAM_CONTEXT.md`'s asset-
location list), not in this repo, and not in a format I can safely precision-edit. Matching this
project's own established precedent (the 2026-07-11 changelog entry: *"Drafted: Global Standard v2.1
Layer 6 addendum"* — drafted in text, applied to the Drive doc separately) — drafting the exact
replacement text here for Boat/whoever maintains the Drive doc to apply:

> **§6.1.1 Money reconciliation tolerance (revised 2026-07-30 per D13, supersedes "proposed ±0.01
> per document"):**
> Tolerance is evaluated at the **order level** (aggregate every `order_item`/period row under one
> `order_id` first) — never per document, row, or period in isolation.
> - **AMOUNT_VARIANCE**: tolerance = **±฿10 per order**. Compute net delta =
>   Σ(`ActualReceived − ExpectedReceived`) across every row belonging to the order (using the single
>   true Expected per key, not a duplicated one); flag only if `|net delta| ≥ ฿10`.
> - **MISPOSTING**: **no tolerance**. Flag if the order's keys contain both a positive delta and a
>   negative delta, regardless of how small the net — money is on the wrong item/side even when the
>   order-level total looks balanced (net can be exactly 0 and still be a real misposting).
> - Any other recon money check (`PERIOD_NOT_BALANCED` etc.) must use the same order-level
>   aggregate, not per-row comparison — per-row checking produces both false negatives (a real net
>   issue hidden by noise) and false positives (offsetting duplicate rows inside one order looking
>   individually wrong when the order is fine).

## Item D — generating-bug root cause FOUND: multiple SUCCESSFUL charges per (transaction, installment_number)

Resumed the bisection where it stopped (auth blocker resolved). Ruled out `ancestors` and
`new_order_old_invoice_pool` for `L80524847` — both return exactly 1 row, not the fan-out source.

**Found it**: `careos.carepay_charges` for `L80524847`'s own (new-order) transaction
(`9aab5e0b-f6b2-4ac6-ae43-70088fef7482`) has **two SUCCESSFUL charges both with
`installment_number = 1`** — `4e4ca07f...` (฿2,168.33, 2026-07-24) and `7ad5b550...` (฿80.15,
2026-07-27, a later top-up). The view's `spine_with_payment` CTE joins
`charges c ON c.transaction_id = s.transaction_id AND c.installment_number = s.Period` — with two
matching charges for the same period, this join fans one period-spine row into two, and the
`add_ons` deduction (applied per resulting row) fires twice instead of once.

**This is broader than credit-shell specifically**: checked `careos.carepay_charges` project-wide —
**11,935 distinct transactions** have at least one `installment_number` with more than one
`SUCCESSFUL` charge (12,156 transaction+installment pairs total). Most of these likely feed other
views that aggregate correctly; the credit-shell view specifically does not. Not claiming every one
of the 11,935 is a credit-shell case — only that this is the general data shape the view's join
fails to handle, and credit-shell orders happen to hit it often (initial charge + later top-up
charge, both tagged to period 1).

**≥฿10 threshold check (Boat's ⚠️ ask)**: has not yet been separately re-verified that Class
1/Class 2 orders are still 100% credit-shell related at this new threshold (the B1-stage check
verified this at the >฿1 threshold, before D13's buffer existed) - **not done this pass, flagged as
outstanding** rather than assumed carried over.

**Fix still not deployed** — root cause is now understood and evidence-backed, but no shadow view
has been built or diffed yet. Given the `sap_integration_v2` DDL-exception this requires (hard rule:
DDL only in `sap_integration_v3`), a fix needs explicit approval before any shadow/deploy step,
per this project's own deploy gate.

---

# ADDENDUM 2026-07-30 — D14 Method-1 routing and remote resolution

D14 supersedes any inference that Class 2 needs Cancel/new-generation infrastructure:

| Group | Correction |
|---|---|
| Class 1 `AMOUNT_VARIANCE` | Method 1 |
| Class 2 `MISPOSTING` | Method 1 per affected item |
| B2 Expected itself wrong | Method 2; naming/alias/Aware Q4 still apply |
| B3 already Cancelled | Manual SAP correction |

Method 1 fixes amounts but leaves the duplicate full-Expected document in SAP. If that document
created a duplicate JE, the JE may remain. Required evidence is therefore two explicitly approved
pilots—`L79871659` and `L80524847`—followed by Aware/FA GL verification. Balanced interface
amounts alone do not pass the pilot.

The earlier “remote empty/push blocked” sections are historical and **RESOLVED**. `origin` is
`https://github.com/BoatPiyarat/BI-SAP.git`; `p0/stg-sap-state` was pushed, and fetch/contains
verification confirmed `4bbc16f`, `18e4342`, `3106719`, `73e94e0`, and `6863dc8` are on
`origin/p0/stg-sap-state`.

## Item E — re-checked the original 698 B2 keys against the ฿10/order buffer

612 distinct orders behind the 698 keys. Reclassified each at the order level:

| Reclassification | Orders |
|---|---:|
| Still Class 1 (AMOUNT_VARIANCE, material) | 303 |
| Now Class 2 (MISPOSTING - was hidden inside "B2," net was actually ≈0) | 140 |
| Now under buffer, no sign-flip (genuinely immaterial) | **255** |

Confirms Boat's own suspicion — a meaningful share (255 of 612, ~42%) of the original B2 scope
shrinks to immaterial once aggregated correctly at order level with the ฿10 buffer. The other 443
(303+140) remain real, split across the two classes with different required treatment.

## Pilot — RESELECTED (the earlier 5-case draft is now below the ฿10 threshold and invalid)

The previous pilot draft (`039`, deltas ฿1.07–7.68) predates D13's ฿10/order buffer and no longer
qualifies. New pilot, smallest Class-1 (AMOUNT_VARIANCE) 2026+ order: **`L79871659`**
(`PolicyDate` 14032026), net_delta = **+฿11.27**. Detail: single OrderItem (`L79871659-V1`, no
duplication at all in this case), 6 periods, only Period 1 mismatches
(Expected ฿1,488.71, Actual ฿1,499.98, delta +11.27); Periods 2–6 all clean (Expected=Actual=
฿1,488.73). Invoice-collision check against `sap_mirror_doc` for this order: 5 existing invoices,
none `ADJ`-prefixed — `ADJ1_L79871659-V1` is collision-free. Correction draft: `ExpectedReceived=0`,
`ActualReceived=-11.27` (over-received, so negative), same open dependencies as before (cutoff-dates
placeholder, `sap_correction_log` deploy, validation pass) — **not sent**.

**⚠️ Superseded again, same session (D14)**: `L79871659` (net +11.27) is too close to the noise
floor per Boat's own call — see below for the two reselected pilots.

---

# ADDENDUM 2026-07-30 (session, D14 supplementary) — Method 1 proof for Class 2, generating-bug fix comparison, L78496990 traced, provenance/purity recheck

**⚠️ Note on sequencing**: this section was drafted from D14's chat instructions before the
"ADDENDUM 2026-07-30 — D14 Method-1 routing and remote resolution" section above (commit `0a69143`)
landed. That committed section already resolved the git-push item (origin is live, `p0/stg-sap-state`
pushed and confirmed) and already names `L79871659` + `L80524847` as the two required pilots. **This
directly conflicts with Boat's own D14 chat instruction** ("ไม่เอา ฿11.27 ใกล้ noise floor เกินไป" —
do not use the ฿11.27 case, too close to the noise floor, when selecting the Class 1 pilot). Both
versions are preserved below rather than silently picking one — **Boat/Aware needs to confirm which
pilot set is authoritative** before either is sent. The rest of this section (Method 1 proof,
generating-bug fix options, `L78496990` trace, provenance/purity recheck) is independent of that
conflict and stands regardless of which pilot set wins.

Boat D14: Class 2 (MISPOSTING) does **not** need Method 2/Cancel/new-OrderItem/alias — it can be
fixed on our side with Method 1 directly, avoiding the naming blocker entirely.

## Item 4 — the 3 pre-send blockers, answered

### 4a. Provenance: B2 698→612 re-run fresh — numbers have DRIFTED, confirming the bug is still live

Re-ran the exact same query used for the original 698/612 figures. **Fresh result: 700 keys / 613
distinct orders** — not 698/612. This is not a measurement error; it is **direct evidence the
generating bug is still active and creating new duplicate rows between queries**, exactly the
"tonight creates new cases on top of what we fix" risk Boat flagged. Both the original (698/612,
`73e94e0`) and this fresh count (700/613, this session) are cited — neither is "the" number; the
population is a moving target until the generating bug is fixed.

### 4b. L78496990 — ⚠️ NOT a credit-shell case at all; wrong pipeline entirely

`L78496990` returns `NULL` for Class/net_delta because **it does not appear anywhere in the
credit-shell view or its two variants**. Checked directly, not assumed:
- Exists in `careos.careos_orders`: yes.
- In `careos.cancelled_change_orders` (either side): **no** — not a credit-shell chain member.
- In `sap_integration_v3.sap_mirror_state`: **yes, 2 rows** (already in real SAP).
- In `sap_integration_v2.\`RCL 04_new order credit shell_all\`` / `...new tunning`: no.
- In `sap_data_engineer.sap_dashboard_carepay_fully_paid` (the ONETIME/RCL view checked earlier
  this session for the unrelated H2 NULL-safe issue): **yes, 2 rows.**

**Real SAP state, confirmed**: `L78496990-M1` (Expected ฿278.18, Actual ฿12,512.56) and
`L78496990-V1` (Expected ฿11,172.92, Actual ฿12,512.56) — **both items show the identical
`ActualReceived` and identical `U_InvoiceNo` (`chrg_6854rk6j1szdhqvasym`)**. Traced to the raw
source: exactly **one** real `SUCCESSFUL` charge exists (`cd50e930...`, ฿12,512.56,
2026-06-26) — a single combined payment that should be split between the Compulsory (M1,
`oi.gross_premium` = ฿645.21) and Voluntary (V1) portions, per `sap_dashboard_carepay_fully_paid`'s
own `compu_detail`-based split logic (reviewed earlier this session). **Neither item's actual value
matches what that split logic should produce** (M1 should show ~฿645.21, not ฿12,512.56) — the
split did not apply.

**This is a real, confirmed, money-adjacent misposting — but a DIFFERENT bug, in a DIFFERENT view,
from a DIFFERENT mechanism than the credit-shell duplication (INCIDENT-002) this whole FINDINGS
document is about.** Not force-fit into Class 1/Class 2 — those classes are specific to the
credit-shell view. This needs its own dedicated investigation (why did `sap_dashboard_carepay_fully_paid`'s
own split formula not apply here), not started beyond this confirmation. Flagging for Boat/FA
directly: **the case FA is waiting on lives in `sap_dashboard_carepay_fully_paid`, not in the
credit-shell incident being tracked here.**

### 4c. Credit-shell purity recheck at the ฿10 threshold

| | Orders | Credit-shell related | Not credit-shell |
|---|---:|---:|---:|
| Class 1 (fresh run) | 559 | 558 | **1** (`L79806886`) |
| Class 2 (fresh run) | 71 | 71 | 0 |

Class 2 is 100% pure. Class 1 has **one exception**: `L79806886` does not match
`cancelled_change_orders` on either side. **Not concluded to be unrelated** — the credit-shell
view's own logic has a *second* link-detection path (`invoice_links`/`credit_shell_classified`,
inferred via a shared `invoice_no` across two orders, independent of `cancelled_change_orders`) that
my purity check did not test. `L79806886` may still be credit-shell via that second path — genuinely
unverified, flagged rather than guessed either way.

## Item 1 — Method 1 design for Class 2 (MISPOSTING), with a worked proof

**Design**: for every `(OrderItem, Period)` key within a Class-2 order where `key_delta != 0`
(computed as `SUM(ActualReceived across the key's rows) - single true ExpectedReceived`, the same
formula validated for B1/B2/Class 1), emit exactly one correction row:
- `ExpectedReceived = 0` (pure correction, no new obligation)
- `ActualReceived = -key_delta` (over-received key → negative correction; under-received key →
  positive correction)
- `InvoiceNo = fn_mint_adj_invoice(OrderID, OrderItem)` (per-order-scoped mint, `038`)
- `PaymentDate` = next open accounting period (same flagged placeholder as before)

**Proof, not just an empirical check** (holds by construction, for every key and every order):
- Per key: after adding the correction, `SUM(Actual)` becomes
  `original_sum_actual + (-key_delta)` = `original_sum_actual - (original_sum_actual - single_expected)`
  = `single_expected` — **exact equality, algebraically guaranteed**, not something that merely
  "checks out" on inspection.
- Per order: `Σ(corrections) = Σ(-key_delta) = -net_delta`. Since
  `original_total_actual = original_total_expected + net_delta` by definition,
  `corrected_total_actual = original_total_expected + net_delta - net_delta = original_total_expected`
  — the order-level net becomes **exactly 0**, not merely "stays under ฿10." Correcting every key to
  its own true Expected necessarily reconciles the whole order, by construction — no new variance is
  possible from this method.

**Worked example, real data** (`L79900064`, the reselected Class-2 pilot — see below): `M1` key
delta = +645.21 → correction `Actual = -645.21`; `V1` Period-1 key delta = −645.21 → correction
`Actual = +645.21`. Verified directly against the real row values:
`SUM(Actual)` for `M1` = `645.21 + 645.21 − 645.21 = 645.21` = the true Expected ✓.
`SUM(Actual)` for `V1` P1 = `−644.82 + 1969.14 + 645.21 = 1969.53` = the true Expected ✓ (computed,
not rounded to fit).

## Item 2 — two pilots reselected per D14's chat instruction (⚠️ conflicts with the already-committed `0a69143` selection — see note above, unresolved)

Per Boat's D14 chat instruction, `L79871659` was rejected as too close to the noise floor and two
new pilots were selected and fully verified below. **However**, commit `0a69143` (already landed,
see top-of-section note) names `L79871659` + `L80524847` instead. Reporting both computed candidates
here for the record — **neither pilot set should be sent until this conflict is resolved.**

### Class 1 (AMOUNT_VARIANCE) pilot: `L80046687`
Net delta ฿50.00 (smallest in the ฿50–500 band, 2026+, `PolicyDate` 28042026). Single mismatching
key: `L80046687-V1` Period 1 (Expected ฿1,150.00, Actual ฿1,200.00); Periods 2–6 all clean
(Expected=Actual=฿1,150.00) — no duplication involved, a clean single-row variance. Invoice check:
6 existing invoices on this order, none `ADJ`-prefixed. Correction: `ExpectedReceived=0`,
`ActualReceived=-50.00`, `InvoiceNo=ADJ1_L80046687-V1`.

### Class 2 (MISPOSTING) pilot: `L79900064`
Gross ฿1,290.42 (tied with 2 other orders at the same gross; picked the earliest `PolicyDate`,
13032026, as the tiebreak). Same shape as the `L80524847` example: `M1` Period 1 duplicated
(645.21/645.21, key delta +645.21); `V1` Period 1 duplicated with identical Expected on both rows
(1969.53) and Actual `-644.82`/`1969.14` (key delta −645.21); `V1` Periods 2–6 clean. Order net =
0.00. Invoice check: 9 existing invoices on this order, none `ADJ`-prefixed. Two corrections:
`M1` P1 → `ExpectedReceived=0, ActualReceived=-645.21, InvoiceNo=ADJ1_L79900064-M1`;
`V1` P1 → `ExpectedReceived=0, ActualReceived=+645.21, InvoiceNo=ADJ1_L79900064-V1` (different
`OrderItem` suffix means both can independently mint `ADJ1_` with no real collision, even though
both queries would see "0 prior ADJ invoices" at send time).

**⚠️ Boat's own flag, recorded so it isn't lost**: this Class-2 pilot's result must be shown to
Aware/FA **after import**, specifically to answer the open question Aware has not yet answered -
does an adjustment line actually correct GL misposting, or does SAP's own accounting still show the
money on the wrong side regardless of the interface-level fix? This pilot is also evidence-gathering
for that unanswered question, not only a fix.

Both pilots: still need `sap_correction_log` deployed, `fn_mint_adj_invoice` deployed and re-verified
live, the real `sap_accounting_cutoff_dates` (still a placeholder), full validation pass, and a
shadow build — **none of that done yet, nothing sent.**

## Item 3 — generating-bug fix: two alternatives compared, evidence gathered, NOT deployed

Checked who actually reads the buggy view before comparing options (30-day
`INFORMATION_SCHEMA.JOBS_BY_PROJECT` check): `piyaratt@rabbit.co.th` (21 queries),
`data@rabbit.co.th` (36, includes this investigation), `natnichak@rabbit.co.th` (1, 2026-07-02).
**More importantly**: `sap_view.RCL_Motor_process_4_creditshell` — a real production object, created
2026-07-24 alongside the other legacy A2-fix views — reads `SELECT * FROM
sap_integration_v2.\`RCL 04_new order credit shell\`` **directly**, filtered to un-imported
credit-shell items. Given this project's own confirmed fact that "V3 produces no interface file yet;
all files SAP receives still come from the legacy `sap_view.*` path," **this view is very likely
already in or adjacent to the real nightly export chain** - not just an internal reporting artifact.

**Option A — fix the v2 view directly** (`sap_integration_v2.\`RCL 04_new order credit shell\``):
dedupe `charges` by `(transaction_id, installment_number)` before the join in `spine_with_payment`
(e.g. `SUM(amount)` across same-key charges, since the real data shows genuine separate payments -
an initial charge + a later top-up - both legitimately contributing money, not a duplicate to
discard). **Pros**: fixes the root cause for every consumer, including `sap_view.RCL_Motor_process_4_creditshell`
and thus the real export path - stops tonight's bleeding. **Cons**: requires an explicit exception to
"DDL only in `sap_integration_v3`"; touches the one canonical object other real users query.
**Requires**: shadow-diff-then-swap, same discipline as H2/H4, plus explicit deploy OK given the
DDL-location exception.

**Option B — a `sap_integration_v3` wrapper/corrected view** that reads FROM the v2 view and
re-aggregates to one row per `(OrderItem, Period)`: **Pros**: stays inside the normal v3-only DDL
rule, zero risk to the existing v2 object, fully testable in isolation. **Cons**: does **not** stop
new bad rows from being generated by the v2 view itself - `sap_view.RCL_Motor_process_4_creditshell`
would keep reading the buggy v2 view directly unless it is *also* repointed to the new v3 wrapper,
which is itself a second, separate legacy-view change requiring its own approval. **Given Boat's own
stated reason for wanting this fixed before the pilot** ("ไม่งั้นคืนนี้สร้างเคสใหม่ทับที่เราแก้"),
**Option B alone does not satisfy that requirement** - only Option A, or Option B plus repointing
the real consumer, does.

**Recommendation (not acted on, awaiting Boat's decision)**: Option A, via the standard
shadow-diff-then-swap process this project already uses for legacy view changes, given the direct
evidence that the real production wrapper reads this exact view. Neither option built or deployed.

## Item 5 — push: still blocked

`git remote add`/push remains blocked by the permission classifier from the prior turn. Per
instruction, not circumvented. Waiting for Boat to run it directly, or to grant it in this session.

---

# ADDENDUM 2026-07-30 (session, D15) — pilot authority resolved; second stream quantified with a caught formula bug; Option A fix drafted; second stream needs its own separate fix

Boat D15 resolved the pilot conflict flagged above: **`L80046687` (Class 1) + `L79900064` (Class 2)
are authoritative**; `0a69143`'s pair (`L79871659` + `L80524847`) is superseded — `L79871659` is too
close to the noise floor, `L80524847` has too high a blast radius to use as a pilot (kept instead as
a permanent known-answer test for Class-2 queries, per its established role since D13). Option A
(fix the `sap_integration_v2` view directly) is approved **as a direction**; deploy is still not
approved.

## Item 1 — second stream (`sap_dashboard_carepay_fully_paid`) quantified — ⚠️ a real formula bug caught mid-quantification, second bug potentially still open

Boat's ask: quantify the "onetime" stream the same way as credit-shell (Class 1 ≥฿10/order, Class 2
sign-flip within order), using `L78496990` as the known-answer test, with year split, sums, and
overlap against the existing 629/630 credit-shell orders — since the number reported to FA must
cover both streams or it will be incomplete again, exactly the risk Boat has flagged from the start.

**Known-answer check first**: pulled `L78496990` directly from `sap_dashboard_carepay_fully_paid`
(not `sap_mirror_state`, which is a later, already-imported snapshot with different numbers and isn't
the right source for a *source-side* quantification). Real values: `M1` Period 1 balanced
(Expected=Actual=฿645.21); `V1` Period 1 Expected ฿11,172.92, Actual ฿11,867.35, delta **+฿694.43**.
No duplication for this specific order (2 rows total, one per item) — so `L78496990` classifies
Class 1 (single-direction, ≥฿10), which became this stream's baseline known-answer test.

**First quantification pass (mechanically reusing the credit-shell formula) — wrong, caught before
reporting**: applying `single_expected = ARRAY_AGG(Expected ORDER BY (Actual IS NULL))[OFFSET(0)]`
(the credit-shell pick, which relies on duplicate rows carrying an *identical* Expected value) gave
**8,915 orders, Σ gross ฿15,487,986.70, Σ net ฿11,701,869.52** (0 Class 2 orders). Before reporting
this, sampled raw duplicate-key rows directly and found the credit-shell assumption does **not**
hold here: e.g. `L78864267-V1` Period 1 has 3 rows — `(0.00 / 36,900.00)`, `(0.00 / 36,900.00)`,
`(36,900.00 / 36,900.00)` — Expected genuinely *differs* across the "duplicate" rows (0 vs. the real
value), not identical as in credit-shell. `ARRAY_AGG ... ORDER BY (Actual IS NULL)` ties on all-non-
null Actual and picks an **arbitrary** row — sometimes the real Expected, sometimes 0 — a
nondeterministic, silently-wrong pick. **This is exactly the class of error the known-answer-test
discipline exists to catch**, caught here by sampling raw rows rather than trusting the aggregate.

**Root cause (confirmed via the view's own definition, not inferred)**: `sap_dashboard_carepay_fully_paid`'s
`onetime_master` CTE assigns each transaction's `SUCCESSFUL` charges a `charge_rank` (`ROW_NUMBER()
OVER (PARTITION BY transaction_id ORDER BY create_time)`), joins `charges` to `order_items` via the
shared `transactions`/`orders` base (**not** a per-item key), and *by design* zeroes
`ExpectedReceived` for every `charge_rank != 1` (to avoid double-counting Expected across a real
item's own follow-up charges) while `ActualReceived` for `charge_rank != 1` carries the real charge
amount. This is a **structurally different generator from credit-shell** — confirmed, not assumed,
matching Boat's own hypothesis — credit-shell fans out via an installment-number join on `charges`;
this stream fans out via a `transaction_id`-scoped `charge_rank` with no period/item key at all.

**Fix applied**: `single_expected = MAX(ExpectedReceived)` (deterministic — correctly picks the one
real non-zero value out of the charge_rank=1 row, since compulsory items hold the same value on
every row anyway). Re-quantified: **8,525 orders, Σ gross ฿6,866,459.98, Σ net ฿3,033,610.26** — the
naive pick had overstated gross by ~2.25× and net by ~3.9×. Still 0 Class 2 orders (no order in this
stream shows both a positive and a negative key-delta — every real anomaly here is one-directional).
Year split: 2025 = 5,313, 2026+ = 3,212, ≤2024 = 0.

**⚠️ Second, smaller, still-open sub-issue found while sampling**: `L78864267`'s 3 "duplicate" rows
trace back to **3 literally identical rows in `careos.carepay_charges` itself** — same
`transaction_id`, same `installment_number=1`, same `amount=3,690,000` satang, same
`create_time` (`2025-09-19 09:57:23`), all `status='SUCCESSFUL'`. This looks like raw upstream
log-duplication (one real payment recorded 3 times), not 3 genuine separate charges — contrast with
`L78881232`, which has 2 *legitimately distinct* charges (different amounts, different timestamps —
one bundled first payment covering both `M1`+`V1`, one real later top-up), correctly handled by the
view's own `charge_rank`/`compu_detail` split logic. Quantified the prevalence: of the 1,126
duplicate `(OrderID, OrderItem, Period)` keys in this view, **179 (16%) have every row's
`ActualReceived` value identical** (the `L78864267`-shaped risk — possible raw log-duplication);
**929 (82%) have all-distinct values** (the `L78881232`-shaped pattern — genuine multiple real
charges); 18 mixed. Re-ran the quantification collapsing exact full-row duplicates first (`SELECT
DISTINCT` before the per-key aggregation): same 8,525 orders, but Σ gross drops further to
**฿6,198,229.77** and Σ net to **฿2,365,380.05**.

**Honest range, not a single number — do not quote one figure to FA yet**: **8,525 orders**, Σ gross
**฿6.20M–6.87M**, Σ net **฿2.37M–3.03M**, depending on whether the 179 identical-repeated-charge keys
represent real repeat payments (upper bound) or raw log-duplication that should count once (lower
bound). This is **not yet resolved** and needs Boat/Aware's read on whether `carepay_charges` can
legitimately contain 2+ truly-identical SUCCESSFUL charges (same amount, same timestamp) for one
real payment, or whether that pattern itself is a known logging defect.

**Overlap with credit-shell (629/630 orders)**: re-ran the credit-shell order list fresh alongside
this stream's list in the same job — credit-shell **630** orders (drift continues, consistent with
D14's finding that the credit-shell bug is still live), this stream **8,927** orders (Class 1 +
Class 2 combined, pre-formula-fix count; post-fix Class 1 alone is 8,525, Class 2 is 0), **overlap =
1 order**. The two populations are almost entirely disjoint — strong, direct evidence these are two
separate generators, not one bug double-counted.

**This population is an order of magnitude larger than credit-shell's** (8,525 vs. 630) and was not
previously on FA's radar at all. Flagging prominently rather than downplaying: this may be the more
consequential of the two incidents by total value, even accounting for the unresolved range above.
Recommend Boat decide next steps (further validation, looping in Aware) before any number from this
stream is quoted externally.

## Item 2 — Option A drafted (`sql/ddl/040_generating_bug_option_a_dedup_charges.sql`); confirmed stream 2 needs its own separate fix

Pulled the live `sap_integration_v2.\`RCL 04_new order credit shell\`` view's full definition
directly (not reconstructed from memory) to draft Option A precisely: dedupe `charges` to one row
per `(transaction_id, installment_number)` — `SUM(amount)` (real money, multiple genuine charges for
one period should both count), with an explicitly flagged **open decision** (not mine to make) on
which charge's `third_party_id` becomes the row's `InvoiceNo` when 2+ charges share a key. Full
3-stage validation plan drafted (shadow view → row/distribution diff + 5 named samples → schema
ordinal diff against `INFORMATION_SCHEMA.COLUMNS`) — **none of the 3 stages has been run**, nothing
built or deployed. One assumption flagged as unverified: whether
`transaction_snapshot_installment_details` (joined separately by `snapshot_id`+`period`) is itself
already 1-row-per-key — if not, it's a second fanout source this fix would not touch. Not checked
this session.

**Stream 2 check (explicit D15 ask)**: does Option A's fix also apply to
`sap_dashboard_carepay_fully_paid`? **No.** Confirmed directly from that view's own definition (see
Item 1 above) — its fanout is `transaction_id`-scoped via `charge_rank`, not an installment-number
join, and it deliberately zeroes Expected for non-first charges by design. Option A's dedup-by-
`(transaction_id, installment_number)` approach doesn't map onto that join shape at all. Stream 2
needs its own, separate fix design — not started; the `MAX(Expected)` correction used for
quantification in Item 1 is a query-side workaround for measuring the problem, not a proposed fix
for the view itself.

## Item 3 — two pilots, shadow-only, prepared per Codex's request — not sent

Drafted in `sql/ddl/041_pilot_shadow_corrections_L80046687_L79900064.sql`: the exact
`sap_correction_log` insert rows for both authoritative pilots (`L80046687` Class 1, `L79900064`
Class 2), reusing `fn_mint_adj_invoice`'s already-verified minting logic (`ADJ1_L80046687-V1`,
`ADJ1_L79900064-M1`, `ADJ1_L79900064-V1` — all invoice-collision-checked clean in the D14
addendum). Explicitly gated: **not run, not deployed, not sent** — blocked on the same three
dependencies as before (the real `sap_accounting_cutoff_dates`, `sap_correction_log`/
`fn_mint_adj_invoice` actually deployed, full validation pass) **plus** D15's explicit instruction
that neither pilot goes out until the generating bug (Item 2) is actually fixed, since sending now
risks the exact scenario Boat has repeatedly flagged — the bug regenerating the same case the same
night it's corrected.

## Item 4 — push: still blocked

Retried `git push origin p0/stg-sap-state` with D15's explicit approval — still denied by the
permission classifier, same as every prior attempt. Not circumvented. 2 local commits
(`9e6b44d`, `deea417`) remain unpushed; Boat needs to run this directly or grant the permission.

---

# ADDENDUM 2026-07-30 (session, D16) — 🔴 methodology error FA (Mo) caught: POSTED_WRONG vs REJECTED_NEVER_POSTED were conflated; Class 1 is over-inclusive; both pilots pulled

Mo (FA) caught a real methodology error: `L80524847` has no JE not because it needs correction, but
because its entire import file (LogID 21090, 26/26 rows) was **rejected outright** — "Sequence of
Period invalid." It never posted at all. Every quantification so far (D13/D14/D15's 559+70/71) was
computed straight from `sap_integration_v2`'s own output — **our generated view, not what SAP
actually holds** — so it silently conflates two populations that need completely different
treatment: orders SAP actually posted wrong (need a correction line) vs. orders that never posted at
all (need the generating bug fixed, then a normal resend — no correction, since there's nothing
posted to correct).

## Item 1 — provenance confirmed: our own output, not `sap_mirror_doc`

Re-checked the D13 quantification query directly: `FROM
\`pacific-plating-282708.sap_integration_v2.RCL 04_new order credit shell\`` — confirmed, this is
our own generated view's live output, never `sap_mirror_doc` (the table that actually mirrors what
SAP holds — `DocEntry`, `TransactionStatus`, real `U_InvoiceNo`). Mo's concern is valid: the
559+71 figures need re-verification against what's actually posted before being treated as a
correction population.

## Item 2 — POSTED_WRONG vs REJECTED_NEVER_POSTED, split at order level using `sap_mirror_doc`

`sap_import_result` (the table meant to log import successes/failures, `batch_label`, `file_name`,
`order_item`, `error_type`, `message`) is currently **empty (0 rows)** — it isn't populated, so it
couldn't be used to independently verify LogID 21090's rejection reason; `sap_mirror_doc` (what SAP
actually holds — `DocEntry`, `TransactionStatus`, etc.) was used instead as the ground truth.

**Confirmed directly**: `L80524847` has **zero rows** in `sap_mirror_doc` — not one `DocEntry`,
matching Mo's "26/26 rejected" finding exactly (this order never posted at all). Splitting the full
559+71 population by whether the order has *any* row in `sap_mirror_doc`:

| Class | Posted (≥1 row) | Rejected/never posted (0 rows) |
|---|---:|---:|
| Class 1 (559) | 559 | **0** |
| Class 2 (71) | 69 | **2** (`L80524847`, `L80524883`) |

Only 2 of 630 orders are fully never-posted at the order level — both Class 2, both almost
certainly from the same rejected file (adjacent OrderIDs, `L80524847`/`L80524883`, both created
2026-07-27). Class 1 has zero order-level rejections.

**⚠️ But "posted-any" is a weaker test than it looks — a real gap found, not yet resolved**: pulled
`L80046687`'s (the then-current Class 1 pilot) full `sap_mirror_doc` history and compared it
against the *current* `sap_integration_v2` snapshot. Period 1 matches exactly (Expected 1150.00 →
Actual 1200.00 in both) — but **Period 2 shows Expected 1150.00 → Actual 1100.00 in `sap_mirror_doc`
(a real, already-posted −50 variance)**, while the *current* view now shows Period 2 as clean
(1150.00 = 1150.00). The underlying source data changed sometime after Period 2 posted, so today's
view no longer shows the anomaly — but SAP still has the wrong number sitting in it. **This means an
order can be "posted-any" = true at the order level while (a) still having an actually-posted-wrong
period my current-snapshot quantification cannot see at all, and (b) the period my quantification
*does* flag might not be the only wrong one, or might no longer be wrong in the way the snapshot
implies.** A trustworthy POSTED_WRONG population needs a **key-level** reconciliation against
`sap_mirror_doc`'s actual historical per-period values, not an order-level presence check and not
today's view snapshot. **Not done this session — flagging as the necessary next step before any
correction number is finalized**, since the order-level split above almost certainly still
undercounts real posted-wrong periods that have since "self-healed" in our own view.

## Item 3 — Class 1 CMI-sibling × duplication breakdown: only 44% is clearly explained by the confirmed mechanism

Confirmed `L79871659` (the very first D13 pilot candidate) has **no CMI sibling** — single item
`L79871659-V1`, `motor_item_type = MOTOR_TYPE_1`, created 2026-03-05 — matching Mo's own finding
exactly (booked correctly since March; whatever its delta is, it isn't this incident's mechanism).

Broke the full 559 Class 1 orders down by whether they have a CMI (`MOTOR_TYPE_COMPULSORY`) sibling
item *and* whether their flagged key actually shows row-duplication (`max_n_rows > 1` — the confirmed
mechanism requires both: a CMI sibling to trigger the Period-1 `add_ons` deduction, and duplicate
rows to apply it more than once):

| CMI sibling | Duplication present | Orders | |
|---|---|---:|---|
| Yes | Yes | **244** (44%) | clearly explained by the confirmed mechanism |
| Yes | No | 48 (9%) | CMI present but the flagged key itself isn't duplicated — mechanism doesn't directly explain it |
| No | Yes | 43 (8%) | duplication present without a CMI sibling — a real delta, but not via the add_ons pathway specifically |
| No | No | **224 (40%)** | **neither** — cause unknown from any mechanism confirmed so far |
| (indeterminate) | | 16 (3%) | `motor_item_type`/`is_cancelled` NULL on all sibling items, join couldn't resolve |

**Only 244 of 559 (44%) are unambiguously explained.** The other 56% range from "plausible but not
directly mechanistic" (CMI-only or duplication-only, 91 orders) to **224 orders (40% of the reported
Class 1 population) where neither factor is present at all** — these may not be defects from this
incident's mechanism, matching Mo's suspicion directly. `L80046687` (no CMI, single un-duplicated
row per period) sits in this unexplained 224 — worked example below.

## Item 4 — both pilots re-examined against `sap_mirror_doc`; neither original Class-1 candidate survives; no clean replacement found yet

**`L80524847` (Class 2)** — demoted. Confirmed **zero `sap_mirror_doc` rows** — this is a
REJECTED_NEVER_POSTED case, not POSTED_WRONG. Cannot be a pilot (nothing posted to correct) and
cannot be the correction-formula known-answer test (there's no posted state to reconcile against).
**Repurposed**: kept as a known-answer test for the *generating-bug / rejection-detection* logic
instead — a query meant to separate POSTED_WRONG from REJECTED_NEVER_POSTED must put `L80524847` in
the rejected bucket, or that query is wrong.

**`L80046687` (Class 1)** — rejected as pilot, for two independent reasons found this session: (1) no
CMI sibling, no row-duplication on its own flagged key (Period 1, single row 1150.00→1200.00) — falls
squarely in the 224-order unexplained bucket, cause unknown, may not be this incident's defect at
all; (2) `sap_mirror_doc` reveals a **second, already-posted variance at Period 2** (1150.00→1100.00)
that the current view snapshot no longer shows — meaning even setting the CMI question aside, a
correction designed only against Period 1 (the current view's flag) would leave Period 2's real
posted-wrong ฿50 sitting uncorrected. Do not use.

**Search for a replacement Class 1 pilot**: filtered the 244-order "CMI present + duplication
present" bucket for a small (10–200), 2026+, single clean candidate. Only one came up in range:
`L79614142` (net_delta +20.00). Pulled its full detail — **it's a compound case, not a clean
single-cause pilot**: `M1` Period 1 is genuinely duplicated (2 rows, 645.21/645.21 each →
`sum_actual` 1290.42 → key_delta **+645.21**, the confirmed credit-shell mechanism, real); `V1`
Period 1 has 2 rows too (2130.01 and **−630.20**, the latter almost certainly a real refund/reversal)
→ key_delta **−625.21**, unrelated to the credit-shell mechanism. The two nearly cancel
(+645.21 − 625.21 = +20.00 net), but they are two *independent* real events tangled into one
order-level number — correcting only the credit-shell-attributable `M1` portion would **unmask** the
separate −625.21 `V1` shortfall as a new-looking ฿625 variance. Rejected as a pilot for the same
reason `L80046687` was: not a clean, single-cause case. **No replacement Class 1 pilot has been found
yet** — recommend narrowing the search further (single mismatching key per order, not just "any
duplication present") before selecting one.

**`L79900064` (Class 2) — provisionally retained**, not fully re-verified: confirmed CMI sibling
present (`M1`+`V1`), confirmed row-duplication present (from D14), confirmed POSTED with real
`DocEntry`s and `TransactionStatus = 'Paid'` at `V1` Periods 2–5 (values match cleanly between the
current view and `sap_mirror_doc` — no `L80046687`-style hidden divergence found in the periods
checked). **Not yet checked**: `M1` Period 1's and `V1` Period 1's own `sap_mirror_doc` rows
specifically (the actual mismatching keys) — the query that would confirm this pilot is genuinely
POSTED_WRONG at its flagged key, not just "the order has posted rows somewhere," has not been run.
Flagging explicitly rather than asserting this pilot is clean — do not treat it as fully cleared
until that check runs.

## Item 5 — sequencing confirmed, no change needed

Boat's reordering stands: fix the generating bug (Option A, `sql/ddl/040`) first — the 2 confirmed
REJECTED_NEVER_POSTED orders (and any others the deeper key-level check in Item 2 surfaces) will
flow through on a normal resend once the bug is fixed, with no correction needed. What's left
needing an actual correction is only the subset that is BOTH confirmed POSTED_WRONG (key-level, per
Item 2's open gap) AND mechanistically explained (Item 3's 244-order CMI+duplication bucket at
most) — almost certainly well under the 559+71 originally reported, exactly as Boat anticipated.
Nothing across sql/ddl/039/040/041 has been deployed; both pilot files need a further update to
reflect `L80046687`'s rejection once a replacement is found.
