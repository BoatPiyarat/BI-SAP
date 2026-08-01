# Chain 1 deployment evidence — E1-E3 / F1

Status: **DEPLOYED AND VERIFIED 2026-08-01**  
Executor: Codex, sole deployer designated by Boat.  
Approved order: `032 → 036 → 037 → CALL`.

Every query was dry-run first in `asia-southeast1` with
`maximum_bytes_billed=21,474,836,480`. No export, GCS write, SAP_LIVE cleanup, legacy-view change,
or mirror-chain deployment occurred in this unit.

## Production jobs

| Step | Job ID | UTC interval | Processed | Billed | Result |
|---|---|---|---:|---:|---|
| Deploy 032 | `deploy_032_e1e3_20260801_140609` | 07:06:34.087–07:06:48.402 | 7,232,067,692 | 7,264,534,528 | DONE; added `test div` only |
| Verify 032 | `verify_032_e1e3_20260801_140723` | 07:07:43.618–07:07:43.946 | 420 | 31,457,280 | DONE |
| Deploy 036 | `deploy_036_e1e3_20260801_140800` | 07:08:13.852–07:08:38.950 | 947,270,702 | 947,912,704 | DONE; staging rebuilt |
| Verify 036 | `verify_036_e1e3_20260801_140923` | 07:09:39.036–07:09:41.640 | 75,880,951 | 76,546,048 | DONE |
| Deploy 037 | `deploy_037_e1e3_20260801_141002` | 07:10:15.160–07:10:16.523 | 0 | 0 | DONE; procedure replaced |
| Pre-CALL verify | `verify_037_pre_call_20260801_141035` | 07:10:52.960–07:10:53.326 | 10,485,760 | 20,971,520 | DONE |
| CALL expected state | `call_expected_state_e1e3_20260801_141106` | 07:11:21.740–07:12:16.494 | 1,650,611,444 | 1,697,644,544 | DONE; all 3 ASSERTs passed |
| Post-CALL verify | `verify_expected_state_e1e3_20260801_141326` | 07:13:51.376–07:13:54.399 | 91,884,758 | 92,274,688 | DONE |

## Verification results

- 032: config exactly `year_no_touch_max=2024`, `year_cancel_only=2025`; test patterns exactly
  `test`, `test div`; insurer master 69 rows with zero NULL/empty codes.
- 036: `stg_order_dim` 758,786 rows = 758,786 source order-items = 758,786 distinct order-items;
  InsuredID NULL/empty 0; `is_cancelled_effective` NULL 0; formula mismatch 0; effective TRUE
  63,916; reverse order-cancel monitor 0.
- 037 before CALL: all five definition markers present (OrderDate tier source, 2025 rule code,
  effective-cancel field, exact-one-period guard, 2024/2025 config pin). `expected_state` remained
  at the pre-change baseline 298,278, proving procedure replacement alone did not refresh data.
- CALL: all three ASSERT statements succeeded.
- Post-CALL `expected_state`: **288,534 records / 128,691 orders / 288,534 distinct keys**.
  Change from baseline: **-9,744 records**. `old_year_rescued` NULL 0 / TRUE 0; InsuredID empty 0;
  OrderDate <=2024 leakage 0; invalid 2025 rows 0; payment-date clamped 164,817; clamped rows with a
  date other than 2026-07-01 = 0.
- Register, new taxonomy: `YEAR_OUT_OF_SCOPE` 789,501 records / 400,684 orders;
  `YEAR_2025_NON_CANCEL_EXCLUDED` 388,295 / 200,367; `TEST_CUSTOMER` 347 / 199;
  `INSURER_NOT_IN_MASTER` 3,172 / 955. `DATE_BASIS_MISSING` has zero rows and therefore no group.
  Sum across rules is not a unique population because exclusions can overlap.
- Total rows under old rule codes = 0.

Chain 1 is accepted as deployed and verified. Chain 2 remains a separate production evidence unit.
