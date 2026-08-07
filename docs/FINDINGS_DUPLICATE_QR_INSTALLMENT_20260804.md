# FINDINGS — Duplicate QR installment charges, 2026-08-04

**Status: READ-ONLY INVESTIGATION ONLY. Nothing fixed, corrected, refunded, or notified outside
the team.** Answers Mo Pawinee's urgent request (relayed via Boat) to identify the cause of
`L78611713` / `L78803976` showing an extra paid amount duplicated, and to list orders sharing the
same cause.

## Trigger

Mo: "รบกวนพี่โบ๊ตช่วยเช็ค script L78611713 L78803976 ว่าอะไรที่ทำให้เกิดปัญหาเอายอดที่จ่ายเพิ่มเข้าซ้ำ
และช่วยลิสต์ order ที่เกิดจากสาเหตุเดียวกันให้หน่อย" — check what caused the extra-payment
duplication on these two orders, and list orders from the same cause.

## Not INCIDENT-002a / INCIDENT-002b

Both orders were checked directly against all three credit-shell view variants
(`sap_integration_v2.\`04_new order credit shell\``, `...RCL 04_new order credit shell`,
`...RCL 04_new order credit shell new tunning`, `...RCL 04_new order credit shell_all`) —
**zero rows** in every variant. Confirmed via `careos.careos_orders`/`careos_order_items`: each
order has exactly **one** item (`L78611713-V1`, `L78803976-V1`, both `MOTOR_TYPE_2_PLUS`, neither
cancelled) — no CMI sibling exists, so neither INCIDENT-002a nor INCIDENT-002b (both require a
CMI sibling item) can mechanically apply. This is a different, previously undocumented cause.

## Confirmed mechanism

Source: `sap_integration_v3.stg_payment_events` joined to `careos.careos_charges` (job run
2026-08-04, `asia-southeast1`, well under the 20 GiB cap; see queries below).

| order_item | period | charge_id | third_party_id | installment_number | payment_method | status | THB | payment_date |
|---|---|---|---|---|---|---|---:|---|
| L78611713-V1 | 1 | `eec70757-...` | `chrg_68bsy12o711bix4s4fp` | 1 | QR_CODE | SUCCESSFUL | 1,083 | 2026-07-13 09:22:55 |
| L78611713-V1 | 1 | `2fb3ac8e-...` | `chrg_68bvpie8z2l7m8fhred` | 1 | QR_CODE | SUCCESSFUL | 824 | 2026-07-13 10:48:10 |
| L78803976-V1 | 1 | `67a8b4ef-...` | `chrg_68cku9r445p5de76zyo` | 1 | QR_CODE | SUCCESSFUL | 1,016 | 2026-07-15 05:52:50 |
| L78803976-V1 | 1 | `3f840f17-...` | `chrg_68clw1pphs1bhm7pep2` | 1 | QR_CODE | SUCCESSFUL | 483 | 2026-07-15 07:54:10 |

Both order items have **two independent, fully successful QR_CODE charges tagged the same
`installment_number`**, 85–121 minutes apart, same calendar day. This is a genuine double payment
collected at the CareOS payment layer (two separate `third_party_id`s — not a re-query of the same
charge). It is **not** a SAP-export duplication: `sap_integration_v3.expected_state` already
collapses each order item's Period 1 to a single charge (the first one, by ID); the second charge
is not currently represented as its own row in the SAP-bound schedule. The money was still
collected twice from/for the customer — this needs a CareOS-side correction (reassign the second
charge to a future period, or refund), not a SAP pipeline fix.

## Population sharing the same signature

Query (dry-run then run, `--maximum_bytes_billed=21474836480`, ~0.17 GiB actual):

