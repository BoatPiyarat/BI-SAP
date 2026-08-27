# Review: full workflow replacement delta, live base to candidate

Reviewer: Claude Code
Artifact: `infra/v3_nightly_orchestrator.workflows.yaml`, commits `30bd693` → `28686d6` → `efd6de0`
→ `65bd74a` → `8a420d7`, against live-proved base `65ebde3`
Verdict: **PASS WITH NOTES** — source only; do not deploy until the dependencies below are staged

## Session limitation, stated up front

No live BigQuery/Workflows/Cloud Scheduler access in this session. This traces the YAML control
flow and cross-checks it against the SQL procedures it calls; nothing here is a live execution.

## What changed, commit by commit

- **`30bd693`** — implements the two-name delivery-identity fix required by
  `docs/FINDINGS_LOG21183_FILENAME_BINDING_GAP_20260805.md`: the caller no longer supplies
  `sap_file_name`; instead the workflow derives `production_file_name` from the actual archive
  object's basename (after the exact-one-object census already in place) and computes
  `sap_result_file_name = "RCB_MOTOR_" + production_file_name`, gated by regex before use. This is
  *exactly* the finding's own "Required correction" section, not a divergent design.
- **`28686d6`** — wires two new subworkflows (`count_export_runs_for_pipeline`,
  `derive_original_pipeline_run_id`) and two call sites so a nightly run actually invokes
  `sp_build_v3_daily_completeness_snapshot` (previously dead code per the cited
  daily-completeness-runtime-gap finding). Author's own commit message discloses the dry-run
  couldn't be run (`ReauthUnattendedError`) and that verification was structural (PyYAML parse +
  byte-level escaping comparison) — an honest, explicit substitute, not a skipped step.
- **`efd6de0`** — Codex's first BLOCK on `28686d6` (missing `jobComplete` gates) gets fixed here,
  plus post-import completion is reordered so the outbox row reaches `SUCCEEDED` only after origin
  resolution and snapshot dispatch both succeed.
- **`65bd74a`** — adds `header_column_count`/`data_row_count` to the delivery call and to
  `promote_daily_archive`'s output/gate, distinguishing physical CSV rows from event identities.
- **`8a420d7`** — already reviewed standalone (`docs/reviews/2026-08-27-8a420d7-claude.md`, PASS):
  closes the remaining NULL-safety/exception-handling BLOCK Codex raised on the completeness
  lookups.

## Cross-checks performed beyond the diff hunks

1. **Parameter parity with `sql/ddl/062_v3_mark_exact_delivery.sql`.** I read the full, current
   `sp_mark_v3_exact_delivery` signature (13 params: `p_pipeline_run_id, p_export_run_id,
   p_archive_uri, p_archive_generation, p_production_uri, p_production_generation, p_size_bytes,
   p_crc32c, p_header_column_count, p_data_row_count, p_production_file_name,
   p_sap_result_file_name, p_file_sha256`) against the workflow's current
   `delivery_call_head`+`delivery_call_tail` construction at HEAD (not the intermediate diff
   states) — the 13 values are supplied in exactly this order. No positional drift across the
   three commits that touched this string.
2. **Two-name policy consistency.** The workflow's regex gate
   (`^INSURANCE_RCB_...$` / `^RCB_MOTOR_INSURANCE_RCB_...$`) and DDL 062's own independent
   assertions (`p_sap_result_file_name = CONCAT('RCB_MOTOR_', p_production_file_name)`, basename
   cross-checks against both URIs) enforce the same rule from two sides — defense in depth, not
   redundant.
3. **`delivery_enabled` is still hardcoded `false`**, read from a literal assignment, not from
   `args` — confirmed by reading the current `main` params block, not just grepping for the
   string. A caller cannot flip this without editing source.
4. **Fail-closed blast radius for an undeployed dependency.** `run_bq_call` (the shared helper
   used by every new call site here) dry-runs the statement before executing it and routes a
   dry-run failure through `fail_closed`. So if a dependency below is missing, the failure mode is
   a loud, alerted `fail_closed` on the first affected nightly run — not silent corruption.

## Checklist 1–12

