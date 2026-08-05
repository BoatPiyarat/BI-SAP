# Insurer codes 30, 46, 48, 49 — SAP LIVE evidence

Status: **NOT CONFIRMED / KEEP HELD**

At `2026-08-05 21:16:54 +07:00`, Codex checked Boat's requested codes against the project's
documented E3 success source and normalization:

- source: `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`;
- acceptance: `SAFE_CAST(DocEntry AS INT64) > 0`;
- code normalization: suffix after `/`, otherwise suffix after the first `-`, otherwise trimmed
  `U_InsurerCode`;
- registry cross-check:
  `pacific-plating-282708.sap_integration_v3.sap_insurer_master`;
- query: `sql/adhoc/20260805_verify_insurer_codes_30_46_48_49.sql`;
- BigQuery job: `bqjob_r2f4166e07184b869_0000019fd2488a6e_1`;
- mandatory dry-run: 7,240,991,840 bytes; real query stayed below the 20 GiB hard cap.

| Insurer code | Valid SAP LIVE rows | Distinct valid DocEntry | Master rows | Passed |
|---|---:|---:|---:|---|
| 30 | 0 | 0 | 0 | no |
| 46 | 0 | 0 | 0 | no |
| 48 | 0 | 0 | 0 | no |
| 49 | 0 | 0 | 0 | no |

Therefore the current canonical SAP LIVE evidence cannot support adding or releasing any of these
codes. Existing `INSURER_NOT_IN_MASTER` holds remain correct. If “passed code” refers to another
SAP object or a mapped code rather than `U_InsurerCode` in `SAP_LIVE_FULL`, Aware/Boat must name
that source or mapping explicitly; do not infer it from the zero-result check.

No table, master row, hold, export, GCS object, scheduler, workflow, or SAP state was changed.
