# V3 July-payment one-time production runbook

Status: source-only / Class A. Do not execute until reviews for 013/035/048/049 PASS.

Scope locked by Boat: raw CareOS payment date `[2026-07-01,2026-08-01)` only; zero August;
temporary delivery folder `gs://interface-file/RCB_MOTOR/`; run once on 2026-08-01.

## Deploy order and gates

1. Rebase shared branch; confirm clean worktree and reviewed commit hashes.
2. Dry-run then deploy `013_stg_payment_events.sql`; verify the qualification-exclusion table and
   procedure exist. Do not refresh if review is not PASS.
3. Dry-run then deploy `035_policyno_too_long_validation.sql`.
4. Dry-run then deploy `048_july_export_shadow_and_archive.sql`.
5. Only after 048 exists live, dry-run then deploy `049_export_july_payment_to_gcs.sql`.
6. Capture every deploy job ID, timestamp, processed/billed bytes, and live routine definition.

## Nightly/full refresh

Run the already-reviewed `scripts/run_sap_sync_manual.ps1`. It orders extract → at-most-one loader
trigger → bronze-empty gate → ten separately capped V3 procedures. Stop at the first failure.

After it succeeds, verify:

- bronze path empty;
- latest SAP_LIVE UpdateDate/DocEntry batch present;
- `sap_payment_qualification_exclusion` counts are visible by rule;
- validation results contain no blocking rule for export candidates;
- active period is exactly July.

## Shadow hard gate

CALL `sp_build_july_export_shadow()` as its own capped job. It must report:

- coverage gap = 0 (otherwise no verified 56-column payload exists);
- exactly 56 columns in canonical order;
- raw PaymentDate min/max within July and August count = 0;
- no previously DELIVERED/ACKNOWLEDGED key;
- BatchRunDate exactly `31072026`;
- all date strings parse as DDMMYYYY and PolicyNo length <=50.

## Archive generation and UAT2 — mandatory G3

CALL `sp_export_july_payment_to_archive()` once. It writes only to the restricted archive prefix,
never the SAP production folder. Record the BigQuery job and exact GCS object generation.

Download that archived generation to a temporary directory outside OneDrive, calculate SHA-256,
size, physical data-row count and header column count, then copy the same local bytes to:
`\\SAP-B1-DBS\tmp\UAT2\RabbitUpload\Insurance_RCB`.

Known-answer verification before acceptance:

- exactly 56 header fields in canonical order;
- quoted BillingAddress containing commas round-trips as one field;
- every one of the 22 numeric/type-drift positions is either valid `-?digits.2digits` or the
  explicitly accepted empty representation; no scientific notation;
- NULL/zero behavior, DDMMYYYY strings, Paid required fields, BatchRunDate 31072026;
- UAT2 SAP result confirms the file/parser contract.

Record archive URI/generation/SHA-256/size/rows/header and UAT2 result in `export_file_manifest`.
Production is blocked until Boat/Aware explicitly accepts this exact hash/generation.

## Production delivery — exact-byte promotion

Copy the already accepted archive object generation server-side to
`gs://interface-file/RCB_MOTOR/`; do not re-run EXPORT DATA or reserialize. Use create-only/no-clobber
semantics. Capture the production generation, verify size/hash equality to the archive, then update
manifest and row archive to DELIVERED. Exact-byte archive evidence therefore exists before SAP can
pick up production.

Never rerun blindly after any partial stage. PREPARED_ARCHIVE, ARCHIVED_PENDING_UAT2,
UAT2_ACCEPTED, and DELIVERED are distinct states and must be reconciled by URI/generation/hash.

Immediately verify the object path, size, generation, row count/header count, and archive hashes.
No file name or content may contain August scope.

## SAP pickup/import evidence

Search Gmail label `notification SAP upload` for the exact generated filename. Treat evidence as
three layers:

1. `DOWNLOAD_GCS_FILE success` = SAP pickup only.
2. `INSURANCE_RCB success/success with error/error` + LogID = import outcome.
3. TXT/XLSX attachment = row-level outcome; email subject alone is insufficient.

Then refresh the SAP mirror and reconcile exported keys against SAP DocEntry/status. Mark archive
ACKNOWLEDGED only for independently matched rows. Persist the exact email LogID, import status and
`acknowledged_at` into `export_archive`; persist row-level attachment outcomes separately. Report
successes, rejects, missing pickup, job IDs, both file generations, SHA-256, LogID, row counts, and
zero-August proof.
