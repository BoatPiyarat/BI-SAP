# V3 NEWPAYMENT manual production handoff — 2026-08-26

Status: prepared for Boat's manual execution. Codex must not run the production copy command.

This handoff covers only the validated fresh V3 RCL later-period NEWPAYMENT artifact. It does not
claim RCB Onetime, RCL first-period CREATE, cancellation, or change-order coverage.

## Immutable source evidence

- Pipeline run: `V3NIGHTLY-2026-08-25T14:32:37-0ce16d45`
- Export run: `V3DAILY-20260825-143823-0c1c161f`
- Archive generation: `1787668717202105`
- Size: `2640970` bytes
- CRC32C: `MDIjTg==`
- SHA-256: `0e02ea0267e063d75fdb9092b65783b76f2abd059b8098e3ad4bd38b1cec37cc`
- Header columns: `56`, exact canonical name/order verified
- Physical CSV data rows: `4288`
- Released payment-event identities: `641`
- Items: `629`; duplicate item-periods: `0`; incomplete spines: `0`

Exact source object:

```text
gs://rcb-bronze-zone/sap-interface-archive/2026/08/25/V3DAILY-20260825-143823-0c1c161f/INSURANCE_RCB_06_V3_DAILY_NEWPAYMENT_20260825_V3DAILY-20260825-143823-0c1c161f_000000000000.csv
```

Exact production object:

```text
gs://interface-file/RCB_MOTOR/INSURANCE_RCB_06_V3_DAILY_NEWPAYMENT_20260825_V3DAILY-20260825-143823-0c1c161f_000000000000.csv
```

## Boat manual step — create only

First confirm the destination is absent. A `404 Not Found` is the required precondition:

```powershell
gcloud storage objects describe `
  "gs://interface-file/RCB_MOTOR/INSURANCE_RCB_06_V3_DAILY_NEWPAYMENT_20260825_V3DAILY-20260825-143823-0c1c161f_000000000000.csv" `
  --format=json
```

Then copy the exact immutable source generation with a destination generation-match of zero:

```powershell
gcloud storage cp `
  "gs://rcb-bronze-zone/sap-interface-archive/2026/08/25/V3DAILY-20260825-143823-0c1c161f/INSURANCE_RCB_06_V3_DAILY_NEWPAYMENT_20260825_V3DAILY-20260825-143823-0c1c161f_000000000000.csv#1787668717202105" `
  "gs://interface-file/RCB_MOTOR/INSURANCE_RCB_06_V3_DAILY_NEWPAYMENT_20260825_V3DAILY-20260825-143823-0c1c161f_000000000000.csv" `
  --if-generation-match=0
```

Do not retry blindly. If the command returns a precondition or already-exists error, stop and
inspect the destination generation; never overwrite it.

## Immediate evidence capture

SAP polls the production bucket, so capture metadata immediately after the copy:

```powershell
gcloud storage objects describe `
  "gs://interface-file/RCB_MOTOR/INSURANCE_RCB_06_V3_DAILY_NEWPAYMENT_20260825_V3DAILY-20260825-143823-0c1c161f_000000000000.csv" `
  --format=json
```

The destination must have size `2640970` and CRC32C `MDIjTg==`. Record its generation. Download
that exact destination generation and verify SHA-256 equals
`0e02ea0267e063d75fdb9092b65783b76f2abd059b8098e3ad4bd38b1cec37cc`.

Only after those checks, replace `REPLACE_WITH_PRODUCTION_GENERATION` in
`sql/operator/20260826_mark_fresh_v3_delivery_after_manual_upload.sql` and run it through
`scripts/bq_safe_query.sh`. That transaction records both 4,288 physical file rows and 641 event
identities. `DELIVERED` means GCS evidence only; SAP pickup/import/acknowledgement remain separate.

