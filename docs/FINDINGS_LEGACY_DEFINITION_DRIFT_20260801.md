# Legacy definition drift inventory — 2026-08-01

Status: **CONFIRMED governance finding**. Read-only metadata only; no object was changed.

## Evidence

Job `p0_legacy_definition_inventory_20260801_000400` read `INFORMATION_SCHEMA.VIEWS` in
`sap_view`, `sap_data_engineer`, and `sap_integration_v2`. Created
`2026-07-31T17:33:01.029Z`, started `17:33:01.143Z`, ended `17:33:01.838Z`; location
`asia-southeast1`. Dry-run, processed, and billed bytes were each 31,457,280 under the
21,474,836,480-byte ceiling. The query returned 66 live views.

The comparison removed comments, whitespace, and the local CREATE VIEW wrapper, then compared the
remaining SQL text. This proves definition equality/drift at normalized-text level; it does not
prove two different definitions are behaviorally equivalent.

## Inventory result

Across 18 exact-name local baseline files relevant to `sap_view`, `sap_data_engineer`, plus the
live source `sap_integration_v2.SAP_LIVE_FULL`, **12 matched and 6 drifted** (33.3% drift at the
local-file baseline grain). `RCB_NonMotor_process_1_create` has two local captures: the
`sql/sap_view` copy matches and the `sql/production` copy drifts, so these are baseline-file counts,
not distinct-object counts.

The six drifted exact-name baselines are:

1. `sap_integration_v2.SAP_LIVE_FULL`
2. `sap_data_engineer.sap_dashboard_carepay_fully_paid`
3. `sap_data_engineer.sap_dashboard_carepay_installment`
4. `sap_view.RCB_NonMotor_process_1_create` (`sql/production` capture only)
5. `sap_view.RCL_Motor_process_1_create`
6. `sap_view.RCL_NonMotor_process_2_newpayment`

Coverage is also incomplete. Ten live views in the explicitly governed legacy datasets have no
exact-name local baseline: nine in `sap_data_engineer` (`RCB_HEALTH`, `RCB_MOTOR`, `RCB_TRAVEL`,
`RCL_HEALTH`, `sap_dashboard_carepay_cancelled`, `sap_dashboard_icollection`,
`sap_fixing_icollection`, `sap_fixing_icollection_no_cancelled`, `sap_fixing_rcb`) and
`sap_view.RCL_Motor_process_2_newpayment`. Four local production captures could not be mapped by
exact name: `RCL_02_items_cancel`, `RCL_04_new_order_credit_shell`,
`RCL_04_new_order_credit_shell_all`, and `RCL_04_new_order_credit_shell_new_tunning`. They may be
aliases for differently named live objects, but that is unverified and must not be inferred.

## Governance decision

Repository files are not live truth for legacy objects. `sql/production/*` and `sql/sap_view/*`
are baseline captures that can drift. Every behavioral claim about `sap_view.*` or
`sap_data_engineer.*` must first inspect the deployed definition through
`INFORMATION_SCHEMA.VIEWS` or `bq show --view` and record the timestamp.

Claude's initial statement that retry-amplified rows were contained cited repo 007 as the reason.
The conclusion remains correct for exact retry copies, because the independently inspected live
`SAP_LIVE_FULL` also has per-branch DISTINCT and final DocEntry `_rn=1`. The original repo-based
reason was invalid, and same-day semantic winner correctness remains open.

Source-only reproducible query:
`sql/adhoc/20260801_legacy_view_definition_inventory.sql`.
