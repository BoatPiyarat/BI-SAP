# Daily SAP↔CareOS reconciliation MTD report — source-only deployment contract

Covers Boat's 2026-08-14 request: one daily step that reconciles SAP and CareOS and emails a
month-to-date summary every morning. The source does not authorize deployment, a trigger, a
mailbox change, or a BigQuery mutation.

## What it does
`sendDailyReconMtdReport()` reads the existing `recon_careos_charges` table (built by
`sp_recon_all_charges`, already inside the nightly `sap_state_and_recon_refresh` chain at 21:00
ICT — see `docs/AS_BUILT_V3.md`) and emails month-to-date counts/THB by `recon_status`
(`IN_SAP` / `MISSING_FROM_SAP` / `NO_ORDER_ITEM`). It performs no write and calls no mutating
procedure — read-only aggregation of an already-refreshed table, then one mail send.

Because the source table refreshes at 21:00 ICT the night before, a 06:00 ICT trigger the next
morning always reads same-night data — no dependency race with the nightly chain.

## Before deployment
Run the offline contract:
```powershell
node workflows/test_daily_recon_mtd_report.js
Get-Content -Raw -Encoding UTF8 workflows/daily_recon_mtd_report.gs | node --check -
```
(Not runnable in this session — no `node` on this machine. Codex must run both before deploying.)

Boat must approve and prove a primary recipient and an independent fallback recipient; they must
be different, and `data@rabbit.co.th` alone is insufficient (same rule as the completeness
report). Set Script Properties `PROJECT_ID`, `RECON_MTD_RECIPIENT`, `RECON_MTD_FALLBACK_RECIPIENT`
(optional `BQ_DATASET=sap_integration_v3`). Use the existing Apps Script BigQuery,
external-request, and send-mail scopes — same project as `v3_daily_completeness_report.gs`, can
share the same Apps Script deployment if convenient.

Install a **daily time-driven trigger at 06:00, script timezone `Asia/Bangkok`**, on
`sendDailyReconMtdReport`, only after review PASS and a scoped production approval per
`AGENT_RULES.md` (single deployer: Codex).

## Acceptance rehearsal (Codex, before enabling the trigger)
1. With real Script Properties set, call `sendDailyReconMtdReport()` manually once and confirm the
   primary recipient receives the MTD summary with plausible counts (cross-check one number against
   a manual `bq_safe_query.sh` query on `recon_careos_charges` for the same month).
2. Force a primary-mail failure (e.g. temporarily invalid primary recipient) and confirm the
   fallback recipient receives the `[ACTION REQUIRED]` message and the function still throws
   (visible in Apps Script execution log / any failure-notification wiring already in place).
3. Only then install the 06:00 ICT trigger.

## Recipients (confirmed by Boat, 2026-08-14)
Primary `piyaratt@rabbit.co.th`, fallback `data@rabbit.co.th` — set as `RECON_MTD_RECIPIENT` /
`RECON_MTD_FALLBACK_RECIPIENT` Script Properties. See `docs/INPUTS_NEEDED.md` (resolved) for the
decision record. No further recipient input needed before deploying.
