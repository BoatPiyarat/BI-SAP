-- 011_stg_order_dim.sql
-- P1 build (Boat, 2026-07-25: "you can start building" the actual V3 architectural rebuild).
-- Implements SAP_INTERFACE_REDESIGN_V3.md §2.2 stg_order_dim - materialize the JSON-parsed order
-- dimension fields (InsuredID/Title/Name/Chassis/LicensePlate/BillingAddress/oicCode) ONCE per
-- order_item, MERGE only orders whose update_time changed. Fixes D2: today every one of the ~8
-- daily interface queries (RCB/RCL create/cancel/newpayment/creditshell x Motor/NonMotor) repeats
-- the same ~15 JSON_VALUE(orders.data, ...) extractions from scratch on every run - this is the
-- single heaviest CPU cost in the whole pipeline per the design doc's own resource audit.
--
-- Field mappings copied verbatim from the real production JSON_VALUE patterns already live in
-- sap_data_engineer.sap_dashboard_carepay_installment, so this is a drop-in replacement source,
-- not a reinterpretation of the business logic.
--
-- Grain: one row per order_item (not per order) - InsurerCode/InsuranceType/GrossPremium come from
-- careos_order_items, which is already at the order_item grain; the JSON-derived fields (identity/
-- address) are naturally the same across all items of one order, just joined in at this grain
-- since that's what every downstream consumer (interface queries, recon) actually joins on.

CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.stg_order_dim` (
  order_item STRING,
  order_id STRING,
  insured_id STRING,
  title STRING,
  first_name STRING,
  last_name STRING,
  insurer_code STRING,
  insurance_group_source STRING,
  insurance_type STRING,
  oic_code STRING,
  vehicle_class STRING,
  chassis_no STRING,
  license_plate STRING,
  gross_premium FLOAT64,
  billing_address STRING,
  order_create_time TIMESTAMP,
  order_update_time TIMESTAMP,
  dim_refreshed_at TIMESTAMP
)
PARTITION BY DATE(order_update_time)
CLUSTER BY order_item;

ALTER TABLE `pacific-plating-282708.sap_integration_v3.stg_order_dim`
ADD COLUMN IF NOT EXISTS insurance_group_source STRING;

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
      CASE
        WHEN JSON_VALUE(o.data, '$.policyHolder.isCompany') = 'true'
          THEN JSON_VALUE(o.data, '$.policyHolder.companyTaxId')
        ELSE JSON_VALUE(o.data, '$.idNumber')
      END AS insured_id,
      JSON_VALUE(o.data, '$.policyHolder.title') AS title,
      COALESCE(
        JSON_VALUE(o.data, '$.policyHolder.firstName'),
        JSON_VALUE(o.data, '$.policyHolder.policyAddress.companyName')
      ) AS first_name,
      JSON_VALUE(o.data, '$.policyHolder.lastName') AS last_name,
      oi.insurer AS insurer_code,
      oi.product AS insurance_group_source,
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
      CURRENT_TIMESTAMP() AS dim_refreshed_at
    FROM `pacific-plating-282708.careos.careos_order_items` oi
    JOIN `pacific-plating-282708.careos.careos_orders` o ON o.id = oi.order_id
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
    insurance_group_source = S.insurance_group_source,
    insurance_type = S.insurance_type,
    oic_code = S.oic_code,
    vehicle_class = S.vehicle_class,
    chassis_no = S.chassis_no,
    license_plate = S.license_plate,
    gross_premium = S.gross_premium,
    billing_address = S.billing_address,
    order_create_time = S.order_create_time,
    order_update_time = S.order_update_time,
    dim_refreshed_at = S.dim_refreshed_at
  WHEN NOT MATCHED THEN INSERT (
    order_item, order_id, insured_id, title, first_name, last_name, insurer_code,
    insurance_group_source, insurance_type,
    oic_code, vehicle_class, chassis_no, license_plate, gross_premium, billing_address,
    order_create_time, order_update_time, dim_refreshed_at
  ) VALUES (
    S.order_item, S.order_id, S.insured_id, S.title, S.first_name, S.last_name, S.insurer_code,
    S.insurance_group_source, S.insurance_type, S.oic_code, S.vehicle_class, S.chassis_no,
    S.license_plate, S.gross_premium,
    S.billing_address, S.order_create_time, S.order_update_time, S.dim_refreshed_at
  );
END;