1. **Traceability — PASS.** Every commit here traces to a named prior finding or review
   (`FINDINGS_LOG21183...`, `RQ-20260805-2205`, Codex's `a82409d`/`28686d6` BLOCKs).
2. **Provenance — PASS.** Fixes cite and build on prior findings rather than re-deriving them.
3. **NULL-safety — PASS.** Covered by the standalone `8a420d7` review; nothing in the other four
   commits reintroduces an ungated dereference.
4. **Ordering — N/A.** No date-string ordering in this delta.
5. **Column order — N/A for the workflow itself; PASS for the DDL 062 dependency** — its 13-param
   order matches the workflow's call construction exactly (checked above).
6. **Grain — PASS.** `pipeline_run_id` / `export_run_id` grain is unchanged; the new snapshot
   plumbing explicitly binds to the *original* outbound `pipeline_run_id`, not the post-import
   child's own run_id (the exact bug class this project has hit before).
7. **Distribution — N/A.** No count-parity claim in this delta.
8. **Knowledge consistency — PASS.** `30bd693` directly implements
   `FINDINGS_LOG21183_FILENAME_BINDING_GAP_20260805.md`'s required correction; no conflict found.
9. **Scope — PASS.** All five commits stay within `infra/v3_nightly_orchestrator.workflows.yaml`
   (plus the already-reviewed sibling SQL each cites).
10. **Rollback — N/A.** Source only; live revision `000009-e96` remains the deployed one per
    `docs/reviews/2026-08-05-0e44aec-claude.md`.
11. **Cost hygiene — NOTE.** `28686d6`'s author explicitly could not obtain a live dry-run
    (`ReauthUnattendedError`) and substituted structural verification instead — disclosed, not
    hidden, but it means this delta still has no live dry-run of its own; `run_bq_call`'s built-in
    dry-run step will be the first live check whenever this actually runs.
12. **Honest labelling — PASS.** No commit claims deployment, a CALL, or a live number; the
    `ReauthUnattendedError` limitation is stated plainly rather than silently worked around.

## Dependencies that must be deployed before this workflow replaces the live one

This is the review's main ask, so stated explicitly:

- **`sql/ddl/070_sap_result_ingestion_heartbeat.sql`** — adds the `production_file_name` column
  DDL 062 requires. DDL 062's own header says so directly ("Deploy reviewed DDL 070's
  production_file_name schema delta before this replacement").
- **`sql/ddl/062_v3_mark_exact_delivery.sql`** (current 13-param version) — the live procedure is
  still the older, single-`sap_file_name` signature per the last delivery-gate deployment review
  I found (`docs/reviews/2026-08-05-daa9331-claude.md`, which still discusses `sap_file_name`).
  Deploying this workflow before this DDL would make `sp_mark_v3_exact_delivery` calls fail at the
  parameter level — caught by `run_bq_call`'s dry-run/`fail_closed`, but still a broken Unit 6 path
  until fixed. Low urgency only because `delivery_enabled` stays hardcoded `false`.
- **`sql/ddl/067_v3_daily_completeness_snapshot.sql`** — the commit message for `28686d6` states
  this procedure "was never deployed." Unlike Unit 6 delivery, the completeness-snapshot call
  sites are **not** gated by `delivery_enabled` — they run on every normal-mode healthy-zero-export
  night and every post-import-mode terminal reconciliation once this workflow is live. This is the
  more pressing of the two dependencies: deploying the workflow without DDL 067 first means the
  very first qualifying nightly run fails closed on a missing procedure.
- **External `promotion_service_url` Cloud Run service** — the workflow's HTTP body to `/promote`
  now sends `production_file_name` (not `sap_file_name`) and expects `production_file_name`,
  `header_column_count`, and `data_row_count` back in the response. This is outside this repo and
  cannot be verified from source; confirm the promoter service has been updated to match before
  relying on `gate_promotion`'s checks (they will correctly fail closed if it hasn't, but the
  night's delivery would be blocked rather than merely late).

No BLOCK. The design is sound and each fix traces to a real, previously documented problem. The
required action is sequencing: deploy DDL 070, DDL 062, and DDL 067 (and confirm the promoter
service contract) before this workflow file replaces the live revision.
