# Motor Commission Clawback Dashboard — progress 2026-08-10

Project: `pacific-plating-282708`

Dataset: `motor_commission`
Status timestamp: 2026-08-10 ICT

## Current status

- `clawback_deducted_history` recovered to 913 rows / 912 unique orders.
- All 739 known legacy hardcoded exclusion orders are covered by history.
- Recovery snapshot: `clawback_deducted_history_backup_20260810_before_legacy_recovery`.
- `manual_clawback_list` uses the confirmed 56% OIC rate for 60–69 days.
- `sale_performance_with_clawback` rounds its seven monetary outputs to two decimal places.
- `Clawback orders` scheduled query now uses a dynamic 16th–15th cycle and history-table exclusion.
- `Deduct cancel paid commission of last period` now uses the dynamic prior cycle, 56% OIC rate, history exclusion, and a human readiness gate.
- `clawback_summary` required no SQL change.
- `raw_orders_clawbacks` Step E remains intentionally out of scope; its hardcoded `com_period` ladder still requires a separately reviewed payroll-facing change before M12 2026 expires.

## Human-gated backup-paid control

Control table: `backup_paid_commission_cycle_ready`

Step D fails before replacing its output unless exactly one cycle row is marked ready and its `approved_row_count` still equals the corresponding row count in `backup_paid_commissions`. Any subsequent manual add/remove invalidates readiness until the cycle is approved again.

Current approval:

- Cycle: `2026 M07`
- Approved rows: 17,162
- Readiness write job: `job_JQ3AX2gnTV8Ucxl9aDiKR5xpdRJ2`
- Verification job: `job_iZQaF-hhBeFjrCj5KRDBQOQ8K3CD`

## Deployment and validation

Updated scheduled-query configs:

- `Clawback orders`: `69e98544-0000-2691-b44d-fc411690d5c9`
- `Deduct cancel paid commission of last period`: `69f1c68e-0000-2f66-83ad-582429cf1e1c`

Manual validation runs:

- C run `6a8bd400-0000-2074-8950-582429cdd44c`: `SUCCEEDED`
- D run `6a8bd401-0000-2074-8950-582429cdd44c`: `SUCCEEDED`
- Output validation job: `job_jULUmcfcqOY9tuiQ_0pJvhhp402E`

Validated output:

| Object | Rows | Distinct orders | Amount | Cancellation window | History overlap |
|---|---:|---:|---:|---|---:|
| `active_clawback_orders` | 91 | 91 | THB 468,228.01 clawback | 2026-07-16 to 2026-08-07 | 0 |
| `deduct_cancel_paid_com_unvalid_policy_last_period` | 0 | 0 | THB 0 | Current M-1 selection | 0 |

The zero-row D result was checked independently before history exclusion and still returned zero, so history recovery did not suppress a valid current candidate.

## Recovery incident note

During preparation, an incorrectly nested BigQuery REST `dryRun` flag caused intended validation DDL/DML to execute. The issue was disclosed immediately. The two affected output tables were restored byte-for-byte from their unchanged live scheduler definitions:

- C rollback job: `job_nkNk7eeIe0ZCVz1k93lMDXDxpOYf`
- D rollback job: `job_hBeYy-TU7SdzwbDojW8h-y17PLrg`
- Restored baselines: 162 C rows and 6 D rows

The corrected payload uses `configuration.dryRun = true`; a non-mutating proof confirmed the object timestamp and 162-row baseline remained unchanged. The approved scheduler deployment occurred only after that proof and a second corrected dry-run.

## Remaining follow-up

1. Validate the dashboard visually with the business owner.
2. Observe the next 2–3 daily runs of both updated schedules.
3. Each month, finish human import/manual/special-approval edits in `backup_paid_commissions`, then approve the exact cycle row count in `backup_paid_commission_cycle_ready`.
4. Do not disable `Motor-commission step 3` (`69006485-0000-24d1-941e-3c286d465a26`) until Boat confirms no consumer depends on its 19th/08:40 ICT timing.
5. Handle Step E only as a separate reviewed task.
