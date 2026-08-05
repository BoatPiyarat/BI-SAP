# Finding — monthly cutoff is not yet unattended

Status: **CONFIRMED FROM REVIEWED REPOSITORY SOURCE; NO LIVE-STATE RECHECK IN THIS INCREMENT**

## Confirmed source trace

1. `infra/v3_nightly_orchestrator.workflows.yaml` calls
   `sp_run_v3_units2_5` after Unit 1.
2. `sql/ddl/061_v3_units2_5_nightly_wrapper.sql` calls Units 2–5 and the archive procedure. It
   never calls `sp_close_open_period`.
3. `sql/ddl/053_v3_unit4_period_state_machine.sql` is the only monthly transition procedure. Its
   `sp_close_open_period` signature requires all four values at call time:
   current period, authoritative current cutoff, authoritative next-period cutoff, and closer.
4. The approved calendar currently records July close `2026-08-03 15:00 ICT` and August close
   `2026-09-01 14:00 ICT`. Finance remains owner of later monthly cutoffs.

Therefore the daily workflow can run unattended inside the current OPEN month, but it cannot
advance the accounting period unattended. At the August cutoff it cannot safely invent
September's closing cutoff, and the nightly source contains no call that would perform the
transition even if that value were known.

This is a fail-closed automation gap, not permission to guess a calendar. Running against an
expired OPEN period should stop and alert; silently retaining August after its authoritative close
or inventing September's cutoff would both violate Unit 4.

## Smallest safe implementation

Use one new V3-only, append-only cutoff registry plus two procedures:

1. `sap_period_cutoff_calendar`
   - one immutable row per month-aligned `period_start`;
   - exact `closing_at`, `approved_by`, `source_reference`, and `recorded_at`;
   - initially seed only the already approved July and August values;
   - corrections require an explicit audited correction artifact, not an in-place silent update.
2. `sp_register_period_cutoff`
   - inserts exactly one future Finance-approved cutoff;
   - rejects duplicates, non-month-aligned periods, blank approver/source, and a cutoff that is not
     later than the period start;
   - never infers a future month.
3. `sp_transition_due_period_from_calendar`
   - requires exactly one OPEN period and exact equality between its stored `closing_at` and the
     calendar;
   - before the cutoff, returns a no-op readiness state;
   - at/after the cutoff, requires the adjacent next period and its approved cutoff, then delegates
     to the already reviewed atomic `sp_close_open_period`;
   - missing/mismatched current or next calendar data fails closed.

After separate Class-A review, call the transition procedure at the start of Units 2–5, before
classification or export. The workflow's existing failure path must persist and alert any missing
calendar/transition error. Add the next-cutoff readiness state to the daily human report so Finance
is warned before the deadline rather than first learning at the cutoff.

## Gates before implementation/deployment

- Confirm the registry/correction policy with Finance; do not assume cutoffs always occur on the
  first day or at a fixed hour.
- Obtain the September closing cutoff before enabling unattended transition at the August close.
- Add executable before/at/after-cutoff, duplicate/missing-next, mismatch, adjacency, timezone, and
  rerun tests.
- Run every DDL/query through the mandatory BigQuery safety wrapper. No SQL was drafted in this
  increment because the local GCP tool account reported its usage limit and could not provide the
  required dry-run evidence.
- Deploy definitions and calendar seed separately from enabling the nightly call.

No table, procedure, calendar row, workflow, scheduler, BigQuery job, GCS object, Gmail state, or
SAP state changed in this finding.
