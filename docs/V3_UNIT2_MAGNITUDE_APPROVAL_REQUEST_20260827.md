# V3 Unit 2 first-baseline approval request

Status: **INPUT REQUIRED — no threshold has been inferred or seeded**

## Why this is required

The reviewed and deployed procedure `sp_bootstrap_v3_unit2_magnitude` can create the first durable
PASS baseline, but only from explicit approved values. Until that configuration exists, the Units
1–5 production wrapper correctly stops before Unit 3; Scenario 1 and Scenario 3 cannot obtain a
fresh release-ready build.

Proposed baseline evidence run:
`V3NIGHTLY-2026-08-25T22:21:31-manual` — exactly one successful `UNITS_2_5_ARCHIVE` row and Unit 2
summary evidence. The later read-only comparison used current run
`V3NIGHTLY-2026-08-27T00:17:51-manual-fresh-sap` under BigQuery job
`bqjob_r653b2df0f1d8c18a_000001a040f3cd28_1`.

Fresh precondition job `codex_v3_bootstrap_candidate_20260827_1230` passed every bootstrap guard:
14 summary rows, 198,853 event rows, 1,500,513 schedule rows, zero active configurations, zero
existing distribution rows for this run, and zero existing magnitude-run rows.

That comparison conserved event/schedule populations. Several normal ready cells changed roughly
46–92%, while stable high-volume cells changed roughly 0–2%; therefore the system must not select
thresholds automatically from this single run pair.

## Gate semantics

A cell is held only when both its absolute delta and relative delta exceed the approved threshold
for that measure. If the baseline value is zero, an absolute delta above the approved absolute
threshold is sufficient. Percentages are decimals in `[0,1]`; amounts are integer satang.

## Exact approval fields

Please provide all fields below. `effective_end` may be `NULL`; every other field is required.

```text
config_id:
effective_start (timestamp with timezone):
effective_end (timestamp with timezone or NULL):

records_absolute (INT64 >= 0):
records_percentage (NUMERIC 0..1):
orders_absolute (INT64 >= 0):
orders_percentage (NUMERIC 0..1):
amount_satang_absolute (INT64 >= 0):
amount_percentage (NUMERIC 0..1):

approval_reference:
approved_by:
approved_at (timestamp with timezone):
baseline_run_id: V3NIGHTLY-2026-08-25T22:21:31-manual
```

Approval of the bootstrap values authorizes one atomic CALL that inserts the configuration,
self-baseline distribution/result rows, and first PASS run. It does not authorize interface-file
delivery, GCS production writes, workflow delivery activation, or Scheduler activation.
