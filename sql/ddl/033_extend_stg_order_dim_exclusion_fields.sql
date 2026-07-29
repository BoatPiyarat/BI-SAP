-- 033_extend_stg_order_dim_exclusion_fields.sql
-- KNOWLEDGE_ADDENDUM_20260729 v2: adds the raw fields E1/F1/F2/E2-phone need, all sourced once
-- here (same rationale as the original 011 - materialize once, every downstream consumer joins,
-- don't re-derive per query).
--
-- New columns:
--   policy_no, policy_start_date  - from careos_order_items (F2 length check, E1 date basis)
--   is_cancelled                  - from careos_order_items (E1's create/paid vs cancel branch)
--   phone_normalized              - careos_orders.customer_id -> hydra_customer_prod.customers
--                                   (primary_phone_id) -> hydra_customer_prod.phones.phone,
--                                   normalized (strip space/-/(), +66 -> 0). Discovered live
--                                   2026-07-29 - NOT guessed: careos_orders has no phone field
--                                   directly or in orders.data JSON (checked via JSON_KEYS, no
--                                   phone/mobile/tel key found there); the real source is the
--                                   separate Hydra customer service dataset. Used only for
--                                   E2/TEST_CUSTOMER_PHONE (report-only, see 034).
--
-- F1 fix: insured_id now COALESCEs to '-' at this source, so every downstream consumer
-- automatically gets the fixed value with no per-flow patching needed.
--
-- One-time backfill: this is a schema change to an existing MERGE-based incremental table -
-- the watermark-driven MERGE alone would NOT retroactively populate the new columns for
-- already-loaded rows. A full CREATE OR REPLACE TABLE rebuild (same SELECT shape as the MERGE
-- source, run once) follows the ALTER, so every existing row gets the new columns filled
-- immediately, not just newly-touched ones going forward.

ALTER TABLE `pacific-plating-282708.sap_integration_v3.stg_order_dim`
  ADD COLUMN IF NOT EXISTS policy_no STRING,
  ADD COLUMN IF NOT EXISTS policy_start_date TIMESTAMP,
  ADD COLUMN IF NOT EXISTS is_cancelled BOOL,
  ADD COLUMN IF NOT EXISTS phone_normalized STRING;

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
    phone_normalized = S.phone_normalized,
    dim_refreshed_at = S.dim_refreshed_at
  WHEN NOT MATCHED THEN INSERT (
    order_item, order_id, insured_id, title, first_name, last_name, insurer_code, insurance_type,
    oic_code, vehicle_class, chassis_no, license_plate, gross_premium, billing_address,
    order_create_time, order_update_time, policy_no, policy_start_date, is_cancelled,
    phone_normalized, dim_refreshed_at
  ) VALUES (
    S.order_item, S.order_id, S.insured_id, S.title, S.first_name, S.last_name, S.insurer_code,
    S.insurance_type, S.oic_code, S.vehicle_class, S.chassis_no, S.license_plate, S.gross_premium,
    S.billing_address, S.order_create_time, S.order_update_time, S.policy_no, S.policy_start_date,
    S.is_cancelled, S.phone_normalized, S.dim_refreshed_at
  );
END;

-- One-time full backfill so every existing row (not just future watermark-touched ones) gets
-- the new columns populated immediately.
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
