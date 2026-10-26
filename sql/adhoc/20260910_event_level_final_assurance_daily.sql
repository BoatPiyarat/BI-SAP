-- Read-only daily assurance for every 2026 SUCCESSFUL CarePay charge.
--
-- Charge header grain: charge_id (amount counted once).
-- SAP obligation grain: charge_id + OrderItem + Period + obligation_role.
--
-- Stage 1 of the daily assurance pack. It finds exact event obligations absent
-- from SAP. Dynamic legacy-view membership is deliberately verified by the
-- companion route-specific query, because scanning all legacy views together
-- exceeds the repository's 20 GiB hard billing ceiling.
--
-- This query does not claim delivery/pickup evidence. MISSING_FROM_SAP_REQUIRES_VIEW_CHECK
-- means candidate only, not an acknowledged production-delivery failure.

CREATE TEMP TABLE raw_successful AS
SELECT
      c.id AS charge_id,
      c.transaction_id,
      NULLIF(TRIM(c.third_party_id), '') AS raw_invoice_no,
      SAFE_CAST(c.installment_number AS INT64) AS raw_period,
      c.amount AS amount_satang,
      ROUND(c.amount / 100, 2) AS amount_thb,
      c.payment_method,
      c.service_provider,
      c.payment_date,
      c.create_time,
      c.update_time,
      COALESCE(c.payment_date, c.update_time, c.create_time) AS charge_time,
      COUNT(*) OVER (PARTITION BY c.id) AS raw_charge_id_rows,
      COUNT(*) OVER (PARTITION BY c.transaction_id) AS transaction_charge_count,
      ROW_NUMBER() OVER (
        PARTITION BY c.transaction_id
        ORDER BY COALESCE(c.payment_date, c.update_time, c.create_time), c.id
      ) AS transaction_charge_rank,
      ROW_NUMBER() OVER (
        PARTITION BY c.transaction_id, c.service_provider
        ORDER BY COALESCE(c.payment_date, c.update_time, c.create_time), c.id
      ) AS provider_charge_rank
    FROM `pacific-plating-282708.careos.carepay_charges` AS c
    WHERE c.status = 'SUCCESSFUL'
  AND DATE(COALESCE(c.payment_date, c.update_time, c.create_time), 'Asia/Bangkok')
    >= DATE '2026-01-01';

