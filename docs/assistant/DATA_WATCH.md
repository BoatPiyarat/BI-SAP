# DATA_WATCH — daily BigQuery health + KPI anomaly watch

Version 1 (2026-11-25). Query: `docs/assistant/data_watch.sql` (read-only, ~100 MB/run,
measured 2026-11-25 = 100,661,892 bytes). Run via the BigQuery connector
(`execute_sql_readonly`, dry-run first; stop if estimate > 1 GB — something changed).
Note: `scripts/bq_safe_query.sh` needs `bq` CLI credentials, which cloud sessions do not have;
the connector dry-run is the equivalent guard here.

Schedule: 07:47 ICT daily — after the 20:30 ICT extract and the ~21:00 ICT recon rebuild.

## Checks
| ID | Source | ALERT when | Why |
|---|---|---|---|
| H1 | `vw_dash_freshness` | SAP_LIVE last load date < yesterday (ICT) | extract didn't run |
| H2 | `vw_dash_export_pipeline_health` | yesterday 0 jobs or any failed | extract jobs failing |
| H3 | `recon_careos_charges.recon_checked_at` | > 30 h old (WARN) | recon not rebuilt → H4/K* stale |
| H4 | `recon_careos_charges` | any day D-7..D-3 with MISSING_FROM_SAP > 10% (WARN > 3%) | backlog into SAP |
| K1 | `recon_careos_charges` | D-2 paid charge count deviates > ±35% from avg of same weekday, 4 prior weeks | volume anomaly |
| K2 | `recon_careos_charges` | same for paid amount (THB) | value anomaly |

**All thresholds are initial estimates**, not business-confirmed. Derivation: H4 3%/10% from
the 2026-11-15..19 range (1.1%–2.6% observed); K ±35% because weekday volume varies widely
(279–1,588 charges/day observed 2026-11-04..24). Tune via `FEEDBACK_LOG.md`.

## Known caveats
- `vw_dash_freshness.status` says STALE every afternoon because `U_BatchRunDate` is
  date-granular (midnight UTC); H1 uses calendar-day lag instead.
- `sap_validation_error` / `sap_excluded_records` were last modified 2026-08-31 — not used as
  live signals until confirmed they are still refreshed.
- K uses D-2, not yesterday: yesterday is cut off at the ~21:00 rebuild.

## Alert format
Push only if any ALERT/WARN: `[DATA] H4 ALERT: MISSING_FROM_SAP 22 พ.ย. 21% | K1 OK`
(≤200 chars). Full table + one-line Thai interpretation + suggested next query in the run's
final message. Numbers must cite source table + query time (AGENT_RULES reporting rule).

## Never
- No DDL, no writes, no CALL, no scheduler changes, no GCS. Read-only only.
- Money/accounting impact found → describe it to Boat; do not notify anyone else.
