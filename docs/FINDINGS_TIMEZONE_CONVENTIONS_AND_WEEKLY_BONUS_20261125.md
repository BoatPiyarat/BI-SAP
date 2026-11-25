# FINDINGS 2026-11-25 — CareOS vs CarePay time-zone conventions; weekly-bonus date off-by-one exposure

Found while building the business AI data guide (`docs/business-ai-data-guide/`). Read-only
evidence only. **Not fixed** — money/pay impact, per AGENT_RULES: record and stop.

## Symptom

A freshness check on `analytics_reports.report_orders.created_at_timestamp` returned a *negative*
lag versus `CURRENT_TIMESTAMP()`.

## Evidence (BigQuery, pacific-plating-282708, queried 2026-11-25 ~09:30–10:30 UTC)

| Column | `CURRENT_TIMESTAMP() − MAX(col)` | Interpretation |
|---|---|---|
| `careos.careos_orders.create_time` | −414 min | value is ~7 h ahead of real UTC → stored as **Bangkok wall-clock** |
| `analytics_reports.report_orders.created_at_timestamp` | −354 min | same (built from CareOS) |
| `careos.careos_orders._loaded_at` | +5 min | true UTC (loader) |
| `careos.carepay_charges.payment_date` / `create_time` | +96 min | **true UTC** |

- `report_order_items` vs `careos_order_items` (items created ≥ 2026-11-01, n = 16,719): `create_time`,
  `approval_time`, `cancel_time` identical (all quantiles 0 min); `create_at_date = DATE(create_time)` for
  16,719/16,719 but `= DATE(create_time,'Asia/Bangkok')` for only 13,404 → report dates are DATE() of
  Bangkok-wall-clock values, no conversion.

Conclusion (evidence-based, needs owner confirmation): **CareOS order/item timestamps = Bangkok time
stored in TIMESTAMP; CarePay timestamps = real UTC.**

## Exposure — commission weekly bonus

Live view `motor_commission.paid_orders_for_weekly_bonus` derives `payment_date` as
`DATE(carepay_charges.payment_date)` with comment "no need to converted region time". If CarePay is
true UTC, payments made 00:00–06:59 Bangkok get the previous day.

Successful first-installment charges paid 2026-05-16 → 2026-11-16 (Bangkok), M06–M11 2026:

| Measure | Count |
|---|---|
| Charges | 89,039 |
| Charges whose UTC date ≠ Bangkok date | 586 (0.66%) |
| …of which Monday early-morning (could fall into previous week) | 59 |
| …of which 16th early-morning (could fall into previous commission cycle) | 14 |

These are charge counts, not confirmed mis-ranked agents or mis-paid orders; whether any weekly rank or
cycle assignment actually changed is **UNVERIFIED** (needs eligibility + submission join).

## Hypotheses not yet excluded

- CarePay timestamps might be Bangkok-local but loaded late (lag 96 min) — judged unlikely because CareOS
  `_loaded_at` is current while CarePay max is only 96 min old at ~16:30 Bangkok on a weekday.

## Action needed (owner: Boat)

1. Confirm both conventions with IT/CareOS (Leong / Pond).
2. Decide whether the weekly-bonus and cycle assignment should use `DATE(payment_date, 'Asia/Bangkok')`.
   Any change affects pay → requires the normal commission-rule approval path.
3. Until decided, the business AI data guide states both conventions and flags the engine behaviour.
