-- F1 pre-deploy audit at expected_state flow grain. Read only.
SELECT
  e.flow,
  COUNT(*) AS expected_records,
  COUNTIF(NULLIF(TRIM(d.insured_id), '') IS NULL) AS insured_id_needing_default,
  COUNTIF(d.insured_id = '-') AS already_defaulted
FROM `pacific-plating-282708.sap_integration_v3.expected_state` e
LEFT JOIN `pacific-plating-282708.sap_integration_v3.stg_order_dim` d USING (order_item)
GROUP BY e.flow
ORDER BY e.flow;
