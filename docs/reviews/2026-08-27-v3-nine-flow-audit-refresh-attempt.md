# V3 nine-flow readiness audit refresh attempt

Date: 2026-08-27

## Outcome

The existing read-only SQL
`sql/operator/20260827_audit_v3_nine_flow_production_readiness.sql` dry-ran at `20,972,548` bytes.
Query job `codex_v3_nine_flow_audit_20260827_115853` subsequently completed `DONE` in
`asia-southeast1` as `statementType=SELECT`, with `maximumBytesBilled=21474836480` and principal
`data@rabbit.co.th`.

The Windows PowerShell client treated `bq`'s stderr progress as a terminating error and did not
retain the returned nine rows. A later metadata lookup proved the job completed, but result-row
retrieval was rejected because the workspace approval service was out of credits.

## Disposition

- No nine-flow readiness conclusion is drawn from this job until its exact rows are retrieved.
- The previous authoritative audit result remains the last readable per-flow evidence.
- The temporary PowerShell query runner was removed uncommitted because the canonical hard rule
  permits only `scripts/bq_safe_query.sh` for non-metadata queries; an equivalent second path is not
  authorized.
- The completed job was read-only. It did not change a scenario, approval, activation ledger,
  Scheduler, Workflow, GCS object, SAP data, or interface file.

## Resume action

When execution credits return, use metadata-only `bq head -j` on
`codex_v3_nine_flow_audit_20260827_115853` to retrieve its existing result rows. Do not rerun the
query. If a future query is required on Windows, install/restore Bash so the canonical wrapper can
be used; do not recreate the rejected PowerShell path.
