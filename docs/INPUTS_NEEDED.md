# INPUTS NEEDED — things only Boat / Aware / Attila / Finance can answer

Created 2026-07-27 per `TASK_V3_GAP_CLOSURE_v2.md` (A0, A5, Housekeeping — "keep this current").
Nothing here blocks build work that doesn't depend on the specific answer; each item notes what
IS being done in the meantime.

---

## Attila (IAM) — blocking real freshness

**Ask**: grant `roles/run.invoker` to `sap-bucket-csv@pacific-plating-282708.iam.gserviceaccount.com`
on the Cloud Run job `sap-extract-job`, so `sap-extract-schedule` (Cloud Scheduler, 20:30 ICT
nightly) can invoke it again — currently failing `401 UNAUTHENTICATED` every night (confirmed via
audit logs: this binding most likely never successfully applied in the first place, not a
regression — see `docs/knowledge/30_SAP_CHANGELOG.md` 2026-07-24 cont'd 6).

**Exact command** (already drafted, see `docs/knowledge/_draft_message_attila.md`):
```bash
gcloud run jobs add-iam-policy-binding sap-extract-job \
  --region=asia-southeast1 --project=pacific-plating-282708 \
  --member="serviceAccount:sap-bucket-csv@pacific-plating-282708.iam.gserviceaccount.com" \
  --role="roles/run.invoker"
```
**In the meantime**: extract is being triggered manually/by other means; freshness depends on that
until this lands. Every real-time freshness claim in the dashboard/recon should be read with this
caveat.

---

## Aware (SAP vendor) — Q3a, the picking-rule question

**Ask**: when a period has MULTIPLE documents in SAP (see `sap_mirror_state.docs_considered > 1`,
328k+ keys), which document's `InvoiceNo`/status is authoritative? Draft already sent for review:
`docs/design/SAP_CANCEL_IMPORT_SPEC_INFERRED_v0.9.md`.

**In the meantime**: `sap_mirror_state`'s picking rule (Cancelled > Paid > Pending, non-empty
InvoiceNo wins ties, latest BatchRunDate wins remaining ties, highest DocEntry as final
deterministic tiebreak — added 2026-07-27) is live and tags every affected row
`PROVISIONAL_PENDING_AWARE_Q3A` so downstream consumers know which answers are still opinion, not
fact. Change only that one `ORDER BY` block when Aware answers.

**Also Aware/SAP DB** (same access gap as Q3a — cannot query `[RCB_LIVE_DB].[dbo].[@INSURANCE]`
directly from this environment):
- Total `@INSURANCE` row count + breakdown by row type — would convert the 373,971
  ceiling-not-estimate "missing DocEntry" number (`docs/FINDINGS_SAP_MIRROR_20260726.md` §10) into
  a real completeness percentage. 2-minute query at source.
- Whether `U_OrderItem = 'Invoice'`/`'SaleOrder'` (541 real, distinct documents that lost their
  true OrderItem to a literal SAP object-type-label string, 2024-03 to 2024-05, confirmed
  non-recurring since — see FINDINGS §12) is a known/recoverable extract defect on SAP's side.
- The 5 (OrderItem, Period) keys with 11-13 duplicate same-amount same-status Pending documents
  clustered in a single ~2.5-week window in 2024-03/04 (FINDINGS §12) — confirmed NOT ongoing and
  NOT real distinct postings (at most 1 row per key ever carried real money), but root cause
  (extract fan-out vs genuine source duplicate rows) unconfirmable without SAP DB access.

---

## Boat — interface_daily_status (A2) alert gap: MISSING/STATUS_CONFLICT can't be alerted on yet

`interface_daily_status` (built 2026-07-27, `030_interface_daily_status.sql`) implements the
OK/PENDING_ACK/MISSING/STATUS_CONFLICT/PAID_AFTER_CANCEL/UNROUTED status set you asked for, but
literally alerting on "MISSING/STATUS_CONFLICT present" would fire every single day - both have
large pre-existing backlogs today (MISSING ~341K, STATUS_CONFLICT ~59K, the exact historical gap
this project exists to close, not new incidents). Only wired an alert for `PAID_AFTER_CANCEL`
(rare, 7 rows today, always actionable) and staleness (no fresh row by late morning). Real
MISSING/STATUS_CONFLICT alerting needs a day-over-day baseline comparison (a small history table
snapshotting counts nightly, alert on meaningful *increase* not absolute presence) - not built,
flagging as a real gap rather than shipping a guaranteed-to-be-ignored daily alarm.

Also unverified and worth your review: the exact classification logic for STATUS_CONFLICT and
PAID_AFTER_CANCEL (see the judgment calls documented at the top of `030_interface_daily_status.sql`)
- built from my own best-effort reading of the task spec, not yet confirmed against your intent.
One real bug already caught and fixed during build: the first version of PAID_AFTER_CANCEL didn't
compare payment date against cancel date, so it fired on the normal "paid some periods, cancelled
later" pattern (1,898 false positives) - fixed to compare timing directly (now 7 genuine cases).

## Boat — email alerts go to data@rabbit.co.th, not you directly

Confirmed 2026-07-27: every BQDTS `enableFailureEmail` alert (dead-man's-switch/missed-extract,
column-contract guard, validation-regression) is owned by `data@rabbit.co.th`
(`ownerInfo.email` on the transfer config) - that's where the failure emails go, not
`piyaratt@rabbit.co.th`. If you don't check that inbox (or it doesn't forward to you), these
alerts won't reach your phone this week. The separate 6am/daily-digest routine (RemoteTrigger
cloud agent) does email you directly, since it uses your own Gmail connector - that one's fine.
Options if this matters: (a) check `data@rabbit.co.th` too while away, (b) set up a forward from
that inbox to yours, (c) tell me and I can look into whether the transfer configs can be
recreated under different ownership (would need to be done under the right identity, not
something I can just reassign).

