-- Read-only postcheck for the atomic DDL 067 definition deployment.

ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.ROUTINES`
  WHERE routine_name = 'sp_build_v3_daily_completeness_snapshot') = 1
  AS 'daily completeness procedure is absent or duplicated';

ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.PARAMETERS`
  WHERE specific_name = 'sp_build_v3_daily_completeness_snapshot'
    AND ordinal_position > 0) = 1
  AS 'daily completeness procedure must have exactly one parameter';

ASSERT (SELECT LOGICAL_AND(
    STRPOS(routine_definition,
      'completeness metric rows already exist; immutable replay refused') > 0
    AND STRPOS(routine_definition,
      'completeness evidence rows already exist; immutable replay refused') > 0
    AND STRPOS(routine_definition, 'BEGIN TRANSACTION') > 0
    AND STRPOS(routine_definition, 'COMMIT TRANSACTION') > 0)
  FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.ROUTINES`
  WHERE routine_name = 'sp_build_v3_daily_completeness_snapshot')
  AS 'live daily completeness procedure lacks atomic replay-safety markers';

ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.v3_daily_completeness_run`) = 0
  AS 'definition deployment unexpectedly created completeness run rows';
ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.v3_daily_completeness_metric`) = 0
  AS 'definition deployment unexpectedly created completeness metric rows';
ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.v3_daily_completeness_evidence`) = 0
  AS 'definition deployment unexpectedly created completeness evidence rows';

SELECT routine_name,
  TO_HEX(SHA256(routine_definition)) AS routine_definition_sha256,
  (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_daily_completeness_run`) AS run_rows,
  (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_daily_completeness_metric`) AS metric_rows,
  (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.v3_daily_completeness_evidence`)
    AS evidence_rows
FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.ROUTINES`
WHERE routine_name = 'sp_build_v3_daily_completeness_snapshot';
