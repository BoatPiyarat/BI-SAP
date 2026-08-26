SELECT hold_code, COUNT(*) AS held_rows
FROM `pacific-plating-282708.sap_integration_v3.v3_onetime_create_hold`
WHERE pipeline_run_id = 'V3NIGHTLY-2026-08-26T13:23:38-e830fff2'
GROUP BY hold_code
ORDER BY held_rows DESC, hold_code;
