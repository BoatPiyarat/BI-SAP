# SAP Interface v1.1 — Project Context

## Source and intent

This project starts from the urgent batch SQL supplied on 2026-08-30. That SQL
was derived from the production `sap_dashboard_carepay_fully_paid` query and
had been narrowed to a hand-picked list of order human IDs in `target_items`.
Version 1.1 generalizes that batch to the full eligible compulsory-item
population and represents it as RCB one-time.

## Inherited confirmed business rules

- Credit-card installments are represented to SAP as one-time fully paid:
  `Period = 1`, `TotalPeriods = 1`, and `PaymentStatus = 'Fully paid'`.
- SAP output is forced to `PaymentMethod = 'EDC EDC'` and
  `PaymentChannel = 'RCB-EDC-KBANK'` (confirmation recorded in the supplied
  SQL as Boat, 2026-07-16).
- The latest transaction snapshot is selected per transaction to prevent
  snapshot fanout; the former `number_of_installment = 1` filter is not used.
- Items already in `SAP_LIVE_FULL` are excluded using `U_OrderItem`.
- RCB credit-card installment was confirmed on 2026-08-30 as the conjunction
  of `transactions.payment_option = 'CREDIT_CARD_INSTALLMENT'`,
  `charges.payment_method = 'EDC'`, and
  `charges.service_provider <> 'RABBIT_LENDING'`.
- The requested output item class is
  `order_items.motor_item_type = 'MOTOR_TYPE_COMPULSORY'`.
- Late successful payments are moved to the first day of the current month
  after the prior-month day-3 threshold, matching the supplied query.

## Data model used

| Object | Join/key role |
|---|---|
| `careos.careos_orders` | Order header; `id`, `human_id`, `payment`, `lead`, JSON `data` |
| `careos.careos_order_items` | SAP item grain; `order_id`, suffixed `human_id` such as `L...-V1` |
| `careos.carepay_transactions` | Payment transaction; joined from `orders.payment = 'transactions/' || id` |
| `careos.carepay_charges` | Successful receipts; joined by `transaction_id` |
| `careos.carepay_transaction_snapshots` | Transaction state history; latest row selected by `update_time, id` |
| `careos.carepay_transaction_snapshot_price_summaries` | WHT, interest, fees, shipping, and discount by `snapshot_id` |
| `careos.careos_leads` | Renewal/new policy classification |
| `careos.cancelled_change_orders` | Previous order reference (`RefOrder`) |
| `sap_integration_v2.SAP_LIVE_FULL` | Export ledger/idempotency check via `U_OrderItem` |

## What changed from the urgent batch

The `target_items` CTE was removed. Both dependencies on it were replaced:

- `orders` now selects all motor orders joined to an installment transaction.
- `order_items` now selects compulsory items belonging to those eligible
  orders, while retaining the item-level `SAP_LIVE_FULL` anti-join.
- `compu_detail` now also uses
  `motor_item_type = 'MOTOR_TYPE_COMPULSORY'`, as confirmed on 2026-08-30.

Filtering early in these CTEs keeps the intended population explicit and avoids
scanning unrelated order rows through the downstream joins.

## Review findings and residual controls

- Removing only the `target_items` declaration is invalid because two CTEs
  referenced it. Both gates have to change together.
- RCB is a composite business definition, not the literal
  `charges.service_provider = 'RCB'` value. The query applies all three
  confirmed source predicates and retains the constant SAP output fields.
- No date boundary means the query is a full historical catch-up of unsent
  items, not a daily-only batch. This is intentional but must be count-checked.
- Multiple successful charges can produce more than one non-compulsory row per
  order item because the inherited logic retains all successful charges. The
  validation query surfaces duplicate output keys for review.
- The latest snapshot is transaction-level, while amounts may be charge-level.
  This is inherited behavior and should be reconciled for any duplicate item.

## Motor Commission repository context

The surrounding workspace is the Motor Commission Engine, whose current
authoritative entry point is `M09_START_HERE.md` and latest handoff is under
`latest_extract/motor_commission_engine`. Its BigQuery objects use the same
CareOS order, item, transaction, snapshot, price-summary, and charge sources.
The commission engine itself is separate from this SAP export; its payroll
rules and output workbooks are not applied to the interface SQL.
