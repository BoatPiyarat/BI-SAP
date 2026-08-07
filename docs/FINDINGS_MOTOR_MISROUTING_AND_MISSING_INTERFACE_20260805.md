# Findings — Motor mislabeling and missing voluntary interface rows, 2026-08-05

**Status: READ-ONLY INVESTIGATION ONLY. Nothing fixed, corrected, exported, or deployed.**
Answers Mo's consolidated list of 7 items (relayed via Boat). Each item below is answered with its
own root cause — **three distinct mechanisms**, not one shared bug. Every query is reproducible;
none mutated data.

## Item 1 (`L80482368-M1`) and Item 3 (`L80483101-M1`) — same, already-documented cause

Both orders were checked directly against the reproducible query in
`docs/FINDINGS_RCB_ONETIME_CHANGE_ORDER_MISROUTED_RCL_20260803.md`
(`sql/adhoc/20260803_l80482368_rcb_creditshell_misroute.sql`). Re-ran it today —
**both order items are members of the same, already-diagnosed 9-order population**:

| order_id | order_item | DocEntry | PaymentMethod | PaymentChannel |
|---|---|---:|---|---|
| L80482368 | L80482368-M1 | 2386647 | RCL-Credit Shell | RCL-Credit Shell |
| L80483101 | L80483101-M1 | 2386648 | RCL-Credit Shell | RCL-Credit Shell |
| (7 more: L78431860, L78443759, L78443918, L79457889, L80236563, L80481460, L80484116) | | | | |

**Root cause (unchanged from 2026-08-03):** historical batch jobs assigned `RCL-Credit Shell` based
solely on `is_carried_over_from_old_order`, without first checking the *new* order's actual
`payment_option`. A FULL_PAYMENT change order should route `ONETIME`/RCB, not `RCL-Credit Shell`.
See that finding's "Future-order correction proposal" for the fix direction (flow-aware routing
before assigning any credit-shell label). No new work needed here — this is confirmation, not a new
cause.

## Item 2 (`L78601664-M1`) — new, different cause: unconditional compulsory→CMI-channel override

`L78601664` is **not** a change order (`old_order_id` is NULL) and is a completely normal
`CREDIT_CARD_INSTALLMENT` (10 installments) RCB order — nothing like items 1/3's mechanism applies.

```sql
-- Confirm order shape (not a change order, genuinely RCB installment)
SELECT o.human_id AS order_id, oi.human_id AS order_item, oi.motor_item_type,
  t.payment_option, t.installments, s.number_of_installment, change_order.old_human_id AS old_order_id
FROM `pacific-plating-282708.careos.careos_orders` o
JOIN `pacific-plating-282708.careos.careos_order_items` oi ON oi.order_id = o.id
JOIN `pacific-plating-282708.careos.carepay_transactions` t ON CONCAT('transactions/', t.id) = o.payment
JOIN (SELECT * EXCEPT(_rn) FROM (SELECT s.*, ROW_NUMBER() OVER (
      PARTITION BY transaction_id ORDER BY is_current DESC, update_time DESC, create_time DESC, id DESC) AS _rn
    FROM `pacific-plating-282708.careos.carepay_transaction_snapshots` s) WHERE _rn=1) s
  ON s.transaction_id = t.id
LEFT JOIN `pacific-plating-282708.careos.cancelled_change_orders` change_order
  ON change_order.current_human_id = o.human_id
WHERE o.human_id = 'L78601664'
```

SAP shows M1 posted as `CompanyDB='RCB'` (correct company) but `PaymentMethod`/`PaymentChannel` both
`'RCL-CMI-channel'` — while the sibling V1 on the *same* order posts correctly as
`RCB-EDC-KBANK`/`EDC EDC`. Same order, same transaction, only the compulsory leg is mislabeled.

**Root cause — confirmed live, not just in the repo copy.** `sap_data_engineer.RCL_MOTOR` (the live
view; repo copy `sql/production/RCL_MOTOR.sql` matches byte-for-byte at the relevant lines) contains
one single, RCB-hardcoded compulsory branch:

```sql
-- sql/production/RCL_MOTOR.sql:602-605 (compulsary_installment_details CTE)
compulsary_installment_details AS (
  SELECT
    'compulsary_installment_details' AS CTE_source,
    'RCB' AS CompanyDB,     -- <- explicitly RCB, not RCL
    ...
```

but the view's final `PaymentMethod`/`PaymentChannel` transformation (lines 950-961) overrides
*every* compulsory row unconditionally, with no `CompanyDB` check:

