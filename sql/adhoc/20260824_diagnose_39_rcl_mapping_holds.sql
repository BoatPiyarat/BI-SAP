-- READ ONLY / diagnosis for the 39 known-clean missing RCL pairs against fresh V3 run.
WITH reported AS (
  SELECT * FROM UNNEST([
    STRUCT('L80385996-V1' AS order_item,2 AS period),STRUCT('L80391048-V1',2),
    STRUCT('L80399700-V1',2),STRUCT('L80399744-V1',2),STRUCT('L80400031-V1',2),
    STRUCT('L80401659-V1',2),STRUCT('L80404037-V1',2),STRUCT('L80407354-V1',2),
    STRUCT('L80409682-V1',2),STRUCT('L80409758-V1',2),STRUCT('L80410554-V1',2),
    STRUCT('L80415229-V1',2),STRUCT('L80415308-V1',2),STRUCT('L80415310-V1',2),
    STRUCT('L80416405-V1',2),STRUCT('L80417258-V1',2),STRUCT('L80417469-V1',2),
    STRUCT('L80421374-V1',2),STRUCT('L80421378-V1',2),STRUCT('L80422758-V1',2),
    STRUCT('L80423766-V1',2),STRUCT('L80428041-V1',2),STRUCT('L80429468-V1',2),
    STRUCT('L80429605-V1',2),STRUCT('L80429606-V1',2),STRUCT('L80438560-V1',2),
    STRUCT('L80438618-V1',2),STRUCT('L80440602-V1',2),STRUCT('L80440818-V1',2),
    STRUCT('L80445725-V1',3),STRUCT('L80447777-V1',2),STRUCT('L80448678-V1',2),
    STRUCT('L80456658-V1',2),STRUCT('L80462072-V1',2),STRUCT('L80463842-V1',3),
    STRUCT('L80473258-V1',2),STRUCT('L80555253-V1',2),STRUCT('L80577344-V1',2),
    STRUCT('L79586489-V1',7)
  ])
),
holds AS (
  SELECT h.order_item,h.period,h.raw_payment_date,h.flow,h.product_scope,h.is_credit_shell,
    h.payment_source_type,h.payment_method_source,h.payment_channel_source,h.hold_code
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit3_mapping_hold` h
  JOIN reported r USING(order_item,period)
  WHERE h.pipeline_run_id='V3MANUAL-2026-08-24T18:27:00-ICT'
),
registry AS (
  SELECT flow,product_scope,is_credit_shell,payment_source_type,payment_method_source,
    payment_channel_source,
    COUNT(*) AS tuple_registry_rows,
    COUNTIF(approval_state='APPROVED') AS approved_rows,
    MIN(effective_start) AS min_effective_start,
    MAX(effective_end) AS max_effective_end,
    STRING_AGG(DISTINCT CONCAT(sap_payment_method,'/',sap_payment_channel),';' ORDER BY
      CONCAT(sap_payment_method,'/',sap_payment_channel)) AS sap_targets
  FROM `pacific-plating-282708.sap_integration_v3.payment_mapping_registry`
  GROUP BY flow,product_scope,is_credit_shell,payment_source_type,payment_method_source,
    payment_channel_source
)
SELECT h.hold_code,h.flow,h.product_scope,h.is_credit_shell,h.payment_source_type,
  h.payment_method_source,h.payment_channel_source,
  COUNT(*) AS held_pairs,
  COUNT(DISTINCT h.order_item) AS held_items,
  MIN(h.raw_payment_date) AS min_payment_date,
  MAX(h.raw_payment_date) AS max_payment_date,
  IFNULL(r.tuple_registry_rows,0) AS tuple_registry_rows,
  IFNULL(r.approved_rows,0) AS approved_rows,
  r.min_effective_start,r.max_effective_end,r.sap_targets,
  STRING_AGG(FORMAT('%s#%d',h.order_item,h.period),';' ORDER BY h.order_item,h.period) AS pair_detail
FROM holds h
LEFT JOIN registry r
  USING(flow,product_scope,is_credit_shell,payment_source_type,payment_method_source,
    payment_channel_source)
GROUP BY h.hold_code,h.flow,h.product_scope,h.is_credit_shell,h.payment_source_type,
  h.payment_method_source,h.payment_channel_source,r.tuple_registry_rows,r.approved_rows,
  r.min_effective_start,r.max_effective_end,r.sap_targets
ORDER BY held_pairs DESC;
