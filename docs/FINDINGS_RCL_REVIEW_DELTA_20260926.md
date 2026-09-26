# Legacy/upstream review delta — 2026-09-26

SOURCE ONLY; NOT DEPLOYED. V3 implementation ON HOLD by the latest user instruction.
Basis: Claude review 472e560, docs/reviews/2026-09-26-c1476a3-claude.md.
No V3 SQL, routine, scheduler, SAP record, production view or GCS object was modified.
This report supersedes earlier ranking/classification findings where explicitly stated.

## Source corrections

- N3: deterministic charge rank `(create_time,id)` in dashboard, source classifier and additional
  gate. This is a technical tiebreak; invoice/charge collisions remain ineligible for extras.
- N4/N10: carry raw source_charge_rank internally. Zero ExpectedReceived is a payload constraint,
  not an event classifier. Rank1 uses ordinary paid-period exclusion; rank>1 also requires valid
  identity and additional payload. Keep rank lineage separate from eligibility so invalid extras
  cannot fall into the ordinary branch. Multiple source rows sharing an identity receive a hold.
- Preserve compulsory rank1 and its period1 NULL InvoiceNo through a NULL-safe lineage join.
  Compulsory cannot become an additional row. Unmatched zero-actual rows retain the ordinary path;
  this compatibility predicate is not restricted to Pending status.
- N5: exact-count assertions added to the four dashboard marker/EIR rewrite anchors.
- Hold diagnostic uses the actual query CTEs and distinguishes missing/ambiguous identity,
  invalid additional identity and invalid additional payload. It is SELECT-only, not deployed.

## Verification

Evidence paths below are under docs/evidence/rcl_additional_20260926/.

| Check | Result and provenance |
| --- | --- |
| Behavioral fixtures | 26 cases; membership/replay/duplicate failures=0. review_delta_fixtures.json, 2026-09-26 14:24:40 UTC |
| Red test | Old c1476a3 on the preceding 24-case fixture fails 4 memberships and returns 1 replay row; review_red_fixture.json |
| Raw-date gate | Old clamped event excluded, recent raw event included; review_date_fixture.json |
| Exact final composed SQL | DONE, 9,846,953,127 bytes; job bqjob_r30406b4ebfd06e4a_000001a0de1e8201_1; review_composed_final_binding.json |
| Target receipts | 20 rows including L80570054 +22.04 and L79109956 +645.21 THB; review_composed_target_final.json |
| Final wrapper | 12,714 rows / 1,758 items; old full payloads changed/removed=0; duplicate event keys/incomplete spines/repeated expected=0; review_final_children.json |
| Raw newpayment | Old full payloads removed=0; review_final_metrics.json, 2026-09-26 14:31:38 UTC |
| Added receipt lineage | Added extra-shaped rows without raw rank>1=0; review_final_metrics.json |
| Positional schema | Exact 56 names/order/types in final newpayment and wrapper; review_final_candidate_*_schema.json |

Final source hashes are review_delta_source_sha256.json. Old source_sha256.json and
execution_binding.json belong to c1476a3, not this delta. All numbers describe candidates or
mirror identity checks, not successful SAP imports or GL posting.

### Dashboard ranking delta

There are 64 changed prior dashboard payloads/item-periods relative to the nondeterministic baseline.
All 64 have tied first charge timestamps. Per affected period, sums of ExpectedReceived,
InterestThisPeriod and InterestEIRThisPeriod have ZERO changes (review_final_metrics.json,
2026-09-26 14:31:14 UTC). rank_delta.json contains 73 joined comparisons, not 73 changed source rows:
several added receipts share an old fallback invoice. This is a disclosed intended ranking change,
not row-for-row dashboard parity. Existing SAP identities remain mirrored from SAP_LIVE_FULL.

### N2: all added rows explained

The exact earlier 589-row addition consists of 80 extra-shaped rows (79 new lowercase paid receipts
and 1 carried Paid extra), plus 509 ordinary spine rows: 84 Paid and 425 Pending. All 509 have a period
in the captured SAP mirror. Paid spine ActualReceived totals 161,414.01 THB: carried context, not
new cash to post. Source: original_added_breakdown.json, 2026-09-26 14:14:16 UTC.

The later snapshot adds 623 payloads: 80 extra-shaped plus 543 spine rows (87 Paid + 456 Pending),
per review_final_children.json. Do not mix snapshot denominators. Whole-spine resend follows the
existing wrapper contract, but SAP file-import idempotency remains UNVERIFIED without import logs;
mirror presence and receipt replay fixtures do not prove it.