## Boat — 2 new findings from return-triage (2026-07-29), both outside sap_integration_v3

1. **`SAP_LIVE` bloat**: 151,024 → 6,858,653 rows in 3 days (distinct DocEntry only 106,873→122,169).
   Root cause: the loader (`sap-order-payment-initial-phase`) crash-looped on its 1024 MiB memory
   limit for ~16 min around 2026-07-29 02:43-02:59 UTC, and since it does plain `INSERT` not `MERGE`,
   each restart likely re-inserted the same rows. No downstream correctness impact confirmed
   (`SAP_LIVE_FULL`/`sap_mirror_doc` dedup correctly), but real storage/cost growth and an active
   bug. Needs: raise the Cloud Run memory limit and/or make the insert idempotent. See
   `docs/RETURN_TRIAGE_20260730.md` §1.
2. **Legacy Cloud Functions reporting `crash` every night** (07-26/27/28, both Motor and NonMotor):
   root-caused to an expired/revoked Gmail SMTP app-password in the post-export notification email
   step (`mailer.py`), NOT the export itself - confirmed via log ordering that every real GCS file
   write completes before the crash. Cosmetic for data delivery, but the notification email nobody
   is receiving, and Cloud Function status alone looks like nightly failure. See
   `docs/RETURN_TRIAGE_20260730.md` §4.

## Boat — sap_integrety_2025_RCL follow-up (§14 in FINDINGS): dormant, but audit_010 isn't

90-day consumer check: `sap_integrety_2025_RCL` and `sap_integrety_2025_Q1` have **no real
consumers** in 90 days (only my own investigation queries today) - the bug is real but currently
dormant. **`audit_010_careos_missing_in_sap_detail` IS actively used by you** (3 times in 90 days)
and has the same unguarded-SUM pattern - not yet individually checked for the same double-counting
risk (time-boxed this pass to the one confirmed-consumer view). Check that one first when you're
back. THB delta for `sap_integrety_2025_RCL` computed by year/BU - see FINDINGS §14; note the sign
flips between years (2024/2025 positive, 2026 negative), consistent with undefined/inconsistent
behavior rather than one-directional overstatement - don't read the raw totals as "money lost."
`reconcile_revenue 202508_booking` (one of the 6 remaining views) wasn't relocated in this pass -
genuinely unverified, not confirmed dormant or active.

## Boat — URGENT, found 2026-07-27: a live view is double-counting money

`sap_integration_v2.sap_integrety_2025_RCL` (301,188 rows, name suggests a Finance-facing
integrity/reconciliation report) `SUM`s `U_TotalAmount` from `SAP_LIVE_FULL` grouped by
(OrderID, OrderItem, Period) with **no dedup** for periods that have multiple documents. Quantified
live: **144,013 of 1,508,026 groups (9.55%) have >1 document, and 142,381 of those produce a wrong
summed total** vs picking a single authoritative document. This is real and current, independent
of anything built in `sap_integration_v3` today. Same search also matched `sap_integrety_2025`,
`sap_integrety_2025_Q1`, `audit_010_careos_missing_in_sap_detail`,
`int_01_careos_missing_in_sap_summary`, `int_020_careos_cancelled_missing_summary`,
`reconcile_revenue 202508_booking` — not yet individually re-verified for the same pattern.
**Recommend looping in whoever owns/consumes this view before trusting any total it has produced.**
Not touched — outside this task's scope, needs your call on both the fix and who else to tell.
See `FINDINGS_SAP_MIRROR_20260726.md` §13 for the full query and verification.

## Boat / accounting — standard decisions

1. **B2B rows**: currently 0 rows in every source table at every layer — confirm this is expected
   (business line genuinely has no B2B SAP records yet) rather than a silent extract-side filter
   losing them. Low priority (no evidence it's causing any reported problem).
2. **ProcessingFee divisor** (`SAP_DATA_PREP_DESIGN_v3.md` §6.4 open Q-A): RCL uses `/103.3`,
   onetime uses `/107` — confirm which is correct per flow before PHASE B builds the full
   56-column engine on top of whichever is wrong today (if either is, that's an existing money
   drift, not a new one this rebuild would introduce).
3. **C2 policy** (PHASE C review item): item-level quarantine vs run-level atomic validation
   failure handling for the shadow/real export layer — needs an explicit choice before PHASE C
   builds the export-blocking logic, not a default silently picked.
4. **EDC channel matrix**: only KBANK confirmed (`RCB-EDC-KBANK`); need the full bank list for
   `CREDIT_CARD_INSTALLMENT` orders on other banks before PHASE B can route them correctly.

---

## Housekeeping notes (not blocking, just tracked)

- `docs/design/SAP_INTERFACE_REDESIGN_V3.md`, `SAP_PIPELINE_E2E_DESIGN_v3.md`,
  `SAP_DATA_PREP_DESIGN_v3.md`, `SAP_DASHBOARD_DESIGN_v1.md`, `SAP_RUNBOOK_v3.md` — all corrected
  2026-07-27 to remove stale `raw_sap_live`/B1 references (see `30_SAP_CHANGELOG.md`).
- `vw_dash_extract_scheduler_health` (the new widget the dashboard design doc now specifies) is
  designed but not yet built — see `docs/AS_BUILT_V3.md`.
