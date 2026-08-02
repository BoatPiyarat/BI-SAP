-- RULE-21 item-map diagnostic (read only; no payload, mutation, or approval implied).
-- Compare provisional mapping strategies and require replacement Paid acceptance in SAP.
WITH link_raw AS (
  SELECT DISTINCT old_human_id old_order_id, current_human_id new_order_id
  FROM `pacific-plating-282708.careos.cancelled_change_orders`
  WHERE old_human_id IS NOT NULL AND current_human_id IS NOT NULL
), links AS (
  SELECT p.*,
    (SELECT COUNT(*) FROM link_raw x WHERE x.old_order_id=p.old_order_id) old_degree,
    (SELECT COUNT(*) FROM link_raw x WHERE x.new_order_id=p.new_order_id) new_degree
  FROM link_raw p
), unambiguous AS (
  SELECT * FROM links WHERE old_degree=1 AND new_degree=1
), order_pk AS (
  SELECT human_id,id FROM `pacific-plating-282708.careos.careos_orders`
), old_items AS (
  SELECT l.old_order_id,l.new_order_id,oi.human_id old_item,
    oi.motor_item_type old_motor_type,oi.product old_product,oi.insurer old_insurer,
    oi.package old_package,REGEXP_EXTRACT(oi.human_id,r'-([^-]+)$') old_suffix
  FROM unambiguous l JOIN order_pk o ON o.human_id=l.old_order_id
  JOIN `pacific-plating-282708.careos.careos_order_items` oi ON oi.order_id=o.id
  JOIN `pacific-plating-282708.sap_integration_v3.sap_mirror_state` sm
    ON sm.U_OrderID=l.old_order_id AND sm.U_OrderItem=oi.human_id
  WHERE sm.TransactionStatus IN ('Paid','paid','Pending')
), new_items AS (
  SELECT l.old_order_id,l.new_order_id,oi.human_id new_item,
    oi.motor_item_type new_motor_type,oi.product new_product,oi.insurer new_insurer,
    oi.package new_package,REGEXP_EXTRACT(oi.human_id,r'-([^-]+)$') new_suffix,
    EXISTS(SELECT 1 FROM `pacific-plating-282708.sap_integration_v3.sap_mirror_state` sm
      WHERE sm.U_OrderID=l.new_order_id AND sm.U_OrderItem=oi.human_id
        AND sm.TransactionStatus IN ('Paid','paid')) new_paid_in_sap
  FROM unambiguous l JOIN order_pk o ON o.human_id=l.new_order_id
  JOIN `pacific-plating-282708.careos.careos_order_items` oi ON oi.order_id=o.id
), candidates AS (
  SELECT o.old_order_id,o.new_order_id,o.old_item,n.new_item,n.new_paid_in_sap,
    o.old_suffix=n.new_suffix suffix_match,
    o.old_suffix=n.new_suffix
      AND o.old_motor_type IS NOT DISTINCT FROM n.new_motor_type
      AND o.old_product IS NOT DISTINCT FROM n.new_product
      AND o.old_insurer IS NOT DISTINCT FROM n.new_insurer strict_match,
    o.old_motor_type IS NOT DISTINCT FROM n.new_motor_type
      AND o.old_product IS NOT DISTINCT FROM n.new_product
      AND o.old_insurer IS NOT DISTINCT FROM n.new_insurer
      AND o.old_package IS NOT DISTINCT FROM n.new_package tuple_match
  FROM old_items o JOIN new_items n USING(old_order_id,new_order_id)
), strategies AS (
  SELECT 'SUFFIX_ONLY' strategy,old_order_id,new_order_id,old_item,
    COUNTIF(suffix_match) candidate_count,
    COUNTIF(suffix_match AND new_paid_in_sap) paid_candidate_count
  FROM candidates GROUP BY 1,2,3,4
  UNION ALL
  SELECT 'SUFFIX_PLUS_TYPE_PRODUCT_INSURER',old_order_id,new_order_id,old_item,
    COUNTIF(strict_match),COUNTIF(strict_match AND new_paid_in_sap)
  FROM candidates GROUP BY 1,2,3,4
  UNION ALL
  SELECT 'TYPE_PRODUCT_INSURER_PACKAGE',old_order_id,new_order_id,old_item,
    COUNTIF(tuple_match),COUNTIF(tuple_match AND new_paid_in_sap)
  FROM candidates GROUP BY 1,2,3,4
)
SELECT strategy,COUNT(*) old_items,COUNTIF(candidate_count=0) no_match,
  COUNTIF(candidate_count=1) unique_match,COUNTIF(candidate_count>1) ambiguous_match,
  COUNTIF(candidate_count=1 AND paid_candidate_count=1) unique_match_paid_in_sap
FROM strategies GROUP BY strategy ORDER BY strategy;