CREATE TEMP TABLE obligation_keyed AS
WITH
  order_link_raw AS (
    SELECT
      r.charge_id,
      t.id AS linked_transaction_id,
      t.payment_option,
      t.status AS transaction_status,
      o.id AS order_pk,
      o.human_id AS OrderID,
      o.product AS order_product,
      o.create_time AS order_create_time,
      o.data AS order_data
    FROM raw_successful AS r
    LEFT JOIN `pacific-plating-282708.careos.carepay_transactions` AS t
      ON t.id = r.transaction_id
    LEFT JOIN `pacific-plating-282708.careos.careos_orders` AS o
      ON o.payment = CONCAT('transactions/', t.id)
  ),

  order_link AS (
    SELECT
      charge_id,
      ANY_VALUE(linked_transaction_id) AS linked_transaction_id,
      ANY_VALUE(payment_option) AS payment_option,
      ANY_VALUE(transaction_status) AS transaction_status,
      ANY_VALUE(order_pk) AS order_pk,
      ANY_VALUE(OrderID) AS OrderID,
      ANY_VALUE(order_product) AS order_product,
      ANY_VALUE(order_create_time) AS order_create_time,
      ANY_VALUE(order_data) AS order_data,
      COUNT(DISTINCT linked_transaction_id) AS transaction_link_count,
      COUNT(DISTINCT order_pk) AS order_link_count
    FROM order_link_raw
    GROUP BY charge_id
  ),

  item_inventory AS (
    SELECT
      o.id AS order_pk,
      COUNT(*) AS item_count,
      COUNTIF(oi.motor_item_type = 'MOTOR_TYPE_COMPULSORY') AS compulsory_item_count,
      COUNTIF(COALESCE(oi.motor_item_type, '') != 'MOTOR_TYPE_COMPULSORY')
        AS non_compulsory_item_count,
      COUNTIF(NULLIF(TRIM(oi.human_id), '') IS NULL) AS blank_item_id_count
    FROM `pacific-plating-282708.careos.careos_orders` AS o
    JOIN `pacific-plating-282708.careos.careos_order_items` AS oi
      ON oi.order_id = o.id
    GROUP BY o.id
  ),

  staged AS (
    SELECT
      charge_id,
      order_item AS staged_order_item,
      order_id AS staged_order_id,
      period AS staged_period,
      third_party_id AS staged_invoice_no,
      event_refreshed_at
    FROM `pacific-plating-282708.sap_integration_v3.stg_payment_events`
    WHERE DATE(charge_time) >= DATE '2026-01-01'
    QUALIFY ROW_NUMBER() OVER (
      PARTITION BY charge_id
      ORDER BY event_refreshed_at DESC
    ) = 1
  ),

  qualification_exclusion AS (
    SELECT
      charge_id,
      STRING_AGG(DISTINCT rule_code, '|' ORDER BY rule_code) AS qualification_rule_codes
    FROM `pacific-plating-282708.sap_integration_v3.sap_payment_qualification_exclusion`
    WHERE DATE(charge_time) >= DATE '2026-01-01'
    GROUP BY charge_id
  ),

  charge_base AS (
    SELECT
      r.*,
      l.payment_option,
      l.transaction_status,
      l.order_pk,
      l.OrderID,
      l.order_product,
      l.order_create_time,
      l.order_data,
      l.transaction_link_count,
      l.order_link_count,
      COALESCE(i.item_count, 0) AS item_count,
      COALESCE(i.compulsory_item_count, 0) AS compulsory_item_count,
      COALESCE(i.non_compulsory_item_count, 0) AS non_compulsory_item_count,
      COALESCE(i.blank_item_id_count, 0) AS blank_item_id_count,
      s.staged_order_item,
      s.staged_order_id,
      s.staged_period,
      s.staged_invoice_no,
      s.event_refreshed_at,
      q.qualification_rule_codes,
      LOWER(TRIM(COALESCE(
        JSON_VALUE(l.order_data, '$.policyHolder.firstName'),
        JSON_VALUE(l.order_data, '$.policyHolder.policyAddress.companyName'),
        ''
      ))) = 'test'
      OR LOWER(TRIM(COALESCE(
        JSON_VALUE(l.order_data, '$.policyHolder.lastName'), ''
      ))) = 'test' AS is_test
    FROM raw_successful AS r
    LEFT JOIN order_link AS l USING (charge_id)
    LEFT JOIN item_inventory AS i USING (order_pk)
    LEFT JOIN staged AS s USING (charge_id)
    LEFT JOIN qualification_exclusion AS q USING (charge_id)
  ),

  rcl_primary AS (
    SELECT
      b.*,
      oi.human_id AS OrderItem,
      oi.product AS item_product,
      oi.motor_item_type,
      oi.is_cancelled,
      oi.cancel_time,
      'RCL_SCHEDULE' AS obligation_role,
      b.raw_period AS Period,
      b.raw_invoice_no AS expected_invoice_no,
      'RCL' AS expected_owner,
      IF(oi.product = 'products/car-insurance', 'Motor', 'NonMotor') AS expected_bu,
      IF(oi.product = 'products/car-insurance',
        'RCL_Motor_process_1_create / RCL_Motor_process_2_newpayment',
        'RCL_NonMotor_process_1_create / RCL_NonMotor_process_2_newpayment'
      ) AS expected_legacy_view
    FROM charge_base AS b
    LEFT JOIN `pacific-plating-282708.careos.careos_order_items` AS oi
      ON oi.human_id = b.staged_order_item
    WHERE b.payment_option = 'RABBIT_CARE_INSTALLMENT'
      AND COALESCE(oi.motor_item_type, '') != 'MOTOR_TYPE_COMPULSORY'
  ),

  rcl_cmi AS (
    SELECT
      b.*,
      oi.human_id AS OrderItem,
      oi.product AS item_product,
      oi.motor_item_type,
      oi.is_cancelled,
      oi.cancel_time,
      CASE
        WHEN b.payment_option = 'FULL_PAYMENT' THEN 'RCL_CMI_FULL_PAYMENT_EXCEPTION'
        ELSE 'RCL_CMI_COMPANION'
      END AS obligation_role,
      1 AS Period,
      IF(b.raw_invoice_no IS NULL, NULL, CONCAT('2_', b.raw_invoice_no))
        AS expected_invoice_no,
      'RCL' AS expected_owner,
      'Motor' AS expected_bu,
      'RCL_Motor_process_1_create' AS expected_legacy_view
    FROM charge_base AS b
    JOIN `pacific-plating-282708.careos.careos_order_items` AS oi
      ON oi.order_id = b.order_pk
     AND oi.motor_item_type = 'MOTOR_TYPE_COMPULSORY'
    WHERE b.service_provider = 'RABBIT_LENDING'
      AND b.provider_charge_rank = 1
      AND b.payment_option IN ('RABBIT_CARE_INSTALLMENT', 'FULL_PAYMENT')
  ),

  rcb_onetime AS (
    SELECT
      b.*,
      oi.human_id AS OrderItem,
      oi.product AS item_product,
      oi.motor_item_type,
      oi.is_cancelled,
      oi.cancel_time,
      CASE
        WHEN oi.product = 'products/car-insurance' AND EXISTS (
          SELECT 1
          FROM `pacific-plating-282708.careos.cancelled_change_orders` AS co
          WHERE co.current_human_id = b.OrderID
        ) THEN 'RCB_MOTOR_CREDITSHELL_ITEM'
        WHEN oi.motor_item_type = 'MOTOR_TYPE_COMPULSORY'
          THEN 'RCB_ONETIME_COMPULSORY_ITEM'
        ELSE 'RCB_ONETIME_ITEM'
      END AS obligation_role,
      1 AS Period,
      b.raw_invoice_no AS expected_invoice_no,
      'RCB' AS expected_owner,
      IF(oi.product = 'products/car-insurance', 'Motor', 'NonMotor') AS expected_bu,
      CASE
        WHEN oi.product = 'products/car-insurance' AND EXISTS (
          SELECT 1
          FROM `pacific-plating-282708.careos.cancelled_change_orders` AS co
          WHERE co.current_human_id = b.OrderID
        ) THEN 'RCB_Motor_process_4_creditshell'
        WHEN oi.product = 'products/car-insurance' THEN 'RCB_Motor_process_create'
        ELSE 'RCB_NonMotor_process_1_create'
      END AS expected_legacy_view
    FROM charge_base AS b
    JOIN `pacific-plating-282708.careos.careos_order_items` AS oi
      ON oi.order_id = b.order_pk
    WHERE b.payment_option IN ('FULL_PAYMENT', 'CREDIT_CARD_INSTALLMENT')
      AND b.service_provider != 'RABBIT_LENDING'
  ),

  unresolved_charge AS (
    SELECT
      b.*,
      CAST(NULL AS STRING) AS OrderItem,
      CAST(NULL AS STRING) AS item_product,
      CAST(NULL AS STRING) AS motor_item_type,
      CAST(NULL AS BOOL) AS is_cancelled,
      CAST(NULL AS TIMESTAMP) AS cancel_time,
      'UNRESOLVED_CHARGE_HEADER' AS obligation_role,
      b.raw_period AS Period,
      b.raw_invoice_no AS expected_invoice_no,
      CAST(NULL AS STRING) AS expected_owner,
      CAST(NULL AS STRING) AS expected_bu,
      CAST(NULL AS STRING) AS expected_legacy_view
    FROM charge_base AS b
    WHERE NOT EXISTS (SELECT 1 FROM rcl_primary p WHERE p.charge_id = b.charge_id)
      AND NOT EXISTS (SELECT 1 FROM rcl_cmi c WHERE c.charge_id = b.charge_id)
      AND NOT EXISTS (SELECT 1 FROM rcb_onetime r WHERE r.charge_id = b.charge_id)
  ),

  obligations AS (
    SELECT * FROM rcl_primary
    UNION ALL SELECT * FROM rcl_cmi
    UNION ALL SELECT * FROM rcb_onetime
    UNION ALL SELECT * FROM unresolved_charge
  )

