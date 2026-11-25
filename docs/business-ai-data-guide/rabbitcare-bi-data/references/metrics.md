# Metric definitions

Status legend: ✅ verified against data (with evidence) · ⚠️ TO CONFIRM by BI/Finance before
using in official reports · 🚫 do not self-serve.

## Money measures (per order item)

| Measure | Formula / column | Status | Notes |
|---|---|---|---|
| Gross premium (เบี้ยรวม) | `gross_premium` = `net_premium + vat_amount + stamp_duty` | ✅ 35,327/35,327 items created ≥ 2026-10-01 match within ฿1 (`report_order_items`, 2026-11-25) | What customers see as the policy price before discount. Default "ยอดขาย" for sales. |
| Net premium (เบี้ยสุทธิ) | `net_premium` | ✅ (component of the above) | Excludes VAT and stamp duty. Base for commission from insurers. |
| VAT / Stamp duty | `vat_amount`, `stamp_duty` | ✅ | |
| Discount | `discount` (item), `rcl_discount`, `report_orders.actual_discount` | ⚠️ | Several discount fields exist (agent discount, voucher, RCL). Ask which. |
| Invoice price (ยอดที่เรียกเก็บลูกค้า) | `invoice_price` ≈ `gross_premium − discount` | ✅ 34,865/35,327 (98.7%) match; the rest include fees/other adjustments | Use for "customer pays". |
| Fees | `shipping_fee`, `payment_fee`, `interest`, `processing_fee_amount`, `fee_amount` | ⚠️ | Installment interest/processing fee are RCL items; not insurance premium. |
| Gross premium after cancel | `gross_premium_after_cancelled` = 0 when item cancelled else `gross_premium` | ✅ 100% match | Convenient "net of cancellation" measure. |
| Cash collected | `SUM(carepay_charges.amount)/100` where `status='SUCCESSFUL'` | ✅ (amount stored in **satang**) | Cash view. Installments → many rows per order. |
| Paid amount (report) | `report_order_items.paid_amount`, `report_orders.amount_paid` | ⚠️ | Check definition with BI before reconciling with Finance. |
| Revenue / income / commission income | — | 🚫 | Broker income = insurer commission rate × premium, rates are not in the approved tables. Send to BI/Finance. `analytics_views.nonmotor_income` is **not** income — it is a customer income-bracket survey lookup. |
| Commission "sales" | engine only | 🚫 | Motor = invoice price after discount, paid + submitted in cycle, 1 per chassis; NonMotor = net premium after discount, paid + QC by 18th. See `domain_commission.md`. Will not equal dashboard sales. |
| Agent commission payout | `motor_commission.*` | 🚫 | Governed payout process; never self-serve. |

## Count measures

| Measure | How | Notes |
|---|---|---|
| Orders (ออร์เดอร์) | `COUNT(DISTINCT short_id)` on `report_orders` | One order can hold several items (e.g. voluntary + CMI). |
| Policies / items (กรมธรรม์) | `COUNT(DISTINCT item_id)` on `report_order_items` | Voluntary and compulsory (CMI) are separate items/policies. |
| Voluntary policies | `order_type = 'voluntary'` | `Type 1`, `Type 2+`, `Type 3`, `Type 3+` (`car_insurance_type`). |
| Compulsory (CMI / พ.ร.บ.) | `order_type = 'mandatory'` or raw `motor_item_type = 'MOTOR_TYPE_COMPULSORY'` | **Never identify CMI by package type.** |
| Health | raw `careos_order_items.product = 'products/health-insurance'` | Health appears from 2024-10. ⚠️ Non-motor reporting tables are separate — see tables.md. |
| Renewal vs new | `is_renewal` | ⚠️ renewal flag logic owned by BI. Renewal *rate* — see `domain_sales_marketing.md`. |
| Cancelled | item: `status = 'cancelled'` in report tables; raw: `is_cancelled IS TRUE OR cancel_time IS NOT NULL` on **`careos_order_items`** | Never use `careos_orders.is_cancelled` (order-level flag is not reliable for item cancellation). Note: `report_daily_cr` filters cancel at order level and commission views use only one of the two flags — small differences are expected. |
| Change order | `careos.cancelled_change_orders` (`old_human_id` → `current_human_id`); replacement lead source `Change - Online` / `Change - Offline` | A cancel + replacement is **one sale**. Plain cancel = cancelled item with no link. Pattern P8. |
| Conversion rate | existing: `analytics_views.report_daily_cr` (online leads by lead-created date; order with same `short_id`, not cancelled, ≤ 4 calendar months) | For any other cohort, define it with the user. See `domain_sales_marketing.md`. |
| Motorbike | `JSON_VALUE(careos_orders.data, '$.oicCode') LIKE 'TYPE_6%'` | Path confirmed in live view `motor_commission.paid_orders_for_weekly_bonus` (2026-11-25); commission excludes `TYPE_610`,`TYPE_620`. Ask whether to include in "Motor". |

## Status values seen in `report_order_items` (all-time, 2026-11-25)

- `status`: shipped 671,056 · insurer accepted 88,433 · cancelled 69,463 · created 1,429
- `approval_status`: ITEM_APPROVAL_STATUS_POLICY_UPLOADED 719,690 · ITEM_APPROVAL_STATUS_PENDING 110,328
- `payment_type`: FULL_PAYMENT 568,087 · RABBIT_CARE_INSTALLMENT 192,520 · CREDIT_CARD_INSTALLMENT 33,590 · NULL 36,192
- `payment_method`: QR_CODE, EDC, ONLINECARD, DIRECT_PAYMENT, BANK_TRANSFER, CASH
- `carepay_charges.status` (2026): SUCCESSFUL, PENDING, FAILED — only SUCCESSFUL is cash.

## Exclusions every official number applies

- Test customers: `LOWER(TRIM(first_name)) IN ('test','test div') OR LOWER(TRIM(last_name)) IN ('test','test div')`
  (exact match only — never `LIKE '%test%'`; source: repo superseding addendum 2026-08-01). IT test orders also
  exist in production — if totals look odd for a specific day, ask BI.
- Soft-deleted raw rows: `delete_time IS NULL`.
