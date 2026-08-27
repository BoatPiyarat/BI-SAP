-- SOURCE ONLY / Class A / MUTATING WHEN FILLED AND EXECUTED.
-- One-time operator for the first approved Unit 2 magnitude configuration.
--
-- Safe default: all human-owned values are SQL NULL, so the script stops before CALL.
-- Edit only the declarations in the marked block after Boat supplies all six thresholds and
-- approval provenance. Execution requires a separate explicit approval naming this exact file,
-- filled values, baseline run, and config ID. Run only through scripts/bq_safe_query.sh.
--
-- The reviewed/deployed procedure performs the configuration, distribution, result, and PASS-row
-- inserts in one transaction. Assertions after CALL verify the committed state; they cannot roll
-- that transaction back, so preserve the BigQuery job ID as deployment evidence.

DECLARE v_baseline_run_id STRING DEFAULT
  'V3NIGHTLY-2026-08-25T22:21:31-manual';

-- =============================================================================================
-- EDIT THESE VALUES ONLY AFTER EXACT HUMAN APPROVAL
-- =============================================================================================
DECLARE v_config_id STRING DEFAULT CAST(NULL AS STRING);
DECLARE v_effective_start TIMESTAMP DEFAULT CAST(NULL AS TIMESTAMP);
DECLARE v_effective_end TIMESTAMP DEFAULT CAST(NULL AS TIMESTAMP); -- optional
DECLARE v_records_absolute INT64 DEFAULT CAST(NULL AS INT64);
DECLARE v_records_percentage NUMERIC DEFAULT CAST(NULL AS NUMERIC);
DECLARE v_orders_absolute INT64 DEFAULT CAST(NULL AS INT64);
DECLARE v_orders_percentage NUMERIC DEFAULT CAST(NULL AS NUMERIC);
DECLARE v_amount_satang_absolute INT64 DEFAULT CAST(NULL AS INT64);
DECLARE v_amount_percentage NUMERIC DEFAULT CAST(NULL AS NUMERIC);
DECLARE v_approval_reference STRING DEFAULT CAST(NULL AS STRING);
DECLARE v_approved_by STRING DEFAULT CAST(NULL AS STRING);
DECLARE v_approved_at TIMESTAMP DEFAULT CAST(NULL AS TIMESTAMP);
-- =============================================================================================

ASSERT NULLIF(TRIM(v_config_id), '') IS NOT NULL
  AS 'STOP: approved config_id is required';
ASSERT v_effective_start IS NOT NULL
  AS 'STOP: approved effective_start is required';
ASSERT v_records_absolute IS NOT NULL
  AND v_records_percentage IS NOT NULL
  AND v_orders_absolute IS NOT NULL
  AND v_orders_percentage IS NOT NULL
  AND v_amount_satang_absolute IS NOT NULL
  AND v_amount_percentage IS NOT NULL
  AS 'STOP: all six approved magnitude thresholds are required';
ASSERT NULLIF(TRIM(v_approval_reference), '') IS NOT NULL
  AND NULLIF(TRIM(v_approved_by), '') IS NOT NULL
  AND v_approved_at IS NOT NULL
  AS 'STOP: approval_reference, approved_by, and approved_at are required';

-- Duplicate/replay preflight. The procedure repeats these checks inside its trusted boundary.
ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_magnitude_config`
  WHERE effective_start <= CURRENT_TIMESTAMP()
    AND (effective_end IS NULL OR effective_end > CURRENT_TIMESTAMP())) = 0
  AS 'STOP: an active Unit 2 magnitude configuration already exists';
ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_magnitude_config`
  WHERE config_id = v_config_id) = 0
  AS 'STOP: config_id already exists';
ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_magnitude_run`
  WHERE pipeline_run_id = v_baseline_run_id) = 0
  AS 'STOP: baseline already has a magnitude result';

CALL `pacific-plating-282708.sap_integration_v3.sp_bootstrap_v3_unit2_magnitude`(
  v_baseline_run_id,
  v_config_id,
  v_effective_start,
  v_effective_end,
  v_records_absolute,
  v_records_percentage,
  v_orders_absolute,
  v_orders_percentage,
  v_amount_satang_absolute,
  v_amount_percentage,
  v_approval_reference,
  v_approved_by,
  v_approved_at
);

ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_magnitude_config`
  WHERE config_id = v_config_id
    AND effective_start = v_effective_start
    AND effective_end IS NOT DISTINCT FROM v_effective_end
    AND records_absolute = v_records_absolute
    AND records_percentage = v_records_percentage
    AND orders_absolute = v_orders_absolute
    AND orders_percentage = v_orders_percentage
    AND amount_satang_absolute = v_amount_satang_absolute
    AND amount_percentage = v_amount_percentage
    AND approval_reference = v_approval_reference
    AND approved_by = v_approved_by
    AND approved_at = v_approved_at) = 1
  AS 'POSTCHECK FAILED: exact approved configuration was not committed';
ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_magnitude_run`
  WHERE pipeline_run_id = v_baseline_run_id
    AND baseline_run_id = v_baseline_run_id
    AND config_id = v_config_id
    AND breached_cells = 0
    AND status = 'PASS') = 1
  AS 'POSTCHECK FAILED: exact self-baseline PASS row is missing';
ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_distribution`
  WHERE pipeline_run_id = v_baseline_run_id) > 0
  AS 'POSTCHECK FAILED: baseline distribution is missing';
ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_magnitude_result`
  WHERE pipeline_run_id = v_baseline_run_id
    AND baseline_run_id = v_baseline_run_id
    AND config_id = v_config_id
    AND ARRAY_LENGTH(breach_reasons) = 0)
  = (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_distribution`
    WHERE pipeline_run_id = v_baseline_run_id)
  AS 'POSTCHECK FAILED: magnitude results do not conserve distribution cells';

SELECT
  v_baseline_run_id AS baseline_run_id,
  v_config_id AS config_id,
  'PASS' AS bootstrap_status,
  'Run a fresh non-bootstrap Units 1-5 build with delivery disabled' AS next_action;
