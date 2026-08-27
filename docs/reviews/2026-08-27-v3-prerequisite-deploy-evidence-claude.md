# Review: V3 bootstrap/workflow SQL prerequisite deployment evidence

Reviewer: Claude Code
Artifact: `docs/reviews/2026-08-27-v3-prerequisite-deploy-evidence-codex.md`; production jobs
`bqjob_r7c5302ba320cb0c8_000001a041055acc_1`, `bqjob_r55a7be3b2b248770_000001a04107efd3_1`,
`bqjob_r57665e184876c0a5_000001a041087c78_1`
Verdict: **PASS WITH NOTES**

## Session limitation, stated up front

No live BigQuery credentials in this session. I cannot independently run the three cited
verification queries or reproduce the posted SHA-256 hashes myself — this review checks internal
consistency of the evidence document and the *source* of what was deployed, not the live state.

## What I checked

- **Verification queries are genuinely read-only.** I read all three cited adhoc files
  (`20260827_verify_ddl099_deploy.sql`, `20260827_verify_workflow_live_dependencies.sql`,
  `20260827_verify_v3_prerequisite_deploy_no_runtime.sql`) in full — every statement is a `SELECT`
  against `INFORMATION_SCHEMA` or a count of existing rows; none contains `CALL`, `INSERT`,
  `UPDATE`, `MERGE`, or DDL. This matches the "no runtime work" claim.
- **Parameter-order cross-check is correct.** The expected-parameters list in
  `20260827_verify_workflow_live_dependencies.sql` (13 names, `p_pipeline_run_id` through
  `p_file_sha256`) matches `sql/ddl/062_v3_mark_exact_delivery.sql`'s actual signature name-for-name
  and in order — the query would genuinely catch a live/source drift, not just assume agreement.
- **DDL 070 change is minimal and additive, matching the claim exactly.** `sap_delivery_manifest_v3`
  and `sap_result_ingestion_heartbeat_v3` both already exist live, so their `CREATE TABLE IF NOT
  EXISTS` statements are no-ops by construction; the actual change is the two `ALTER TABLE ... ADD
  COLUMN IF NOT EXISTS` statements, one of which (`production_file_name`) was genuinely missing and
  one (`event_identity_count`) was already present from an earlier DDL 062 change — exactly what the
  evidence claims ("added only the missing nullable column... already-present column was skipped").
- **Timestamp sanity.** `creationTime=1787797265930` converts to 2026-08-27T02:21:05 UTC =
  09:21:05 ICT, consistent with the same morning's other review requests (09:04–09:31 ICT) and with
  all three cited SHA-256 strings being well-formed 64-character hex.
- **DDL 062's already-live 13-param signature.** This evidence corrects something my own earlier
  full-delta review (`docs/reviews/2026-08-27-8a420d7-full-delta-claude.md`) could not establish —
  I had flagged DDL 062's current signature as an undeployed dependency based on a stale 2026-08-05
  review file; this live precheck shows it was already deployed with the exact current signature.
  Noting this to correct my own prior review's dependency list, not to relitigate it.

## Note — a pre-existing gap in the now-deployed DDL 067, found while reading it for this review

`sp_build_v3_daily_completeness_snapshot` (deployed by job 2 of this evidence) is **not** wrapped in
a transaction across its three `INSERT`s (metric rows, evidence rows, then the final `run` row).
Its only replay guard (line 63-66) checks `v3_daily_completeness_run` for an existing
`pipeline_run_id` — if the procedure fails after the metric/evidence inserts but before the final
`run`-row insert (e.g., a downstream assert or transient error), that guard is still empty on retry,
so a retry would insert a second copy of the metric/evidence rows before finally succeeding. This is
an append-only evidence/audit table, not an interface or financial correctness path, so the impact
is duplicate rows in `v3_daily_completeness_metric`/`v3_daily_completeness_evidence`, not a wrong
number reaching SAP or Finance — but it does violate this project's own conservation discipline.
**This was not part of what RQ-20260827-0931 asked me to review** (deployment-evidence, not DDL 067's
internal logic), and the evidence correctly confirms the procedure has never been called
(`v3_daily_completeness_run`/`metric`/`evidence` all at 0 rows) — so nothing has actually duplicated
yet. Flagging it now, before the first call, rather than after.

## Checklist 1–12

1. **Traceability — PASS.** Three named job IDs, exact `creationTime`/`endTime`, principal, and the
   three read-only verification queries used to prove the post-state.
2. **Provenance — PASS.** Cites the already-PASSed source reviews for DDL 099 and the workflow
   delta rather than re-arguing their content.
3. **NULL-safety — N/A.** No new query logic introduced by this evidence document itself.
4. **Ordering — N/A.**
5. **Column order — N/A.** DDL 070 only adds a nullable column; no interface file involved.
6. **Grain — N/A.**
7. **Distribution — PASS.** "0 active configs / 0 bootstrap runs / 0/0/0 completeness rows" is
   consistent with "no CALL occurred" rather than being offered as unrelated proof of correctness.
8. **Knowledge consistency — PASS.** Matches the dependency list from the already-PASSed full-delta
   workflow review, and actually improves on it (see DDL 062 note above).
9. **Scope — PASS.** Exactly three schema/definition-only deployments; explicitly disclaims
   workflow/promoter/Scheduler/GCS/SAP action, consistent with `delivery_enabled` still being false.
10. **Rollback — N/A for a schema-only, additive, IF-NOT-EXISTS-guarded deployment.**
11. **Cost hygiene — PASS.** Job 1 explicitly reports 0 bytes processed/billed (a `CREATE OR REPLACE
    PROCEDURE` statement, consistent with expected BigQuery behavior); the other two are DDL/schema
    jobs of the same class.
12. **Honest labelling — PASS.** Explicitly states what did *not* happen (no bootstrap/completeness
    CALL, no magnitude config, no workflow/Scheduler/Cloud Run/GCS/SAP/ACK state) rather than
    rounding up to "the pipeline is ready."

No BLOCK on the deployment evidence itself — it is internally consistent, the cited queries are
genuinely read-only and would catch real drift, and the actions taken match the stated scope
exactly. One required action before `sp_build_v3_daily_completeness_snapshot` is ever called: add a
transaction wrapper (or a stronger pre-insert idempotency key) so a partial failure can't duplicate
metric/evidence rows on retry.
