# Domain: finance, accounting, insurer & payment

Use to explain finance numbers and why they differ from sales numbers. Anything for accounting
close, SAP correction, refund approval or insurer billing → BI / FA, not self-serve.

## Companies & flows

- **RCB** — Rabbit Care Broker: one-time (full) payment. **RCL** — Rabbit Care Lending: installment
  financing ("ผ่อน", CI order). Separate SAP companies, separate month-end close. Never mix them in one total
  without saying so.
- RCL identification:
  - Reporting proxy: `report_order_items.payment_type = 'RABBIT_CARE_INSTALLMENT'` (good for business analysis, label it "proxy").
  - Accounting rule (PROVISIONAL, awaiting IT field): voluntary = installment details present / installments > 1
    + follow-up + number_of_installment > 1; CMI = `service_provider = 'RABBIT_LENDING'` (can be a single period).
- **Credit-card installment** (`CREDIT_CARD_INSTALLMENT`): bank pays Rabbit in full → RCB / one-time.
  Rabbit itself offers no card installment plans.
- SAP order-item suffixes: `-V1` voluntary, `-M1` compulsory (CMI), `-1` NonMotor.
- New **Rabbit Card Gateway** replacing Omise QR from late 2026 (channel `RCB-Rabbit Card`).

## When money is "revenue" in SAP

- SAP posts on **PaymentDate = actual payment date**; if that accounting month is already closed, it moves to the
  **1st day of the next open period**. One-off: July-2026 payments were posted as 31/07/2026.
- FA announces each month's close instant (usually 1st–3rd of next month, ~14:00–16:00). RCL closes separately.
- Cheque / credit term: goes to SAP only when money is actually received.
- SAP excludes orders ≤ 2024 and 2025 non-cancel rows by design → **SAP vs BI totals for 2024–2025 will never match**.
- ⚠️ TO CONFIRM (FA): P&L revenue-recognition date basis (policy start vs approval vs payment) and income
  measure — **not written anywhere in Teams/email/repo** as of 2026-11-25. Do not state one as fact. (Drive shows FA keeps three parallel installment accounting views — by created date, payment date
  and coverage date — evidence that no single basis is agreed.)

## Premium components & the SAP naming trap

- CareOS: `gross_premium = net_premium + vat_amount + stamp_duty` (verified).
- **SAP interface files label them differently: SAP `GrossPremium` = CareOS net premium; SAP `TotalPremium` = CareOS gross premium.**
  Always say which system's label you mean.
- GWP in insurer contracts (e.g. AXA installment fee) = net premium.

## Taxes & fees (from interface code)

| Item | Rule | Status |
|---|---|---|
| RCL interest | specific business tax 3.3% inclusive: tax = interest × 3.3/103.3 | confirmed |
| RCL processing fee | net = fee × 100/103.3 | confirmed |
| RCB processing fee | net = fee × 100/107 (VAT) | ⚠️ unconfirmed by Finance |
| Shipping fee, refunds | net = amount × 100/107 | code |
| CarePay amounts | stored in **satang** (÷100) | verified |

## Cancellation, change order, credit shell

- Cancelled item = `careos_order_items.is_cancelled IS TRUE OR cancel_time IS NOT NULL` (item level; M and V
  of the same order can cancel separately).
- **Change order** = old order cancelled and replaced; link table `careos.cancelled_change_orders`
  (`old_human_id → current_human_id`); replacement lead source "Change - Online / Change - Offline".
  Plain cancel = cancelled with no link. Money carried over = **credit shell** (not new cash).
- Count change orders once: a cancel + replacement is **one sale**, not a cancellation plus a new sale.
  Scale: in Oct 2026, 700 of 1,495 cancelled items (47%, ฿8.9M gross) were change orders with a replacement
  (`report_order_items` × `cancelled_change_orders`, pattern P8, 2026-11-25) — a "cancellation rate" that
  ignores this roughly doubles the real loss.

## Refunds (rules as of Nov 2026)

- Regulator guidance (20 Nov 2026): premium refunds are **in full**; no deduction of vouchers, discounts or fees.
- CI (RCL) cancellations: insurer short-rate return goes to the customer with no other deduction.
- Corporate customers' 1% WHT: deduct at refund only if the WHT certificate (50 ทวิ) was not received.
- Insurer return premium = pro-rata or short-rate, as stated by insurer (net + stamp + VAT); the draft refund SOP (Mar 2026)
  says insurers use short-rate for both Motor and NonMotor.
- RCL installment follow-up (work instructions 2026): overdue 1–3 days system reminders, 4–9 days collection calls,
  day 9 cancellation notice, day 10 insurer asked to cancel.

## Insurers

- Insurers bill Rabbit per policy: "เบี้ยบวก" (due) − "เบี้ยลบ" (credit notes) = net remittance.
- Brokerage commission ("ค่าบำเหน็จ") paid net of WHT with a 50 ทวิ; some insurers net it off the remittance.
- Insurer commission **rates are not in BigQuery** → broker income cannot be self-served.
- Insurer id = `careos_insurance_companies.id` (Motor numeric; NonMotor `N`+digits in SAP).

## Daily reconciliation

BI sends a daily CareOS↔SAP status (charges paid in CareOS but missing in SAP); tolerance ±฿10 per order.
