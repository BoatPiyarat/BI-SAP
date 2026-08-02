-- SOURCE ONLY / Class A diagnostic. One batched plan; no table/GCS/SAP mutation.
-- Run only through scripts/bq_safe_query.sh (mandatory dry-run + 20 GiB ceiling).
-- Event count is not assumed to equal file row count.

DECLARE p_pipeline_run_id STRING DEFAULT 'V3NIGHTLY-2026-08-02T09:02:26-b36e1712';

ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit3_run_summary`
  WHERE pipeline_run_id=p_pipeline_run_id)=1
  AS 'Unit 5 population gate requires exactly one Unit 3 summary';
ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.v3_automation_gate_result`
  WHERE pipeline_run_id=p_pipeline_run_id AND blocker_count!=0)=0
  AS 'Unit 5 population gate requires every automation blocker count to be zero';

CREATE TEMP TABLE _releasable_event AS
SELECT e.*,
  IF(EXISTS (SELECT 1
      FROM `pacific-plating-282708.sap_integration_v3.sap_mirror_doc` m
      WHERE m.U_OrderItem=e.order_item), 'NEWPAYMENT', 'CREATE') AS file_role
FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_event_shadow` e
WHERE e.pipeline_run_id=p_pipeline_run_id
  AND e.outcome='READY_CREATE_OR_PAYMENT'
  AND NOT EXISTS (
    SELECT 1
    FROM `pacific-plating-282708.sap_integration_v3.v3_unit3_mapping_hold` h
    WHERE h.pipeline_run_id=e.pipeline_run_id
      AND h.order_item=e.order_item
      AND h.period=e.period
      AND h.charge_id=e.charge_id);

-- CREATE is an order-item package: include the complete schedule spine, not only the Paid event.
CREATE TEMP TABLE _create_spine AS
SELECT s.order_item,s.order_id,s.period,s.total_periods,s.flow,s.expected_status,
  s.expected_invoice_no
FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_schedule_shadow` s
WHERE s.pipeline_run_id=p_pipeline_run_id
  AND EXISTS (SELECT 1 FROM _releasable_event e
    WHERE e.file_role='CREATE' AND e.order_item=s.order_item);

CREATE TEMP TABLE _create_spine_check AS
SELECT order_item,
  COUNT(*) AS rows_in_spine,
  COUNT(DISTINCT period) AS distinct_periods,
  MIN(period) AS min_period,
  MAX(period) AS max_period,
  MAX(total_periods) AS total_periods,
  COUNT(DISTINCT total_periods) AS total_period_variants
FROM _create_spine
GROUP BY order_item;

ASSERT (SELECT COUNT(*) FROM _create_spine_check
  WHERE total_period_variants!=1 OR min_period!=1 OR max_period!=total_periods
     OR distinct_periods!=total_periods OR rows_in_spine!=total_periods)=0
  AS 'CREATE package lacks the exact 1..TotalPeriods schedule spine';

SELECT 'RELEASABLE_TOTAL' AS metric,'ALL' AS file_role,
  COUNT(*) AS records,COUNT(DISTINCT order_id) AS orders,
  SUM(charge_amount) AS amount_satang
FROM _releasable_event
UNION ALL
SELECT 'RELEASABLE_BY_ROLE',file_role,COUNT(*),COUNT(DISTINCT order_id),SUM(charge_amount)
FROM _releasable_event GROUP BY file_role
UNION ALL
SELECT 'DISTINCT_ORDER_ITEMS_BY_ROLE',file_role,COUNT(DISTINCT order_item),
  COUNT(DISTINCT order_id),NULL
FROM _releasable_event GROUP BY file_role
UNION ALL
SELECT 'MULTI_EVENT_ITEM_PERIODS',file_role,COUNT(*),COUNT(DISTINCT order_id),
  SUM(charge_amount)
FROM (
  SELECT file_role,order_item,period,ANY_VALUE(order_id) order_id,
    COUNT(*) event_count,SUM(charge_amount) charge_amount
  FROM _releasable_event
  GROUP BY file_role,order_item,period
  HAVING event_count>1)
GROUP BY file_role
UNION ALL
SELECT 'CREATE_FILE_ROWS','CREATE',COUNT(*),COUNT(DISTINCT order_id),NULL
FROM _create_spine
UNION ALL
SELECT 'CREATE_EXPECTED_PAYLOAD_ROWS','CREATE',
  (SELECT COUNT(*) FROM _create_spine)+IFNULL((SELECT SUM(event_count-1) FROM (
    SELECT COUNT(*) event_count FROM _releasable_event
    WHERE file_role='CREATE' GROUP BY order_item,period HAVING event_count>1)),0),
  COUNT(DISTINCT order_id),NULL
FROM _create_spine
UNION ALL
SELECT 'CREATE_ORDER_ITEMS_WITH_BAD_SPINE','CREATE',COUNT(*),COUNT(*),NULL
FROM _create_spine_check
WHERE total_period_variants!=1 OR min_period!=1 OR max_period!=total_periods
   OR distinct_periods!=total_periods OR rows_in_spine!=total_periods
ORDER BY metric,file_role;
