-- Read-only live dependency inventory for replacing workflow revision 000009-e96.
WITH expected_parameters AS (
  SELECT * FROM UNNEST([
    STRUCT(1 AS ordinal_position, 'p_pipeline_run_id' AS parameter_name),
    STRUCT(2, 'p_export_run_id'), STRUCT(3, 'p_archive_uri'),
    STRUCT(4, 'p_archive_generation'), STRUCT(5, 'p_production_uri'),
    STRUCT(6, 'p_production_generation'), STRUCT(7, 'p_size_bytes'),
    STRUCT(8, 'p_crc32c'), STRUCT(9, 'p_header_column_count'),
    STRUCT(10, 'p_data_row_count'), STRUCT(11, 'p_production_file_name'),
    STRUCT(12, 'p_sap_result_file_name'), STRUCT(13, 'p_file_sha256')
  ])
),
live_parameters AS (
  SELECT ordinal_position, parameter_name
  FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.PARAMETERS`
  WHERE specific_name = 'sp_mark_v3_exact_delivery'
),
parameter_diff AS (
  (SELECT * FROM expected_parameters EXCEPT DISTINCT SELECT * FROM live_parameters)
  UNION ALL
  (SELECT * FROM live_parameters EXCEPT DISTINCT SELECT * FROM expected_parameters)
)
SELECT
  (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name = 'sap_delivery_manifest_v3'
      AND column_name = 'production_file_name') AS production_file_name_column_count,
  (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.ROUTINES`
    WHERE routine_name = 'sp_mark_v3_exact_delivery') AS delivery_routine_count,
  (SELECT COUNT(*) FROM live_parameters) AS delivery_parameter_count,
  (SELECT COUNT(*) FROM parameter_diff) AS delivery_parameter_diff_count,
  (SELECT COUNT(*)
    FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.ROUTINES`
    WHERE routine_name = 'sp_build_v3_daily_completeness_snapshot')
    AS completeness_routine_count,
  (SELECT TO_HEX(SHA256(routine_definition))
    FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.ROUTINES`
    WHERE routine_name = 'sp_mark_v3_exact_delivery') AS delivery_definition_sha256,
  (SELECT TO_HEX(SHA256(routine_definition))
    FROM `pacific-plating-282708.sap_integration_v3.INFORMATION_SCHEMA.ROUTINES`
    WHERE routine_name = 'sp_build_v3_daily_completeness_snapshot')
    AS completeness_definition_sha256;
