# CreditShell NonMotor correction — three views deployed

Scope: user explicitly requests updating existing legacy views for NonMotor CreditShell.
Captured live definitions at 2026-09-28 03:32:52–53 UTC (capture.json). Both sap_view wrappers
already admit NonMotor from sap_integration_v2.RCL 04_new order credit shell.
The wrappers differ: RCB already clamps old paid dates; RCL leaves them unchanged.

Source changes in sql/production/nonmotor_creditshell_20260928:
- producer.sql: apply all 35 exact insurer-code pairs from live RCL_HEALTH after receipt ranking for Health/TA; preserve
  Motor mapping. At final projection, Pending NonMotor ActualReceived equals final ExpectedReceived.
  Paid actuals, receipt identities, interest, principal, row eligibility are unchanged.
- rcl_wrapper.sql and rcb_wrapper.sql: final NonMotor Paid dates before the Bangkok current month
  become its first day; current/future dates stay. Apply after ranking to preserve receipt allocation.
  RCB keeps its existing generic clamp; additional expression makes the NonMotor timezone explicit.
  Both wrappers reassert Pending Actual=final Expected after their own ranking.

Profile job creditshell_profile_20260928_002, observed 2026-09-28 03:35:09 UTC, 9,382,584,701 bytes:
Each wrapper contains the same 84 Health rows / 9 items (do not sum across wrappers).
All 84 have numeric insurer codes: 27, 34, 46 -> N017, N079, N105.
68 Pending rows have Actual different from Expected; RCL has 10 prior-month Paid dates.
RCB already has zero prior-month Paid dates. No TA sample in this wrapper snapshot.

Validation and deployment completed; final evidence is detailed below.
Rollback uses exact before.json view.query. No SAP import success is inferred from view output.
Known unrelated risk: both wrappers currently overlap; this patch does not reassign ownership.
Unknown insurers retain upstream's ELSE InsurerCode behavior, not an invented N code.
V3, production files, schedules and SAP records are unchanged.


## Release validation and deployment

Final preflight creditshell_preflight_20260928_004 completed, 9,696,099,453 bytes; metrics
observed2026-09-28 03:44:46–03:44:50 UTC. Producer43,921 rows and wrappers101 rows each
preserved. All Motor/unrelated-field/paid-amount/preserved-date/multiplicity differences0.
All NonMotor insurer and Pending amount failures0; historical Paid dates in wrappers0.
Producer historical dates intentionally remain for chronological receipt ranking.
Candidate schemas match all56 ordered names/types for each of the three views.
Exact candidate SELECT/DDL and executed preflight binding verified offline; independent
Standards and Spec reviews PASS at a07b771.

All3 DDL jobs DONE, definitions read back match candidates, schemas preserved. See
deployment_results.json for per-object UTC verification timestamps and job IDs. Rollback
DDL generated from original live metadata retained alongside deployment files.
Live postcheck creditshell_postcheck_20260928_001 DONE, observed2026-09-28 03:50:19 UTC
(10:50:19 Bangkok), 9,382,589,556 bytes. Each wrapper emits the same84 Health rows /9 items:
16 Paid +68 Pending. All insurer-prefix, Pending Actual/Expected and historical Paid-date
failure counts0. Exact codes N017/N079/N105. Do not sum the overlapping wrappers.
This confirms live view behavior, not SAP file delivery or posting.

Earlier validation attempts:001 stopped at20GiBcap;002 invalid CTE split (zero bytes);003
exposed14 historical producer expectation-allocation changes. Final004 fixed these by mapping
after ranking and passed all invariants. Source comments inherited from old live definitions
may say proposal/do-not-deploy; current user authorization and this report govern this release.

PR: https://github.com/BoatPiyarat/BI-SAP/pull/5
