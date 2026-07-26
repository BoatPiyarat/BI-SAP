# 20_SAP_PROGRESS.md
Last Updated: 2026-07-26 (cont'd) - MASTER_INSURER_UNKNOWN + MASTER_PAYMENTDATE_LOCKED validation checks shipped and verified live; V3 backlog now clear except deferred Balance check (overwrite ได้ — สถานะปัจจุบันเสมอ)

---

## ✅ MASTER CHECKS (§2.6 #5) SHIPPED - LAST OPEN BACKLOG ITEM CLOSED — 2026-07-26 (cont'd)

Boat: "continue until the whole process complete." Closed the last remaining item from the V3
backlog (`020_extend_nightly_refresh_with_p2_p3.sql`'s validation layer, originally scoped to
PK_DUP + SCHEDULE_GAP only).

Built and shipped **`MASTER_INSURER_UNKNOWN`** and **`MASTER_PAYMENTDATE_LOCKED`** in
`017_sap_validation_error.sql` - directly motivated by TODAY's real SAP rejections (InsurerCode 29
not found; PaymentDate hitting a locked posting period). Both check the actual create/newpayment
candidate source tables (`sap_dashboard_carepay_fully_paid`, `sap_dashboard_carepay_installment`)
BEFORE a file gets generated, restricted to rows not already in SAP:
- InsurerCode check builds a "known good" master from `stg_sap_state`'s own history
  (`SPLIT(U_InsurerCode,'-')[OFFSET(1)]` - confirmed this transform matches the candidate tables'
  plain-numeric format, e.g. `VRY-27` -> `27`). Verified InsurerCode 29 (today's real failure) has
  zero matches anywhere in SAP history before shipping.
- PaymentDate check flags any candidate PaymentDate before the current accounting month.

Verified live via `CALL sp_run_validation()`: 24 real `MASTER_INSURER_UNKNOWN` rows (6 distinct
codes), 0 `MASTER_PAYMENTDATE_LOCKED` (sane baseline), PK_DUP/SCHEDULE_GAP unaffected (still 0).

**This closes the V3 build-out backlog from today's session except the Balance check (§2.6 #3),
which stays deliberately deferred** - tested twice against real data (~60% match, then worse after
adding Interest/Principle fields) and not shippable without a correct formula, which needs either
Aware/accounting input or a much deeper empirical sweep than time allowed today.

---

## ❌ BALANCE CHECK (§2.6 #3) FORMULA NOT VERIFIED - REMAINS DEFERRED — 2026-07-26 (cont'd)

Attempted to verify the design doc's formula (`TotalAmount = GrossPremium+StampDuty+VAT+WHT+TotalEIR+TotalSBT+fees-Discount`)
against real `stg_sap_state` data before building it as a blocking check. Result: only holds for
~60% of rows (775,142/1,291,581) at whole-dataset scale, despite matching perfectly on an initial
20-row sample - a reminder that small samples can look clean while missing the real pattern.
Mismatch concentrates in Motor (~46% mismatch) while most NonMotor groups (Life, Home, TA,
Personal Accident) are ~100% clean - not a period-1-vs-later-period split (checked, roughly even
mismatch in both). Mismatch amounts cluster around specific values (225, 177, 198, 236, 375, 219,
264, 207, 183, 465, 450, ...) rather than random noise, suggesting a genuine missing/extra term
specific to Motor, not measurement error.

**Tested one candidate fix**: adding `InterestThisPeriod + PrincipleThisPeriod + InterestEIRThisPeriod
+ PrincipleEIRThisPeriod` to the formula - made it WORSE (887,467 mismatches, up from 513,625),
meaning these fields are likely already reflected inside GrossPremium/TotalEIR rather than being
additional components - do not add them.

**Decision**: not shipping this check with a guessed formula - same discipline as the SCHEDULE_GAP
false-positive earlier today (verify or don't ship, don't guess into a blocking gate). Remains
deferred. Whoever revisits this needs either Motor-specific field documentation from
Aware/accounting, or a wider empirical sweep isolating exactly which Motor sub-population
(installment vs one-time? which fee combination?) drives the ~46% mismatch.

---

## ❓ RCB CREDIT-SHELL "PolicyStatus is duplicated" — 3 HYPOTHESES TESTED, ALL RULED OUT — 2026-07-26 (cont'd)

Boat's lead ("PolicyStatus duplicated means it exists on SAP as Paid") pointed at a shared-PolicyNo
conflict with the superseded (`old_human_id`) order. Tested this and two follow-up hypotheses
directly against real data, using `stg_sap_state` (properly deduped, unlike the earlier raw
`SAP_LIVE_FULL` attempt which returned misleading blank PolicyNo values):

1. **Shared PolicyNo with the old order, already Paid** - RULED OUT. Only 14 of the 41 old
   (`old_human_id`) orders even exist in `stg_sap_state` at all (the other 27 have no SAP record
   whatsoever for the old order); and searching SAP directly by the 27 PolicyNo values my backfill
   actually submitted found ZERO matches anywhere in `stg_sap_state` (which does have PolicyNo
   populated generally - 791,061/1,291,581 rows - so this isn't a systemically blank field).
2. **Race condition** (another process created these same order_items independently between my
   verification and SAP processing my file, like the earlier Motor newpayment 4-row race) - RULED
   OUT. None of the 41 `current_human_id` order_items exist in `stg_sap_state` even now, after the
   import.
3. **Duplicate PolicyNo within my own 41-row submission** (e.g. one policy referenced by two
   different order_items in the same file) - RULED OUT. Zero PolicyNo values repeat within the
   file.

**Not resolved**: what SAP's "PolicyStatus is duplicated" check is actually keying on remains
unknown from BigQuery alone - it isn't OrderItem, isn't the old order's PolicyNo, and isn't an
in-file duplicate. Likely checks something in SAP's own internal Policy master that isn't mirrored
in any table this project has access to. Needs either Aware's (the vendor's) input on what this
validation rule actually checks, or a different investigation angle (e.g. asking SAP support to
pull the specific existing record it's conflicting against) - not something to keep guessing at via
BigQuery queries alone. **Do not re-attempt this same 41-row export as-is** - whatever the real
conflict is, resubmitting the identical rows will hit it again.

---

## 📥 REAL IMPORT RESULTS: RCL CREDIT-SHELL SUCCEEDED, RCB CREDIT-SHELL MOSTLY BLOCKED — 2026-07-26 (cont'd)

Both Credit-Shell backfills (022/023) came back from SAP:

- **RCL Credit-Shell (37 rows, Upload LogID 21020)**: `Status: success` - all 37 rows imported clean,
  real SAP journal entry references created (`RCB-JE-InstallmentRCL1stPeriod`, `RCL-JE-InstallmentRCL`).
- **RCB Credit-Shell (41 rows, Upload LogID 21019)**: `Status: error` - nearly every row failed with
  `PolicyStatus: is duplicated` (one row, L80395333, also showed
  `PolicyStatus:In DB Status Cancelled not allow to interface`). One unrelated row (L79977888) failed
  separately on `InsurerCode: is not found in DB`. One row (L80346837) failed on
  `PaymentDate:Posting Periods must be Unlocked`.

**Root cause, confirmed by Boat**: "PolicyStatus duplicated means it exists on SAP as Paid." These
RCB Credit-Shell orders share their underlying PolicyNo with the superseded (`old_human_id`) order,
and that policy is ALREADY marked Paid in SAP via the old order's own record. My backfill tried to
create a fresh "Paid" record for the new (`current_human_id`) order under the same policy, which
SAP correctly rejects as a duplicate - **this means most of these 41 "gaps" were never actually
missing in the sense assumed**; the policy's Paid status already exists in SAP, just attached to the
old order_item id rather than the new one. Attempted a live query to verify this via shared
`U_PolicyNo` directly but it returned blank for both old/new order (likely because `SAP_LIVE_FULL`
has multiple period-rows per OrderID and the query grabbed an unfiltered one, not the canonical
row) - not yet re-run with a proper DISTINCT/period-aware query.

**Open, not yet resolved**: the correct interfacing model for Credit-Shell orders where the
underlying policy is already Paid is unclear - does SAP need a different flag/mechanism (e.g. an
OrderID reassignment on the existing record) rather than a fresh Paid insert under the new order_item?
This needs a proper design discussion, not another blind backfill attempt - re-submitting the same
41 rows as-is would fail the same way.

**The 2 other, unrelated errors triaged**:
- `L79977888` - `InsurerCode: is not found in DB` - submitted code `29` (Motor) has no matching
  entry in SAP's Insurer master (missing Vendor/Customer code mapping). A SAP-side master-data
  setup gap, not fixable from BigQuery - needs whoever manages SAP's Business Partner/Insurer setup
  to add code 29 properly.
- `L80346837` - `PaymentDate:Posting Periods must be Unlocked` - submitted `24062026` (June 2026),
  which is now a closed/locked accounting period. **Found a real gap in my own backfill scripts**:
  `009_fix_rcl_newpayment_date_override.sql`/`019_fix_column_reordering_bug.sql` already roll a
  stale PaymentDate forward to the start of the current month specifically to avoid this, but
  `022_backfill_rcl_creditshell_20260726.sql`/`023_backfill_rcb_creditshell_20260726.sql` never
  carried that same safeguard over. Not fixing this in isolation right now since the RCB
  Credit-Shell backfill's bigger blocker (PolicyStatus duplicate, above) needs a design decision
  first - flagging so the PaymentDate rollover gets added whenever that Credit-Shell backfill
  approach gets redesigned, not forgotten.

---

## ✅ CREDIT-SHELL BACKFILLS CLOSED; RCL CREDIT-SHELL AUTOMATION GAP FOUND — 2026-07-26 (cont'd)

Boat: "do backfill, make sure the new design will cover the missing daily. The timeout fix, give me
the script." Closed both halves of the 135-order Credit-Shell gap:

- **RCL Credit-Shell (37 rows)**: `RCL_Motor_process_4_creditshell` already exists and correctly
  identifies real candidates (confirmed live), but **the Motor Cloud Function's daily chain has no
  step for it at all** - the 6-step chain covers RCB create/cancel/change/creditshell + RCL
  create/newpayment, with RCL Credit-Shell simply never wired in. This is a structural automation
  gap, not a query bug - confirmed `RCL_Motor_process_1_create`'s exclusion of `current_human_id`
  is correct by design (it deliberately routes those orders to this dedicated view instead).
  Raw view output needed cleaning first: 129 rows, only 115 distinct (OrderItem, Period), 78 with
  null InvoiceNo. Deduped to 37 clean rows (`022_backfill_rcl_creditshell_20260726.sql`), exported
  to `gs://interface-file/RCB_MOTOR/INSURANCE_RCB_MANUALCLOSE_RCL_CREDITSHELL_20260726*.csv`.
- **RCB Credit-Shell (41 rows)**: identified earlier today but not yet exported before the
  investigation moved on. `RCB_Motor_process_4_creditshell`'s raw output also had duplicates (51
  rows, 41 distinct) - deduped preferring `PaymentChannel='RCB-Credit Shell'`
  (`023_backfill_rcb_creditshell_20260726.sql`), exported to
  `gs://interface-file/RCB_MOTOR/INSURANCE_RCB_MANUALCLOSE_RCB_CREDITSHELL_20260726*.csv`.

**Real-time confirmation the earlier Motor newpayment backfill worked**: SAP's actual import result
for `RCB_MOTOR_INSURANCE_RCB_MANUALCLOSE_NEWPAYMENT_GAP_20260726CORRECTED*.csv` (Upload LogID 21018)
came back "success with error" - only 4 of 268 rows flagged (`Period: Sequence of Period invalid`
for L78526086/L78560110/L78560667/L80313656). Checked directly: all 4 already show
`Period 1, Paid` in SAP with a real InvoiceNo - the regular daily production pipeline closed these
exact same gaps on its own between when I verified "missing" and when SAP processed my file hours
later. Harmless race, not a bug - **264/268 of the original backfill succeeded**.

**"Cover the missing daily" - two separate mechanisms, one still open**:
1. **Diagnostic visibility (delta_export)**: already fixed. Since `stg_schedule` now correctly
   includes `current_human_id` orders as normal schedule rows (see the stg_schedule fix above) and
   the nightly chain refreshes `expected_state`/`delta_export` automatically, any FUTURE Credit-Shell
   gap will show up as `MISSING_NO_ROW_IN_SAP` in tomorrow's refresh without anyone needing to
   re-run today's investigation from scratch.
2. **Actual daily export automation**: **still has a real hole** - the RCL Credit-Shell step needs
   to be added to `rcb-motor-order-payment-sap-bucket-1`'s script (alongside the timeout fix), or
   this same gap reaccumulates. This requires editing the function's deployed source, which is not
   something doable safely via CLI this session (same reachability issue as the timeout fix) -
   needs whoever owns that source repo to add a 7th step calling
   `RCL_Motor_process_4_creditshell`, with the same dedup logic used in 022 baked in (the raw view
   has real duplicate/null-InvoiceNo rows, so a naive direct export would reintroduce today's data
   quality problem daily).

**Timeout fix script delivered**: `scripts/fix_motor_function_timeout.sh` - uses the Cloud
Functions v1 REST API's `updateMask=timeout` partial update (not `gcloud functions deploy`, which
would try to rebuild from a local directory and risk replacing the function's real source). Asks
for confirmation before applying. Not yet run - hand-off to whoever has
`cloudfunctions.functions.update` permission on this function.

---

## 🚨 CLOUD FUNCTION ROOT CAUSE: rcb-motor-order-payment-sap-bucket-1 TIMES OUT DAILY — 2026-07-26 (cont'd)

Continued the ~2,022-order create-flow gap investigation (Boat: "keep going into the create-flow
root cause"). Found the actual GCS-writing mechanism: Pub/Sub topic
`motor-order-payment-sap-interface` (published by Cloud Scheduler job `sap-order-payment`, daily
01:30 ICT) triggers Cloud Function **`rcb-motor-order-payment-sap-bucket-1`** (asia-southeast1,
Python 3.12, 512MB, `entryPoint: extract_and_store`).

**This single function runs SIX BigQuery export steps sequentially in one invocation**, in this
order: `01_RCB_Motor_process_1_create` → `02_RCB_Motor_process_2_cancel_new` →
`03_RCB_Motor_process_3_change` → `04_RCB_Motor_process_4_creditshell` →
`05_RCL_Motor_process_1_create` → `06_RCL_Motor_process_2_newpayment` (the exact view fixed for
column-reordering earlier today). Configured timeout: **300s**.

**Confirmed via logs: this function has timed out every single day for the last 5 consecutive
days** (2026-07-21 through 2026-07-25), always killed at ~296-299s. Reading the logs chronologically:
steps 1-5 complete and confirm their GCS writes successfully within the first ~70 seconds every
day; step 6 (RCL newpayment) starts, logs its target filename, then the function is killed by the
300s timeout before it can confirm that file was written. (Before that, 2026-07-19/20 it was
crashing after only ~25-29s - a different, apparently since-resolved failure mode.)

**Implication for the create-flow gap**: since steps 1 (RCB create) and 5 (RCL create) DO complete
and write their CSVs successfully every day, "the create file never gets generated" is ruled out as
the cause of the ~2,022-order gap. Two possibilities remain, neither confirmed: (a) these specific
orders are being exported daily but SAP is silently rejecting them on import (nobody has been
watching CREATE-flow import results the way NEWPAYMENT was watched today), or (b) something
intermittently excludes them from the daily candidate set that I haven't found. Boat confirmed no
SAP import logs are available for the CREATE-flow files specifically, so this couldn't be resolved
further this session - **still open**.

**Timeout fix NOT applied**: attempted `gcloud functions deploy ... --timeout=540s` (540s is the
gen1 max) but the deployed source isn't reachable via CLI (no persistent `sourceArchiveUrl`, only a
one-time signed `sourceUploadUrl` from the original deploy; omitting `--source` makes gcloud try to
zip up the local working directory instead, which is wrong and was caught before doing anything
destructive). **Needs Boat or whoever has Cloud Console access to bump the timeout to 540s via the
Console's Edit UI** (a source-safe single-field change) - Boat approved this fix, just couldn't be
completed via CLI this session.

**Checked the NonMotor equivalent** (`rcb-nonmotor-order-payment-sap-bucket-1`, timeout 60s): runs
in a healthy ~33-37s on 6 of the last 7 days (status 'ok'). Only 2026-07-25 - the exact day of the
column-reordering incident and the RCL_HEALTH schema-drift fix - spiked to 59s and timed out. Looks
like a one-off tied to that day's real incident, not a chronic pattern like Motor's. Still worth
noting the margin is thin (60s limit vs ~35s typical runtime) if NonMotor's data volume grows.

---

## 🔧 CREDIT-SHELL CHAIN BUG FOUND AND FIXED IN stg_schedule — 2026-07-26 (cont'd)

While investigating the ~2,022 "never created in SAP" orders, Boat corrected a wrong hypothesis
(I'd found none were Credit-Shell by PaymentChannel) with the real semantics: **`careos.cancelled_change_orders`
identifies Credit-Shell change-order chains** - `old_human_id` is the superseded order (should
interface to SAP as `Cancelled (Change order)`), `current_human_id` is the real replacement order
(should interface as `Paid` with `PaymentChannel = "RCB Credit-Shell"`).

`012_stg_schedule.sql` had this **exactly backwards**: it excluded `current_human_id` (the real,
active order - ~20,249 order_items with real successful charges were invisible to the entire
V3 pipeline) and did NOT exclude `old_human_id` (the superseded order - ~25,009 order_items were
flowing through stg_schedule/expected_state/delta_export as if they were normal active schedules).

**Impact check before fixing further**: of the ~20,249 wrongly-excluded current_human_id items,
20,114 (99.3%) are already correctly in SAP via some other path (not the dedicated
`sap_integration_v2."04_new order credit shell"` view, which only covers 8,713 of them - most
went through the normal create flow). Only ~135 are genuinely missing from SAP - much smaller than
the raw exclusion count suggested. Not yet closed - flagged for the same backfill treatment as the
279-row Motor gap, pending confirmation these went through the "RCB Credit-Shell" channel
correctly wherever they did land.

**Caught contamination in the already-exported 279-row Motor newpayment backfill** (see prior
entry): 11 of those 279 rows were actually `old_human_id` (superseded) order_items - the bug meant
my reverification never excluded them. The exported file
(`gs://interface-file/RCB_MOTOR/INSURANCE_RCB_MANUALCLOSE_NEWPAYMENT_GAP_20260726*.csv`) had NOT
yet been pulled by the vendor's hourly process - removed the contaminated file and re-exported a
corrected 268-row version (`...20260726CORRECTED*.csv`, 161,160 bytes) before the next pull.

**Fixed** `012_stg_schedule.sql`: exclude `old_human_id` only (not `current_human_id`). Deployed,
ran the full nightly chain live: `stg_schedule`/`expected_state`/`delta_export` all at 1,462,333
rows (down from 1,465,025 - net effect of removing ~25k superseded rows and adding back ~20k real
ones, weighted by schedule length), `sap_validation_error` = 0 (both checks still clean).
`delta_export` category counts post-fix are sane (OK: 1,036,380; MISSING_NO_ROW_IN_SAP: 376,073;
NEEDS_PAID_UPDATE: 48,573; UNEXPECTED_ALREADY_PAID: 1,307) - no explosion, pipeline healthy.

**Not yet done**: `current_human_id` orders now flow through as normal schedule rows, but
`stg_schedule` still has no `PaymentChannel` field - if a future export step needs to specifically
emit `"RCB Credit-Shell"` for these, that's a real, separate gap (not yet built). The ~135 genuinely
missing current_human_id order_items still need their own backfill. The ~2,022-order create-flow
gap from earlier (dominated by ONETIME/FULL_PAYMENT, confirmed NOT Credit-Shell-related) is still
open and unresolved.

---

## 📤 MANUAL BACKFILL EXPORTED TO PRODUCTION — 2026-07-26 (cont'd)

Closed the confirmed, real subset of the missing-installment gap per Boat's direction ("list the
backfill and reverify, if it is real missing - use one of the production query to generate
interface and let's close the gap today"). Full reverification trail (see `021_backfill_motor_newpayment_gap_20260726.sql`):

- Of ~3,575 recent (2026) `MISSING_NO_ROW_IN_SAP` periods, 1,201 are still expected_status=Pending
  (not real gaps - SAP just hasn't reached them yet), 73 (all NonMotor) are Paid but have no
  resolved invoice_no yet (separate open issue), leaving 2,301 genuinely actionable rows.
- Of those 2,301, only 279 order_items already have an existing row in SAP (any period) - a real
  "newpayment gap" (order exists, one period never posted). The other ~2,022 have ZERO rows in SAP
  at all - the CREATE flow never ran for them, a much bigger and different problem, deliberately
  **excluded** from this backfill and flagged for separate investigation.
- All 279 are voluntary Motor items (TYPE_1/2_PLUS/3/3_PLUS) - zero MOTOR_TYPE_COMPULSORY, zero
  RCB-channel, zero cancelled orders.
- Row content sourced entirely from `sap_data_engineer.sap_dashboard_carepay_installment` - the
  SAME table the real, live `RCL 05_newpayment` view already uses for its financial breakdown
  fields (GrossPremium, interest/principal, etc.). Nothing invented - every value is
  already-computed CareOS data, confirmed present for all 279 target rows before use.
- Validated: 279/279 unique (order_item, period), all TransactionStatus=Paid, all have InvoiceNo,
  all PaymentDate in correct DDMMYYYY format, no null required fields. Schema matches the real
  production view's 56-column layout exactly (verified via INFORMATION_SCHEMA), built with the
  column-preserving `REPLACE` pattern (not `EXCEPT`+re-add) per the reordering-bug fix earlier
  today.

**Exported** (Boat confirmed naming just needs to contain "INSURANCE_RCB", rest is free text) to
`gs://interface-file/RCB_MOTOR/INSURANCE_RCB_MANUALCLOSE_NEWPAYMENT_GAP_20260726*.csv` (corrected
naming: template is `INSURANCE_RCB_<free text>`, not embedded mid-name - my first export used the
wrong prefix, Boat corrected it, file was renamed to match, same 167,411 bytes/content) - confirmed
landed via `gsutil ls`. This will be picked up by the vendor's normal hourly pull - **watch
tomorrow's import log to confirm all 279 rows import clean** (same log location as the
column-reordering incident).

**Staged in BigQuery** (not yet cleaned up): `sap_integration_v3.manual_close_20260726_motor_newpayment_gap`
- kept for reference/audit until the import is confirmed clean.

**Not done**: the ~2,022 orders with zero SAP rows need their own root-cause investigation (why
did CREATE never run?) before any file can be generated for them - a create-flow gap, not a
newpayment gap, and likely much higher stakes given the volume.

---

## 🔌 P2/P3 WIRED INTO NIGHTLY CHAIN — 2026-07-26 (cont'd)

Boat asked directly: will the existing production process detect and close the ~1,900-3,500 missing
installments (orders with a real successful charge in CareOS that never got exported to SAP)? Tested
this empirically instead of guessing - joined the recent (2026-only) `MISSING_NO_ROW_IN_SAP` rows
from `delta_export` against the actual `RCL_Motor_process_2_newpayment` / `RCL_NonMotor_process_2_newpayment`
views (the queries that really generate the nightly interface files). **Answer: no.** Of ~3,575
genuinely-recent missing periods, only ~205 (~6%, Motor only) would surface if production ran again;
**0% of NonMotor missing periods and 0% of MOTOR_TYPE_COMPULSORY missing periods would be caught** -
the legacy per-flow queries are a forward-looking "what's newly payable today" feed, not a diff
against reality, so they cannot self-heal a historical gap. This is exactly why `delta_export` was
built.

Boat's direction based on this: (1) wire the new P2/P3 refresh into the nightly chain so the gap is
tracked going forward, (2) reverify the missing list and manually close today's backfill using a
production query, after validation.

**Done**: `sp_nightly_state_and_recon_refresh` (021, see 008/014 history) extended to call
`sp_refresh_expected_state` -> `sp_run_validation` -> `sp_refresh_delta_export` after the existing
P1 staging + `stg_sap_state` + recon refresh (order matters: expected_state needs stg_schedule/
stg_payment_events refreshed first; delta_export needs both expected_state AND stg_sap_state).
Deployed and run live end-to-end: `expected_state` and `delta_export` both landed at 1,465,025 rows
(consistent 1:1), `sap_validation_error` = 0 (PK_DUP and SCHEDULE_GAP both clean). This closes the
"wire into nightly schedule" item that had been open since P2/P3 were first built.

**Not done yet**: this only refreshes the diagnostic tables nightly - it does NOT write any file to
`gs://interface-file/`. Boat's "put everything in the bucket" ask is the next step, gated on
validating the reverified missing list first (in progress) - per CLAUDE.md's hard rule, nothing
gets written to that bucket without passing validation first, no exceptions.

---

## ✅ SCHEDULE_GAP VALIDATION CHECK: ROOT-CAUSED AND RE-ENABLED — 2026-07-26

Picked back up the previously-disabled SCHEDULE_GAP check (see `sql/ddl/017_sap_validation_error.sql`)
while root-causing the column-reordering incident above, since both involved re-verifying BigQuery
query behavior. Ran a sequence of minimal reproductions directly against BigQuery (not guessed at)
to isolate the exact trigger:

- Ruled out, in order: procedure-vs-script execution context, UNION ALL combining, `CLUSTER BY` on
  the destination table, and the destination table already holding rows from the PK_DUP check -
  each was tested in isolation and still reproduced (or didn't reproduce) independent of the real
  bug.
- **Actual root cause**: the old SCHEDULE_GAP query computed `COUNT(DISTINCT period)` and
  `MAX(total_periods)` TWICE - once inside the SELECT list's CONCAT (building the `detail` message)
  and again in the HAVING clause. When this query ran in the same script *after* another
  aggregation query (exactly the real shape: PK_DUP's CREATE OR REPLACE TABLE, then SCHEDULE_GAP),
  the duplicated aggregate expressions caused the HAVING filter to stop filtering, returning
  ~728,736 rows instead of the correct 0. Isolated with a minimal repro: the same query selecting
  only `order_item` (no duplicate aggregates in SELECT) was clean; adding the CONCAT with the
  aggregates back in reproduced the bug immediately, independent of everything else.
- **Fix**: compute each aggregate exactly once via a CTE, then reference the already-materialized
  columns in both the SELECT list and the filter (`WHERE` on the CTE, not `HAVING` on raw
  aggregates). Never repeat an aggregate expression across SELECT/HAVING in a query that runs after
  another aggregation query in the same script/procedure - this project's validation and export
  queries are exactly this shape (nightly chain, sequential steps), so this is now a standing
  pattern to avoid, not a one-off.
- **Verified live**: deployed the fix, called the real `sp_run_validation()` stored procedure
  end-to-end, `SCHEDULE_GAP` now returns 0 rows - matches every order checked by hand as clean.
  Re-enabled (previously commented out).

---

## 🚨 URGENT INCIDENT: SELF-CAUSED PRODUCTION BUG FOUND AND FIXED — 2026-07-26

Boat shared real SAP import error logs from the night of 2026-07-25/26. Multiple files failed
identically: `Conversion failed when converting the nvarchar value 'X' to data type int` - a
whole-file bulk-insert rejection, no field name or row number. This hit both my NonMotor backfill
chunks AND, critically, **that night's real, regular, automated NonMotor RCL newpayment production
file** - a file this session never touched directly, but which reads from a view this session DID
modify earlier that same day.

**Root cause, identified by Boat directly** ("this is interface column, I know the root cause.
Your backfill file reordering column") after he shared the real SAP destination interface schema:
the PaymentDate override fix from earlier (`009_fix_rcl_newpayment_date_override.sql`) used
`SELECT * EXCEPT(PaymentDate), <expr> AS PaymentDate FROM base`. In BigQuery, `* EXCEPT(col)`
followed by re-adding that column as a new expression **moves it to the end of the output** - it
does not preserve the original column position. Since SAP's import is column-position-based (not
header-name-based, now confirmed), this silently shifted every column after PaymentDate's real
slot by one, eventually landing a decimal value in an Int-typed destination column
(Period/TotalPeriods) - exactly matching the error. **My own earlier fix, deployed to the real
production views that day, is the very likely cause of that night's real automated NonMotor import
failure** - not a pre-existing data-quality issue as first assumed.

Two wrong hypotheses were chased and dropped before the real cause surfaced: (1) GrossPremium/VAT
fractional values (disproven - near-universal across historically-successful rows, so can't be
fatal); (2) an extraneous `ExpectedReceived` column not in SAP's schema (a draft fix,
`019_remove_expectedreceived_column.sql`, was built but never deployed, then deleted once Boat
corrected the diagnosis).

**Fixed** (`019_fix_column_reordering_bug.sql`, committed `758ce99`): replaced with
`SELECT * REPLACE(<expr> AS PaymentDate) FROM base` for both `RCL_Motor_process_2_newpayment` and
`RCL_NonMotor_process_2_newpayment` - `REPLACE` overwrites a column's value without moving it.
Verified via `INFORMATION_SCHEMA.COLUMNS`: PaymentDate back at its correct position (45 of 56),
immediately before Period/TotalPeriods. Row-count sanity check post-fix: Motor view = 647,345 rows,
matching expected scale - fix didn't break anything else.

**Also fixed in the same pass** (unrelated schema drift hit while redeploying): external table
`sap_data_engineer.RCL_HEALTH` gained an `InsuranceProduct` column since this view last deployed
successfully earlier that same day, breaking the NonMotor view's `sap`/`interface` UNION ALL column
count (55 vs 56). Added `InsuranceProduct` (from `SAP_LIVE_FULL`'s `U_InsuranceProduct`) into the
`sap` CTE in the correct position.

**Lesson for this pipeline going forward**: `SELECT * EXCEPT(col), new_expr AS col` silently
reorders columns in BigQuery and must never be used for anything that feeds a
column-position-based downstream import (i.e. anything in this pipeline) -
`SELECT * REPLACE(new_expr AS col)` is the only safe way to override a column's value in place.

**Not yet done / needs Boat's input:**
- Confirming this actually fixes tonight's real import - won't know until the next nightly cycle
  produces a fresh log.
- Whether/how to re-attempt the 44-file backfill now that the underlying bug is fixed - this exact
  backfill has now failed twice for two different reasons, so re-running it automatically without
  asking felt like the wrong call given it writes real files to `gs://interface-file/`.
- The other real production errors visible in the same pasted logs (PolicyStatus duplicated,
  InsuranceGroup/InsurerCode not found in DB, Period sequence invalid, various Cancelled-order
  rules) - read but not yet triaged; likely pre-existing data-quality issues, separate from this
  bug.

---

## 🏗️ P2 ENGINE + P3 DELTA_EXPORT BUILT — 2026-07-25 (cont'd 9)

Continued "start building" P1-P3 per Boat's "skip to next tasks you can do without my new input."
Auth expired mid-session (gcloud token), Boat re-authenticated, work resumed cleanly - nothing lost.

**P2 built, all three real bugs caught by checking real data before trusting output:**
- **`fn_invoice_no`** (`015_fn_invoice_no.sql`) - single UDF implementing the resolved B1 standard
  (raw `third_party_id`, no prefix). Every future create-flow query should call this instead of
  writing its own CONCAT/prefix logic.
- **`expected_state`** (`016_expected_state.sql`) - the L3 engine, joins stg_schedule +
  stg_payment_events into "what SAP should show." **Bug #1 caught**: `charges.id` (UUID) and
  `charges.third_party_id` (real InvoiceNo source) are different fields - stg_payment_events
  originally only captured `id`. Fixed before expected_state was built on top of it. **Bug #2
  caught**: compulsory items' charges all get attributed to their voluntary sibling by the
  item_rank de-fanout, leaving compulsory items permanently "Pending" even when SAP shows Paid -
  fixed via order-level "any successful charge on this transaction" recognition, gated on
  `motor_item_type = 'MOTOR_TYPE_COMPULSORY'` (not `flow` - a compulsory item can route to
  ONETIME too, a narrower first fix missed those). **Bug #3 caught**: a single (order_item,
  period) can have multiple SUCCESSFUL charges (verified: one period had 10 retry charges) -
  fixed via dedup to the earliest charge per period.
- **`sap_validation_error`** (`017_sap_validation_error.sql`) - PK_DUP check is live and clean (0
  errors after the dedup fix). **SCHEDULE_GAP check disabled** - genuinely unreliable, not yet
  root-caused (identical HAVING logic gives 0 rows as a plain SELECT but 728,745 rows via the
  stored procedure, reproduced even after splitting a suspected UNION ALL interaction into two
  sequential steps). Flagged for future investigation, not guessed at further.

**P3 started - `delta_export`** (`018_delta_export.sql`, §2.7 L5): diffs `expected_state` against
`stg_sap_state` at (order_item, period) grain - the modern successor to the 3-bucket
`recon_careos_charges` model. **Cross-validated against the earlier, independently-built recon**:
after excluding pre-2026 historical noise (259,396 rows from 2023 alone - the exact same
historical-scope trap the recon already learned to avoid), genuinely-recent
`MISSING_NO_ROW_IN_SAP` is 1,909 - close to the ~1,963 found completely independently earlier this
session via the ad-hoc recon table. Two very different construction methods converging on
basically the same number is a strong signal both are finding the same real thing, not an
artifact of either approach.

Not yet built: actual file generation (delta_export identifies what should change, but nothing
writes a CSV from it), balance/master validation checks (§2.6 #3/#5 - deferred, no verified
formula yet), Credit Shell's recursive schedule (still excluded from stg_schedule entirely),
2026-scoping convenience view for delta_export (currently includes all-history noise, same as
raw stg_schedule/expected_state - by design, for future reusability, but needs a scoped view for
practical day-to-day use).

---

## 🏗️ P1 BUILT: STAGING LAYER LIVE, WIRED INTO NIGHTLY SCHEDULE — 2026-07-25 (cont'd 8)

Boat: "start building" the actual V3 architectural rebuild (P1-P3) - everything before today
patched the old per-flow queries in place, none of the new staging/engine/delta-export design had
been built. Also: "you can start next phase without waiting me. anything need confirmation you can
skip to other tasks" - proceeding autonomously, flagging anything genuinely undecided rather than
guessing or blocking.

**Two open V3 decisions resolved by Boat first:**
- **B1 InvoiceNo standard**: raw `third_party_id`, no prefix, for anything new. Existing `2_`
  prefix stays untouched wherever `newpayment`/`cancel` mirror an already-existing SAP record
  (immutable once set). Checked the real create-flow source
  (`sap_data_engineer.sap_dashboard_carepay_installment`) - already compliant, no code change
  needed, just documents the standard (CLAUDE.md updated).
- **A1 CREDIT_CARD_INSTALLMENT routing**: "remains the same, only change to Onetime(RCB)" -
  confirms exactly what §2.4's router table already proposed (TotalPeriods=1, bank pays in full).
  Baked directly into `stg_schedule`.

**P1 (§2.2/§2.3) - three staging tables, all live and verified against real data:**
- **`stg_order_dim`** (`011_stg_order_dim.sql`) - materializes the ~15 `JSON_VALUE(orders.data,
  ...)` extractions once per order_item instead of every one of the 8 daily interface queries
  repeating them from scratch (D2 - the heaviest CPU cost in the pipeline per the design doc's own
  audit). Field mappings copied verbatim from the real production source, not reinterpreted.
  `sp_refresh_stg_order_dim()` MERGEs only orders whose `update_time` changed. Verified: 755,231
  rows, matches expected order_item count.
- **`stg_schedule`** (`012_stg_schedule.sql`) - the "spine": one row per (order_item, period),
  driven by real transactions, not follow_ups/snapshot presence (fixes A3, A4). Encodes the
  confirmed router: CREDIT_CARD_INSTALLMENT/FULL_PAYMENT/unknown -> ONETIME (TotalPeriods=1),
  RABBIT_CARE_INSTALLMENT + MOTOR_TYPE_COMPULSORY -> RCL_CMI (TotalPeriods=1),
  RABBIT_CARE_INSTALLMENT + not compulsory -> RCL (TotalPeriods = GREATEST-of-3-signals formula,
  fixes A5). **Caught before building**: the design doc's router table names a `RABBIT_LENDING`
  payment_option for the compulsory case - checked real data first, this value doesn't exist
  (only FULL_PAYMENT/RABBIT_CARE_INSTALLMENT/CREDIT_CARD_INSTALLMENT/PAYMENT_OPTION_UNKNOWN are
  real) - built on the actual, already-verified motor_item_type split instead of the doc's stale
  text. Verified: `L78115086-V1` shows exactly 6 periods, matching real SAP data. 876,723 RCL rows/
  140,420 orders, 554,920 ONETIME rows/orders (1:1 as expected), 33,405 RCL_CMI rows/orders (1:1).
  **Not yet handled**: Credit Shell's recursive/pool schedule - flagged as a real gap, not guessed
  at (orders in `cancelled_change_orders` are currently excluded from the spine entirely).
- **`stg_payment_events`** (`013_stg_payment_events.sql`) - the actual charge-driven population
  source (successful charges only). Reuses the item_rank de-fanout fix (compulsory vs voluntary
  item on a bundled charge) already verified live in `sp_recon_all_charges`, so every future
  consumer inherits the fix instead of re-discovering it. Verified: 1,189,734 rows, 1:1 with
  distinct charge_id (no fan-out duplication).

**Wired into the existing schedule, no new schedule needed** (`014_extend_nightly_refresh_with_
p1_staging.sql`): extended `sp_nightly_state_and_recon_refresh` (already running daily 21:00 ICT)
to refresh all three P1 tables before the existing SAP-state/recon refresh - matches decision #5's
own preference ("ต่อท้าย extract 20:30 ทั้งเส้น" - append one chain, don't stand up a second).

**Next (P2, in progress)**: `fn_invoice_no` UDF (implements the resolved B1 standard as reusable
code), the L3 `expected_state` engine (joins the three staging tables into what SAP *should* show),
and `sap_validation_error` (the blocking-validation output sink) - none of these exist yet.

---

## ✅ BACKFILL CORRECTED + RE-PUSHED, CHUNKED — 2026-07-25 (cont'd 7)

The first backfill (below) violated the real RCL interface rule, which Boat clarified after the
fact: **"when you want the new period payment change from pending to paid - you need to interface
the full periods starting with the old paid (on SAP) together with new payment period and
anything unpaid is remain pending."** The first attempt scoped by `(order_item, period)` against
`MISSING_FROM_SAP`, which stripped out each order's already-Paid anchor period and still-Pending
tail periods - sending a fragment of an order's state instead of its full, self-consistent picture.
Boat: "no need to pull back... SAP will reject it anyway, malformatted file" - confirmed correct,
the files were already gone (pulled) by the time this was caught, nothing to undo.

**Fix**: `010_rcl_backfill_full_period_chunked.sql` - `sp_backfill_rcl_newpayment_chunked(run_label,
n_chunks_motor, n_chunks_nonmotor)`. Scopes by whole `OrderItem` (any order with >=1 currently-
missing period), then pulls that order's **complete** period range from the unmodified production
view - Paid periods keep their real invoice, unpaid periods stay Pending. Chunks via
`MOD(ABS(FARM_FINGERPRINT(OrderItem)), N)` so every period for a given order always lands in the
same file - chunking can never split one order's periods across two files, which would reintroduce
the same violation. Verified directly: `L78115086-V1`'s all 6 periods (1 Paid anchor, 2-5 newly
Paid, 6 still Pending) landed together in the same chunk (`chunk_id=1`).

Boat also asked to split the backfill into smaller files (first attempt was one 36,917-row/20.5MB
file). Re-scoping to full-period-per-order naturally grew the row count (as expected - it's no
longer just the gap, it's every affected order's complete history) to 135,607 Motor rows / 20,530
orders and 13,577 NonMotor rows / 1,590 orders. Chunked into 40 Motor files (~1.7-2.0 MiB each) and
4 NonMotor files (~1.2-1.3 MiB each) - 44 files total, ~78 MiB combined.

**Pushed live** via `EXPORT DATA` to a temp wildcard path per chunk, then renamed to match the
production filename convention with a `_chunkN` suffix:
- `gs://interface-file/RCB_MOTOR/INSURANCE_RCB_06_RCL_MOTOR_PROCESS_2_NEWPAYMENT_20260725_chunk{0..39}.csv`
- `gs://interface-file/RCB_NONMOTOR/INSURANCE_RCB_04_RCL_NONMOTOR_PROCESS_2_NEWPAYMENT_20260725_chunk{0..3}.csv`

Confirmed live in the bucket 2026-07-25 ~13:30-13:36 UTC (~20:30-20:43 ICT - already evening in
Bangkok, so this satisfies "run it one time tonight" without needing to wait further). Audit
tables kept: `sap_integration_v3._backfill_rcl_{motor,nonmotor}_newpayment_20260725b`.

Not yet confirmed whether SAP's import scans a folder for *all* matching CSVs (like the daily
Cloud Function's own 8 distinctly-named files coexisting in the same folder, which is a working
precedent) vs a single hardcoded filename per process-type - the `_chunkN` suffix is a reasonable
bet given that precedent, but only the follow-up check (below) will confirm it was actually picked
up and processed rather than silently skipped.

**Next check (not yet done)**: same as below - query `SAP_LIVE_FULL` for these OrderItem+Period
pairs tomorrow to see whether they flipped to Paid. If yes: confirms this really was our bug
(stale PaymentDate + malformed partial submissions), not SAP's posting-period lock. If the specific
periods pushed in *this* corrected run still don't flip, but the *previous* malformed run's periods
also didn't flip, that at least isolates the malformed-submission theory from the date-override
theory as two separate, now both-tested fixes.

---

## 🚀 ONE-TIME BACKFILL PUSHED LIVE (FIRST ATTEMPT - LATER CORRECTED ABOVE) — 2026-07-25 (cont'd 6)

Boat: "Let's do backfill one time. import all unsuccess interface files I'm pretty sure it is our
side" - then, after reviewing, pinpointed the likely bug himself: "the current
RCL_Motor_process_2_newpayment / RCL_NonMotor_process_2_newpayment logic of payment date... it can
be only in current month. If the actual payment date on charge table is older than current month
you can override to 1st date of current month."

**Fix applied first** (`009_fix_rcl_newpayment_date_override.sql`, live in `sap_view`): wrapped
both views with `CASE WHEN PARSE_DATE(PaymentDate) < DATE_TRUNC(CURRENT_DATE(), MONTH) THEN
FORMAT_DATE(..., DATE_TRUNC(CURRENT_DATE(), MONTH)) ELSE PaymentDate END` - any PaymentDate older
than the current month gets bumped to the 1st of the current month, keeping every post inside
SAP's currently-open posting period (matches the "Posting Periods must be Unlocked" error from the
real SAP log). Row selection logic untouched - verified count stable (646,400 -> 646,402, just
real-time drift) before/after.

**Backfill scoped deliberately narrow**: not the full 646K/14.6K row query output (most of that is
harmless daily re-assertion of already-correct state) - joined against
`recon_careos_charges WHERE recon_status = 'MISSING_FROM_SAP' AND period > 1` (the confirmed real
gap only). Materialized to `sap_integration_v3._backfill_rcl_motor_newpayment_20260725` (36,917
rows) and `_backfill_rcl_nonmotor_newpayment_20260725` (3,758 rows) - left in place as an audit
trail of exactly what was pushed, not cleaned up.

**Pushed live via BigQuery `EXPORT DATA`** (not the Cloud Function - bypasses its 512Mi/300s
resource limits entirely, which is itself plausibly why the daily automated run silently fails to
finish writing files this large - 646K rows is a lot for a naive Python per-row CSV loop within a
300s Cloud Function timeout, though not confirmed):
- `gs://interface-file/RCB_MOTOR/INSURANCE_RCB_06_RCL_MOTOR_PROCESS_2_NEWPAYMENT_20260725.csv` (36,917 rows, 20.5 MiB)
- `gs://interface-file/RCB_NONMOTOR/INSURANCE_RCB_04_RCL_NONMOTOR_PROCESS_2_NEWPAYMENT_20260725.csv` (3,758 rows, 1.5 MiB)

Filenames match the exact production convention (`INSURANCE_RCB_{process_name}_{YYYYMMDD}.csv`) so
SAP's normal 15-minute pull picks them up like any other file - no special handling needed on
SAP's side. **Confirmed live in the bucket 2026-07-25 ~13:07 UTC (~20:07 ICT).**

**Not covered by this backfill**: the ~1,795 period-1 (first-ever-payment) periods that get no
export at all from either `_process_1_create` or `_process_2_newpayment` today - a structurally
different, still-unfixed gap (see the ROOT-CAUSED entry below).

**Next check (not yet done)**: verify tomorrow whether these 40,675 periods actually flip to Paid
in `SAP_LIVE_FULL` - `SELECT COUNT(*) FROM sap_integration_v2.SAP_LIVE_FULL s JOIN
sap_integration_v3._backfill_rcl_motor_newpayment_20260725 b ON s.U_OrderItem = b.OrderItem AND
s.U_Period = b.Period WHERE s.TransactionStatus IN ('Paid','paid')` (and same for NonMotor). If
they flip: confirms this was genuinely our bug (stale dates + maybe function timeout), not SAP's
posting-period lock as originally suspected. If they stay Pending: the lock is real and deeper
than a date fix, or the Cloud Function timeout theory needs checking directly.

---
Overall: ~78% | โหมดปัจจุบัน: **P0 A2 fix ครบทั้ง 8 views แล้ว (live)** — **stg_sap_state ตอนนี้ auto-refresh
ทุกวัน 21:00 ICT แล้ว** (เดิม stale ค้างมาตั้งแต่ 07-24, ไม่เคยมี schedule) — **MISSING_FROM_SAP (48,429
periods) root-caused: 99.98% ไม่ใช่ order หาย - SAP มี row Pending รออยู่แล้ว ขาดแค่ invoice/payment step
(= RCL automation gap ที่เจอก่อนหน้านี้) - ห้าม backfill แบบ "create" เพราะจะซ้ำซ้อน order เดิม** —
dead-man's-switch deploy จริงแล้ว (BQ scheduled query 22:00 ICT ทุกวัน + failure email) — Looker Studio
dashboard views (4 views) พร้อมใช้ — รอ Attila แก้ scheduler IAM (401, ล่ม 3 คืน) — secret rotation:
ตามคำสั่ง Boat ไม่ rotate ตอนนี้

---

## 🔍 MISSING_FROM_SAP ROOT-CAUSED: NOT A BACKFILL PROBLEM — 2026-07-25 (cont'd 4)

Boat, before authorizing any backfill: "check SAP_LIVE_FULL or raw to have actual records on SAP"
— and separately, on scope: "you can pull data from SAP all the missing doc entry I don't mind
other BU eg. B2B will come out, rather have it 100% better than guess." Both checks done before
touching anything that writes toward real SAP. Both changed the picture.

**B2B exclusion: real, but currently a non-issue.** `SAP_LIVE_FULL` (sap_integration_v2) hardcodes
`WHERE U_InsuranceGroup <> 'B2B'` in all 4 unioned branches (confirmed live via
`bq show --view`). Built `sap_integration_v3.SAP_LIVE_FULL_ALL_BU` (`007_sap_live_full_all_bu.sql`)
— identical view (same DocEntry-partition dedup, same column mapping), minus that filter, so
recon/state work never has to guess at BU scope again. Verified: **0 rows with
`U_InsuranceGroup = 'B2B'` exist in the raw source tables right now** — the filter is dead code
today, not hiding anything. Left the ALL_BU view live for the future since it costs nothing and
matches Boat's "don't guess" instruction.

**`stg_sap_state` was stale — this was the real distortion, not B2B.** Built once
(`002_sp_refresh_sap_state.sql`, 2026-07-24) and **never scheduled anywhere** — checked every
transfer config in the project, confirmed none call `sp_refresh_sap_state`. Comparing the 48,993
`MISSING_FROM_SAP` periods directly against raw `SAP_LIVE_FULL` found 584 that already had a real
`Paid` status + invoice in current raw data, but still showed a month-old `Pending`/no-invoice
snapshot in `stg_sap_state`. Refreshed it live, re-ran recon: `MISSING_FROM_SAP` 48,993 → 48,429.
Built `sp_nightly_state_and_recon_refresh` (`008_schedule_state_recon_refresh.sql`), scheduled
daily 21:00 ICT with failure email, so this can't go stale again — also directly serves Boat's
goal #2 ("make the job cover all transaction (recon) - auto").

**The real, current, verified split of the 48,429 (checked directly against fresh raw
`SAP_LIVE_FULL`, not just `stg_sap_state`):**
- **48,420 (99.98%, ~107M THB) already have a row in raw `SAP_LIVE_FULL`** — status `Pending`,
  no invoice. SAP already knows these orders exist. This is **not** a missing-order problem — it's
  the RCL invoice/payment step never running (the automation gap found earlier tonight, see below).
  A "create" backfill for these would risk **duplicating orders SAP already has**. The correct fix
  is the missing RCL payment-export automation, not a backfill.
- **9 periods (~16K THB) are a "Paid then Cancelled" edge case in the recon model itself**, not a
  real gap — genuinely paid (real invoice), then legitimately cancelled later. The 3-bucket recon
  model (IN_SAP/MISSING_FROM_SAP/NO_ORDER_ITEM) has no bucket for that, so they land in
  `MISSING_FROM_SAP` even though nothing is wrong. Consistent with Boat's "Paid→Cancelled is final"
  rule. Negligible — not worth adding a 4th bucket for 9 rows.
- **0 periods have zero row in SAP at all**, checked directly against raw `SAP_LIVE_FULL`. There is
  currently no genuine "SAP never heard of this order" case in the 2026 scope.

**Bottom line: there is no safe "backfill" action to run right now.** Every real gap in this number
is the missing RCL export automation, already scoped below. Building that closes ~107M THB /
48,420 periods safely, because it only ever adds the missing *payment* record to an order SAP
already has — it never creates a new order, so no duplicate-order risk. Still not attempted without
Boat's explicit go-ahead, per the stakes noted below.

## 📊 LOOKER STUDIO DASHBOARD VIEWS BUILT — 2026-07-25 (cont'd 3, AFK fallback task)

Built `006_dashboard_views.sql` (4 views in `sap_integration_v3`), Boat's explicitly-authorized AFK
fallback ("if you have nothing to do then go prepare data for dashboard Looker studio data
source"). Connect Looker Studio directly to these (BigQuery connector, project
`pacific-plating-282708`, dataset `sap_integration_v3`) — each is pre-shaped for one chart, no
Looker-side transforms needed:
- `vw_dash_completeness` — daily/payment-option/gap-category breakdown, for a funnel or backlog-
  by-flow chart. Verified live: 1,189 rows, 213,579 total periods across all rows.
- `vw_dash_completeness_summary` — single-row KPI tile. Verified live: 76.03% completeness
  (162,384 IN_SAP / 213,579 total) as of this build.
- `vw_dash_export_pipeline_health` — real `EXTRACT`-type job history (the real export mechanism
  found tonight, not `EXPORT DATA` SQL text), 90-day window. Verified live: real daily job counts,
  e.g. 2026-07-24 showed 6 successful extracts.
- `vw_dash_freshness` — wraps `vw_dead_mans_switch`. Verified live: FRESH, 26h since last load.

Not built: Page 3 "Correctness" from `SAP_DASHBOARD_DESIGN_v1.md` — needs `sap_validation_error`,
which doesn't exist yet (P2 territory).

---

## 🔒 ROOT CAUSE FOUND: SAP POSTING-PERIOD LOCK — 2026-07-25 (cont'd 5)

Boat asked me to sample one stuck installment in detail (`L78115086-V1`: created 2026-01-29 with
6 periods, period 1 Paid at creation, periods 2-6 left Pending by design). CareOS showed periods
2-5 actually paid on 2026-04-16 / 05-14 / 06-09 / 07-03 - all still Pending in SAP with a real
DocEntry assigned since January. Confirmed via `INFORMATION_SCHEMA.JOBS_BY_PROJECT` that the
correct "mark this period Paid" query has run via the automated Cloud Function every single night
for 10+ days straight (18:30 UTC daily) and already computes the right InvoiceNo/PaymentDate/
status - so the export side has been doing its job correctly the whole time.

Boat then shared a real SAP import error log (`import_20260716-163056018.txt`, an
`INSURANCE_RCB_CANCEL` batch from 2026-07-16, confirmed "job submitted in correct validation to
SAP"). It reveals the actual mechanism: **SAP's own accounting posting-period lock.**
Recurring errors across hundreds of rows:
- `PaymentDate:Posting Periods must be Unlocked,PaymentDate:RCL Posting Periods must be Unlocked` -
  SAP refuses any transaction dated into an already-closed accounting period, permanently, until
  someone unlocks that period on the SAP side. This is a standard SAP B1 accounting control, not a
  bug - but it means once a period closes, our correctly-generated nightly "mark Paid" row for that
  period will keep failing forever, silently, with no retry ever succeeding.
- `InvoiceNo: Cannot change InvoiceNo when status Paid,Cancelled` - SAP refusing to touch InvoiceNo
  on anything already Paid/Cancelled (matches the existing "InvoiceNo immutable" hard rule).
- `PolicyStatus: Cancelled order first period in DB must be Status Paid before` - SAP won't allow
  cancelling an order unless period 1 is already Paid in its own DB - directly compounds the
  ~1,960 period-1-never-invoiced orders found earlier: those can't even be cleanly cancelled later.

**Conclusion: this is not a BigQuery/export/query problem at all.** The interface file has been
correct and complete every night. The block is entirely SAP's own posting-period lock policy -
squarely Aware's territory per the hard rule ("SAP-side import program - Aware owns these").
Also explains why some orders DO progress fine (99,599 order-items found earlier with genuinely
sequential Paid dates) vs others permanently stall: whether the relevant posting period happened
to still be open when the payment was first attempted.

**Not yet done**: drafting the Aware escalation with this evidence (the channel failure-rate
breakdown + the `L78115086-V1` sample + this error log). Open question for Boat: does Aware/SAP
finance periodically reopen old posting periods, or is there a policy for how far back RCL
payments can post before being permanently rejected? That would clarify whether the ~46,420
stuck periods are recoverable at all without a posting-period reopen, or genuinely lost to this
lock.

---

## 🎯 REAL EXPORT MECHANISM FOUND — 2026-07-25 (Boat AFK, "fix missing from SAP" request)

Boat asked to fix the `MISSING_FROM_SAP` gap (48,993 order-periods, ~108M THB in 2026), run a
one-time backfill, and add it to the pipeline. Before touching anything that writes toward real
SAP, traced how `gs://interface-file/` (the bucket SAP actually pulls from hourly) really gets
fed - this had never been verified all session; every fix so far touched query *logic*, not the
actual export step.

**Found the real chain, finally**: Cloud Scheduler (`sap-order-payment` /
`sap-order-payment-non-motor`, confirmed healthy earlier tonight) → Pub/Sub topics
(`motor-order-payment-sap-interface` / `non-motor-order-payment-sap-interface`) → Cloud Functions
(`rcb-motor-order-payment-1` → `rcb-motor-order-payment-sap-bucket-1`, same 2-stage pattern for
NonMotor and ADB Motor) → `gs://interface-file/{RCB_MOTOR,RCB_NONMOTOR,ADB_MOTOR}/`. Confirmed via
real `EXTRACT`-type BigQuery jobs (not `EXPORT DATA` SQL - a different job type, missed on first
search): 61 extracts in the last 7 days, most recent hours before this check. **This pipeline is
alive and running regularly.** The bucket looking "empty" just now is the same ephemeral-file
pattern found earlier tonight for the bronze zone - files get pulled and consumed quickly, not a
sign of failure.

Along the way, also found (and ruled out as the actual export path) an **older, separate,
already-broken** pipeline: BigQuery scheduled queries `SQ_SAP_2025_new_create_order` /
`_cancelled_order` / `_credit_shell` / `_cancelled_change_order`, writing into
`SAP.SQ_sap_daily_order_payment`, refreshed by `truncate_sap_order_payment_table`. These use the
*old* non-RCL-prefixed views (`04_new order credit shell`, `03_cancel change orders`, etc.), not
tonight's `sap_view.RCB_Motor_process_*`. `SQ_SAP_2025_new_create_order`'s transfer config state is
literally `FAILED`, last touched 2026-06-17 - over a month stale. Not investigated further since
it's confirmed not the live path; flagged as another dead pipeline worth cleaning up eventually.

**The real finding, and it changes the whole picture**: there is **no equivalent automated export
for RCL (installment) at all** - checked the complete Cloud Functions list, nothing named
rcl-anything exists. RCB Motor, RCB NonMotor, and ADB Motor each have a real 2-stage
scheduler→function pipeline; RCL has nothing. This isn't a new discovery - it's exactly problem
**A7** from `SAP_INTERFACE_REDESIGN_V3.md` ("RCL flows ไม่มี daily scheduler... ทั้งสาย RCL เป็น
manual"), now empirically confirmed against real infrastructure rather than taken on faith. It
directly explains why `RABBIT_CARE_INSTALLMENT` was ~70% (34,434 of 48,993) of the
`MISSING_FROM_SAP` recon: **it's not a bug scattered across many queries - it's one missing piece
of automation.**

**Did not attempt the actual fix** (generate + push a real RCL export to `gs://interface-file/`,
or build new export automation) while Boat is AFK. This would be the single most consequential
action possible in this entire pipeline - it creates real records SAP will import - and:
1. There's no established RCL bucket-folder convention to follow (unlike RCB_MOTOR/RCB_NONMOTOR/
   ADB_MOTOR, which are established patterns)
2. A one-time backfill of 34,434 periods needs validation-stage review first (hard rule: "never
   bypass validation before export, no exceptions including urgent") - haven't built/wired
   sp_validate for this yet
3. This needs Boat's own review before anything real ships to SAP, full stop

**What's ready for Boat's decision, not yet built**: extending the RCB pattern to RCL - a new
Pub/Sub topic + Cloud Function (or reusing `sap_view.RCL_*` process views, already fixed/verified
tonight, as the source query) + a new Cloud Scheduler job, matching the existing 3-flow pattern.

## ✅ POLICY CONFIRMED + RECONCILIATION EMAIL SENT — 2026-07-25

**Boat's rule, confirmed**: once an order shows Paid periods then Cancelled in SAP, that's final -
never modify it. This resolves the open design question from the `stg_sap_state` repoint work
above - the 5 reverted `sap_view` views don't need "fixing," their current behavior (treat any
Cancelled-order signal as "leave alone") is already correct. What was actually needed instead was
a **reporting mechanism**, not automated correction.

Built `sql/adhoc/reconcile_careos_vs_sap_cancelled_installments.sql`: for cancelled installment
(RCL) orders, compares CareOS's real paid-period count against SAP's. Key finding while building
this: a cancel-send mirrors **every** period to `TransactionStatus = 'Cancelled'` (verified live,
e.g. `L78210940-V1` - all 6 periods show Cancelled regardless of real history) - so current status
can't tell you what was actually paid before cancellation. `U_InvoiceNo` can: it's only populated
once a period was actually invoiced, so "non-empty invoice among Cancelled periods" = "was paid
before cancellation." Credit Shell orders (`U_OrderID LIKE 'C#%'`) excluded - different
single-invoice-on-period-1 pattern, would otherwise look like hundreds of false positives.

**Results**: 1,072 cancelled installment orders checked, 85 mismatches. 58 are off by exactly 1
period - almost certainly the customer's last payment landing at/around cancellation time, not a
real gap. **6 show a genuine 2+ period gap** (up to 5 periods missing) - these are real and worth a
look: `L73727249`, `L74670396`, `L76394133` (5 periods each), `L73400356`, `L73683565`,
`L76993090` (2 periods each).

**Sent as a Gmail draft** to `rc_sap_interfaceresult@rabbit.co.th` (no direct-send tool available,
by design - draft is ready for Boat to review and send). Purely informational per the policy above -
no SAP/CareOS data touched.

---

## 🔥 IN-FLIGHT

1. **Cancel batch 21 items** — ตก 3 รอบ (root cause สุดท้าย: SAP เก็บหลาย doc ต่องวด + InvoiceNo ต้องตรง doc ปัจจุบัน)
   → v4 พร้อม (one-row-per-period, Paid priority) แต่**รอคำตอบ Aware Q3a ก่อนยิง** (spec inferred ส่งแล้ว)
   → ⚠️ business flag: ลูกค้าจ่ายงวดต่อหลัง CareOS cancel — รอ FA confirm intent (cancel+refund?)
2. **RCL new-payment quick fix (27 orders)** — หลักใหม่จาก Boat: **charge-driven full schedule**
   (charge ถึงงวดไหน เติม paid ถึงงวดนั้น, mirror งวดเดิมเป๊ะ InvoiceNo ห้ามแตะ) — query v3 พร้อม รอ sample run
3. **EDC batch 2 (~70 orders จาก list บัญชีชุด 2)** — รอบัญชี confirm channel mapping ธนาคารอื่นนอกจาก KBANK
4. **Secret Manager rebind + password rotation** — ⚠️ ค้างตั้งแต่ 16/07! plaintext ยังอยู่ใน job config
   และ password exposed แล้ว 2 ครั้ง — สถานะ: secret sap-db-password ยังไม่มี version, ขั้นตอนอยู่ใน chat/runbook

## ⏳ WAITING ON OTHERS

- Aware: confirm cancel import spec v0.9 (ส่งแล้ว — โดยเฉพาะ Q3a: หลาย doc ต่องวด อ้าง InvoiceNo ตัวไหน)
- บัญชี: (a) EDC channel matrix (b) Credit Shell = จ่ายครบงวดเดียว OK? (c) intent 21 cancel ที่จ่ายต่อหลังยกเลิก
- IT Leong: Credit Shell ไม่มี installment_details = by design หรือ bug + ขอ direct RCL field (ถามใน group แล้ว)
- Head of Products: COALESCE fix (INCIDENT-001) — ใช้ targeted ไปแล้ว 1 เคส (L80347249-M1 เข้า SAP 22/07)

## ✅ DONE เพิ่มจาก 16/07

- Scheduler self-trigger verified (20:30 ICT, SA sap-bucket-csv@) — Phase 6 automation ครบฝั่ง extract
- เจอ loader B1 = `auto_load_sap_data_in_bucket_to_bigquery` (Pub/Sub 01:00) → อธิบาย incident 07-14
- **ROOT CAUSE ใหญ่: SAP_LIVE/SAP_LIVE_FULL = stale mirror** (mirror comparison 23/07 ยืนยัน INVOICE_DIFF)
  → DECISION: raw_sap_live คือ SAP truth เดียว, sunset B1 (ดู 10_CONTEXT)
- Urgent batches เข้า SAP: 30 EDC + L80347249-M1 + L79189867-1 (self-resolved) + cancel 1 (L80391648-M1)
- EDC gap วินิจฉัยครบ: CREDIT_CARD_INSTALLMENT ไม่มี pipeline เจ้าของ (ตกร่อง 2 flow) — เจอ 2 list รวม ~100 orders
- InvoiceNo convention conflict ยืนยัน: '2_' prefix (BI, กัน collision) vs raw charge id (flow 21/07)
- **Design package v3 ครบ 6 ฉบับ** (REDESIGN / E2E / DATA_PREP / RUNBOOK / DASHBOARD / CANCEL_SPEC) — รอ review/decisions
- Delta-export gap ใน design ถูกจับได้จาก review ของ Boat (new payment Pending→Paid) → amend แล้ว + generalize เป็น charge-driven

## 🚧 P0 STATUS (2026-07-24 session — reauth done, verified against live BigQuery)

- ✅ `sap-interface-repo` ตั้งจริงแล้ว (local git, branch `p0/stg-sap-state`) ที่
  `.../02 SAP/Phase1.1/agentic_bootstrap/codex_bootstrap`
- ⚠️ **CORRECTION ใหญ่: `raw_sap_live` ไม่มีอยู่จริง** — Phase 6 B2 extract job ไม่เคย deploy จริงใน
  project นี้ (เป็นแค่แผนใน design docs) — Boat ยืนยัน: **`sap_integration_v2.SAP_LIVE_FULL` คือ SAP
  source จริงที่ใช้อยู่ตอนนี้** ตรงข้ามกับ hard rule เดิมใน AGENTS.md/CLAUDE.md ("SAP truth = raw_sap_live
  ONLY") ที่เขียนไว้ก่อนเช็คจริง — ต้อง**แก้ hard rule นี้ในสองไฟล์นั้นด้วย** (ยังไม่ได้แก้)
- ✅ Verified `SAP_LIVE_FULL` จริง (schema 56 คอลัมน์ ดึงมาแล้ว, ดู view definition ใน
  `sql/production/SAP_LIVE_FULL.sql`): union SAP_LIVE + SAP_LIVE_2024/2025/2026, dedup ด้วย DocEntry
  (ROW_NUMBER by BatchRunDate DESC) — แต่**ยังมี duplicate ที่ (U_OrderItem, U_Period) 328,071 keys
  (687,700/1,649,468 แถว = ~42%)** เพราะ dedup แค่ระดับ DocEntry ไม่ใช่ระดับ period — ตัวอย่างจริง:
  L73340138-V1 period 2 มีทั้งแถว Paid (DocEntry 750141) และ Cancelled (DocEntry 1005571) — ตรงกับ
  CANCEL_IMPORT_SPEC Q3a เป๊ะ
- ✅ TransactionStatus จริง: Paid 1,087,891 / Pending 432,840 / Cancelled 90,489 /
  Cancelled (Change order / Rejected) 38,248 — ตรงกับที่ design assume ไว้พอดี
- ✅ `sql/ddl/002_sp_refresh_sap_state.sql` — **แก้แล้ว** ให้ source จาก `SAP_LIVE_FULL` แทน
  `raw_sap_live`, dedup by (U_OrderItem, U_Period) priority Cancelled>Paid>Pending — ยังไม่รัน
  (ต้อง approve ก่อน — สร้าง dataset+ตารางใหม่ ไม่กระทบของเดิม)
- ✅ `sql/ddl/003_...` — **แผนเดิม (repoint SAP_LIVE_FULL) ตกไป** เพราะ SAP_LIVE_FULL คือ source จริง
  ไม่ใช่ mirror เก่าที่ต้องแทนที่ (ทำแบบเดิมจะ circular) — เช็คจริงแล้วพบว่ามีแค่ 2 consumer ที่แตะ
  SAP_LIVE_FULL (fully_paid's `sap_batchrun`, credit shell's `sap_cancelled`) และทั้งคู่ทำแค่
  `MAX(BatchRunDate)` ต่อ OrderID — **ไม่โดน duplicate bug จริง** (MAX กันซ้ำในตัวอยู่แล้ว) — เป็นแค่
  cleanup ไม่ใช่ live bug
- ✅ **A2 NULL-safe filter bug — ยืนยันจริง, แก้จริง, LIVE ใน BigQuery ทั้ง 8 views แล้ว (2026-07-24):**
  พบ `motor_item_type != 'MOTOR_TYPE_COMPULSORY'` แบบไม่กัน NULL ใน **9 views จริง** — เช็ค `sap_view`
  (12 views, nightly จริง) แยกต่างหาก: **สะอาด** เจอแค่ 1 จุดที่ใช้ `=` (safe) ไม่ต้องแก้
  ยืนยันด้วยข้อมูลจริง: `careos_order_items.motor_item_type` มี NULL 10,559 แถว ทุกแถวเป็น NonMotor
  → **Applied จริงแล้วทั้ง 8 views** (`CREATE OR REPLACE VIEW`, bq CLI, location asia-southeast1),
  ทุกตัวแถวเพิ่มขึ้น ไม่มีลดลง = ไม่มี regression:
  - `sap_dashboard_carepay_installment`: 631,487 → 665,388 (+33,901)
  - `RCL 04_new order credit shell`: 13,894 → 14,379 (+485)
  - `RCL 02_items_cancel`: 633,470 → 667,377 (+33,907)
  - `RCL 04_new order credit shell_all`: 51,884 → 52,696 (+812)
  - `RCL 04_new order credit shell new tunning`: 56,818 → 57,405 (+587)
  - `sap_fix_rcl_2025`: 2,625 → 2,759 (+134)
  - `sap_fixing_rcl`: 929,641 → 963,609 (+33,968)
  - `RCL_MOTOR`: 929,641 → 963,609 (+33,968, identical to sap_fixing_rcl — likely same underlying query,
    confirms these two are redundant copies of each other; not consolidated, Boat said fix + leave as-is)
  Boat's call: fix all 8 (not just the 2 confirmed-production ones), leave everything else about these
  files untouched (no consolidation of the redundant copies).
- ✅ **`sap_integration_v3.stg_sap_state` — สร้างจริงแล้วใน BigQuery** (dataset + `pipeline_run_log`
  ผ่าน `001`, proc `sp_refresh_sap_state` ผ่าน `002`, รันแล้วผ่าน `CALL`)
  → 1,649,468 แถวใน SAP_LIVE_FULL → **1,289,839 แถวหลัง dedup, 0 duplicate key เหลือ** (verified)
- ⏸️ **Secret rotation — Boat's call: keep it, don't rotate now.** Deferred, not forgotten.

## 🆘 NEW INCIDENT (found while rechecking scheduler health, 2026-07-24)

**Symptom**: `sap-extract-schedule` (Cloud Scheduler, fires 20:30 ICT daily, on time every night) —
the HTTP call it makes to trigger `sap-extract-job` fails every night with `401 UNAUTHENTICATED`.
Confirmed via Cloud Logging for 2026-07-22, 07-23, 07-24 — **3 nights running**. The Cloud Run job
executions that DID exist (05:40, 17:09, 01:17, 17:03, 03:53 UTC — all off-schedule) were someone
manually running `gcloud run jobs execute sap-extract-job` by hand to compensate, not the automation
working. `auto_load_sap_data_in_bucket_to_bigquery` (the B1 loader, Pub/Sub-triggered, 01:00 ICT) also
shows extra off-schedule triggers on the same days — consistent with the same person manually
re-running the downstream loader too after manually running the extract.

**Root cause**: `gcloud run jobs get-iam-policy sap-extract-job` returns an **empty policy** — the
`sap-bucket-csv@...` service account (the one Cloud Scheduler uses for its OIDC token) has no
`roles/run.invoker` binding on this job. It was granted 2026-07-15 (see 30_SAP_CHANGELOG.md) but is
gone now — never diagnosed why (redeploy resetting IAM? manual revert? not investigated further).

**Fix** (prepared, NOT applied — `data@rabbit.co.th` got `PERMISSION_DENIED` on `run.jobs.setIamPolicy`,
this needs someone with IAM admin on the project, i.e. Attila per 90_TEAM_CONTEXT.md):
```
gcloud run jobs add-iam-policy-binding sap-extract-job \
  --region=asia-southeast1 --project=pacific-plating-282708 \
  --member="serviceAccount:sap-bucket-csv@pacific-plating-282708.iam.gserviceaccount.com" \
  --role="roles/run.invoker"
```

**Other SAP scheduler jobs checked, all healthy** (blank status = success in Cloud Scheduler logs):
`sap-order-payment` (01:30 ICT), `sap-order-payment-non-motor` (01:30 ICT),
`auto_load_sap_data_in_bucket_to_bigquery` (01:00 ICT) — all firing on schedule, no errors.

**Lesson**: nobody noticed for 3 nights because someone was quietly running it manually - the "dead
man's switch" the design docs proposed (Page 1 / 22:00 alert) would have caught this on night one.
Worth prioritizing that alert.

## 🗺️ REAL ARCHITECTURE DISCOVERED (2026-07-24) — supersedes design docs' B1/B2 framing

While investigating the "is SAP_LIVE_FULL missing records" question, traced the actual live pipeline
end to end. It does **not** match REDESIGN_V3/10_SAP_CONTEXT's B1 (legacy CSV, sunset) vs B2 (Phase 6,
target `raw_sap_live`) story:

- `sap-extract-job` (Cloud Run Job, pyodbc → real SAP SQL Server `RCB_LIVE_DB`) genuinely runs, genuinely
  pulls real rows (confirmed via its own run logs, e.g. 47,888 rows in one run), and writes NDJSON to
  `gs://rcb-bronze-zone/SAP/production_database/`
- That GCS write triggers (Eventarc) the Cloud Run **service** `sap-order-payment-initial-phase`, which
  loads the rows into **`sap_integration_v2.SAP_LIVE`** and deletes the source file
- So **`SAP_LIVE` is the real, fresh, direct-from-SAP-DB table** — not a legacy stale mirror. It's been
  running since 2026-07-09, 14/14 runs SUCCESS, zero errors, watermark current to within ~15 min as of
  this session. `raw_sap_live` (the name in every design doc) was never built - the docs describe a plan,
  not what got deployed.
- `gs://sap-bucket-csv` (the vendor CSV-drop bucket the docs describe) **does not exist in this project.**
- Practical implication: the scheduler incident above is more serious than "a redundant legacy path
  stalled" - it's the only ingestion path into fresh `SAP_LIVE` data. Data is fine because people have
  been running it manually; it would go stale if that stopped.

**Docs to eventually reconcile** (not done yet): 10_SAP_CONTEXT.md's B1/B2 section, REDESIGN_V3's
target architecture diagram, and the 2026-07-23 changelog's "SAP_LIVE_FULL = stale mirror" root-cause
entry all describe an architecture that isn't what's actually running.

## 🔍 sap_view COMPLETENESS AUDIT (2026-07-24) — "no CareOS charge silently dropped" check

Boat asked to verify the new `sap_view` production process (12 views: RCB/RCL × Motor/NonMotor ×
create/cancel/change/creditshell/newpayment) doesn't silently drop records. Pulled and read all 12,
plus 5 more upstream dependencies not yet examined this session (`04_new order credit shell`,
`03_cancel change orders`, `02_items_cancel`, `1_nonMotor_new order`, `2_nonMotor_items_cancel` -
distinct from the `RCL 04...`-prefixed ones already A2-fixed).

**Found and fixed**: `RCB_NonMotor_process_1_create` had `interface.OrderDate LIKE '%2025%'` hardcoded
into its WHERE clause. Since the anti-join against `SAP_LIVE_FULL` already restricts results to
"not yet in SAP," this date filter was pure leftover, not load-bearing - and it meant **every 2026-dated
NonMotor Health/Travel one-time order was silently excluded from ever being proposed for SAP creation**.
The view had been producing **zero rows for months** (checked: 0 before fix). Confirmed against real
data before fixing: ~3,097 `RCB_HEALTH` rows dated 2026, of which 91 were genuinely absent from SAP
(most of the rest apparently got there via manual intervention). Fixed (deleted the filter line),
applied live: **0 → 95 rows** now surfaced.

**Everything else checked out clean**: the other 11 `sap_view` views either have no date restriction or
an already-open-ended one (e.g. `RCL_Motor_process_4_creditshell` already says
`OrderDate LIKE '%2025%' OR LIKE '%2026%'` - will need `%2027%` added eventually, not urgent). The 5
additional dependency views checked for the A2 NULL-unsafe pattern - all clean.

**Not done**: a full formal reconciliation (charge-driven expected population vs. combined output of
all 12 views) - what's been done is a targeted read-through + spot-check, which is how this specific
bug was found. A full reconciliation would be a bigger, separate piece of work if more assurance is
wanted later.

## ✅ DEAD-MAN'S-SWITCH — deployed 2026-07-24

Built and deployed (see `sql/ddl/004_dead_mans_switch.sql`):
- `sap_integration_v3.vw_dead_mans_switch` — freshness check on `SAP_LIVE.U_BatchRunDate`
  (excludes ~5 anomalous future-dated rows found earlier, which would otherwise always read FRESH)
- `sap_integration_v3.sp_check_dead_mans_switch` — RAISEs if stale >26h
- BigQuery scheduled query "sap_dead_mans_switch", daily 15:00 UTC (22:00 ICT).
- **Recipients (settled)**: Boat asked for piyaratt@rabbit.co.th + rc_bi@rabbit.co.th. BQDTS native
  failure-email only supports one recipient (owner, data@rabbit.co.th) — left that on as a backup,
  added a real multi-recipient path via Cloud Monitoring: log-based metric
  `sap_dead_mans_switch_failure` → alert policy `SAP dead-man's-switch failure`
  (alertPolicies/2008919338975126785) → 2 email channels. **Verified end-to-end**: forced a test
  failure, confirmed via Monitoring API that the metric ingested it, reverted immediately. **Boat
  confirmed the test alert email actually arrived** — fully closed, nothing else to check here.

## 🔎 sap_view 6-OTHER-VIEWS USAGE CHECK — answered 2026-07-24

Checked 180-day BigQuery job history (query text, not just referenced_tables — that field only
captures underlying base tables for view queries, not the view name itself) for the 6 A2-fixed
views not on Boat's confirmed-production list:
- `RCL 04_new order credit shell_all` — used 2026-07-20 (4 days ago) by **you**
- `RCL 02_items_cancel` — used 2026-07-01 by **you + suphakornh@rabbit.co.th**
- `RCL_MOTOR` — used 2026-05-03 (~3 months ago) by you
- `RCL 04_new order credit shell new tunning`, `sap_fix_rcl_2025`, `sap_fixing_rcl` — **zero
  queries found in 180 days** — genuinely dead, candidates for eventual archival (not done, no
  action needed now — the A2 fix already applied to them is harmless either way)

## 🕵️ WHY THE IAM BINDING WAS MISSING — investigated 2026-07-24 (not a "disappeared" mystery)

Checked Cloud Audit Logs (60-day window) for every `SetIamPolicy` call referencing `sap-extract-job`.
Found exactly 2, both **DENIED**:
- 2026-07-13, via Cloud Shell (interactive) — someone (very likely Boat) already tried this exact
  `gcloud run jobs add-iam-policy-binding ... --role=roles/run.invoker` fix 11 days ago and hit the
  same `PERMISSION_DENIED` I hit tonight
- 2026-07-24 (tonight), my own attempt, same error

No successful `SetIamPolicy` call on this resource exists in the audit trail at all. Cross-checked
against the *working* pipeline (`sap-order-payment-initial-phase`, via Eventarc) - its trigger uses
`919786098205-compute@developer.gserviceaccount.com` (the project's default Compute service account,
likely with broad pre-existing permissions), **not** `sap-bucket-csv@...`. So this isn't a binding
that regressed - it most likely **never successfully applied in the first place**. The 2026-07-15
changelog entry ("Granted (Attila/DevOps): roles/run.invoker + roles/secretmanager.secretAccessor...
→ แก้ blocker scheduler self-trigger") most likely refers to the Secret Manager grant (which clearly
did work - the job successfully reads its DB credentials every run) - the `run.invoker` half appears
to have never gone through, silently, because whoever ran it (Boat, then me) lacked
`run.jobs.setIamPolicy` themselves. The pipeline "worked" anyway because everyone's been triggering
it manually with their own broader account permissions, which masked the scheduler-specific gap.

**Implication for Attila's fix**: this isn't "restore what was lost" - it's "grant this for the first
time," and it specifically requires his account (IAM Admin), not yours or mine.

## ⚠️ stg_sap_state REPOINT ATTEMPT — 2026-07-25 (partial success, one real bug caught + fixed)

Boat: wire `stg_sap_state` into real consumers instead of reading `SAP_LIVE_FULL` directly. Attempted
this across all 11 `sap_view` process views that reference `SAP_LIVE_FULL` (all of them except
`RCL_Motor_process_2_newpayment`, which doesn't touch it at all).

**Found two genuine, pre-existing bugs first** (unrelated to the repoint, hit while dry-running):
`RCL_Motor_process_3_cancel` and `RCL_NonMotor_process_2_newpayment` both reference
`U_EndorsementNo`, which doesn't exist (`SAP_LIVE_FULL`/`stg_sap_state` only have `EndorsementNo`,
no `U_` prefix) - **both queries wouldn't even parse**. These two views were completely broken
before tonight, silently. Fixed the column name in both (real bug fix, independent of source table).

**Repointed and verified 5 views as genuinely safe** (pure existence checks - "does this OrderItem
exist in SAP at all," no status filter - dedup can't change these results, confirmed by exact
zero row-count delta before/after): `RCB_NonMotor_process_1_create`, `RCL_NonMotor_process_1_create`,
`RCB_Motor_process_3_change`, `RCB_Motor_process_4_creditshell`, `RCB_NonMotor_process_2_cancel`.
**These are live on `stg_sap_state` now.**

**Caught a real bug before it did damage**: `RCB_Motor_process_create`'s row count jumped
1,579 → 16,578 after repointing - way too large to wave through. Sampled the new output: every row
was an order that had been **Paid, then later Cancelled**. `SAP_LIVE_FULL` kept both the historical
Paid row and the Cancelled row (its dedup is only by DocEntry), so this view's
`WHERE TransactionStatus IN ('Paid','paid')` check could still find "was this ever paid" evidence.
`stg_sap_state` collapses to one row per (OrderItem, Period) with Cancelled beating Paid by design -
so the same check now says "never paid," and the view wrongly proposed recreating 14,999
already-cancelled orders in SAP. **This would have been a real, damaging bug shipped straight into
the create-export pipeline if the count jump hadn't been sanity-checked.**

Given that, treated every non-zero-delta view as equally suspect (not just the confirmed one) and
**reverted 5 views back to `SAP_LIVE_FULL`**, since I couldn't verify their semantics were safe at
this hour with no one available to check: `RCB_Motor_process_create`, `RCL_Motor_process_1_create`,
`RCB_Motor_process_2_cancel_new`, `RCL_Motor_process_4_creditshell`, `RCL_Motor_process_3_cancel`
(this last one keeps its `EndorsementNo` fix - net improvement from completely-broken to working,
just on the original source). `RCL_NonMotor_process_2_newpayment` also stays on `SAP_LIVE_FULL`
(same `TransactionStatus IN Paid` risk pattern found in its `newpayment` CTE) with just its
column-name fix applied - went from broken to working.

**Net result**: 2 previously-broken views now work; 5 views now correctly deduped; 4 views
untouched in effect (reverted to their original behavior) pending a properly-designed fix. Verified
every final count against BigQuery directly before stopping - not just trusting the local files.

**What "properly-designed" would need**: any view that checks a specific status (e.g. "IN Paid") to
mean "already settled" needs a source that preserves *history*, not just current dominant status -
either keep reading `SAP_LIVE_FULL` for that specific check, or build a different dedup that
preserves "has ever been X" alongside "is currently X." Don't just swap the FROM clause on these 5
without that design work.

## ⬜ NEXT

1. **Get Attila to run the `run.invoker` fix** — active incident, 3+ nights and counting. Per the
   investigation above, this is a first-time grant, not a restore - only he can do it (you and I both
   confirmed lacking `run.jobs.setIamPolicy` ourselves)
2. ~~Investigate why the run.invoker binding disappeared~~ — **done above**
3. Decide dead-man's-switch email recipient (data@ vs personal vs Slack) — **done: piyaratt@ + rc_bi@ + data@, verified delivered**
4. Reconcile 10_SAP_CONTEXT.md / REDESIGN_V3.md architecture sections against the real pipeline found
   this session (SAP_LIVE fed by sap-extract-job → sap-order-payment-initial-phase, not B1/B2 as written)
   — **done, 2026-07-24**
5. Consider archiving the 3 genuinely-dead views (`RCL 04...new tunning`, `sap_fix_rcl_2025`,
   `sap_fixing_rcl`) — not urgent
6. **Design a real fix for the 5 reverted `sap_view` views** (see section above) before attempting the
   `stg_sap_state` repoint on them again - needs actual business input on what "already in SAP" should
   mean once an order's been through Paid→Cancelled, not a mechanical FROM-clause swap
7. P1–P4 ตาม migration plan ใน REDESIGN_V3 §4 / E2E §3 (ยังไม่แตะ) - now needs re-scoping given #4 above
8. If more assurance is wanted: full charge-driven completeness reconciliation across all 12 sap_view
   process views (not just the targeted read-through done this session)

## DECISIONS PENDING (จาก design review)

1. Orchestration: Cloud Workflows? 2. InvoiceNo standard (raw id + rank prefix) — บัญชี ack
3. ProcessingFee 100/103.3 (RCL) vs 100/107 (onetime) — ตัวไหนถูกต่อ flow ไหน (เจอ discrepancy ใหม่)
4. Backfill scope 5. EDC channel matrix 6. Parallel-run กี่วัน (เสนอ 5)
