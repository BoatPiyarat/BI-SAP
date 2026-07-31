# SAP import-result evidence — S1 schema gate

Status: **S1 COMPLETE; S2–S4 WAITING HUMAN INPUT**. Boat has not supplied the 2026-07-16 to
present email export. No mailbox content was read, moved, labeled, or changed; no email data was
committed; no BigQuery object was changed.

## Live schema, 2026-07-31

`sap_integration_v3.sap_import_result` is unpartitioned and empty (`numRows=0`) with seven nullable
columns: `batch_label`, `file_name`, `order_item`, `error_type`, `message`, `reported_at`, and
`ingested_at`.

It cannot answer the requested audit questions. Missing fields are `log_id`, `import_type`,
`status`, `period`, `error_code`, `row_number`, `rows_total`, `rows_failed`, `imported_at`, and
`source`. Generic `message` also lacks an enforceable sanitized-template boundary and is a PII risk.

## Source-only proposal

`sql/ddl/045_sap_import_result_schema_v2.sql` creates non-destructive shadow table
`sap_import_result_v2` with approved metadata plus restricted `message_raw` and sanitized
`error_template`, partitions by
`DATE(imported_at)`, and clusters by `log_id, order_item, error_type`. Dry-run proved BigQuery
rejects `CREATE OR REPLACE` when partitioning changes, so swap/drop/rename remains a separate
reviewed deployment gate after parser validation.

No expiration is proposed. The repository's 30-day rule applies to scratch/diagnostic tables;
this is durable audit evidence and email is currently the only retained source. Expiration needs a
separate Boat-approved retention decision.

## Parser gate

No parser or ingestion starts until a real export passes all three known answers:

- K1 `L80524847`: LogID 21090, whole-file rejection, 26/26 rows;
- K2 `L79871659`: successfully posted since March 2026, no CMI;
- K3 shared 16-Jul `INSURANCE_RCB_CANCEL` error.

Failure on any one stops ingestion. Raw body, attachment, and header are not stored in the audit
table. `message_raw` may contain names, InsuredID, address, or other PII and is therefore retained
only in restricted BigQuery for diagnosis. It must never be quoted or copied into git, docs, review
artifacts, logs, or chat; reports use `error_template`.

## Definition drift found

Repository 007 and `sql/production/SAP_LIVE_FULL.sql` order DocEntry winners by BatchRunDate; the
live SAP_LIVE_FULL view orders by UpdateDate. All use per-branch DISTINCT and outer DocEntry
row-number filtering, so exact retry copies remain contained. 007 must not be described as the
deployed legacy definition.
