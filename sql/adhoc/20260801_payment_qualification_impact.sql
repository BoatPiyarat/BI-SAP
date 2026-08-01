-- Read-only impact measurement for Boat rule 2. Run dry-run first with 20 GiB ceiling.
WITH raw AS (
  SELECT c.id AS charge_id, o.id AS order_pk, oi.id AS order_item_pk,
    oi.human_id AS order_item, l.id AS lead_pk, l.status AS lead_status
  FROM `pacific-plating-282708.careos.carepay_charges` c
  JOIN `pacific-plating-282708.careos.carepay_transactions` t ON t.id = c.transaction_id
  LEFT JOIN `pacific-plating-282708.careos.careos_orders` o
    ON CONCAT('transactions/', t.id) = o.payment
  LEFT JOIN `pacific-plating-282708.careos.careos_order_items` oi ON oi.order_id = o.id
  LEFT JOIN `pacific-plating-282708.careos.careos_leads` l ON CONCAT('leads/', l.id) = o.lead
  WHERE c.status = 'SUCCESSFUL'
), per_charge AS (
  SELECT charge_id,
    CASE
      WHEN COUNTIF(order_pk IS NOT NULL) = 0 THEN 'NO_ORDER'
      WHEN COUNTIF(order_item_pk IS NOT NULL) = 0 THEN 'NO_ORDER_ITEM'
      WHEN COUNTIF(NULLIF(TRIM(order_item), '') IS NOT NULL) = 0 THEN 'EMPTY_ORDER_ITEM_HUMAN_ID'
      WHEN COUNTIF(lead_pk IS NOT NULL AND lead_status = 'LEAD_STATUS_PURCHASED') = 0
        THEN 'LEAD_NOT_PURCHASED'
      ELSE 'QUALIFIED'
    END AS qualification_status
  FROM raw GROUP BY charge_id
)
SELECT qualification_status, COUNT(*) AS successful_charges
FROM per_charge GROUP BY qualification_status ORDER BY qualification_status;