SELECT
  obligations.*,
  TO_HEX(SHA256(TO_JSON_STRING(STRUCT(
    charge_id, OrderItem, Period, obligation_role, expected_invoice_no
  )))) AS obligation_id,
  CASE
    WHEN item_product = 'products/car-insurance' THEN 'Motor'
    WHEN item_product IN ('products/health-insurance', 'products/travel-insurance')
      THEN 'NonMotor'
    ELSE 'Unknown'
  END AS product_scope,
  COALESCE(is_cancelled, FALSE) OR cancel_time IS NOT NULL AS item_cancelled
FROM obligations;

CREATE TEMP TABLE sap_match AS
WITH
  sap_rows AS (
    SELECT
      U_OrderItem AS OrderItem,
      SAFE_CAST(U_Period AS INT64) AS Period,
      NULLIF(TRIM(U_InvoiceNo), '') AS InvoiceNo,
      TransactionStatus,
      U_ActualReceived AS ActualReceived,
      PaymentDate,
      PaymentMethod,
      PaymentChannel,
      DocEntry,
      UpdateDate
    FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
    WHERE U_OrderItem IS NOT NULL
  )
SELECT
  o.obligation_id,
  COUNT(s.OrderItem) AS sap_key_rows,
  COUNTIF(s.InvoiceNo = o.expected_invoice_no) AS sap_exact_rows,
  ARRAY_AGG(DISTINCT s.InvoiceNo IGNORE NULLS ORDER BY s.InvoiceNo LIMIT 10)
    AS sap_invoices,
  ARRAY_AGG(DISTINCT s.TransactionStatus IGNORE NULLS ORDER BY s.TransactionStatus LIMIT 10)
    AS sap_statuses,
  MAX(s.UpdateDate) AS latest_sap_update
