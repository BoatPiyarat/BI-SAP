# RULE-09 deployment runbook

> **SUPERSEDED 2026-08-01 — DO NOT RUN.** Final E1 makes every OrderDate year <=2024 row
> untouched with no recovery, so the OLD_YEAR_NO_TOUCH rescue below is no longer valid.
> Current source is 037 and requires a new Class A PASS plus separate Boat deploy approval.

Status: **SOURCE ONLY — DO NOT RUN without Claude Code review and Boat deploy approval**

Artifact under review: `aba1aad`. Deployment target is
`pacific-plating-282708.sap_integration_v3`; location is `asia-southeast1`.

## Required order

1. Capture the deployed routine definition and pre-change counts for `expected_state` and all
   seven `sap_excluded_records.rule_code` values. Preserve the query job IDs/timestamps.
2. Dry-run every script/query with `--location=asia-southeast1` and
   `--maximum_bytes_billed=21474836480`.
3. Apply `sql/ddl/044_sap_period_lock_and_payment_date_clamp.sql`.
4. Insert the Boat-owned July control row:

   ```sql
   INSERT INTO `pacific-plating-282708.sap_integration_v3.sap_period_lock`
     (period, open_period_start, lock_datetime, locked_by, locked_at)
   VALUES
     ('2026-07', DATE '2026-07-01', TIMESTAMP '2026-08-03 14:00:00+07',
      SESSION_USER(), CURRENT_TIMESTAMP());
   ```

5. Stop unless this returns exactly one row and the exact July values:

   ```sql
   SELECT period, open_period_start, lock_datetime, locked_by, locked_at
   FROM `pacific-plating-282708.sap_integration_v3.sap_period_lock`
   WHERE lock_datetime > CURRENT_TIMESTAMP();
   ```

6. Apply `sql/ddl/037_fix_expected_invoice_no_null_unsafe.sql` from reviewed commit `aba1aad`.
7. Confirm the deployed routine definition contains `raw_payment_date`, both RULE-09 gates, and
   `old_year_rescued`; confirm `expected_state` has not yet changed merely from replacing the
   procedure.
8. Dry-run, then execute:

   ```sql
   CALL `pacific-plating-282708.sap_integration_v3.sp_refresh_expected_state`();
   ```

9. Verify before accepting the refresh:

   - the call job is `DONE` without error;
   - `expected_state.old_year_rescued` exists and is non-NULL for every row;
   - every `old_year_rescued=TRUE` row has old `date_basis` and raw PaymentDate in
     `[2026-07-01, 2026-08-01)`;
   - no rescued key is registered as `OLD_YEAR_NO_TOUCH`;
   - the other six rule populations have no unexplained change;
   - record count/order count/amount and representative row samples are captured, not only totals.

10. Run S6, then the single batched S7/S9/S10 plan. All pre-deploy G1/gap numbers are stale.

## Rollback

The rollback source is the exact pre-RULE-09 procedure at commit `c67045a`:
`sql/ddl/037_fix_expected_invoice_no_null_unsafe.sql`. Do not use historical 034.

If step 6 fails, BigQuery leaves the prior procedure in place; stop and record the error. If the
new procedure deploys but step 8 fails or verification fails:

1. Preserve the failed call job ID, error, deployed routine definition, and post-failure table
   counts before changing anything.
2. From a clean temporary checkout of commit `c67045a`, dry-run and re-apply its 037 file. This
   restores the previous live procedure while retaining the newly created period-lock table.
3. Dry-run and call the restored procedure to rebuild `expected_state` and
   `sap_excluded_records` under the previous rules. Its `CREATE OR REPLACE TABLE` removes the new
   `old_year_rescued` column and restores the former OLD_YEAR exclusion population.
4. Re-run the captured pre-change counts and rule distributions. Do not claim rollback complete
   from procedure replacement alone; the restored refresh and data comparison must both pass.

Do not delete the July period row during rollback. Deleting it would make the previous 037 fail
closed and would destroy control evidence.
