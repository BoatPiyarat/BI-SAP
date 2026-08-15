# Daily SAP↔CareOS reconciliation MTD report — source-only deployment contract

Covers Boat's 2026-08-14 request: one daily step that reconciles SAP and CareOS and emails a
month-to-date summary every morning. The source does not authorize deployment, a trigger, a
mailbox change, or a BigQuery mutation.

**Status: corrective delta applied 2026-08-15 against Codex BLOCK
`docs/reviews/2026-08-14-ff1db18-codex.md`.** Re-review required before rehearsal/install.

## What it does
`sendDailyReconMtdReport()` reads the existing `recon_careos_charges` table (built by
`sp_recon_all_charges`, already inside the nightly `sap_state_and_recon_refresh` chain at 21:00
ICT — see `docs/AS_BUILT_V3.md`) and emails month-to-date counts/THB by `recon_status`
(`IN_SAP` / `MISSING_FROM_SAP` / `NO_ORDER_ITEM`), scoped to the correct Asia/Bangkok calendar
month with an explicit upper bound of "now". It performs no write and calls no mutating
procedure — read-only aggregation of an already-refreshed table, then one mail send.

The report refuses to send (fails closed, both queries throw before any mail call) if
`recon_careos_charges`' own `MAX(recon_checked_at)` for the current month is older than
`FRESHNESS_STALE_AFTER_HOURS` (15h) — it no longer just asserts freshness from the nightly-chain
schedule.

## Corrective delta vs. the BLOCKed version (2026-08-15)
Fixes items 1, 2, 5, and the Spec §1/§2/§3/§5 gaps from the BLOCK review, plus added tests:
1. ICT month boundary now converts via `TIMESTAMP(DATETIME, 'Asia/Bangkok')` semantics
   (`reconMtdIctMonthStart_`) instead of `TIMESTAMP(DATE)`, which BigQuery reads as UTC midnight
   (7h early) — was silently excluding 00:00–06:59 ICT on the 1st. Added an explicit `<= now` upper
   bound so future-dated rows can't enter MTD.
2. `buildReconMtdReport_()` now runs inside the same `try` as the primary mail send, so a
   BigQuery/API/JSON/unknown-status failure reaches the fallback recipient too, not just a
   mail-send failure.
3. `reconMtdQuery_` now polls `jobs.getQueryResults` on `jobComplete:false` (BigQuery's normal
   async response) instead of throwing, and paginates via `pageToken`.
4. Unknown `recon_status` values fail closed (throws `RECON_MTD_UNKNOWN_RECON_STATUS`) instead of
   being silently omitted from the three rendered rows — protects against schema drift.
5. Recipient distinctness now compares trimmed, lower-cased values.
6. Freshness gate described above (Spec §5).
7. `workflows/test_daily_recon_mtd_report.js` gained coverage for: correct month-boundary SQL,
   stale-data fail-closed, unknown-status fail-closed, async polling, pagination, recipient
   normalization, and report-build failures reaching the fallback (not just mail-send failures).

**Not fixed here — requires Codex's environment (flagged explicitly in the .gs header, not hidden):**
- Item 3 (live dry-run of the exact SQL): still blocked by the `bq` `ReauthUnattendedError` on this
  machine (`docs/INPUTS_NEEDED.md` "OPEN 2026-08-14 — `bq` CLI reauth..."). No `node` is available
  on this machine either, so the offline contract test below is untested by this delta — verify it
  actually passes before trusting it.
- Item 4 (exact runbook): no browser/authenticated `clasp` session available here. Runbook below is
  a template with placeholders `<...>` — Codex must fill in real values and capture real IDs, not
  treat the placeholders as done.

## Before deployment
Run the offline contract (mandatory — unverified by this delta, see above):
```powershell
node workflows/test_daily_recon_mtd_report.js
Get-Content -Raw -Encoding UTF8 workflows/daily_recon_mtd_report.gs | node --check -
```
Then a live dry-run of both queries in `buildReconMtdReport_` via `scripts/bq_safe_query.sh`
(needs the `bq` reauth fix first).

## Exact deployment runbook (Codex fills in `<...>` and keeps this file updated with real values)

1. **Script ID**: `<APPS_SCRIPT_PROJECT_ID>` — either the existing project backing
   `v3_daily_completeness_report.gs` (if sharing a deployment) or a new one; record which.
2. **Push source**: `clasp push` (or paste via the Apps Script editor) — record the exact deployed
   file hash/timestamp.
3. **Manifest/timezone**: confirm `appsscript.json` `"timeZone"` is `"Asia/Bangkok"` — the 06:00
   trigger fires against the *script's* project timezone, not the runner's. If the manifest is
   already `Asia/Bangkok` for the completeness report's project, no change needed; state that
   explicitly rather than assuming.
4. **Script Properties** (`clasp` or Apps Script editor → Project Settings):
   ```
   PROJECT_ID=pacific-plating-282708
   RECON_MTD_RECIPIENT=piyaratt@rabbit.co.th
   RECON_MTD_FALLBACK_RECIPIENT=data@rabbit.co.th
   ```
   (`BQ_DATASET` left unset — defaults to `sap_integration_v3`.)
5. **Rehearsal** (before installing any trigger) — see below.
6. **Install trigger**: time-driven, day timer, **06:00–07:00 window** (Apps Script triggers fire
   within their configured hour, not at an exact instant — state this in whatever confirms the
   install, don't claim "exactly 06:00"), function `sendDailyReconMtdReport`. Record the resulting
   trigger ID (`ScriptApp.getProjectTriggers()` after install).
7. **Rollback** (<5 minutes): `ScriptApp.getProjectTriggers().forEach(t => { if (t.getHandlerFunction() === 'sendDailyReconMtdReport') ScriptApp.deleteTrigger(t); })`
   run once in the Apps Script editor, or delete the specific trigger ID recorded in step 6 via
   the Triggers UI. No BigQuery or mail-recipient state needs cleanup — this step is read-only.

## Acceptance rehearsal (Codex, before enabling the trigger)
1. With real Script Properties set, call `sendDailyReconMtdReport()` manually once and confirm the
   primary recipient receives the MTD summary with plausible counts (cross-check one number against
   a manual `bq_safe_query.sh` query on `recon_careos_charges` for the same month, and confirm the
   reported freshness age is plausible for a nightly-refreshed table).
2. Force a primary-mail failure (e.g. temporarily invalid primary recipient) and confirm the
   fallback recipient receives the `[ACTION REQUIRED]` message and the function still throws
   (visible in Apps Script execution log).
3. Force a report-build failure (e.g. temporarily wrong dataset name) and confirm the fallback
   still fires — this is the delta's item 2 fix; the original BLOCKed version could not do this.
4. Only then install the 06:00–07:00 ICT trigger per step 6 above.

## Recipients (confirmed by Boat, 2026-08-14)
Primary `piyaratt@rabbit.co.th`, fallback `data@rabbit.co.th` — set as `RECON_MTD_RECIPIENT` /
`RECON_MTD_FALLBACK_RECIPIENT` Script Properties. See `docs/INPUTS_NEEDED.md` (resolved) for the
decision record. No further recipient input needed before deploying.
