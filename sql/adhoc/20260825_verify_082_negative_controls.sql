-- READ ONLY verification (negative controls for 082's view-body logic).
-- 1. L78753909-V1 is ONETIME, must NOT appear (proves correct flow scoping).
-- 2. A deterministic sample of 20 current RCL order_items with TotalPeriods>1 and a positively
--    populated latest detail set must NOT appear (proves no false positives on valid schedules).
WITH latest_snapshot AS (
  SELECT * EXCEPT(rn) FROM (
    SELECT *, ROW_NUMBER() OVER (
      PARTITION BY transaction_id ORDER BY update_time DESC, id DESC) AS rn
    FROM `pacific-plating-282708.careos.carepay_transaction_snapshots`
  ) WHERE rn = 1
),
detail_counts AS (
  SELECT s.transaction_id, s.id AS snapshot_id, s.number_of_installment,
    COUNT(d.id) AS detail_row_count
  FROM latest_snapshot s
  LEFT JOIN `pacific-plating-282708.careos.carepay_transaction_snapshot_installment_details` d
    ON d.snapshot_id = s.id
  GROUP BY 1,2,3
),
hold_view_body AS (
  SELECT DISTINCT ss.order_item
  FROM `pacific-plating-282708.sap_integration_v3.stg_schedule` ss
  JOIN detail_counts dc ON dc.transaction_id = ss.transaction_id
  WHERE ss.flow = 'RCL' AND ss.total_periods > 1 AND dc.detail_row_count = 0
),
rcl_sample AS (
  SELECT DISTINCT ss.order_item AS OrderItem
  FROM `pacific-plating-282708.sap_integration_v3.stg_schedule` ss
  JOIN detail_counts dc ON dc.transaction_id=ss.transaction_id
  WHERE ss.flow='RCL' AND ss.total_periods>1 AND dc.detail_row_count>0
  ORDER BY ss.order_item
  LIMIT 20
)
SELECT
  (SELECT COUNT(*) FROM hold_view_body WHERE order_item='L78753909-V1') AS l78753909_appears,
  (SELECT COUNT(*) FROM rcl_sample s WHERE EXISTS(
     SELECT 1 FROM hold_view_body h WHERE h.order_item=s.OrderItem)) AS false_positives_in_sample,
  (SELECT COUNT(*) FROM rcl_sample) AS sample_size;
