# Independent Class-A review — 2026-09-29

Verdict: **SQL regression PASS; production deployment BLOCK; interface release BLOCK.** Reviewer read artifacts only; zero BigQuery queries or production changes.

1. Traceability — initial immutable comparison is named by capture_comparison.sql and captured_at 2026-09-29 02:55:39 UTC; release_rows.json/read_release.sql independently yield 1,145 rows / 129 items. Final schema evidence timestamp 2026-09-29T06:08:56.186Z and release job bqjob_r2a938fdc486bf28f_000001a0ebc64d46_1 retained in schema_validation.json.
2. Provenance — exact reviewed SQL SHA256 below; author commit/session provenance remains required.
3. NULL-safety — new anti-join and spine counters fail closed; unchanged nullable legacy filters remain outside this surgical fix. No optional NULL formatting introduced.
4. Ordering — trigger uses typed update_time/create_time/id tie-break; integer spine 1..N; no new string-date sorting. Legacy PARSE_DATE/SPLIT failure risks remain unchanged.
5. Column order — refreshed final before/candidate schemas identical (56 names/types/positions), canonical ordinal match and exact staged source match confirmed in schema_validation.json.
6. Grain — item+period anti-match correct; trigger dedup is eligibility only. Export never arbitrarily discards split charges: duplicate/incomplete items held in full.
7. Distribution — 0 bad spines among 129 final items, statuses only Paid/Pending. Both target spines complete (8/10); missing periods 5/4 Paid. For retained items, all 159 before-Paid rows remain with unchanged InvoiceNo and ActualReceived. Initial comparison contains 47 held-item spines; durable holds view supports diagnosis.
8. Knowledge — Paid history retained, terminal guards applied, financial/date formulas unchanged. Period control lacks September and August remains past closing without locked_at; current-date clamp is not approval to release. Enabled NonMotor scheduler can defeat separate file hold unless its consumer is gated/contained.
9. Scope — production view change explicitly authorized; holds diagnostic supports same fix. No SAP import/export authorized by this review.
10. Rollback — verbatim before SQL/metadata and rollback_trigger.sql/rollback_newpayment.sql present; two view restores expected under five minutes (execution untested).
11. Cost hygiene — reviewer issued no queries; author retained final dry-run 9,873,277,104 bytes and named execution job in schema_validation.json. Verify cost-wrapper cap again in any deployment invocation.
12. Honest labelling — SQL/data recovery verified; import readiness and SAP acknowledgement not verified. Do not label release_rows.json as ready-to-import.

Deployment blocker (unresolved after one author response): enabled sap-order-payment-non-motor feeds the linked NonMotor exporter; no verified containment prevents automatic export of blocked candidate. Establish an approved pause/gate or resolve release gates before changing live views. Interface blockers: resolve approved open period, required/optional NULL rules and all exact immutable-file gates; no export may bypass these.

One-round disposition: final schema and dry-run evidence close those evidence gaps; target_reconcile.json plus verification script establish source/SAP invoice and amount checks on target Paid periods. Operational containment remains unresolved. **No production view mutation, CSV generation, SAP import, or scheduler change occurred in this reviewed unit.**

Specific residual risks: unchanged annual bounds, unsafe legacy PARSE_DATE/SPLIT, narrowed terminal status spelling list, and upstream snapshot/payment duplicates; quarantine prevents malformed spines but is not full interface validation.

Reviewed hashes:
```
RCL_NonMotor_paid_period_gap_trigger_20260929.sql: b54eb441231e3fbc2e55ec3c73fc86b01aafceecbca0082cb955c3c56ce0d6ca
RCL_NonMotor_newpayment_period_gap_20260929.sql: 818d7c09757f0300c21f495d4d060b52394f1dface4625b0a732f0d9feb6c407
RCL_NonMotor_newpayment_period_gap_holds_20260929.sql: 2e61c5677d97ff73435efdafe50796508ffc7851b771476e90ebecdedc6a29fb
```