FROM obligation_keyed AS o
LEFT JOIN sap_rows AS s
  ON s.OrderItem = o.OrderItem
 AND s.Period = o.Period
GROUP BY o.obligation_id;

CREATE TEMP TABLE interface_rows AS
    SELECT 'RCB_Motor_process_create' AS view_name, OrderItem,
      SAFE_CAST(Period AS INT64) AS Period, NULLIF(TRIM(InvoiceNo), '') AS InvoiceNo,
      TransactionStatus, SAFE_CAST(ActualReceived AS FLOAT64) AS ActualReceived
    FROM `pacific-plating-282708.sap_view.RCB_Motor_process_create`
    WHERE FALSE;

CREATE TEMP TABLE interface_match AS
SELECT
      o.obligation_id,
      COUNT(i.OrderItem) AS interface_key_rows,
      COUNTIF(i.InvoiceNo = o.expected_invoice_no) AS interface_exact_rows,
      ARRAY_AGG(DISTINCT IF(i.InvoiceNo = o.expected_invoice_no, i.view_name, NULL)
        IGNORE NULLS ORDER BY IF(i.InvoiceNo = o.expected_invoice_no, i.view_name, NULL)
        LIMIT 12) AS exact_interface_views,
      ARRAY_AGG(DISTINCT i.InvoiceNo IGNORE NULLS ORDER BY i.InvoiceNo LIMIT 10)
        AS interface_invoices
FROM obligation_keyed AS o
LEFT JOIN interface_rows AS i
  ON i.OrderItem = o.OrderItem
 AND i.Period = o.Period
GROUP BY o.obligation_id;

