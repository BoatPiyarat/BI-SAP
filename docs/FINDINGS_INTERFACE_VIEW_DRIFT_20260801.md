# Live interface process-view inventory — 2026-08-01

Status: **CONFIRMED from live metadata; no legacy object changed**.

## Evidence

`p0_interface_view_compact_20260801_0140` read
`sap_view.INFORMATION_SCHEMA.VIEWS` in `asia-southeast1`. Created
`2026-07-31T18:25:07.159Z`, started `18:25:07.240Z`, ended `18:25:07.471Z`.
Dry-run, processed, and billed bytes were each 10,485,760 under the 21,474,836,480-byte ceiling.
Therefore the earlier expectation that this metadata query would be 0 bytes was incorrect; the
actual minimum billed unit was 10 MiB. Source:
`sql/adhoc/20260801_p0_interface_view_live_inventory.sql`.

Classification uses the normalized live-versus-repo comparison from
`p0_legacy_definition_inventory_20260801_000400`. `MATCH` means normalized SQL equals an exact-name
baseline; it does not make the repo authoritative.

| Live `sap_view` process view | Baseline class | Direct `CURRENT_DATE` BatchRunDate | Direct 2023/24 exclusion |
|---|---|---:|---|
| `RCB_Motor_process_2_cancel_new` | MATCH | yes | OrderDate |
| `RCB_Motor_process_3_change` | MATCH | no | none |
| `RCB_Motor_process_4_creditshell` | MATCH | no | none |
| `RCB_Motor_process_create` | MATCH | no; inherited | none |
| `RCB_NonMotor_process_1_create` | MATCH in `sql/sap_view`; stale duplicate capture in `sql/production` DRIFTS | no; inherited | none |
| `RCB_NonMotor_process_2_cancel` | MATCH | no | none |
| `RCL_Motor_process_1_create` | **DRIFT** | yes | none |
| `RCL_Motor_process_2_newpayment` | **NO EXACT-NAME BASELINE** | no | none |
| `RCL_Motor_process_3_cancel` | MATCH | yes | OrderDate |
| `RCL_Motor_process_4_creditshell` | MATCH | no | none |
| `RCL_NonMotor_process_1_create` | MATCH | no; inherited | none |
| `RCL_NonMotor_process_2_newpayment` | **DRIFT** | yes | PolicyDate |

Object-level total: **9 MATCH / 2 DRIFT / 1 NO BASELINE**. The extra stale
`sql/production/RCB_NonMotor_process_1_create.sql` is a duplicate baseline file, not a thirteenth
live process view.

## The four CREATE views Boat is using

Live upstream metadata was checked in two batched follow-ups because three process views pass
`interface.*` through and do not show the generating expression themselves.

- `RCL_Motor_process_1_create`: defines `CURRENT_DATE() AS BatchRunDate`, then formats it DDMMYYYY.
- `RCL_NonMotor_process_1_create`: inherits `RCL_HEALTH`, which defines `CURRENT_DATE()`.
- `RCB_NonMotor_process_1_create`: inherits `RCB_HEALTH`/`RCB_TRAVEL`; both define
  `CURRENT_DATE()`.
- `RCB_Motor_process_create`: inherits live `sap_dashboard_carepay_fully_paid`. That drifted
  upstream definition contains an active `'31072026' AS BatchRunDate` path and a separate
  `CURRENT_DATE()` fallback path; the result is branch-dependent and cannot be labelled uniformly.

Consequently, the deliberate `31072026` override remains necessary for a July-close candidate
unless the exact exported rows prove they already carry that value. Repo baselines cannot answer it.

## Year filter and blacklist findings

None of the four CREATE process views directly contains
`OrderDate/PolicyDate NOT LIKE '%2023%'/'%2024%'`. The old statement that all four CREATE views
apply that year exclusion is retracted. Year exclusion remains in the two motor cancel views
(OrderDate) and RCL NonMotor newpayment (PolicyDate).

The live hardcoded blacklist is also not “six orders”:

- `RCB_Motor_process_create`: 26 hardcoded OrderItem literals;
- `RCB_Motor_process_3_change`: 1 OrderID literal;
- `RCB_Motor_process_4_creditshell`: 4 OrderID literals;
- `RCL_Motor_process_4_creditshell`: 3 OrderID literals;
- the other eight process views: no literal order/order-item blacklist detected.

These counts describe literals in deployed definitions, not whether each predicate currently
removes rows. Impact quantification would require a separate data query and is not authorized here.
