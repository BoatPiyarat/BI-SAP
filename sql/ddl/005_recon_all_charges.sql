-- 005_recon_all_charges.sql
-- Goal (Boat, 2026-07-25): "make the job cover all transaction (recon) - auto - we can do
-- workaround while waiting Attila." This recon does NOT depend on sap-extract-schedule/
-- sap-extract-job at all - it just reads whatever's currently in BigQuery (SAP_LIVE via
-- stg_sap_state, refreshed whenever the extract runs - manual or automatic) and CareOS/
-- CarePay directly. So it can run on its own schedule regardless of the IAM incident.
--
-- Three-bucket model (generalizes tonight's cancelled-installment reconciliation to ALL
-- successful charges, not just cancelled ones):
--   NO_ORDER_ITEM     - charge has no linked CareOS order at all (confirmed real, 2026-07-25:
--                       ~17,457 charges, ~130M THB all-time, ~21M THB in 2026, still
--                       happening - ~461 in the last 30 days, average age 500-1450 days,
--                       i.e. these orders never get created, not just delayed). This is a
--                       CareOS/product-engineering gap, upstream of the SAP interface
--                       entirely - surfaced here for visibility only, not something this
--                       pipeline can fix.
--   MISSING_FROM_SAP  - charge has an order_item + period, but stg_sap_state has no evidence
--                       (no row, or no real invoice) that SAP ever recorded it - this IS
--                       actionable on the SAP-interface side.
--   IN_SAP            - charge has an order_item + period, and stg_sap_state shows a real
--                       invoice for it. Healthy.
--
-- Grain: one row per (order_item, installment_number) that CareOS shows a SUCCESSFUL charge
-- for - NOT one row per charge_id (a period can have multiple charge attempts; we care about
-- "was this period ever successfully paid," not charge-attempt counting).
--
-- Scoped to 2026 charges only (Boat, 2026-07-25) - ignores 2022-2023 entirely. Two real bugs
-- were found and fixed while building this (both would have overcounted MISSING_FROM_SAP):
--   1. Credit Shell orders use a single invoice on period 1 only, not one per period -
--      excluded (U_OrderID LIKE 'C#%') from the cancelled-installment recon this generalizes.
--   2. Orders with both a compulsory (-M1) and voluntary (-V1) item: a bundled charge was
--      fanning out to both items in the join, wrongly flagging -M1 as missing periods 2+ that
--      structurally only ever belong to -V1's schedule. Fixed via item_rank (prefer non-
--      compulsory item per charge).
-- After both fixes + 2026 scoping, results (2026-07-25): IN_SAP 162,384 (~1.02B THB),
-- MISSING_FROM_SAP 48,993 (~108M THB), NO_ORDER_ITEM 2,202 (~21M THB). Spot-checked a random
-- MISSING_FROM_SAP sample (L79912530-V1 period 2) against real SAP data: genuinely stuck as
-- Pending with no invoice, last touched 2026-03-26, despite CareOS showing it paid
-- 2026-04-30 - periods 1/3/4 on the same order synced fine. Confirms the bucket is catching
-- real gaps, not just leftover query artifacts - though further edge cases may still exist
-- (only spot-checked, not exhaustively proven).

CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_recon_all_charges`()
BEGIN

CREATE OR REPLACE TABLE `pacific-plating-282708.sap_integration_v3.recon_careos_charges`
PARTITION BY DATE(first_paid_time)
CLUSTER BY recon_status, order_item
AS
WITH charge_link_raw AS (
  -- an order can have >1 order_item (e.g. compulsory -M1 + voluntary -V1 bundled
  -- together) - naive join fans a single charge out across all of them. Compulsory
  -- items only ever get ONE period (period 1, full premium) in SAP by design - they
  -- don't carry a real per-period installment schedule the way voluntary items do
  -- (confirmed live 2026-07-25: an M1 item had zero SAP rows while its sibling V1
  -- had a full 6-period paid history - the charges genuinely belong to V1's
  -- schedule, not M1's). So: prefer the non-compulsory item per charge, so a
  -- bundled charge is checked against the item that actually has a real per-period
  -- schedule, not fanned out across both.
  SELECT
    c.id AS charge_id,
    c.transaction_id,
    c.installment_number,
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
  LEFT JOIN `pacific-plating-282708.careos.careos_orders` o ON CONCAT('transactions/', t.id) = o.payment
  LEFT JOIN `pacific-plating-282708.careos.careos_order_items` oi ON oi.order_id = o.id
  WHERE c.status = 'SUCCESSFUL'
    -- scoped to 2026 only (Boat, 2026-07-25) - ignore 2022-2023 history entirely, both
    -- to sidestep the unresolved raw_sap_live/SAP_LIVE backfill-scope question (design
    -- docs decision #4, never settled) and because current operational health matters
    -- more than an unvalidated historical number
    AND c.update_time >= '2026-01-01'
),
charge_link AS (
  SELECT * EXCEPT(item_rank) FROM charge_link_raw WHERE item_rank = 1
),

careos_periods AS (
  -- collapse to one row per (order_item, period) - the unit that matters for recon,
  -- not per charge attempt. NO_ORDER_ITEM charges (order_item IS NULL) must NOT be
  -- grouped together across different transactions - COALESCE onto transaction_id so
  -- each stays distinct instead of collapsing into one row per installment_number.
  SELECT
    ANY_VALUE(order_item) AS order_item,
    installment_number AS period,
    MIN(order_id) AS order_id,
    MIN(payment_option) AS payment_option,
    MIN(lead_human_id) AS lead_human_id,
    MIN(charge_time) AS first_paid_time,
    SUM(amount) AS total_amount_satang
  FROM charge_link
  GROUP BY COALESCE(order_item, CONCAT('NO_ORDER:', transaction_id)), installment_number
),

sap_invoiced AS (
  -- a period counts as "in SAP" only if it has a real invoice - status alone isn't
  -- reliable once an order's been cancelled (cancel mirrors every period to Cancelled,
  -- see 30_SAP_CHANGELOG.md 2026-07-25)
  SELECT DISTINCT U_OrderItem, U_Period
  FROM `pacific-plating-282708.sap_integration_v3.stg_sap_state`
  WHERE IFNULL(U_InvoiceNo, '') != ''
)

SELECT
  cp.order_item,
  cp.period,
  cp.order_id,
  cp.payment_option,
  cp.lead_human_id,
  cp.first_paid_time,
  ROUND(cp.total_amount_satang / 100, 2) AS total_amount_thb,
  CASE
    WHEN cp.order_item IS NULL THEN 'NO_ORDER_ITEM'
    WHEN sap.U_OrderItem IS NOT NULL THEN 'IN_SAP'
    ELSE 'MISSING_FROM_SAP'
  END AS recon_status,
  CURRENT_TIMESTAMP() AS recon_checked_at
FROM careos_periods cp
LEFT JOIN sap_invoiced sap ON sap.U_OrderItem = cp.order_item AND sap.U_Period = cp.period;

END;
