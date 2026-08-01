# Phase B 56-column source coverage — 2026-08-01

Status: OPEN / CLASS A / NO SHADOW DDL YET

## Decision

Do not build `expected_interface_state` by blindly joining `expected_state` to the two legacy
contract-shaped views. Coverage is incomplete and both sources contain duplicate `(OrderItem,
Period)` keys. A naive join would silently omit 13,659 V3 rows and fan out another 1,647 keys.

## Live schema facts

- `sap_integration_v3.expected_state`: 290,319 rows, 15 columns.
- `sap_integration_v3.sap_column_contract`: 56 rows and the authoritative positional contract.
- `sap_integration_v3.sap_mirror_state`: contains all 56 contract-semantic fields for SAP-known
  rows, plus mirror audit columns.
- `sap_data_engineer.sap_dashboard_carepay_fully_paid` and
  `sap_dashboard_carepay_installment`: live views with 56 columns in contract order, but different
  numeric types at known type-drift positions.

Live objects were inspected on 2026-08-01 around 14:31–14:32 UTC. Repository definitions are not
used as proof of legacy live behavior.

## Corrected coverage result

Job `phaseb_coverage_corrected_20260801_213400`, 2026-08-01
14:34:06.367Z–14:34:27.289Z; dry-run/processed 9,079,090,679 bytes, billed 9,079,619,584 bytes,
ceiling 21,474,836,480 bytes.

| Metric | Rows/keys |
|---|---:|
| expected_state records | 290,319 |
| covered by fully-paid view | 82,824 |
| covered by installment view | 193,836 |
| covered by both | 0 |
| uncovered by either view | 13,659 |
| fully-paid source keys with >1 row | 322 |
| installment source keys with >1 row | 1,325 |

| Flow | Expected records | Uncovered |
|---|---:|---:|
| ONETIME | 95,489 | 12,665 |
| RCL | 189,219 | 986 |
| RCL_CMI | 5,611 | 8 |

Covered population is 276,660 records (`82,824 + 193,836`; overlap zero). This is coverage only,
not proof that every covered row's 56 values are correct for V3's intended state.

## Retracted query

Job `phaseb_coverage_20260801_213300` is **RETRACTED**. Its final aggregation joined a per-flow
summary back to detail rows by `flow`, multiplying the overall population and repeating the output
array. It processed/billed the same 9,079,090,679 / 9,079,619,584 bytes at
14:32:57.619Z–14:33:19.093Z. No number from that job may be cited. The corrected query separates
`overall` and `by_flow` into independent aggregates and is committed for reproduction.

## Next gate

One batched diagnostic must classify the 13,659 uncovered rows and determine a deterministic winner
for the 1,647 duplicate source keys. Only then may a source-only 56-column shadow model be written.
No export, GCS write, legacy-view edit, or production DDL occurred here.
