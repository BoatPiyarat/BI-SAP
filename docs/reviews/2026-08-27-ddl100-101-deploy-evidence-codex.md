# DDL 100/101 production definition deployment evidence

Recorder: Codex (single deployer)
Date: 2026-08-27
Scope: Scenario 3 lifecycle DDL 100 and Scenario 1 adapter DDL 101 definitions only

## Source approvals

- DDL 100 original review: BLOCK only for import CASE ordering —
  `docs/reviews/2026-08-27-051543b-claude.md`.
- Exact correction commit `5c8d4e7`: PASS —
  `docs/reviews/2026-08-27-5c8d4e7-delta-claude.md`.
- DDL 101 commit `7842cc1`: PASS WITH NOTES —
  `docs/reviews/2026-08-27-7842cc1-claude.md`; deployed after corrected DDL 100.

## Authenticated deployment

Both final source files passed authenticated BigQuery dry-run first at a lower bound of 0 bytes.

| Dependency order | Artifact | BigQuery job | Result |
|---:|---|---|---|
| 1 | DDL 100 | `codex_v3_ddl100_20260827_1215` | DONE; table, two procedures, and view created |
| 2 | DDL 101 | `codex_v3_ddl101_20260827_1216` | DONE; adapter procedure created |

No procedure was called. The DDL 100 archive procedure therefore did not execute `EXPORT DATA`.
No interface, GCS, SAP, workflow, promoter, Scheduler, pickup, import, or ACK action occurred.

## Read-only postcheck

Verifier: `sql/adhoc/20260827_verify_ddl100_101_deploy_no_runtime.sql`

- Dry-run: PASS, lower bound 0 bytes.
- Execution job: `codex_v3_verify_ddl100_101_20260827_1218` — DONE.
- All three routines exist with exact parameter counts 3, 12, and 3.
- Claim table and lifecycle view exist.
- `v3_flow_export_claim`: 0 rows.
- `vw_v3_flow_export_lifecycle`: 0 rows.

Live routine-definition SHA-256 values:

| Routine | SHA-256 |
|---|---|
| `sp_export_v3_scenario3_archive` | `88127ce6432be7b770b674303390a706678bcd11154b45f924984663dd5c0c8c` |
| `sp_mark_v3_flow_exact_delivery` | `5fbb56e706e418faf651cd547dcca0588ce85d2672a93e0d2834e210206ce339` |
| `sp_register_v3_scenario1_lifecycle` | `8e9e647aab382e0e8bf4e2948c47fcd2da5bbead18365366538634396dfb9b94` |

The definitions are live and inert. Runtime archive/registration remains separately gated by an
exact release-ready evidence run and unexpired per-flow activation approval.
