# P0 SAP mirror completeness gate — BLOCKED

Evidence timestamp: 2026-07-31. This investigation was read-only except for one explicit run of
the existing loader scheduler requested by Boat. No extract, deploy, view change, export, or file
write/delete was performed by Codex.

## Verdict

`sap_integration_v2.SAP_LIVE` is incomplete for the July-close diagnostics. The locked D1/D2
figures for groups (ก) and (ง) are stale and must not be cited or extended until the pending extract
is loaded and the complete diagnostic suite is rerun.

## Bronze backlog

The production landing prefix contains one unprocessed object:

- `SAP/production_database/Results2026_07_31_6fb20167.json`
- generation `1785497692838383`
- created/updated `2026-07-31T11:34:52.846Z`
- size `169,695,148` bytes

The loader deletes a source object only after a successful load. Its continued presence proves
that the 31-Jul extract has not reached `SAP_LIVE`.

## SAP_LIVE batch evidence

Query `p0_mirror_batch_20260731_162600` was created at
`2026-07-31T16:25:09.973Z`, started `16:25:10.052Z`, and ended `16:25:10.788Z`.
Dry-run/processed bytes were `133,186,480`; billed bytes were `134,217,728`, under the
`21,474,836,480` ceiling in `asia-southeast1`.

Daily raw row/distinct-DocEntry counts were:

| U_BatchRunDate (BKK) | rows | distinct DocEntry |
|---|---:|---:|
| 2026-07-22 | 1,494 | 1,494 |
| 2026-07-23 | 1,578 | 1,578 |
| 2026-07-24 | 11,900 | 11,846 |
| 2026-07-25 | 1,584 | 1,584 |
| 2026-07-26 | 2,484,385 | 66,952 |
| 2026-07-27 | 4,226,950 | 60,385 |
| 2026-07-28 | 1,465,475 | 58,619 |
| 2026-07-29 | 27 | 27 |
| 2026-07-30 | 0 | 0 |
| 2026-07-31 | 0 | 0 |

Therefore `SAP_LIVE` contains zero 31-Jul batch rows versus the extract's reported 61,133 rows.
The 61,133 figure is an extract count, not yet a loaded mirror count.

## Loader history and current blocker

The loader is Cloud Run service `sap-order-payment-initial-phase` revision
`sap-order-payment-initial-phase-00019-hm7`, with 1,024 MiB memory and 300-second timeout. It is
invoked through Pub/Sub/Eventarc; the existing scheduler
`auto_load_sap_data_in_bucket_to_bigquery` runs at 01:00 Asia/Bangkok. It is not triggered directly
by the GCS finalize event.

Read-only logs for 22–31 Jul show no POST on 22–23; a 24-Jul invocation found no JSON; successful
loads occurred on 25–30 Jul, interspersed with large retry storms on 27–29 Jul caused by the same
1,024 MiB memory ceiling. File dates and `U_BatchRunDate` are not interchangeable, so the batch
table above—not request status alone—is the completeness control.

Boat instructed that an incomplete mirror be loaded before further analysis. Codex ran the
existing loader scheduler once at approximately `2026-07-31T16:27Z`. It did not deploy or alter
configuration. The request and automatic Pub/Sub retries failed:

| request timestamp UTC | HTTP | evidence |
|---|---:|---|
| 16:27:21.314 | 503 | container terminated; 1,106 MiB used over 1,024 MiB limit |
| 16:27:45.870 | 503 | automatic retry failed |
| 16:28:12.364 | 503 | automatic retry failed |
| 16:28:41.870 | 503 | automatic retry failed |

The object remains in bronze. Increasing memory or changing loader implementation would be a
deployment and is prohibited by the current gate. Repeated manual triggers would amplify the
already active retry stream and were not issued.

## Required next gate

An authorized loader remediation must make exactly one load succeed, delete the bronze object,
and produce 61,133 corresponding 31-Jul rows (or a reconciled explanation if the loader's actual
row count differs). Only then rerun D1/D2, overlap analysis, view-filter attribution, and the wider
G1 population. Until that verification passes, P0-2 and P1-3 through P1-5 remain on hold.
