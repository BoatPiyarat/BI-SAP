# Current-month CareOS/SAP audit evidence

Authoritative result: audit_final.json.gz (gzip lossless original BigQuery output); query_sha256.json and execution_binding.json bind it to sql/operator/careos_current_month_sap_completeness.sql.
Final user-facing CSVs: exceptions.csv, paid_missing.csv, cancellation_missing.csv, summary.csv. CSV route-membership columns were enriched from later read-only diagnostic snapshots; no financial values rewritten.

Provenance: final_jobs.json; live object metadata and definition captures. Report: docs/FINDINGS_CAREOS_MONTH_COMPLETENESS_20260926.md.

Historical, superseded: audit_result.json.gz and audit_corrected.json.gz. first_audit_job/children and first error record describe those earlier runs, not the final result. upstream_diagnostic.json contains the failed UNION-type diagnostic; upstream_diagnostic_final.json is successful. cancel_diagnostic.json uses the earlier same-count snapshot; cancel_final_membership.json joins the final population. Cached SQL references expiring BigQuery temporary datasets and is forensic evidence, not the reusable entrypoint.

No customer names, contact details or addresses in result exports. Metadata definitions contain schema and SQL only. Large result JSON is losslessly gzip-compressed; CSV is directly readable.

Readable .sql definition copies normalize line endings/trailing whitespace; .json metadata retains exact original view query strings.
