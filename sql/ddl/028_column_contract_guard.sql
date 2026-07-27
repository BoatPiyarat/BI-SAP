-- 028_column_contract_guard.sql
-- TASK_V3_GAP_CLOSURE_v2.md A1 — direct fix for the 2026-07-26 positional-import incident
-- (SELECT * EXCEPT(col), expr AS col silently reordering PaymentDate, fixed in 019 but only
-- caught after a real SAP import rejected a whole file). This guard makes sure the NEXT such
-- bug is caught before the file is even exported, not after SAP rejects it.
--
-- Verified live 2026-07-27: all 12 sap_view.* interface views currently have IDENTICAL
-- (ordinal_position, column_name) for all 56 columns - a clean, consistent contract exists
-- today, confirmed via INFORMATION_SCHEMA.COLUMNS (0 rows differ across any view). Seeded the
-- contract table from RCB_Motor_process_create (arbitrary pick among the 12 - they're identical).
--
-- Column TYPE is deliberately NOT part of the drift check (only name+ordinal): SAP's own import
-- is documented as column-POSITION-based (CLAUDE.md), not type-based, and BigQuery infers types
-- per-query (e.g. a CASE expression can flip STRING/INT64 depending on branches actually hit that
-- day) - false-positive risk from type drift outweighs the (already covered by name+position)
-- protection it would add. Recorded in the contract table for reference only.

CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.sap_column_contract` (
  ordinal_position INT64,
  column_name STRING,
  data_type STRING,
  seeded_from STRING,
  seeded_at TIMESTAMP
);

-- Seed once (idempotent - only inserts if empty). Re-seeding after a deliberate, reviewed
-- contract change is a manual, separate action - never automatic.
INSERT INTO `pacific-plating-282708.sap_integration_v3.sap_column_contract`
  (ordinal_position, column_name, data_type, seeded_from, seeded_at)
SELECT ordinal_position, column_name, data_type, 'RCB_Motor_process_create', CURRENT_TIMESTAMP()
FROM `pacific-plating-282708.sap_view.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'RCB_Motor_process_create'
  AND NOT EXISTS (SELECT 1 FROM `pacific-plating-282708.sap_integration_v3.sap_column_contract`);

-- The 12 real interface views this guard watches (every sap_view.* object that feeds a real
-- exported file, per sap_interface_pipeline.yaml's motor_views/nonmotor_views lists).
CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_check_column_contract`()
BEGIN
  DECLARE drift_count INT64;
  DECLARE run_id STRING DEFAULT GENERATE_UUID();

  CREATE OR REPLACE TEMP TABLE _drift AS
  WITH watched_views AS (
    SELECT view_name FROM UNNEST([
      'RCB_Motor_process_create', 'RCB_Motor_process_2_cancel_new', 'RCB_Motor_process_3_change',
      'RCB_Motor_process_4_creditshell', 'RCL_Motor_process_1_create', 'RCL_Motor_process_2_newpayment',
      'RCL_Motor_process_3_cancel', 'RCL_Motor_process_4_creditshell',
      'RCB_NonMotor_process_1_create', 'RCB_NonMotor_process_2_cancel',
      'RCL_NonMotor_process_1_create', 'RCL_NonMotor_process_2_newpayment'
    ]) AS view_name
  ),
  actual AS (
    SELECT c.table_name AS view_name, c.ordinal_position, c.column_name
    FROM `pacific-plating-282708.sap_view.INFORMATION_SCHEMA.COLUMNS` c
    JOIN watched_views w ON w.view_name = c.table_name
  )
  SELECT
    w.view_name,
    ct.ordinal_position AS expected_ordinal,
    ct.column_name AS expected_column,
    a.column_name AS actual_column
  FROM watched_views w
  CROSS JOIN `pacific-plating-282708.sap_integration_v3.sap_column_contract` ct
  LEFT JOIN actual a ON a.view_name = w.view_name AND a.ordinal_position = ct.ordinal_position
  WHERE IFNULL(a.column_name, '<MISSING>') != ct.column_name;

  SET drift_count = (SELECT COUNT(*) FROM _drift);

  IF drift_count > 0 THEN
    INSERT INTO `pacific-plating-282708.sap_integration_v3.sap_validation_error`
      (order_item, period, check_name, detail, detected_at)
    SELECT view_name, NULL, 'COLUMN_CONTRACT_DRIFT',
      FORMAT('ordinal %d: expected "%s", actual "%s"', expected_ordinal, expected_column, actual_column),
      CURRENT_TIMESTAMP()
    FROM _drift;

    RAISE USING MESSAGE = FORMAT(
      'Column contract drift: %d column(s) out of position across the sap_view interface views - a file exported right now would very likely be rejected by SAP (column-position-based import). Check sap_validation_error WHERE rule=\'COLUMN_CONTRACT_DRIFT\' AND run_id=\'%s\'. Do NOT let tonight\'s export run until this is fixed.',
      drift_count, run_id
    );
  END IF;
END;