## N1: actual live dependencies

live_dependents.json (2026-09-26 14:05:38 UTC) confirms the three source baselines have not drifted.
There are 4 direct view readers and 6 V3 procedures. The dashboard itself and the gate selected for
baseline comparison are not counted as direct readers.

| Direct live reader | Measured delta |
| --- | --- |
| sap_integration_v2.RCL05_newpayment | Old payloads removed=0; additional receipts routed by validated raw rank |
| sap_integration_v2.rcl_01_new_paid_by_period | 14,353 to 14,410 rows;68 added /11 removed payloads; review_population_children.json,14:16:23 UTC |
| sap_view.RCL_Motor_process_1_create | 1,262 to 1,265 rows;3 added /0 removed;0 duplicate event keys; review_final_metrics.json,14:31:13 UTC |
| sap_integration_v3.vw_v3_rcl_cmi_payload_source | Read-only body comparison:22,923 rows before/after;1 payload replaced; review_population_final.json,14:19:42 UTC |

Six routine names/hashes are preserved in the inventory. No routine was CALLed. Their detailed
release impacts remain pending with V3 implementation held. Reading CMI source/metadata changed no
V3 object. A project hold is not evidence that every scheduled downstream consumer is paused.
N6: live CREATE/NEWPAYMENT wrappers contain stale source-only comments; metadata establishes their
live status. No wrapper definition was changed in this unit.

## All-date raw-charge audit (N9)

Population A: every SUCCESSFUL RABBIT_LENDING source row on a RABBIT_CARE_INSTALLMENT transaction
sharing its transaction/period with another successful charge, across all dates/products.
review_charge_ledger_final.jsonl durably records 5,299 rows: 2,605 first + 2,694 additional. Zero rows
lack a disposition. review_final_metrics.json has count and THB amount splits by product mix,
first/additional, period1/later, month and payment channel. Observed product enums are recorded in
product_mapping.json (products/car-insurance and products/health-insurance).

Exclusive IDENTITY-presence/triage buckets: 4,125 SAP_IDENTITY_PRESENT; 74 LEGACY_CANDIDATE_PRESENT;
1,100 requiring a hold/further routing. These are NOT full allocation-conservation or posting claims:
one transaction may have V1/M1 allocations and one matched invoice does not prove all posted.
The JSONL is an audit snapshot, not an operational quarantine ledger or recurring report. Strong
production conservation acceptance therefore remains OPEN.

4,820 rows are older than the recency window; 1,068 older rows have neither a terminal SAP identity
match nor a legacy candidate. 777 additional charges link to an order containing a compulsory item;
this is not 777 missing compulsory postings. Compulsory extra allocation remains undecided and its
rank1 filter remains. No historical backfill ran.

NonMotor slice: 112 rows; 101 SAP terminal identities; 9 outside this dashboard scope; 2 outside
recency. The 11 unmatched span Sep2026(8),Aug2026(1),Apr2026(1),May2025(1). This is not a passed rerun
of old MS-06: the separate NonMotor producer/lineage still needs checking before calling these
missing or releasable. Correct final product grouping supersedes the first diagnostic's incorrect
assumption that CareOS product enum was MOTOR.

## Remaining release gates

- Authoritative principal mapping for later-period extras (previous 54-row finding still open).
- Import-log evidence for carried-spine idempotency; preserve existing legacy invoice aliases.
  The proposed V3 prefix rule is deferred with V3, not silently adopted into legacy.
- Operational durable holds/reporting and unresolved NonMotor/allocation/backlog routing.
- Review/accept measured shared-consumer deltas and resolve downstream compatibility before a
  shared-dashboard replacement affects consumers. No V3 implementation change is included here.
- New Class-A review and explicit scoped legacy deploy authorization. PR #2 remains a draft.

## Query execution and cost record

All queries used the safe wrapper and 20-GiB cap. Combined review_population hit the cap after core
regression and a consumer check (21,287,948,899 processed bytes); the whole job is FAILED, while
completed child results are retained. Continuations reused cached tables instead of rescanning SAP.
review_final_checks later failed on an unqualified diagnostic table name after completing the final
source pipeline and ledger. review_final_children retains those completed results; the corrected
review_final_metrics continuation succeeded. The final native composed job independently succeeded
on exact source. Temporary datasets expire; future reproduction must refresh the staged baseline
and update cached references. No failed whole job is represented as successful.
