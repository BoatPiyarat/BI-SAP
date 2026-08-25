# SAP delivery promoter

Source-only Cloud Run service for the Unit 6 exact-byte promotion boundary. It is not deployed by
this change, and `delivery_enabled` remains `false` in the workflow.

`POST /promote` accepts an archive bucket/object/generation and an explicit production-object
filename.
It streams SHA-256 over that immutable source generation, strictly parses the UTF-8 CSV, requires
the exact canonical 56-column header order and 56 fields in every logical record, then uses GCS
create-only rewrite to `$PRODUCTION_PREFIX/$production_file_name`. The response is accepted only
after destination size and CRC32C equal the source. It returns the source/destination URIs and
generations, exact filename, CRC32C, size, SHA-256, header count, and physical CSV data-row count;
it never returns file contents.

Required service configuration:

- `ARCHIVE_BUCKET=rcb-bronze-zone`
- `PRODUCTION_BUCKET=interface-file`
- `PRODUCTION_PREFIX=RCB_MOTOR`

Deploy only after a Class-A review and explicit scoped production approval. The runtime service
account needs read access to the archive objects and write/create-only access to the constrained
production prefix. The Workflow service account must have `run.invoker` on this private service.
The workflow supplies the exact `production_file_name` only after finding exactly one immutable
archive object and validating its configured `INSURANCE_RCB_...csv` contract. SAP's result email
adds the BU reporting prefix (`RCB_MOTOR_`) to that production basename; the workflow persists
that separate result-facing name through DDL 062. The promoter never interprets or constructs the
SAP-reported name.