```sql
-- sql/production/RCL_MOTOR.sql:950-961
CASE
  WHEN InsuranceType = 'MOTOR_TYPE_COMPULSORY' THEN 'RCL-CMI-channel'   -- fires for RCB rows too
  WHEN PaymentMethod = 'CASH' THEN 'TRF Transfer'
  WHEN PaymentMethod = 'QR_CODE' THEN 'OME Omise QR Prompt Pay'
  ELSE PaymentMethod
END AS PaymentMethod,
CASE
  WHEN InsuranceType = 'MOTOR_TYPE_COMPULSORY' THEN 'RCL-CMI-channel'
  ...
END AS PaymentChannel,
```

There is no separate RCL compulsory-installment branch in `combine`'s active union (only
`rcb_voluntary_installment_details`, `rcl_voluntary_installment_details`, and
`compulsary_installment_details` are unioned) — meaning **this single compulsory branch is the only
path for compulsory installment items of either company**, and its output label was written back
when (per the "CMI" name) all compulsory business ran through RCL. It was never updated to check
`CompanyDB` when RCB started using the same branch.

**Population — confirmed live, current, not historical-only:**

```sql
WITH posted_latest AS (
  SELECT * EXCEPT (_rn) FROM (
    SELECT sap.*, ROW_NUMBER() OVER (
      PARTITION BY U_OrderItem, U_Period ORDER BY UpdateDate DESC, SAFE_CAST(DocEntry AS INT64) DESC) AS _rn
    FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL` AS sap
    WHERE SAFE_CAST(DocEntry AS INT64) IS NOT NULL
  ) WHERE _rn = 1
)
SELECT CompanyDB, COUNT(DISTINCT U_OrderItem) AS n_order_items, COUNT(*) AS n_period_rows,
  MIN(UpdateDate) AS earliest, MAX(UpdateDate) AS latest
FROM posted_latest
WHERE (PaymentMethod = 'RCL-CMI-channel' OR PaymentChannel = 'RCL-CMI-channel')
  AND ENDS_WITH(U_OrderItem, '-M1')
