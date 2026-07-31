# FINDING — July 2026 InsurerCode exclusions

Status: **OPEN — Aware confirmation required; no production fix applied**

## Answer-first

The current `INSURER_NOT_IN_MASTER` rule excludes **300 records / 294 orders / THB 2,260,768.08**
whose real PaymentDate falls in July 2026. All 300 records had a non-NULL amount. Distinct normalized
codes requiring Aware disposition are:

`30`, `46`, `48`, `49`

Under EXCLUDED ≠ DELETED these records remain visible in `sap_excluded_records`; they must not be
silently restored or deleted. This finding does not establish whether each code should be added to
the SAP insurer master, remapped, or intentionally held.

## Evidence

- BigQuery job: `p0_insurer_risk_20260731_152353`
- Query result timestamp: `2026-07-31 15:23:55 UTC`
- Job creation/start/end: `15:23:55.594` / `15:23:55.687` / `15:24:01.582 UTC`
- Dry-run estimate and actual processed: 371,716,873 bytes
- Billed: 372,244,480 bytes
- Hard ceiling: 21,474,836,480 bytes
- Sources: `sap_excluded_records`, `stg_schedule`, `stg_payment_events`, `stg_order_dim`,
  `careos.carepay_charges`, `expected_state`, `sap_mirror_state`, and `sap_config`.

The query reconstructed pre-exclusion PaymentDate/amount using the same payment-event and
compulsory-item logic as procedure 037, joined exclusions by `(order_item, period)`, restricted
PaymentDate to `[2026-07-01, 2026-08-01)`, and divided CarePay satang by 100. Amount NULL count was
zero.

## Related confirmations

- Exact unique orders across G1 groups (ก)+(ค)+(ง): **4,810**. Per-group order totals overlap by
  six orders, so 4,816 must not be quoted as unique.
- `sap_config.year_no_touch_max = 2024` at the same query timestamp.
- Current procedure 037 computes exclusion `date_basis` from
  `GREATEST(OrderDate, PolicyDate)`. This conflicts with the 2026-07-31 locked instruction that the
  July scope date basis is PaymentDate. No interpretation or fix was applied in this finding.

## Deferred control improvement

After the 2026-08-03 close, extend `sap_excluded_records` with amount and date_basis populated from
the existing `_rules` temp table. This is intentionally deferred and requires reviewed DDL; no
production object was changed in this session.
