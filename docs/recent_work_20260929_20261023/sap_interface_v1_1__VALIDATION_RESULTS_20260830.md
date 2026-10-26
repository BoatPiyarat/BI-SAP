# Validation Results — 2026-08-30

All checks were executed against BigQuery project `pacific-plating-282708`.

## Query validation

- BigQuery Standard SQL dry-run: passed.
- Estimated upper-bound bytes processed: `9,471,576,317` (about 9.47 GB).
- Capped compulsory-only live execution: passed and returned the canonical
  56-column SAP shape.

## Population

- Distinct eligible compulsory item keys before the SAP anti-join: `5,696`.
- Compulsory item keys already in `SAP_LIVE_FULL`: `4,239`.
- Expected unsent compulsory item keys: `1,457`.

Unsent items by `service_provider`:

| Provider | Orders | Items |
|---|---:|---:|
| ICOLLECTION | 1,438 | 1,438 |
| KRUNGTHAI | 6 | 6 |
| KRUNGSRI | 5 | 5 |
| KASIKORN | 4 | 4 |
| SCB | 2 | 2 |
| UOB | 1 | 1 |
| BANGKOK_BANK | 1 | 1 |

The counts overlap where a transaction has successful charges under more than
one provider, so provider rows should not be summed as a unique total.

## Duplicate/fanout controls

- Unsent compulsory item keys with more than one successful EDC charge: `52`.
- Maximum successful charges for one unsent compulsory item: `4`.
- Eligible orders with more than one compulsory item: `0`; therefore the
  revised compulsory `compu_detail` order-grain join does not create fanout.

Multiple successful charges are present in the source, but the inherited
`cmi_rank` rule keeps only rank 1 for compulsory items. The final query therefore
returns one one-time row per eligible unsent compulsory item under the current
data shape.

## Original six-order audit

The six values in the supplied `target_items` list were not a uniform source
definition: observed rows included provider `RCB`, provider `KRUNGTHAI`, payment
option `RABBIT_CARE_INSTALLMENT`/provider `RABBIT_LENDING`, and one
`FULL_PAYMENT` order. All observed item rows were already present in SAP at the
time of validation; one target ID did not join to the audited payment rows.

## Confirmed production definition

On 2026-08-30, RCB credit-card installment was confirmed as:

```sql
transactions.payment_option = 'CREDIT_CARD_INSTALLMENT'
AND charges.payment_method = 'EDC'
AND charges.service_provider <> 'RABBIT_LENDING'
```

The main query and every population/duplicate control use this same predicate.