GROUP BY CompanyDB
```

**Result before correction: 23,562 RCB M1 items** matched the blanket "any compulsory item" filter —
**this overstated the real defect population and was corrected after Boat's review.**

**CORRECTION (per Boat, 2026-08-05 20:1x):** `CompanyDB='RCB'` is a fixed SAP structural requirement,
not a routing signal — it says nothing about whether the "RCL" indication is right or wrong. The
actual rule for whether a `PaymentChannel` starting with `RCL` is *correct* is: the charge's
`service_provider = 'RABBIT_LENDING'`, **or** the transaction's `payment_option` is an installment
type (`RABBIT_CARE_INSTALLMENT` or `CREDIT_CARD_INSTALLMENT`). `L78601664` is
`CREDIT_CARD_INSTALLMENT` — it satisfies this rule, so its `RCL-CMI-channel` label is **correct
behavior, not a bug**. My original framing (motor_item_type = COMPULSORY alone is wrong) missed this
and overcounted by roughly 2,350x.

**Re-run against the correct rule:**

```sql
WITH posted_latest AS (
  SELECT * EXCEPT (_rn) FROM (
    SELECT sap.*, ROW_NUMBER() OVER (
      PARTITION BY U_OrderItem, U_Period ORDER BY UpdateDate DESC, SAFE_CAST(DocEntry AS INT64) DESC) AS _rn
    FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL` AS sap
    WHERE SAFE_CAST(DocEntry AS INT64) IS NOT NULL
  ) WHERE _rn = 1
),
mislabeled_m1 AS (
  SELECT U_OrderItem FROM posted_latest
  WHERE (PaymentMethod = 'RCL-CMI-channel' OR PaymentChannel = 'RCL-CMI-channel')
    AND ENDS_WITH(U_OrderItem, '-M1') AND CompanyDB = 'RCB'
),
order_facts AS (
  SELECT oi.human_id AS order_item, o.human_id AS order_id, t.payment_option,
    EXISTS (
      SELECT 1 FROM `pacific-plating-282708.careos.careos_charges` c
      WHERE c.transaction_id = t.id AND c.service_provider = 'RABBIT_LENDING'
    ) AS has_rabbit_lending_charge
  FROM `pacific-plating-282708.careos.careos_order_items` oi
  JOIN `pacific-plating-282708.careos.careos_orders` o ON o.id = oi.order_id
  JOIN `pacific-plating-282708.careos.carepay_transactions` t ON CONCAT('transactions/', t.id) = o.payment
  WHERE oi.human_id IN (SELECT U_OrderItem FROM mislabeled_m1)
)
SELECT order_id, order_item, payment_option, has_rabbit_lending_charge
FROM order_facts
WHERE NOT (has_rabbit_lending_charge OR payment_option IN ('RABBIT_CARE_INSTALLMENT','CREDIT_CARD_INSTALLMENT'))
ORDER BY order_item
```

**Corrected result: only 10 order items are genuinely mislabeled** (23,552 of the original 23,562
are correctly labeled per the real rule): `L73476108-M1`, `L73565973-M1`, `L75045318-M1`,
`L75102829-M1`, `L76846787-M1`, `L76979626-M1`, `L77003586-M1`, `L77008532-M1`, `L77436355-M1`,
`L77440810-M1` — **every one is `FULL_PAYMENT` (one-time), not a change order** (`old_order_id` is
NULL for all 10, so this is not the same population as Items 1/3). This is a small, distinct
residual gap: the live code's actual condition (`motor_item_type = 'MOTOR_TYPE_COMPULSORY'` alone)
is broader than the correct rule (installment-type or RABBIT_LENDING) — it wrongly catches a
one-time FULL_PAYMENT compulsory item that happens to have neither signal.

**Mo's original example (`L78601664-M1`) is correctly labeled and is not part of this defect.**

**Future-order correction proposal (source only, not applied):** change the
`WHEN InsuranceType = 'MOTOR_TYPE_COMPULSORY' THEN 'RCL-CMI-channel'` branches (lines 950-951,
956-957) to the actual business rule — gate on `service_provider = 'RABBIT_LENDING'` or an
installment-type `payment_option`, not on `motor_item_type` alone.

## Item 4 (`L78611713-V1`) — already answered

This is Mo's original duplicate-QR-installment case, fully documented in
`docs/FINDINGS_DUPLICATE_QR_INSTALLMENT_20260804.md`. No new work in this pass.

## Item 5 (`L78794968`, `L78583606`, `L78786429`) — new cause: voluntary periods vanish once paid

**CORRECTION (2026-08-07, see `docs/FINDINGS_VMI_MISSING_EXPORT_PIPELINE_20260807.md`): the root
cause below is wrong.** Directly re-verified live: `rcl_voluntary_installment_details` (the
complementary CTE requiring `follow_ups.transaction_id IS NOT NULL`) DOES reclaim paid periods,
and the live `RCL_MOTOR` view, `sap_dashboard_carepay_installment` view, and
`RCL_Motor_process_1_create` query all currently return complete, correct rows for all 3 orders.
The real cause is an unreliable export Cloud Function (`rcb-motor-order-payment-sap-bucket-1`) —
see the corrected doc for full evidence. **Do not apply the "future-order correction proposal"
below** — it would be a no-op fix to code that isn't broken.

All three orders genuinely have a voluntary (V1) item in `careos` (not cancelled,
`RABBIT_CARE_INSTALLMENT`, 6–8 installments) — the coverage was purchased. **None of the three V1
items appear anywhere in SAP, at any period.** Only the compulsory M1 leg posted (itself also
carrying Item 2's `RCL-CMI-channel` mislabel).

```sql
-- V1 confirmed to exist and be active in careos
SELECT o.human_id AS order_id, oi.human_id AS order_item, oi.motor_item_type, oi.is_cancelled,
  t.payment_option, t.installments
FROM `pacific-plating-282708.careos.careos_orders` o
JOIN `pacific-plating-282708.careos.careos_order_items` oi ON oi.order_id = o.id
LEFT JOIN `pacific-plating-282708.careos.carepay_transactions` t ON CONCAT('transactions/', t.id) = o.payment
WHERE o.human_id IN ('L78794968','L78583606','L78786429')
```

**Root cause.** `rcb_voluntary_installment_details` (`sql/production/RCL_MOTOR.sql:132-284`) joins
`carepay_follow_ups` per `(transaction_id, installment period)` and then filters:

```sql
-- sql/production/RCL_MOTOR.sql:275-279
WHERE
  transaction_snapshot_installment_details.id IS NOT NULL
  AND (order_items.motor_item_type != 'MOTOR_TYPE_COMPULSORY' OR order_items.motor_item_type IS NULL)
  AND (follow_ups.transaction_id IS NULL)   -- <- excludes any period that already has a follow-up row
```

All three orders' V1 period 1 already has a `carepay_follow_ups` row with
`status = 'FOLLOWUP_STATUS_PAID'` (confirmed directly):

```sql
SELECT o.human_id AS order_id, f.installment, f.status, f.due_date
FROM `pacific-plating-282708.careos.careos_orders` o
JOIN `pacific-plating-282708.careos.carepay_transactions` t ON CONCAT('transactions/', t.id) = o.payment
LEFT JOIN `pacific-plating-282708.careos.carepay_follow_ups` f ON f.transaction_id = t.id AND f.installment = 1
WHERE o.human_id IN ('L78794968','L78583606','L78786429')
-- all 3 return status = FOLLOWUP_STATUS_PAID
```

Once a period reaches `FOLLOWUP_STATUS_PAID`, this branch stops emitting it — and `combine`'s active
union (`rcb_voluntary_installment_details` + `rcl_voluntary_installment_details` +
`compulsary_installment_details`) has **no other branch to reclaim it**. The row simply never
reaches SAP. The `MOTOR_TYPE_COMPULSORY` exclusion on the same WHERE (marked "A2 fix 2026-07-24" in
the file) shows this exact filter block is under active, recent maintenance — consistent with this
being a live, current gap rather than long-dead code.

**Population — bounded to a recent window to control cost:**

```sql
WITH voluntary_paid_followups AS (
  SELECT o.human_id AS order_id, oi.human_id AS order_item, f.installment AS period
  FROM `pacific-plating-282708.careos.careos_orders` o
  JOIN `pacific-plating-282708.careos.careos_order_items` oi ON oi.order_id = o.id
  JOIN `pacific-plating-282708.careos.carepay_transactions` t ON CONCAT('transactions/', t.id) = o.payment
  JOIN `pacific-plating-282708.careos.carepay_follow_ups` f ON f.transaction_id = t.id
  WHERE oi.motor_item_type != 'MOTOR_TYPE_COMPULSORY'
    AND f.status = 'FOLLOWUP_STATUS_PAID'
    AND f.due_date >= '2026-05-01'
),
posted AS (
  SELECT DISTINCT U_OrderItem, U_Period FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
  WHERE SAFE_CAST(DocEntry AS INT64) IS NOT NULL
)
SELECT COUNT(DISTINCT vp.order_item) AS n_missing_from_sap
FROM voluntary_paid_followups vp
LEFT JOIN posted p ON p.U_OrderItem = vp.order_item AND p.U_Period = vp.period
WHERE p.U_OrderItem IS NULL
```

**Result: 541 voluntary order items (541 orders), due 2026-05-01 or later, paid per `follow_ups` but
completely absent from SAP.** Out of ~27,698 voluntary items checked in the same window, roughly 2%
show this complete-absence pattern — a real, sizeable, currently-active gap.

**Future-order correction proposal (source only, not applied):** either drop the
`follow_ups.transaction_id IS NULL` exclusion once a period is genuinely paid (a paid period must
still be emitted, not treated as "not yet due"), or add the missing branch that re-includes voluntary
periods once `FOLLOWUP_STATUS_PAID` is reached, so paid coverage is never silently dropped.

## Item 6 (`L80425164`, ฿183.3) — already answered this session

Same mechanism as Item 4 (duplicate QR charge on one installment): it was excluded from the
original 111-item list only by an arbitrary ≤6-hour gap filter (its two charges are 25h41m apart).
Widening that window surfaces ~194 more matching order items (~฿1.79M) with the identical signature.
See this session's chat answer for the full bucketed table and reproducible SQL; no new query
needed here.

## Item 7 (`L78643402` example; ~40 July orders with incomplete installment records) — inconclusive

Checked `L78643402-V1` from every angle available:

```sql
-- SAP-posted periods
SELECT U_OrderItem, U_Period, TotalPeriods, DocEntry, PaymentMethod, TransactionStatus, UpdateDate
FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
WHERE U_OrderItem = 'L78643402-V1' AND SAFE_CAST(DocEntry AS INT64) IS NOT NULL

-- Dashboard view with due dates
SELECT OrderItem, Period, TotalPeriods, PaymentDate, ExpectedDate, TransactionStatus, PaymentStatus
FROM `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_installment`
WHERE OrderItem = 'L78643402-V1'
```

Result: **all 6/6 periods are present**, correctly sequenced, period 1 is paid, and periods 2–6 are
not yet due (`ExpectedDate` 2026-08-24 through 2026-12-24, all in the future relative to today). I
could not reproduce "missing installment records" on this specific example — it does not match
Item 5's "voluntary period vanishes once paid" mechanism either (Item 5's population check above
would have caught `L78643402-V1` if it did).

**I need one of two things to continue this item**: either (a) the exact list of the ~40 July
order items Mo found, or (b) the specific query/view Mo used to detect "missing" — since "missing"
evidently doesn't mean "absent from `SAP_LIVE_FULL`" for this example, it likely means something
else (e.g. a JE/reconciliation-side count mismatch, or a different accounting extract). Without
that, further investigation would be guessing at the definition rather than testing it.

## Caveats — read before any correction

1. **Three distinct causes, not one.** Do not batch Items 2 and 5 into a single fix — one is a
   labeling override in the compulsory branch, the other is an exclusion filter in the voluntary
   branch, in different CTEs of the same file.
2. **Not yet Class-A reviewed.** Diagnostic only, per this project's standing rule.
3. **Population counts are point-in-time** (queried 2026-08-05) and, like the duplicate-QR case,
   will likely keep growing while the underlying mechanisms remain live.
4. **Item 2's financial impact is not established** — only the mechanism and scale are. Confirm with
   Finance whether the `RCL-CMI-channel` label drives any downstream account routing before treating
   it as a correction target.
