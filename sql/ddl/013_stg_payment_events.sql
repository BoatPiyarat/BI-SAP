-- 013_stg_payment_events.sql
-- P1 build (Boat, 2026-07-25: "start building" V3 P1-P3).
-- Implements SAP_INTERFACE_REDESIGN_V3.md §2.3 stg_payment_events - "population driver ใหม่...
-- ขับจาก 'เงินเข้า' (charges SUCCESSFUL) ไม่ใช่ขับจาก follow_ups/snapshot". Partitioned by charge
-- date (D1: incremental, not full-history rescan every run) and MERGE-refreshed by watermark on
-- charge update_time (same incremental pattern as stg_order_dim).
--
-- Reuses the item_rank de-fanout fix already verified live this session (sp_recon_all_charges,
-- 005_recon_all_charges.sql): a single bundled charge can join to BOTH the compulsory (-M1) and
-- voluntary (-V1) order_items of the same order via the order->order_items join. Compulsory items
-- never carry a real per-period schedule (confirmed live: an M1 item had zero SAP rows while its
-- sibling V1 had a full paid history) - so a bundled charge belongs to the non-compulsory item's
-- schedule. Without this, every consumer of this table would inherit the same fan-out bug this
-- session spent real effort finding and fixing once already.

-- NOTE (fixed 2026-07-25, before expected_state was built on top of this): charges.id (UUID) and
-- charges.third_party_id (e.g. "OR6610021650539" for bank refs, or Omise's own "chrg_..." format
-- for card/QR channels) are DIFFERENT fields - confirmed by checking real rows, not assumed. The
-- real InvoiceNo comes from third_party_id (falling back to order_items.human_id when null on a
-- successful charge, per the real production logic in sap_dashboard_carepay_installment), never
-- from charges.id. charge_id (= charges.id) stays as this table's own unique key; third_party_id
-- is carried separately so callers can pass the correct value to fn_invoice_no.
CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.stg_payment_events` (
  charge_id STRING,
  third_party_id STRING,
  order_item STRING,
  order_id STRING,
  transaction_id STRING,
  period INT64,
  amount INT64,
  charge_time TIMESTAMP,
  payment_option STRING,
  lead_human_id STRING,
  event_refreshed_at TIMESTAMP
)
PARTITION BY DATE(charge_time)
CLUSTER BY order_item;

CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_refresh_stg_payment_events`()
BEGIN
  DECLARE watermark TIMESTAMP DEFAULT (
    SELECT IFNULL(MAX(charge_time), TIMESTAMP('2000-01-01'))
    FROM `pacific-plating-282708.sap_integration_v3.stg_payment_events`
  );

  MERGE `pacific-plating-282708.sap_integration_v3.stg_payment_events` T
  USING (
    WITH charge_link_raw AS (
      SELECT
        c.id AS charge_id,
        -- fallback matches the real production InvoiceNo rule: successful charge with no
        -- third_party_id falls back to the order_item's own human_id
        COALESCE(c.third_party_id, oi.human_id) AS third_party_id,
        c.transaction_id,
        c.installment_number AS period,
        c.amount,
        c.update_time AS charge_time,
        t.payment_option,
        t.lead_human_id,
        o.human_id AS order_id,
        oi.human_id AS order_item,
        ROW_NUMBER() OVER (
          PARTITION BY c.id
          ORDER BY IF(oi.motor_item_type = 'MOTOR_TYPE_COMPULSORY', 2, 1)
        ) AS item_rank
      FROM `pacific-plating-282708.careos.carepay_charges` c
      JOIN `pacific-plating-282708.careos.carepay_transactions` t ON t.id = c.transaction_id
      -- Qualification gate: money alone is not an SAP-interface population. A successful charge
      -- must resolve to an Order, a non-empty OrderItem human_id, and a PURCHASED lead.
      JOIN `pacific-plating-282708.careos.careos_orders` o
        ON CONCAT('transactions/', t.id) = o.payment
      JOIN `pacific-plating-282708.careos.careos_order_items` oi
        ON oi.order_id = o.id AND NULLIF(TRIM(oi.human_id), '') IS NOT NULL
      JOIN `pacific-plating-282708.careos.careos_leads` l
        ON CONCAT('leads/', l.id) = o.lead
       AND l.status = 'LEAD_STATUS_PURCHASED'
      WHERE c.status = 'SUCCESSFUL'
        AND c.update_time > watermark
    )
    SELECT
      charge_id, third_party_id, transaction_id, period, amount, charge_time, payment_option,
      lead_human_id, order_id, order_item, CURRENT_TIMESTAMP() AS event_refreshed_at
    FROM charge_link_raw
    WHERE item_rank = 1
  ) S
  ON T.charge_id = S.charge_id
  WHEN MATCHED THEN UPDATE SET
    order_item = S.order_item,
    order_id = S.order_id,
    third_party_id = S.third_party_id,
    transaction_id = S.transaction_id,
    period = S.period,
    amount = S.amount,
    charge_time = S.charge_time,
    payment_option = S.payment_option,
    lead_human_id = S.lead_human_id,
    event_refreshed_at = S.event_refreshed_at
  WHEN NOT MATCHED THEN INSERT (
    charge_id, third_party_id, order_item, order_id, transaction_id, period, amount, charge_time,
    payment_option, lead_human_id, event_refreshed_at
  ) VALUES (
    S.charge_id, S.third_party_id, S.order_item, S.order_id, S.transaction_id, S.period, S.amount,
    S.charge_time, S.payment_option, S.lead_human_id, S.event_refreshed_at
  );
END;
