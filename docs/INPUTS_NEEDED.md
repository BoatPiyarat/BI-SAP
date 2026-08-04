# INPUTS NEEDED — things only Boat / Aware / Attila / Finance can answer

Created 2026-07-27 per `TASK_V3_GAP_CLOSURE_v2.md` (A0, A5, Housekeeping — "keep this current").
Nothing here blocks build work that doesn't depend on the specific answer; each item notes what
IS being done in the meantime.

## NonMotor InsuranceGroup mapping — PARTIAL INPUT 2026-08-02

Boat supplied the SAP InsuranceGroup master and the live scheduled-query source. Exact matches
`Health -> Health` and `Life -> Life` are usable after registry review. Human mapping is still
required for scheduled-query outputs `Cancer`, `Home`, and `ERROR`; these values remain held and
reported. Do not silently map them to `Miscellaneous`.

## P0 — Aware disposition for July InsurerCode exclusions

Job `p0_insurer_risk_20260731_152353` at `2026-07-31 15:23:55 UTC` found 300 July-PaymentDate
records / 294 orders / THB 2,260,768.08 excluded as `INSURER_NOT_IN_MASTER`. Aware must confirm the
disposition for normalized codes `30`, `46`, `48`, `49`: add to SAP master, map to an existing
code, or intentionally hold. Do not silently restore/delete records; see
`docs/FINDINGS_INSURER_EXCLUSION_RISK_20260731.md`.

## RESOLVED 2026-07-31 — RULE-09 narrow OLD_YEAR_NO_TOUCH exception

Boat kept `GREATEST(OrderDate, PolicyDate)` as the year-rule basis and approved one narrow
exception: `OLD_YEAR_NO_TOUCH` does not remove a row whose raw PaymentDate falls inside the open
calendar month. For July the exact window is `[2026-07-01, 2026-08-01)`; `lock_datetime` does not
extend it. No other exclusion rule inherits this exception.

## SOURCE READY 2026-08-04 — enrich excluded-record audit

Source DDL 032/037 now retains `amount` (successful charge amount in satang; nullable where no
charge exists) and processing `date_basis` on every `sap_excluded_records` row, sourced from the
existing `_rules` temp table. Exclusion predicates and `expected_state` output are unchanged.
Both complete files passed dry-run-only validation at 0 bytes. Deployment still requires Class-A
review and separate approval.

## RESOLVED 2026-07-31 — scheduler 401; run.invoker downgraded to P3 hygiene

The scheduler used an OIDC ID token against the Cloud Run Admin API, which requires OAuth. It was
changed to OAuth using the default compute service account and returned HTTP 200 at
`2026-07-31T14:16:30Z`; IAM was never the blocker. The former blocking Attila request below is
superseded. A future `run.invoker` grant for `sap-bucket-csv@` is P3 least-privilege hygiene only.

## Boat — extract timing before 2026-08-03 reconciliation

**Decision needed:** approve one manual extract immediately before reconciliation (recommended),
or add a permanent morning schedule. The current 20:30 ICT extract trails the ~01:30 ICT interface
import by about 19 hours. Until Boat decides, do not manually trigger the job.

## RESOLVED 2026-07-30 — GitHub remote URL

Repository remote is `https://github.com/BoatPiyarat/BI-SAP.git`. `origin` was configured and
`p0/stg-sap-state` pushed successfully on 2026-07-30. Do not request the URL again.

## RESOLVED 2026-07-30 — materiality buffer and grain

D12/D13 resolves the former tolerance input: ±฿10 **per order**, after order aggregation.
`MISPOSTING` has no buffer. Do not ask whether the threshold is per row/period/document again.

## Finance — monthly accounting cutoff calendar remains open

**Ask**: provide/confirm the monthly closed-period cutoff calendar and the allowed rollover date
for PaymentDate. `sap_accounting_cutoff_dates` is referenced by design but was not found in the
project during commit `3106719`; do not replace it with an inferred calendar.

**Current production blocker (2026-08-02):** `sap_period_state` still marks July
`[2026-07-01,2026-08-01)` OPEN, while all 585 ready NEWPAYMENT events are dated 2026-08-01.
Boat must supply the exact July `closing_at` and the intended August `closing_at` for the reviewed
`sp_close_open_period` transition. Codex must not invent either timestamp.

## RESOLVED 2026-07-29 — Aware actual-received correction method

Aware and Sarawut/Boyd confirmed two supported methods. Adjustment lines use the original Period,
`ExpectedReceived=0`, and `ActualReceived=delta`; Cancel + new Paid is mandatory when
`ExpectedReceived` is incorrect or negative. Test evidence: adjustment `L79899055` /
`L79965977`; Cancel + Paid `L79899088` / `L79965966`. This closes the former validation-library
question “cancel+re-import vs manual SAP correction — รอคำตอบ Aware”; do not ask it again.