WITH
  change_order AS (
    SELECT DISTINCT current_human_id AS OrderID
    FROM `pacific-plating-282708.careos.cancelled_change_orders`
    WHERE current_human_id IS NOT NULL
  ),

  classified AS (
    SELECT
      o.*,
      s.sap_key_rows,
      s.sap_exact_rows,
      s.sap_invoices,
      s.sap_statuses,
      s.latest_sap_update,
      i.interface_key_rows,
      i.interface_exact_rows,
      i.exact_interface_views,
      i.interface_invoices,
      CASE
        WHEN o.OrderItem = 'L80161278-M1' THEN 'MS-06'
        WHEN o.item_product = 'products/health-insurance'
          AND o.payment_option = 'CREDIT_CARD_INSTALLMENT' THEN 'MS-02'
        WHEN co.OrderID IS NOT NULL
          AND o.item_product = 'products/health-insurance'
          AND o.payment_option != 'RABBIT_CARE_INSTALLMENT' THEN 'MS-01'
        WHEN o.obligation_role = 'RCL_CMI_COMPANION' THEN 'MS-05'
        ELSE NULL
      END AS scenario_code,
      CASE
        WHEN o.raw_charge_id_rows != 1
          THEN 'QUARANTINE_SOURCE_IDENTITY'
        WHEN o.transaction_link_count != 1 OR o.order_link_count != 1
          OR o.OrderID IS NULL OR o.OrderItem IS NULL
          THEN 'QUARANTINE_SOURCE_IDENTITY'
        WHEN o.raw_invoice_no IS NULL OR o.expected_invoice_no IS NULL
          THEN 'QUARANTINE_SOURCE_IDENTITY'
        WHEN o.blank_item_id_count > 0
          THEN 'QUARANTINE_SOURCE_IDENTITY'
        WHEN o.payment_option IN ('FULL_PAYMENT', 'CREDIT_CARD_INSTALLMENT')
          AND o.item_count > 1 AND o.transaction_charge_count > 1
          THEN 'QUARANTINE_ITEM_ALLOCATION'
        WHEN o.obligation_role = 'UNRESOLVED_CHARGE_HEADER'
          OR o.expected_owner IS NULL OR o.expected_bu = 'Unknown'
          THEN 'QUARANTINE_ROUTE_MAPPING'
        WHEN o.obligation_role = 'RCL_SCHEDULE'
          AND (o.non_compulsory_item_count != 1 OR o.Period IS NULL OR o.Period < 1)
          THEN 'QUARANTINE_ROUTE_MAPPING'
        WHEN o.is_test THEN 'EXCLUDED_BUSINESS_RULE'
        WHEN s.sap_exact_rows > 0
          AND EXISTS (
            SELECT 1 FROM UNNEST(s.sap_statuses) AS sap_status
            WHERE sap_status IN ('Paid', 'paid')
          ) THEN 'IN_SAP_EXACT'
        WHEN s.sap_exact_rows > 0
          AND EXISTS (
            SELECT 1 FROM UNNEST(s.sap_statuses) AS sap_status
            WHERE sap_status IN ('Cancelled', 'Cancelled (Change order / Rejected)')
          ) THEN 'SAP_TERMINAL_CANCELLED'
        WHEN s.sap_exact_rows > 0 OR s.sap_key_rows > 0
          THEN 'SAP_STATUS_OR_IDENTITY_CONFLICT'
        WHEN i.interface_exact_rows > 0 THEN 'IN_INTERFACE_CANDIDATE'
        WHEN i.interface_key_rows > 0 THEN 'INTERFACE_IDENTITY_CONFLICT'
        WHEN o.item_cancelled THEN 'QUARANTINE_CANCELLED_LIFECYCLE'
        WHEN o.OrderItem = 'L80161278-M1' THEN 'KNOWN_SCENARIO'
        ELSE 'MISSING_FROM_SAP_REQUIRES_VIEW_CHECK'
      END AS assurance_status
    FROM obligation_keyed AS o
    JOIN sap_match AS s USING (obligation_id)
    JOIN interface_match AS i USING (obligation_id)
    LEFT JOIN change_order AS co USING (OrderID)
  ),

  allocation_summary AS (
    SELECT
      assurance_status,
      expected_owner,
      expected_bu,
      obligation_role,
      scenario_code,
      COUNT(*) AS obligation_rows,
      COUNT(DISTINCT charge_id) AS charge_count,
      COUNT(DISTINCT OrderID) AS order_count,
      COUNT(DISTINCT OrderItem) AS item_count,
      MIN(charge_time) AS first_charge_time,
      MAX(charge_time) AS last_charge_time
    FROM classified
    GROUP BY
      assurance_status, expected_owner, expected_bu, obligation_role, scenario_code
  ),

  charge_header_status_rows AS (
    SELECT
      charge_id,
      ANY_VALUE(transaction_id) AS transaction_id,
      ANY_VALUE(OrderID) AS OrderID,
      ANY_VALUE(amount_satang) AS amount_satang,
      ANY_VALUE(amount_thb) AS amount_thb,
      ANY_VALUE(charge_time) AS charge_time,
      ARRAY_AGG(DISTINCT assurance_status ORDER BY assurance_status) AS allocation_statuses,
      CASE
        WHEN COUNTIF(assurance_status LIKE 'QUARANTINE%') > 0 THEN 'QUARANTINE'
        WHEN COUNTIF(assurance_status = 'MISSING_FROM_SAP_REQUIRES_VIEW_CHECK') > 0
          THEN 'MISSING_FROM_SAP_CANDIDATE'
        WHEN COUNTIF(assurance_status IN (
          'SAP_STATUS_OR_IDENTITY_CONFLICT', 'INTERFACE_IDENTITY_CONFLICT'
        )) > 0 THEN 'CONFLICT'
        WHEN COUNTIF(assurance_status IN ('KNOWN_SCENARIO')) > 0 THEN 'KNOWN_SCENARIO'
        WHEN COUNTIF(assurance_status = 'IN_INTERFACE_CANDIDATE') > 0 THEN 'IN_INTERFACE'
        WHEN COUNTIF(assurance_status IN ('IN_SAP_EXACT', 'SAP_TERMINAL_CANCELLED')) = COUNT(*)
          THEN 'IN_SAP'
        ELSE 'MIXED_REVIEW'
      END AS charge_header_status
    FROM classified
    GROUP BY charge_id
  ),

  charge_header_summary_rows AS (
    SELECT
      charge_header_status,
      COUNT(*) AS charge_count,
      COUNT(DISTINCT OrderID) AS order_count,
      SUM(amount_satang) AS amount_satang,
      ROUND(SUM(amount_satang) / 100, 2) AS amount_thb,
      MIN(charge_time) AS first_charge_time,
      MAX(charge_time) AS last_charge_time
    FROM charge_header_status_rows
    GROUP BY charge_header_status
  ),

  reportable AS (
    SELECT *
    FROM classified
    WHERE assurance_status NOT IN ('IN_SAP_EXACT', 'SAP_TERMINAL_CANCELLED')
  )

