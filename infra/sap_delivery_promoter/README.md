# SAP delivery promoter

Source-only Cloud Run service for the Unit 6 exact-byte promotion boundary. It is not deployed by
this change, and `delivery_enabled` remains `false` in the workflow.

`POST /promote` accepts an archive bucket/object/generation and an explicit SAP-facing filename.
It streams SHA-256 over that immutable source generation, then uses GCS create-only rewrite to
`$PRODUCTION_PREFIX/$sap_file_name`. The response is accepted only after destination size and
CRC32C equal the source. It returns the source/destination URIs and generations, exact filename,
CRC32C, size, and SHA-256; it never returns file contents.

Required service configuration:

- `ARCHIVE_BUCKET=rcb-bronze-zone`
- `PRODUCTION_BUCKET=interface-file`
- `PRODUCTION_PREFIX=RCB_MOTOR`

Deploy only after a Class-A review and explicit scoped production approval. The runtime service
account needs read access to the archive objects and write/create-only access to the constrained
production prefix. The Workflow service account must have `run.invoker` on this private service.
The workflow caller supplies `promotion_service_url` and the exact `sap_file_name`; archive names
are never used to derive that SAP-facing name.