---

## SUPERSEDED 2026-07-31 — Attila IAM request was not blocking freshness

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
**Current status**: scheduler automation works through OAuth with the default compute SA. Retain
this command only as a P3 least-privilege option for switching back to `sap-bucket-csv@`; it is not
a recovery action and manual compensation must stop.

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

## Aware (SAP vendor) — change-order supersession, separate from Q3a

**Ask**: when an old CareOS order is superseded through `careos.cancelled_change_orders`, must the
old order receive an explicit SAP `Cancelled` document, or does the replacement order supersede it
without a separate cancel import?

This is deliberately separate from Q3a: Q3a chooses the authoritative document when SAP already
has multiple documents; this question decides whether a superseded old order must receive a new
cancel document at all. Per D2, do not send this population until all three change-order preflight
checks are documented and passed and FA approves the batch.

Evidence population: **⚠️ PROVISIONAL — UNDER VERIFICATION: 9,625 order_items**, sourced from
`careos.cancelled_change_orders`, `careos.careos_orders`, `careos.carepay_transactions`,
`sap_integration_v3.stg_order_dim`, and the SAP mirror logic. Exact query timestamp was not captured;
evidence was recorded in session commit `19d9452` at 2026-07-29 17:58:53 ICT. Do not cite as a
production batch count until a provenance-complete rerun.

## Aware (SAP vendor) — Q4, Method-2 replacement naming

**Ask**: what exact SAP-facing OrderItem prefix/template must be used for a replacement generation
created by Method 2? Does the SAP C# code currently apply or recognize an existing prefix,
especially the `C#` convention observed around Credit Shell?

**Why this is open**: `-M2` cannot mean “revision 2”; `careos.careos_order_items` already has
**⚠️ PROVISIONAL 1,019 real `-M2` rows**, source query recorded in commit `73e94e0`, exact query
timestamp not retained. `-M1R2` is only a rejected-as-hardcode proposal, not a decision.

**In the meantime**: D10 requires a configuration parameter for the naming template/prefix.
Do not hardcode or deploy any replacement naming until Aware answers. Per D14, this question is a
blocker only for B2 (`ExpectedReceived` wrong); it is **not** a blocker for Class 1 or Class 2,
which use Method 1.

## Aware + FA — GL verification for two Method-1 pilots

**Ask after explicit pilot approval and execution**: verify both the SAP interface amounts and the
underlying GL/journal entries for:

1. Class 1 `AMOUNT_VARIANCE`: `L80046687`.
2. Class 2 `MISPOSTING`: `L79900064`.

D15 makes this pair authoritative. `0a69143`'s `L79871659`/`L80524847` pair is superseded:
the former is too close to the noise floor and has no confirmed CMI sibling; the latter was
rejected and has no JE, so it is only a rejection-detection test case.

Purpose: replace the theoretical question “can the interface fix GL?” with observed evidence.
Method 1 can correct item amounts but does not remove a duplicate document holding full Expected.
If that document generated a duplicate JE, the JE may remain. Do not expand either correction
population based only on balanced interface amounts; require explicit Aware/FA GL confirmation.

## FA — approve change-order cancel batch only after preflight

**Ask**: after Aware answers the supersession question and all three D2 preflight checks pass,
approve or reject sending the change-order cancel batch. No batch may be sent before explicit FA
approval.

Current candidate count is the same **⚠️ PROVISIONAL 9,625 order_items** described immediately
above; source tables and evidence timestamp are inherited from that entry, not a second count.

## Boat / IT — parent cancel flag not set after every child item was cancelled

**Ask**: should `careos.careos_orders.is_cancelled` automatically become TRUE when every
`careos.careos_order_items` child has a non-NULL `cancel_time`?

Latest diagnostic found **⚠️ PROVISIONAL 25 orders / 50 items** with all child items individually
cancelled but the parent order flag not TRUE. This is an IT/data-consistency question, not a reason
to cancel active siblings or change the canonical revised-D1 formula. Sources:
`careos.careos_orders`, `careos.careos_order_items`, `careos.cancelled_change_orders`, and
`sap_integration_v3.sap_mirror_state`; queried 2026-07-29, exact query timestamp not retained,
evidence committed in `fa9b351` at 2026-07-29 18:46:14 ICT. Session evidence says only a small
subset requires SAP action; do not derive a batch from this count.

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

