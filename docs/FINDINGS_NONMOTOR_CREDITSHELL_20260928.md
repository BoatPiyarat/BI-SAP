# CreditShell NonMotor correction — candidate, not deployed

Scope: user explicitly requests updating existing legacy views for NonMotor CreditShell.
Captured live definitions at 2026-09-28 03:32:52–53 UTC (capture.json). Both sap_view wrappers
already admit NonMotor from sap_integration_v2.RCL 04_new order credit shell.
The wrappers differ: RCB already clamps old paid dates; RCL leaves them unchanged.

Source changes in sql/production/nonmotor_creditshell_20260928:
- producer.sql: copy all 35 exact insurer mappings from live RCL_HEALTH for Health/TA; preserve
  Motor mapping. At final projection, Pending NonMotor ActualReceived equals final ExpectedReceived.
  Paid actuals, receipt identities, interest, principal, row eligibility are unchanged.
- rcl_wrapper.sql and rcb_wrapper.sql: final NonMotor Paid dates before the Bangkok current month
  become its first day; current/future dates stay. Apply after ranking to preserve receipt allocation.
  RCB keeps its existing generic clamp; additional expression makes the NonMotor timezone explicit.

Profile job creditshell_profile_20260928_002, observed 2026-09-28 03:35:09 UTC, 9,382,584,701 bytes:
Each wrapper contains the same 84 Health rows / 9 items (do not sum across wrappers).
All 84 have numeric insurer codes: 27, 34, 46 -> N017, N079, N105.
68 Pending rows have Actual different from Expected; RCL has 10 prior-month Paid dates.
RCB already has zero prior-month Paid dates. No TA sample in this wrapper snapshot.

Validation: exact-source preflight currently running; result required before deployment.
Column order remains 56, verified from captured metadata; candidate type/schema comparison pending.
Rollback uses exact before.json view.query. No SAP import success is inferred from view output.
Known unrelated risk: both wrappers currently overlap; this patch does not reassign ownership.
Unknown insurers retain upstream's ELSE InsurerCode behavior, not an invented N code.
V3, production files, schedules and SAP records are unchanged.
