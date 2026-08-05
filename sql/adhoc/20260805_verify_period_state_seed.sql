SELECT
  period_id,
  period_start,
  period_end,
  status,
  closing_at,
  closed_at,
  closed_by,
  state_version
FROM `pacific-plating-282708.sap_integration_v3.sap_period_state`
ORDER BY period_start;