`interface_daily_status` (built 2026-07-27, `030_interface_daily_status.sql`) uses the revised
status vocabulary OK/PENDING_ACK/MISSING/STATUS_CONFLICT/PAID_AFTER_CANCEL/
CANCEL_TIME_MISSING/UNROUTED. `CANCEL_TIME_MISSING` keeps an effective cancellation visible when
`careos.careos_orders.is_cancelled IS TRUE` but `careos.careos_order_items.cancel_time IS NULL`,
so PAID_AFTER_CANCEL timing cannot be evaluated. The current deployed classification predates
revised D1 and needs Claude Code implementation/0A–0B verification.

Literally alerting on "MISSING/STATUS_CONFLICT present" would still fire every day. **⚠️ PROVISIONAL
— UNDER VERIFICATION; DO NOT CITE until Claude Code reports passing 0A/0B and STATUS_CONFLICT
decreases in line with D1 acceptance:** after E1–E3
filtering, the 2026-07-29 14:01:28 ICT snapshot is MISSING 576 and STATUS_CONFLICT 34,758
(Return Triage's 340,051/59,501 snapshot was pre-filter). Only wired an alert for `PAID_AFTER_CANCEL`
(rare, 7 rows today, always actionable) and staleness (no fresh row by late morning). Real
Source DDL 066 now provides an immutable daily history snapshot and increase-based checker for
MISSING/STATUS_CONFLICT. It intentionally contains no threshold seed. Boat must approve the
maximum day-over-day record and order increases for both statuses before the checker can run;
missing or duplicated active configuration fails closed.

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
   Leading hypothesis: the loader (`sap-order-payment-initial-phase`) crash-looped on its 1024 MiB
   memory limit for ~16 min around 2026-07-29 02:43-02:59 UTC and plain `INSERT` retries reinserted
   rows. Daily count comparison at 2026-07-30 09:10:41 UTC found no distinct-DocEntry deficit
   against Boat's supplied SQL row counts, but set-level real loss remains **UNVERIFIED** because
   source DocEntry IDs were not supplied for anti-join. Phase B/C remain ON HOLD. `SAP_LIVE` is an append-only audit trail: no cleanup,
   dedup, truncate, rebuild, or delete is allowed before the incident closes and a reviewed
   preservation/retention decision exists. Read-only investigation must precede loader changes.
   See `docs/RETURN_TRIAGE_20260729.md` §1 and HANDOVER queue item 2.
2. **Legacy Cloud Functions reporting `crash` every night** (07-26/27/28, both Motor and NonMotor):
   root-caused to an expired/revoked Gmail SMTP app-password in the post-export notification email
   step (`mailer.py`), NOT the export itself - confirmed via log ordering that every real GCS file
   write completes before the crash. Cosmetic for data delivery, but the notification email nobody
   is receiving, and Cloud Function status alone looks like nightly failure. See
   `docs/RETURN_TRIAGE_20260729.md` §4.

## CLOSED — `sap_integrety_2025_RCL`: dormant/obsolete housekeeping candidate

90-day consumer check: `sap_integrety_2025_RCL` and `sap_integrety_2025_Q1` have **no real
consumers** in 90 days (only my own investigation queries today) - the bug is real but currently
dormant. Boat confirmed on 2026-07-30 that `sap_integrety_2025_RCL` has no real consumer:
**no notification is required and no owner follow-up remains**. Classify it as dormant/obsolete
and retain only as a housekeeping/archive candidate.

**Separate note:** `audit_010_careos_missing_in_sap_detail` IS actively used by Boat (3 times in 90 days)
and has the same unguarded-SUM code pattern, but Return Triage verified its actual zero-match output
is unaffected because the risky SUM is never used for matched rows. No fix is currently requested
for that view. THB delta for `sap_integrety_2025_RCL` computed by year/BU - see FINDINGS §14; note the sign
flips between years (2024/2025 positive, 2026 negative), consistent with undefined/inconsistent
behavior rather than one-directional overstatement - don't read the raw totals as "money lost."
`reconcile_revenue 202508_booking` (one of the 6 remaining views) wasn't relocated in this pass -
genuinely unverified, not confirmed dormant or active.

## Boat / accounting — standard decisions

1. **B2B rows**: currently 0 rows in every source table at every layer — confirm this is expected
   (business line genuinely has no B2B SAP records yet) rather than a silent extract-side filter
   losing them. Low priority (no evidence it's causing any reported problem).
2. **ProcessingFee divisor**: RCL `/103.3` is confirmed. Onetime `/107` remains unconfirmed —
   keep it as-is and flag until Finance confirms; do not re-open the RCL decision.
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
