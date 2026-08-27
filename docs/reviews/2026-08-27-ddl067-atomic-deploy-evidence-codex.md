# DDL 067 atomic definition deployment evidence

Recorder: Codex (single deployer)
Date: 2026-08-27
Source commit: `557598c`
Source review: `docs/reviews/2026-08-27-557598c-claude.md` — PASS WITH NOTES

The exact corrected source passed its regression checker and authenticated BigQuery dry-run at a
lower bound of 0 bytes before deployment.

- Deployment job: `codex_v3_ddl067_atomic_20260827_1240` — DONE.
- Existing three tables: skipped/preserved.
- Procedure: replaced with replay guards and one transaction around all three inserts.
- No procedure CALL occurred.

Read-only verifier `sql/adhoc/20260827_verify_ddl067_atomic_deploy.sql` passed dry-run and executed
as `codex_v3_verify_ddl067_atomic_20260827_1242` — DONE. It proved one live one-parameter routine,
both new replay messages, transaction markers, and zero run/metric/evidence rows.

Live routine-definition SHA-256:
`2ededb2fe055b64509239dd432a131e97b59ee711ef6bf1b26c87c9638a92435`.

Claude's non-blocking concurrency note remains an activation constraint: the workflow/Scheduler
must not invoke completeness twice concurrently for the same pipeline run. No Scheduler exists or
was activated by this deployment.
