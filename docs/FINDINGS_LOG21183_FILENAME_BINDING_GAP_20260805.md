# LogID 21183 — production basename vs SAP-reported filename binding gap

Status: **CONFIRMED STRUCTURAL BLOCKER FOR UNATTENDED INGESTION**

## Live evidence

At 2026-08-05 21:25 ICT, read-only job
`bqjob_r11d028b8cfd54f2e_0000019fd251056f_1` compared retained delivery evidence for export run
`V3DAILY-20260803-113257-55042e7c` with the confirmed SAP email filename for LogID 21183. Mandatory
dry-run estimate was 308,583 bytes.

- Delivered production URI:
  `gs://interface-file/RCB_MOTOR/INSURANCE_RCB_06_V3_DAILY_NEWPAYMENT_20260803_`
  `V3DAILY-20260803-113257-55042e7c_000000000000.csv`
- Production object basename:
  `INSURANCE_RCB_06_V3_DAILY_NEWPAYMENT_20260803_`
  `V3DAILY-20260803-113257-55042e7c_000000000000.csv`
- SAP email `FileName`:
  `RCB_MOTOR_INSURANCE_RCB_06_V3_DAILY_NEWPAYMENT_20260803_`
  `V3DAILY-20260803-113257-55042e7c_000000000000.csv`
- The two names are not equal.
- `export_archive` retained 558 delivered event identities; `export_file_manifest` retained 3,857
  payload rows. No `sap_delivery_manifest_v3` or ingested header row exists for this historical
  run because those runtime objects were introduced later.

The query is `sql/adhoc/20260805_verify_log21183_filename_binding.sql`.

## Why current source cannot close the loop

1. DDL 062 asserts `p_sap_file_name` equals the basename of `p_production_uri`, then stores that
   value as `sap_delivery_manifest_v3.sap_file_name`.
2. The Apps Script ingestor parses SAP email `FileName` and requires exact equality with
   `sap_delivery_manifest_v3.sap_file_name`; zero matches remain unlabeled and `PENDING_ACK`.
3. The workflow/promoter currently use the same caller-supplied `sap_file_name` as the production
   object basename.
4. A static daily scheduler cannot supply the full exact name because the archive export adds the
   run ID and shard suffix during that execution.

Therefore a future unattended delivery following current source would persist the production
basename (`INSURANCE_RCB_...`) while the actual SAP result is expected to report the BU-prefixed
name (`RCB_MOTOR_INSURANCE_RCB_...`). The Gmail result cannot bind to its manifest, so automatic
outbox enqueue/reconciliation cannot start.

## Required correction

Persist and validate two immutable names at promotion:

- `production_file_name`: exact basename under `gs://interface-file/RCB_MOTOR/`, beginning
  `INSURANCE_RCB_`;
- `sap_result_file_name`: exact name SAP will report, observed as
  `RCB_MOTOR_<production_file_name>`.

The transformation must be an explicit reviewed delivery policy, not a heuristic hidden in the
Gmail parser. The promoter copies to `production_file_name`; the delivery manifest and result
ingestor bind on `sap_result_file_name`; both names and the production URI/generation/hash remain
in the same atomic delivery record. The daily workflow must construct them only after it has
identified exactly one archive object, so no scheduler supplies a dynamic shard name.

Do not enable delivery or deploy the Apps Script publisher until the two-name delta passes Class-A
review, deploys, and is included in the synthetic/controlled production rehearsal.

No manifest, table, GCS object, workflow, scheduler, Gmail label, delivery, or SAP state changed in
this investigation.
