# V3 Scenario 1 manual fallback — RCB/ONETIME CREATE

Use this only after DDL 085 has a Class-A PASS, an authenticated dry-run, deployment, and a successful
procedure call for the exact pipeline run. It does not authorize an automated GCS write.

1. Run `sql/operator/20260826_report_v3_onetime_create_holds.sql` with the exact pipeline run ID.
   Resolve or explicitly accept the reported holds; never add held rows to the interface file.
2. Make a temporary copy of `sql/operator/20260826_export_v3_onetime_create_manual.sql`, replace
   its run-ID sentinel, and run this exact serializer from `codex_bootstrap`:

   ```cmd
   bq query --project_id=pacific-plating-282708 --use_legacy_sql=false --quiet --format=csv < TEMP_QUERY.sql > INSURANCE_RCB_06_V3_ONETIME_CREATE_YYYYMMDD_RUNID.csv
   ```

   The byte contract is UTF-8 CSV, comma delimiter, one explicit 56-column header, RFC 4180-style
   quoting when required, **LF record separators**, and a terminal LF. Replace
   `YYYYMMDD` and `RUNID` with the ICT run date and a filename-safe exact run token. Do not use the
   BigQuery UI copy/paste path or a spreadsheet re-save because either can change types or bytes.
3. Normalize the local file to LF before hashing or upload. Record its byte size, row count, and
   SHA-256. The marker recomputes the exact deterministic CSV bytes from the reviewed BigQuery
   payload and refuses any SHA-256 or byte-size mismatch.
4. Upload archive and production objects with `--if-generation-match=0`; record `0` as both
   precondition values passed to the marker, plus each resulting immutable generation and CRC32C.
   A normal overwrite/copy command is prohibited. Retain the run ID, commit, operator, timestamp,
   local hash, object metadata, and exact upload commands in the delivery evidence.
5. **Current fail-closed gate:** do not upload this Scenario 1 file yet. The deployed
   `sp_mark_v3_exact_delivery` in DDL 062 is hard-coded to `file_role='NEWPAYMENT'` and cannot safely
   register `CREATE_ONETIME`. A separately reviewed Scenario 1 archive/manifest marker must first be
   deployed and must prove exact identity/hash bijection. Reusing DDL 062 would create false evidence.
6. After that marker is deployed, a human with current session authority may copy the exact reviewed
   archive generation to `gs://interface-file/RCB_MOTOR/<the exact filename>` using create-only
   generation semantics. Record source/destination URI, generation, size, CRC32C, SHA-256, 56 header
   columns, data rows, event identities, production filename, and expected SAP result filename in
   `export_file_manifest` and `sap_delivery_manifest_v3` through that reviewed marker.
7. Ingest the exact SAP result using `docs/design/SAP_RUNBOOK_v3.md` sections 6.3–6.4, then call
   `sp_reconcile_v3_post_import_rows` from DDL 073. Verify the target export run with the row-level
   reconciliation pattern in `sql/adhoc/20260805_verify_post_import_rehearsal.sql`: every identity
   must end `ACKNOWLEDGED` or a named reject; zero matches stays `PENDING_ACK`; multiple LogIDs is
   `AMBIGUOUS_ACK`; partial reject is terminal and must retain the rejected identities.
8. If pickup has no independently matched result by the timeout defined in
   `docs/design/V3_AUTONOMY_UNITS_2_6_DESIGN.md`, retain `TIMEOUT`/`PENDING_ACK`, alert a human, and
   do not replay the file. Pickup email or header status alone is never row-level ACK.
9. If any assertion, hash, count, pickup, import, or ACK check differs, stop. Preserve the file and
   evidence, mark the delivery held, and do not regenerate or overwrite the object.

Rollback before pickup means pausing only the future Scenario 1 scheduler (its exact name must be
recorded in the activation artifact) and withholding the file; do not touch V2 or another scenario.
After pickup, do not delete or overwrite evidence. Use `docs/design/SAP_RUNBOOK_v3.md` incident path
and a separately reviewed SAP cancel/compensation artifact; never infer rollback from GCS deletion.
