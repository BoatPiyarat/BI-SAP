-- 036_stg_order_dim_cancel_effective.sql
-- Boat 2026-07-29, CONFLICT RESOLVED: canonical definition is 2-field, careos_order_items ONLY.
-- (Supersedes this file's own first draft, which used a 3-field OR including careos_orders.is_cancelled
-- - that draft was NEVER DEPLOYED, so no live redeploy is needed, only this source correction. Reason
-- for dropping the order-level term: it only added ~1 item of coverage in practice, but risks pulling
-- an order-level cancel signal across ALL of an order's items - directly conflicting with the
-- per-order_item-only design constraint, since 98.5% of the item-level cancel population has a
-- still-active sibling on the same order (partial cancel-recreate, normal practice). Matches legacy
-- `02 RCB Motor cancel-new`'s own 2-field condition exactly.)
--
-- Nested definition (grain and source table called out per Boat's explicit ask - BOTH fields are
-- item grain, same table, no cross-table term):
--   is_cancelled_effective =
--        oi.is_cancelled IS TRUE       -- item grain, careos.careos_order_items.is_cancelled
--     OR oi.cancel_time IS NOT NULL    -- item grain, careos.careos_order_items.cancel_time
--   cancel_time_effective = oi.cancel_time   -- item grain, careos.careos_order_items.cancel_time
--     (verbatim, NULL if not set - never guess/derive a date; a row can be effective=TRUE with
--      cancel_time_effective NULL if only is_cancelled is set - see CANCEL_TIME_MISSING, planned
--      for the interface_daily_status update later in this batch)
--
-- NOT DEPLOYED YET - source only. Confirmed via `bq show`/INFORMATION_SCHEMA before this rewrite:
-- live `stg_order_dim` still has exactly 033's columns, no is_cancelled_effective/cancel_time_effective
-- column exists yet - so there was nothing live to fix, only this source file's formula.
--
-- Diagnostic context (2026-07-29, read-only, see docs/sessions/2026-07-29-claude.md): this 2-field
-- definition adds 3,352 order_items over the old single-column (`is_cancelled` only) definition -
-- same population as before, since is_cancelled and cancel_time on careos_order_items were already
-- confirmed near-fully redundant with each other (63,748 vs 63,748, 1 item apart each direction).
-- 98.5% of the added 3,352 have a still-active sibling on the same order - confirmed normal partial
-- cancel-recreate per 10_SAP_CONTEXT, not a data problem. This is exactly why every consumer of these
-- columns MUST stay at order_item grain - is_cancelled_effective describes ONE item, never "the whole
-- order this item belongs to."
--
-- Cross-check monitor (separate from is_cancelled_effective, per Boat's item 3): the REVERSE
-- direction - order.is_cancelled = TRUE but the item itself isn't - is tracked here as its own view,
-- for the morning digest, NOT folded into is_cancelled_effective. Verified live 2026-07-29: 0 items
-- match today (Boat's own estimate was ~1; the real number is 0 - reported as found, not adjusted to
-- match the estimate).
--
-- Same MERGE-incremental + one-time-backfill shape as 033 (BigQuery routines have no ALTER-to-add-
-- logic; full procedure body per file, per project convention).

ALTER TABLE `pacific-plating-282708.sap_integration_v3.stg_order_dim`
  ADD COLUMN IF NOT EXISTS is_cancelled_effective BOOL,
  ADD COLUMN IF NOT EXISTS cancel_time_effective TIMESTAMP;

CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_refresh_stg_order_dim`()
BEGIN
  DECLARE watermark TIMESTAMP DEFAULT (
    SELECT IFNULL(MAX(order_update_time), TIMESTAMP('2000-01-01'))
    FROM `pacific-plating-282708.sap_integration_v3.stg_order_dim`
  );

  MERGE `pacific-plating-282708.sap_integration_v3.stg_order_dim` T
  USING (
    SELECT
      oi.human_id AS order_item,
      o.human_id AS order_id,
      COALESCE(
        CASE
          WHEN JSON_VALUE(o.data, '$.policyHolder.isCompany') = 'true'
            THEN JSON_VALUE(o.data, '$.policyHolder.companyTaxId')
          ELSE JSON_VALUE(o.data, '$.idNumber')
        END,
        '-'
      ) AS insured_id,  -- F1: never empty, fixed at the one shared source
      JSON_VALUE(o.data, '$.policyHolder.title') AS title,
      COALESCE(
        JSON_VALUE(o.data, '$.policyHolder.firstName'),
        JSON_VALUE(o.data, '$.policyHolder.policyAddress.companyName')
      ) AS first_name,
      JSON_VALUE(o.data, '$.policyHolder.lastName') AS last_name,
      oi.insurer AS insurer_code,
      oi.motor_item_type AS insurance_type,
      JSON_VALUE(o.data, '$.oicCode') AS oic_code,
      CASE
        WHEN JSON_VALUE(o.data, '$.oicCode') IN ('TYPE_610', 'TYPE_620', 'TYPE_630') THEN 'MotorBike'
        ELSE 'Car'
      END AS vehicle_class,
      JSON_VALUE(o.data, '$.chassisNumber') AS chassis_no,
      JSON_VALUE(o.data, '$.carLicensePlate') AS license_plate,
      oi.net_premium AS gross_premium,
      CASE
        WHEN JSON_VALUE(o.data, '$.policyHolder.policyAddress.isBillingAddress') = 'true' THEN CONCAT(
          COALESCE(JSON_VALUE(o.data, '$.policyHolder.policyAddress.fullName'), JSON_VALUE(o.data, '$.policyHolder.policyAddress.companyName')), ', ',
          JSON_VALUE(o.data, '$.policyHolder.policyAddress.address'), ', ',
          JSON_VALUE(o.data, '$.policyHolder.policyAddress.subDistrict'), ', ',
          JSON_VALUE(o.data, '$.policyHolder.policyAddress.district'), ', ',
          JSON_VALUE(o.data, '$.policyHolder.policyAddress.province'), ', ',
          JSON_VALUE(o.data, '$.policyHolder.policyAddress.postCode')
        )
        ELSE CONCAT(
          JSON_VALUE(o.data, '$.policyHolder.billingAddress.fullName'), ', ',
          JSON_VALUE(o.data, '$.policyHolder.billingAddress.address'), ', ',
          JSON_VALUE(o.data, '$.policyHolder.billingAddress.subDistrict'), ', ',
          JSON_VALUE(o.data, '$.policyHolder.billingAddress.district'), ', ',
          JSON_VALUE(o.data, '$.policyHolder.billingAddress.province'), ', ',
          JSON_VALUE(o.data, '$.policyHolder.billingAddress.postCode')
        )
      END AS billing_address,
      o.create_time AS order_create_time,
      o.update_time AS order_update_time,
      oi.policy_number AS policy_no,
      oi.policy_start_date AS policy_start_date,
      oi.is_cancelled AS is_cancelled,
      -- nested definition, table+grain per field (see header comment) - 2-field, item grain only:
      (
        IFNULL(oi.is_cancelled, FALSE)   -- item grain, careos_order_items.is_cancelled
        OR oi.cancel_time IS NOT NULL    -- item grain, careos_order_items.cancel_time
      ) AS is_cancelled_effective,
      oi.cancel_time AS cancel_time_effective,  -- item grain, careos_order_items.cancel_time verbatim
      REGEXP_REPLACE(
        CASE WHEN STARTS_WITH(REGEXP_REPLACE(ph.phone, r'[\s\-()]', ''), '+66')
          THEN CONCAT('0', SUBSTR(REGEXP_REPLACE(ph.phone, r'[\s\-()]', ''), 4))
          ELSE REGEXP_REPLACE(ph.phone, r'[\s\-()]', '') END,
        r'[^0-9]', ''
      ) AS phone_normalized,
      CURRENT_TIMESTAMP() AS dim_refreshed_at
    FROM `pacific-plating-282708.careos.careos_order_items` oi
    JOIN `pacific-plating-282708.careos.careos_orders` o ON o.id = oi.order_id
    LEFT JOIN `pacific-plating-282708.hydra_customer_prod.customers` cust ON cust.id = o.customer_id
    LEFT JOIN `pacific-plating-282708.hydra_customer_prod.phones` ph ON ph.id = cust.primary_phone_id
    WHERE o.update_time > watermark
  ) S
  ON T.order_item = S.order_item
  WHEN MATCHED THEN UPDATE SET
    order_id = S.order_id,
    insured_id = S.insured_id,
    title = S.title,
    first_name = S.first_name,
    last_name = S.last_name,
    insurer_code = S.insurer_code,
    insurance_type = S.insurance_type,
    oic_code = S.oic_code,
    vehicle_class = S.vehicle_class,
    chassis_no = S.chassis_no,
    license_plate = S.license_plate,
    gross_premium = S.gross_premium,
    billing_address = S.billing_address,
    order_create_time = S.order_create_time,
    order_update_time = S.order_update_time,
    policy_no = S.policy_no,
    policy_start_date = S.policy_start_date,
    is_cancelled = S.is_cancelled,
    is_cancelled_effective = S.is_cancelled_effective,
    cancel_time_effective = S.cancel_time_effective,
    phone_normalized = S.phone_normalized,
    dim_refreshed_at = S.dim_refreshed_at
  WHEN NOT MATCHED THEN INSERT (
    order_item, order_id, insured_id, title, first_name, last_name, insurer_code, insurance_type,
    oic_code, vehicle_class, chassis_no, license_plate, gross_premium, billing_address,
    order_create_time, order_update_time, policy_no, policy_start_date, is_cancelled,
    is_cancelled_effective, cancel_time_effective, phone_normalized, dim_refreshed_at
  ) VALUES (
    S.order_item, S.order_id, S.insured_id, S.title, S.first_name, S.last_name, S.insurer_code,
    S.insurance_type, S.oic_code, S.vehicle_class, S.chassis_no, S.license_plate, S.gross_premium,
    S.billing_address, S.order_create_time, S.order_update_time, S.policy_no, S.policy_start_date,
    S.is_cancelled, S.is_cancelled_effective, S.cancel_time_effective, S.phone_normalized,
    S.dim_refreshed_at
  );
END;

-- One-time full backfill so every existing row gets the two new columns populated immediately
-- (same rationale as 033's backfill - the watermark-driven MERGE alone would not retroactively
-- touch already-loaded rows).
CREATE OR REPLACE TABLE `pacific-plating-282708.sap_integration_v3.stg_order_dim`
PARTITION BY DATE(order_update_time)
CLUSTER BY order_item AS
SELECT
  oi.human_id AS order_item,
  o.human_id AS order_id,
  COALESCE(
    CASE
      WHEN JSON_VALUE(o.data, '$.policyHolder.isCompany') = 'true'
        THEN JSON_VALUE(o.data, '$.policyHolder.companyTaxId')
      ELSE JSON_VALUE(o.data, '$.idNumber')
    END,
    '-'
  ) AS insured_id,
  JSON_VALUE(o.data, '$.policyHolder.title') AS title,
  COALESCE(
    JSON_VALUE(o.data, '$.policyHolder.firstName'),
    JSON_VALUE(o.data, '$.policyHolder.policyAddress.companyName')
  ) AS first_name,
  JSON_VALUE(o.data, '$.policyHolder.lastName') AS last_name,
  oi.insurer AS insurer_code,
  oi.motor_item_type AS insurance_type,
  JSON_VALUE(o.data, '$.oicCode') AS oic_code,
  CASE
    WHEN JSON_VALUE(o.data, '$.oicCode') IN ('TYPE_610', 'TYPE_620', 'TYPE_630') THEN 'MotorBike'
    ELSE 'Car'
  END AS vehicle_class,
  JSON_VALUE(o.data, '$.chassisNumber') AS chassis_no,
  JSON_VALUE(o.data, '$.carLicensePlate') AS license_plate,
  oi.net_premium AS gross_premium,
  CASE
    WHEN JSON_VALUE(o.data, '$.policyHolder.policyAddress.isBillingAddress') = 'true' THEN CONCAT(
      COALESCE(JSON_VALUE(o.data, '$.policyHolder.policyAddress.fullName'), JSON_VALUE(o.data, '$.policyHolder.policyAddress.companyName')), ', ',
      JSON_VALUE(o.data, '$.policyHolder.policyAddress.address'), ', ',
      JSON_VALUE(o.data, '$.policyHolder.policyAddress.subDistrict'), ', ',
      JSON_VALUE(o.data, '$.policyHolder.policyAddress.district'), ', ',
      JSON_VALUE(o.data, '$.policyHolder.policyAddress.province'), ', ',
      JSON_VALUE(o.data, '$.policyHolder.policyAddress.postCode')
    )
    ELSE CONCAT(
      JSON_VALUE(o.data, '$.policyHolder.billingAddress.fullName'), ', ',
      JSON_VALUE(o.data, '$.policyHolder.billingAddress.address'), ', ',
      JSON_VALUE(o.data, '$.policyHolder.billingAddress.subDistrict'), ', ',
      JSON_VALUE(o.data, '$.policyHolder.billingAddress.district'), ', ',
      JSON_VALUE(o.data, '$.policyHolder.billingAddress.province'), ', ',
      JSON_VALUE(o.data, '$.policyHolder.billingAddress.postCode')
    )
  END AS billing_address,
  o.create_time AS order_create_time,
  o.update_time AS order_update_time,
  oi.policy_number AS policy_no,
  oi.policy_start_date AS policy_start_date,
  oi.is_cancelled AS is_cancelled,
  (
    IFNULL(oi.is_cancelled, FALSE)
    OR oi.cancel_time IS NOT NULL
  ) AS is_cancelled_effective,
  oi.cancel_time AS cancel_time_effective,
  REGEXP_REPLACE(
    CASE WHEN STARTS_WITH(REGEXP_REPLACE(ph.phone, r'[\s\-()]', ''), '+66')
      THEN CONCAT('0', SUBSTR(REGEXP_REPLACE(ph.phone, r'[\s\-()]', ''), 4))
      ELSE REGEXP_REPLACE(ph.phone, r'[\s\-()]', '') END,
    r'[^0-9]', ''
  ) AS phone_normalized,
  CURRENT_TIMESTAMP() AS dim_refreshed_at
FROM `pacific-plating-282708.careos.careos_order_items` oi
JOIN `pacific-plating-282708.careos.careos_orders` o ON o.id = oi.order_id
LEFT JOIN `pacific-plating-282708.hydra_customer_prod.customers` cust ON cust.id = o.customer_id
LEFT JOIN `pacific-plating-282708.hydra_customer_prod.phones` ph ON ph.id = cust.primary_phone_id;

-- Cross-check monitor (Boat item 3): the REVERSE direction, order-level flagged cancelled but the
-- item itself carries neither signal. Separate from is_cancelled_effective on purpose - this is a
-- data-quality digest count, not part of the cancellation rule. Verified live 2026-07-29: 0 rows
-- (Boat's own estimate was ~1 based on an earlier item-level-only mismatch found in a different
-- check - that 1-item mismatch was is_cancelled vs cancel_time on the SAME table, careos_order_items;
-- this cross-order check is a different comparison and currently finds 0).
CREATE OR REPLACE VIEW `pacific-plating-282708.sap_integration_v3.v_order_cancelled_item_not_monitor` AS
SELECT
  oi.human_id AS order_item,
  o.human_id AS order_id,
  oi.is_cancelled AS item_is_cancelled,
  oi.cancel_time AS item_cancel_time,
  o.is_cancelled AS order_is_cancelled
FROM `pacific-plating-282708.careos.careos_order_items` oi
JOIN `pacific-plating-282708.careos.careos_orders` o ON o.id = oi.order_id
WHERE IFNULL(o.is_cancelled, FALSE) = TRUE
  AND NOT (IFNULL(oi.is_cancelled, FALSE) OR oi.cancel_time IS NOT NULL);
