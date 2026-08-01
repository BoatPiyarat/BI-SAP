# Manual SAP sync — one-command recovery path

Status: SOURCE ONLY / CLASS A REVIEW REQUIRED

Run from the repository root in PowerShell:

```powershell
.\scripts\run_sap_sync_manual.ps1
```

Do not start this recovery command during the automatic 20:30 extract / 21:00 V3 window. A manual
extract can overlap the scheduled extract before either has written its bronze object, and a manual
V3 refresh can overlap the scheduled V3 procedure. Wait until the scheduled V3 run has reached a
terminal state (normally after 21:05 ICT), inspect bronze/extract status, and use this command only
to recover a missing or stale chain. Never run it in parallel with either schedule.

The command is fail-closed and ordered:

1. If exactly one bronze object already exists, it skips extract rather than create a second batch.
2. Otherwise it executes `sap-extract-job --wait`.
3. It triggers `auto_load_sap_data_in_bucket_to_bigquery` at most once and waits for bronze deletion.
4. It runs each V3 procedure as a separate BigQuery job, each with its own dry-run and 20 GiB cap;
   the mirror procedures use `ADHOC:manual-operator` so audit logs cannot mislabel recovery as nightly.
5. Any failure stops the sequence; never rerun blindly or trigger the loader again while an object remains.

The separate BigQuery jobs are mandatory. On 2026-08-01, the single wrapper CALL
`manual_v3_after_loader_20260801_211800` committed the early refresh steps but failed inside
validation after processing 20,246,650,795 bytes because the script-wide 20 GiB allowance had only
~1.14 GiB left. Validation alone then succeeded under its own cap at 18,168,069,896 processed bytes.

This runbook does not write interface CSV files and does not trigger SAP's production interface
bucket. It synchronizes SAP database evidence into `SAP_LIVE` and refreshes the V3 analytical/control
tables only.

## 2026-08-01 execution evidence

- Extract execution `sap-extract-job-sw95z`: 2,241 rows, completed 13:30:32Z.
- Loader job `2017bec6-c8cf-446e-a804-21e32624849f`: one input file, 2,241 output rows,
  `badRecords=0`, completed 14:15:30Z; bronze object removed.
- Scheduled V3 run was 14:00:01Z–14:05:01Z, before loader completion, so it was stale for this batch.
- Whole-chain catch-up failed at validation as described above; it was not retried.
- Recovery jobs all DONE with no error:
  - `manual_v3_validation_20260801_212300`
  - `manual_v3_delta_20260801_212400`
  - `manual_v3_status_20260801_212500`
- Post-recovery metadata rows: `sap_mirror_doc=1,664,889`, `sap_mirror_state=1,302,470`,
  `expected_state=290,319`, `sap_validation_error=275`, `delta_export=290,319`, and
  `interface_daily_status=290,319`.
