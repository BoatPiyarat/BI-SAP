SELECT l.run_id,l.ended_at
FROM `pacific-plating-282708.sap_integration_v3.pipeline_run_log` l
WHERE l.step='UNIT1_COMPLETE' AND l.status='SUCCESS'
  AND NOT EXISTS (
    SELECT 1
    FROM `pacific-plating-282708.sap_integration_v3.v3_onetime_create_build_manifest` m
    WHERE m.pipeline_run_id=l.run_id
  )
QUALIFY ROW_NUMBER() OVER (ORDER BY l.ended_at DESC,l.run_id DESC)=1;
