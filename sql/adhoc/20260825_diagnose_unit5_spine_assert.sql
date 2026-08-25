DECLARE target_run_id STRING DEFAULT 'V3NIGHTLY-2026-08-25T11:17:18-ca7ee9e7';

SELECT
  'HOLD' AS evidence,
  hold_code AS key,
  COUNT(*) AS row_count,
  COUNT(DISTINCT order_item) AS item_count,
  STRING_AGG(DISTINCT order_item,';' ORDER BY order_item LIMIT 20) AS detail
FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_balance_hold`
WHERE pipeline_run_id=target_run_id
GROUP BY hold_code

UNION ALL

SELECT
  'BAD_DELIVERY_SPINE',
  OrderItem,
  COUNT(*),
  1,
  FORMAT('period_n=%d; min=%d; max=%d; total_values=%d; total=%d; keys=%s',
    COUNT(DISTINCT SAFE_CAST(Period AS INT64)),MIN(SAFE_CAST(Period AS INT64)),
    MAX(SAFE_CAST(Period AS INT64)),COUNT(DISTINCT SAFE_CAST(TotalPeriods AS INT64)),
    MAX(SAFE_CAST(TotalPeriods AS INT64)),
    STRING_AGG(CONCAT(Period,':',COALESCE(InvoiceNo,'<blank>')),';' ORDER BY
      SAFE_CAST(Period AS INT64),InvoiceNo))
FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_delivery_ready`
GROUP BY OrderItem
HAVING COUNT(DISTINCT SAFE_CAST(TotalPeriods AS INT64))!=1
  OR MIN(SAFE_CAST(Period AS INT64))!=1
  OR MAX(SAFE_CAST(Period AS INT64))!=MAX(SAFE_CAST(TotalPeriods AS INT64))
  OR COUNT(DISTINCT SAFE_CAST(Period AS INT64))!=MAX(SAFE_CAST(TotalPeriods AS INT64))
  OR COUNT(*)!=MAX(SAFE_CAST(TotalPeriods AS INT64))
ORDER BY evidence,key;
