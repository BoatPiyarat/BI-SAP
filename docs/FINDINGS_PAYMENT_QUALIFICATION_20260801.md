# Successful-charge SAP qualification impact — 2026-08-01

Source-only/Class A. Boat rule 2 requires successful charges to resolve to an Order, a non-empty
OrderItem human_id, and a PURCHASED lead before SAP interface qualification.

Job `payment_qualification_impact_20260801_223100`, 2026-08-01
15:31:17.728–15:31:23.185 UTC; dry-run/processed 642,520,556 bytes, billed 642,777,088 bytes,
ceiling 21,474,836,480, location `asia-southeast1`.

| Result | Successful charges |
|---|---:|
| QUALIFIED | 1,127,882 |
| LEAD_NOT_PURCHASED (including unresolved lead) | 52,828 |
| NO_ORDER | 17,567 |
| NO_ORDER_ITEM | 0 |
| EMPTY_ORDER_ITEM_HUMAN_ID | 0 |

The 70,395 non-qualified charges must not disappear. Updated source 013 writes them at charge grain
to `sap_payment_qualification_exclusion` with rule_code, amount, charge_time, reason, and timestamps.
This table is separate from `(order_item,period)`-grain `sap_excluded_records` because NO_ORDER
cannot supply that key. No deployment or staging refresh occurred.
