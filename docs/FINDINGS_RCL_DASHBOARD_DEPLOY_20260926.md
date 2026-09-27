# Dashboard-only live correction — 2026-09-26

The user explicitly requested immediate deployment of only `sap_data_engineer.sap_dashboard_carepay_installment`: additional payments have ExpectedReceived=0 and ActualReceived equal to the new charge, with other consumers reviewed later. This supersedes the earlier source-only hold for this view only. V3 remains held; RCL newpayment and paid-period gate definitions are unchanged.

The deployed SQL is `sql/production/rcl_dashboard_only_20260926/deploy.sql`. It retains all successful voluntary charges, ranks by (create_time,id), takes additional ActualReceived directly from charges.amount/100, and keeps additional EIR interest zero. The existing compulsory first-charge filter and principal formulas remain. The earlier three-view proposal is not the deployed set.

Evidence: `docs/evidence/rcl_dashboard_only_20260926/`. Before/after metadata and rollback SELECT are retained; complete executable SQL matches the candidate (BigQuery removes leading comments). All 56 column names/order/types/modes match; absent mode in fresh metadata defaults to NULLABLE. Newpayment and gate etags/query hashes are identical before/after.

Precheck: `codex_rcl_dashboard_only_precheck_20260926_2150`, passed two expected/actual receipt assertions plus no duplicate target identity assertion. Deployment: `codex_rcl_dashboard_only_deploy_20260926_2152`, successful CREATE OR REPLACE VIEW after zero-byte dry-run. Live postcheck: `codex_rcl_dashboard_only_postcheck_20260926_2153`; PASSED all three assertions; 20 target rows, including both additional receipts. All three jobs are DONE without errors; see jobs.json.

Expected live additional receipts: L80570054-V1 / 2_chrg_68ve8ufva4h1iil7wrn = Expected 0, Actual 22.04; L79109956-V1 / 2_chrg_68w87npgw0hbvid58ho = Expected 0, Actual 645.21 THB. No SAP import success is asserted. Existing downstream paid-period filters can still block these receipts until separately reviewed.

Rollback: run the safe query wrapper against `sql/production/rcl_dashboard_only_20260926/rollback.sql` to restore the exact prior query body. No rollback was needed. Prior findings on downstream compatibility, principal allocation and durable reporting remain follow-up items, explicitly deferred from this one-view deployment.
