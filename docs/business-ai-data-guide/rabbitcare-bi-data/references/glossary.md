# Glossary

| Term | Meaning |
|---|---|
| CareOS | Rabbit Care's core sales/order system. Source of orders, items, leads in BigQuery dataset `careos`. |
| CarePay | Payment module of CareOS (`carepay_*` tables): transactions, charges, installments, refunds. |
| Order (`short_id`, `human_id`) | A customer purchase. Can contain several items. |
| Order item / policy | One insurance policy inside an order (e.g. Type 1 voluntary + CMI = 2 items). |
| Voluntary (ภาคสมัครใจ) | Motor insurance Type 1, 2+, 3, 3+ (`order_type='voluntary'`). |
| Compulsory / CMI / พ.ร.บ. | Mandatory motor insurance (`order_type='mandatory'`, `motor_item_type='MOTOR_TYPE_COMPULSORY'`). |
| Type 1 / 2+ / 3 / 3+ | Motor coverage classes (`car_insurance_type`). |
| Health | Health insurance (`product='products/health-insurance'`), since 2024-10. |
| RCB | Rabbit Care Broker — the broker entity. One-time (full) payments are RCB flow. |
| RCL | Rabbit Care Lending — installment financing ("ผ่อนกับ Rabbit Care"). Reporting proxy `payment_type='RABBIT_CARE_INSTALLMENT'`; the accounting rule is stricter (see `domain_finance.md`). Interest/processing fees belong here. Separate company & month-end close. |
| Credit-card installment | Bank pays Rabbit Care in full; customer pays bank in instalments (`CREDIT_CARD_INSTALLMENT`). Treated as one-time for accounting. |
| Full payment | `payment_type='FULL_PAYMENT'`. |
| Renewal | Policy renewed from an expiring one (`is_renewal`). |
| Change order | Order replaced by a new order (e.g. customer changes package); the old one is cancelled. Link: `careos.cancelled_change_orders`. Count the pair as one sale. |
| Credit shell | Paid money held as credit after cancel/change, applied to a new order. |
| Commission month | Sales/commission cycle from the 16th to the 15th of next month. |
| Lead | A sales prospect (`report_leads`). `lead_source` = channel (Google, Facebook, Database-renew, Friendgetfriend…). |
| Insurer approval / policy uploaded | `approval_status='ITEM_APPROVAL_STATUS_POLICY_UPLOADED'` — insurer has issued the policy. |
| Gross / net premium | Gross = net + VAT + stamp duty. |
| Satang | 1/100 baht. CarePay amounts are stored in satang. |
| SAP | Accounting ERP. BI sends CareOS data to SAP nightly; SAP numbers follow accounting-period rules. |
| SAP `GrossPremium` / `TotalPremium` | **Naming trap**: SAP `GrossPremium` = CareOS net premium; SAP `TotalPremium` = CareOS gross premium. |
| GWP | Gross written premium. In exec reports = gross premium; in insurer contracts (e.g. AXA fee) = net premium — ask. |
| Mxx / รอบคอม | Commission/sales cycle 16th→15th, named by the month it ends (M11 2026 = 16 Oct–15 Nov 2026). |
| แจ้งงาน / submission | Sending the paid order to the insurer. Gate for counting Motor sales in commission. |
| QC approved | Internal quality check of sale/documents. Gate for counting NonMotor sales (cut-off the 18th). |
| ยกยอด (carry-in) | An order from an earlier cycle counted later because it was submitted late. |
| อนุโลม | Approved exception to count something outside the rules — commission only, never weekly. |
| หักคืน / clawback | Commission recovered when a policy is cancelled. |
| ออเดอร์ซ้ำ | Cancel + new order for the same customer/car in the same cover period — counted once. |
| ต่ออายุล่วงหน้า (advance renewal) | Renewal paid > 60 days before start; insurer cannot accept submission yet. |
| Weekly bonus | Weekly top-3 prize per team above a premium threshold; never clawed back once paid. |
| Fresh / Database / Retainer / Renew | Lead types (and team names) — always ask whether the user means lead type or agent team. |
| `lead_source` | BI-normalised channel (Google, Facebook, Database - renew expired, Friendgetfriend, Change - Online…). |
| CR / RR | Conversion rate / renewal rate — see `domain_sales_marketing.md`. |
| CI order / CI team | Installment (RCL) order / the collection team that follows up installments. |
| WHT / 50 ทวิ | Withholding tax / its certificate. |
| Short-rate / pro-rata | Insurer refund methods on mid-term cancellation. |
| ค่าบำเหน็จ | Brokerage commission paid by insurers to Rabbit Care. |
| เบี้ยบวก / เบี้ยลบ | Insurer debit (premium billed) / credit note. |
| OIC / คปภ. | Thai insurance regulator. |
| RCV / HSBC | Vietnam credit-card telesales programme — separate definitions; never mix with Thai insurance. |
