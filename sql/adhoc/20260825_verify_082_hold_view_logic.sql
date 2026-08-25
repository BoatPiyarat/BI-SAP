-- READ ONLY verification. Reproduces 082's view body as a plain SELECT (no CREATE, no
-- persistence) to prove the detection logic before Codex deploys the actual view.
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
)
SELECT DISTINCT
  ss.order_item,
  ss.order_id,
  ss.transaction_id,
  dc.snapshot_id,
  ss.total_periods AS declared_total_periods,
  dc.number_of_installment,
  dc.detail_row_count,
  'HOLD_EMPTY_INSTALLMENT_DETAILS' AS rule_code
FROM `pacific-plating-282708.sap_integration_v3.stg_schedule` ss
JOIN detail_counts dc ON dc.transaction_id = ss.transaction_id
WHERE ss.flow = 'RCL'
  AND ss.total_periods > 1
  AND dc.detail_row_count = 0
ORDER BY ss.order_item;