```sql
WITH dup_period AS (
  SELECT order_item, period, ARRAY_AGG(DISTINCT charge_id) AS charge_ids, COUNT(*) AS n_events
  FROM `pacific-plating-282708.sap_integration_v3.stg_payment_events`
  GROUP BY order_item, period
  HAVING COUNT(*) = 2
),
item_period_count AS (
  SELECT order_item, COUNT(*) AS n_affected_periods FROM dup_period GROUP BY order_item
),
charge_detail AS (
  SELECT dp.order_item, dp.period, c.id AS charge_id, c.installment_number, c.payment_method,
    c.status, c.amount AS thb_amount, c.payment_date
  FROM dup_period dp, UNNEST(dp.charge_ids) AS charge_id
  JOIN `pacific-plating-282708.careos.careos_charges` c ON c.id = charge_id
),
per_key AS (
  SELECT order_item, period, COUNT(*) AS n_matched_charges,
    COUNT(DISTINCT installment_number) AS distinct_installment_numbers,
    COUNT(DISTINCT payment_method) AS distinct_payment_methods,
    LOGICAL_AND(status = 'SUCCESSFUL') AS all_successful,
    SUM(thb_amount) AS sum_thb, MIN(payment_date) AS first_paid, MAX(payment_date) AS last_paid,
    TIMESTAMP_DIFF(MAX(payment_date), MIN(payment_date), MINUTE) AS minutes_apart
  FROM charge_detail GROUP BY order_item, period
)
SELECT pk.order_item, pk.period, pk.sum_thb, pk.minutes_apart, pk.first_paid, pk.last_paid
FROM per_key pk JOIN item_period_count ipc ON ipc.order_item = pk.order_item
WHERE pk.n_matched_charges = 2 AND pk.distinct_installment_numbers = 1
  AND pk.distinct_payment_methods = 1 AND pk.all_successful
  AND ipc.n_affected_periods = 1
  AND pk.minutes_apart IS NOT NULL AND pk.minutes_apart BETWEEN 0 AND 360
  AND pk.first_paid >= '2026-06-01'
ORDER BY pk.first_paid
```

Signature: exactly 2 charge events on one `(order_item, period)`, same `installment_number`, same
`payment_method`, both `SUCCESSFUL`, ≤6 hours apart, and the order item has **no other** period
affected (excludes a separate, systemic multi-period double-charge pattern seen on some order
items — e.g. `L72976128-1` and `L72864164-1` had 2 charges on *every* period, going back to 2024;
that looks like a different, larger and older bug and was deliberately excluded here, not folded
into this population).

**Result: 100 order items, 2026-06-01 through 2026-07-30, ฿1,078,326 total duplicated.**
**July 2026 only: 44 order items, ฿403,977** — this is the set matching Mo's stated window.
22 of the 100 (10 of the 44 July rows) have a date-only `payment_date` (both read `00:00:00`), so
the precise time gap is unconfirmed for those — still two independently-created, fully successful
charges on the same installment, just without sub-day timestamp precision.

Full list (order_item, period, sum_thb, minutes_apart, first_paid, last_paid) is in the artifact
handed to Mo; scratch CSV also retained this session at
`mo_dup_v2.csv` (not committed — regenerate via the query above, it is fully reproducible).

### Individual charge amounts split out — a second sub-pattern found

Re-ran with each charge's own amount kept separate (`ARRAY_AGG(thb_amount ORDER BY charge_time)`,
picking element 0/1) instead of only the pair sum. **31 of the 100 rows have one leg equal to
exactly ฿645 (27 rows) or ฿651 (4 rows)** — a suspiciously exact, repeating amount that reads more
like a fixed fee riding along with the installment charge than an accidental re-collection of the
installment itself. Neither of Mo's two reported orders shows this pattern (L78611713-V1's second
charge is ฿824; L78803976-V1's is ฿483 — both irregular, installment-sized amounts, not a round
fee). The artifact flags these 31 rows separately (`฿645-like` badge, filterable) and splits the
remaining **69 rows** as "likely real duplicate" — two irregular, similarly-scaled charge amounts,
matching the two known orders' shape. **Do not treat the 31 fee-like rows as the same defect
without confirming with Finance/product what the ฿645/651 charge actually is** — it may be a
legitimate second charge (e.g. a processing or delivery fee) that only coincidentally shares the
installment_number tag used to build this population's signature.

## Caveats — read before bulk-correcting

1. **Not yet Class-A reviewed.** This is a diagnostic worklist, not an approved correction
   population. Per this project's standing rule, money-impact findings get documented and stopped
   here, not auto-corrected.
2. **The duplicated amount is not automatically the correction amount.** One of the two charges per
   order may be legitimately reassignable to a future installment rather than refunded — Mo/Finance
   need to decide per-order whether the fix is "apply to next period" or "refund."
3. **This pattern is not new to June–July** — an earlier, unscoped version of this query surfaced
   matching cases back to 2024. The window here was deliberately narrowed to June 1 – July 30 2026
   to match the two reported orders' timeframe; the historical scope is materially larger and is a
   separate quantification exercise if Boat wants the full picture.
4. **Root cause of the double QR collection itself was not investigated** (e.g. whether it's a
   double-tap on the payment page, a webhook firing twice, or a retry-after-timeout bug) — this
   finding identifies and quantifies the *symptom* population; the payment-flow engineering fix is
   a separate, un-started task.

## Scope note

This is a CareOS/payment-collection-layer finding, outside this repo's SAP-integration build (V3
units 1–6, credit-shell/CMI incidents). Recorded here only because it was investigated using this
project's BigQuery access/tooling and shares the "money-impact → document + stop" house rule.
