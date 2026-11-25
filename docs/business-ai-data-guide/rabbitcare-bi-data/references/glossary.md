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
| RCL | Rabbit Care Lending — installment financing ("ผ่อนกับ Rabbit Care", `payment_type='RABBIT_CARE_INSTALLMENT'`, charge `service_provider='RABBIT_LENDING'`). Interest/processing fees belong here. |
| Credit-card installment | Bank pays Rabbit Care in full; customer pays bank in instalments (`CREDIT_CARD_INSTALLMENT`). Treated as one-time for accounting. |
| Full payment | `payment_type='FULL_PAYMENT'`. |
| Renewal | Policy renewed from an expiring one (`is_renewal`). |
| Change order | Order replaced by a new order (e.g. customer changes package); the old one is cancelled. Avoid double counting — ⚠️ ask BI for the change-order rule. |
| Credit shell | Paid money held as credit after cancel/change, applied to a new order. |
| Commission month | Sales/commission cycle from the 16th to the 15th of next month. |
| Lead | A sales prospect (`report_leads`). `lead_source` = channel (Google, Facebook, Database-renew, Friendgetfriend…). |
| Insurer approval / policy uploaded | `approval_status='ITEM_APPROVAL_STATUS_POLICY_UPLOADED'` — insurer has issued the policy. |
| Gross / net premium | Gross = net + VAT + stamp duty. |
| Satang | 1/100 baht. CarePay amounts are stored in satang. |
| SAP | Accounting ERP. BI sends CareOS data to SAP nightly; SAP numbers follow accounting-period rules. |
