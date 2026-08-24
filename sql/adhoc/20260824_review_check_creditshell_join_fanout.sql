-- READ ONLY reviewer verification query (Claude Code, RQ-20260824-1217).
-- Checks whether cancelled_change_orders join fanout is a live, concrete risk for the
-- unreviewed 20260824_qualify_v3_normal_motor_newpayment.sql pattern:
--   LEFT JOIN cancelled_change_orders c ON c.current_human_id = p.OrderID OR c.old_human_id = p.OrderID
-- No mutation, no write.
WITH dup_current AS (
  SELECT current_human_id, COUNT(*) n
  FROM `pacific-plating-282708.careos.cancelled_change_orders`
  GROUP BY current_human_id
  HAVING COUNT(*) > 1
),
overlap_current_old AS (
  SELECT cc.current_human_id
  FROM `pacific-plating-282708.careos.cancelled_change_orders` cc
  WHERE cc.current_human_id IN (
    SELECT old_human_id FROM `pacific-plating-282708.careos.cancelled_change_orders`
  )
)
SELECT
  (SELECT COUNT(*) FROM dup_current) AS order_ids_with_multiple_current_human_id_rows,
  (SELECT COUNT(*) FROM overlap_current_old) AS order_ids_that_are_both_current_and_old_somewhere;