SELECT
  CONCAT('event-assurance-', FORMAT_TIMESTAMP('%Y%m%d-%H%M%S', CURRENT_TIMESTAMP(),
    'Asia/Bangkok')) AS assurance_run_id,
  CURRENT_TIMESTAMP() AS as_of_utc,
  CURRENT_DATETIME('Asia/Bangkok') AS as_of_ict,
  DATE '2026-01-01' AS charge_scope_start,
  (SELECT COUNT(*) FROM raw_successful) AS successful_charge_rows,
  (SELECT COUNT(DISTINCT charge_id) FROM raw_successful) AS successful_charge_count,
  (SELECT SUM(amount_satang) FROM raw_successful) AS successful_charge_amount_satang,
  (SELECT ROUND(SUM(amount_satang) / 100, 2) FROM raw_successful)
    AS successful_charge_amount_thb,
  (SELECT COUNT(*) FROM classified) AS obligation_rows,
  (SELECT COUNT(*) FROM reportable) AS reportable_obligation_rows,
  (SELECT COUNTIF(assurance_status = 'MISSING_FROM_SAP_REQUIRES_VIEW_CHECK') FROM classified)
    AS missing_from_sap_candidate_obligation_rows,
  (SELECT COUNT(DISTINCT charge_id)
    FROM classified
    WHERE assurance_status = 'MISSING_FROM_SAP_REQUIRES_VIEW_CHECK')
    AS missing_from_sap_candidate_charge_count,
  (SELECT COUNT(DISTINCT OrderID)
    FROM classified
    WHERE assurance_status = 'MISSING_FROM_SAP_REQUIRES_VIEW_CHECK')
    AS missing_from_sap_candidate_order_count,
  ARRAY(SELECT AS STRUCT chs.* FROM charge_header_summary_rows AS chs
    ORDER BY chs.charge_header_status)
    AS charge_header_summary,
  ARRAY(SELECT AS STRUCT a.* FROM allocation_summary AS a
    ORDER BY a.assurance_status, a.expected_owner, a.expected_bu,
      a.obligation_role, a.scenario_code)
    AS allocation_summary,
  ARRAY(
    SELECT AS STRUCT
      assurance_status,
      scenario_code,
      charge_id,
      transaction_id,
      OrderID,
      OrderItem,
      obligation_role,
      Period,
      expected_invoice_no AS InvoiceNo,
      amount_thb,
      charge_time,
      payment_option,
      payment_method,
      service_provider,
      expected_owner,
      expected_bu,
      expected_legacy_view,
      sap_key_rows,
      sap_exact_rows,
      sap_invoices,
      sap_statuses,
      interface_key_rows,
      interface_exact_rows,
      exact_interface_views,
      interface_invoices,
      qualification_rule_codes,
      item_cancelled,
      is_test
    FROM reportable
    ORDER BY assurance_status, charge_time, charge_id, OrderItem
    LIMIT 500
  ) AS reportable_samples,
  (SELECT COUNT(*) > 500 FROM reportable) AS reportable_samples_truncated
;
