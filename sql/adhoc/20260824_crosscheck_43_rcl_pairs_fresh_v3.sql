-- READ ONLY / Class A evidence. Cross-checks Boat's exact 43 reported missing RCL period pairs
-- against fresh V3 run V3MANUAL-2026-08-24T18:27:00-ICT.
-- The four BASELINE_EXCEPTION pairs are taken from the reviewed finding; the other 39 are the
-- previously proven clean-but-not-in-SAP population. No wide SELECT * is used.

WITH reported_pairs AS (
  SELECT order_id,period,
    IF(CONCAT(order_id,'#',CAST(period AS STRING)) IN (
      'L78710141#2','L79361881#3','L78322384#4','L79770471#4'),
      'BASELINE_EXCEPTION','BASELINE_CLEAN_39') AS baseline_group
  FROM UNNEST([
    STRUCT('L78710141' AS order_id,2 AS period),STRUCT('L80385996',2),
    STRUCT('L80391048',2),STRUCT('L80399700',2),STRUCT('L80399744',2),
    STRUCT('L80400031',2),STRUCT('L80401659',2),STRUCT('L80404037',2),
    STRUCT('L80407354',2),STRUCT('L80409682',2),STRUCT('L80409758',2),
    STRUCT('L80410554',2),STRUCT('L80415229',2),STRUCT('L80415308',2),
    STRUCT('L80415310',2),STRUCT('L80416405',2),STRUCT('L80417258',2),
    STRUCT('L80417469',2),STRUCT('L80421374',2),STRUCT('L80421378',2),
    STRUCT('L80422758',2),STRUCT('L80423766',2),STRUCT('L80428041',2),
    STRUCT('L80429468',2),STRUCT('L80429605',2),STRUCT('L80429606',2),
    STRUCT('L80438560',2),STRUCT('L80438618',2),STRUCT('L80440602',2),
    STRUCT('L80440818',2),STRUCT('L80447777',2),STRUCT('L80448678',2),
    STRUCT('L80456658',2),STRUCT('L80462072',2),STRUCT('L80473258',2),
    STRUCT('L80555253',2),STRUCT('L80577344',2),STRUCT('L79361881',3),
    STRUCT('L80445725',3),STRUCT('L80463842',3),STRUCT('L78322384',4),
    STRUCT('L79770471',4),STRUCT('L79586489',7)
  ])
),
pair_mapping AS (
  SELECT r.order_id,r.period,r.baseline_group,
    COUNT(DISTINCT e.order_item) AS mapped_item_count,
    MIN(e.order_item) AS order_item
  FROM reported_pairs r
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.stg_payment_events` e
    ON e.order_id=r.order_id AND e.period=r.period
  GROUP BY r.order_id,r.period,r.baseline_group
),
checked AS (
  SELECT m.order_id,m.period,m.baseline_group,m.order_item,m.mapped_item_count,
    (SELECT COUNT(*)
     FROM `pacific-plating-282708.sap_integration_v3.stg_sap_state` s
     WHERE s.U_OrderItem=m.order_item AND s.U_Period=m.period
       AND NULLIF(TRIM(s.U_InvoiceNo),'') IS NOT NULL) AS sap_rows,
    (SELECT COUNT(*)
     FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity` i
     WHERE i.pipeline_run_id='V3MANUAL-2026-08-24T18:27:00-ICT'
       AND i.file_role='NEWPAYMENT' AND i.order_item=m.order_item AND i.period=m.period)
      AS identity_rows,
    (SELECT COUNT(*)
     FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_delivery_ready` d
     WHERE d.OrderItem=m.order_item AND SAFE_CAST(d.Period AS INT64)=m.period)
      AS delivery_ready_rows
  FROM pair_mapping m
),
classified AS (
  SELECT order_id,period,baseline_group,order_item,
    CASE
      WHEN mapped_item_count!=1 THEN 'MAPPING_NOT_EXACT_ONE'
      WHEN sap_rows>0 THEN 'NOW_IN_SAP'
      WHEN identity_rows=1 AND delivery_ready_rows=1 THEN 'FRESH_V3_READY'
      WHEN identity_rows=0 THEN 'NOT_IN_FRESH_V3_IDENTITY'
      ELSE 'FRESH_V3_IDENTITY_NOT_DELIVERY_READY'
    END AS fresh_status
  FROM checked
),
regression_gate AS (
  SELECT COUNTIF(baseline_group='BASELINE_CLEAN_39'
    AND fresh_status='FRESH_V3_READY') AS clean_pairs_ready
  FROM classified
)
SELECT baseline_group,fresh_status,
  IF(clean_pairs_ready=39,'PASS',
    ERROR(CONCAT('Expected all 39 known-clean pairs in FRESH_V3_READY; found ',
      CAST(clean_pairs_ready AS STRING)))) AS regression_signal,
  COUNT(*) AS reported_pairs,
  COUNT(DISTINCT order_item) AS order_items,
  STRING_AGG(FORMAT('%s#%d=>%s',order_id,period,IFNULL(order_item,'<NULL>')),
    ';' ORDER BY order_id,period) AS pair_detail
FROM classified
CROSS JOIN regression_gate
GROUP BY baseline_group,fresh_status,clean_pairs_ready
ORDER BY baseline_group,fresh_status;
