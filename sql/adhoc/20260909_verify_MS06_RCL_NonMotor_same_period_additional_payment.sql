-- Read-only live verification for MS-06 candidate.
--
-- Candidate: a later distinct SUCCESSFUL RABBIT_LENDING charge on a NonMotor
-- RCL installment period already present in SAP is silently removed because
-- RCL_NonMotor_process_2_newpayment advances only by MAX(Period).
--
-- Grain: OrderItem + Period + raw charge_id + nonblank third_party_id.
-- A multi-charge period is accepted here only when it has at least two distinct
-- charge ids and at least two distinct nonblank third-party invoice identities.

WITH
  multi_charge_periods AS (
    SELECT
      transaction_id,
      installment_number AS Period
    FROM `pacific-plating-282708.careos.carepay_charges`
    WHERE status = 'SUCCESSFUL'
      AND service_provider = 'RABBIT_LENDING'
      AND installment_number IS NOT NULL
    GROUP BY transaction_id, Period
    HAVING COUNT(DISTINCT id) > 1
      AND COUNT(DISTINCT NULLIF(TRIM(third_party_id), '')) > 1
  ),

  ranked_charges AS (
    SELECT
      charges.transaction_id,
      charges.installment_number AS Period,
      charges.id AS charge_id,
      charges.third_party_id AS InvoiceNo,
      charges.amount,
      charges.payment_method,
      charges.service_provider,
      charges.payment_date,
      charges.create_time,
      ROW_NUMBER() OVER (
        PARTITION BY charges.transaction_id, charges.installment_number
        ORDER BY charges.create_time, charges.id
      ) AS charge_rank
    FROM `pacific-plating-282708.careos.carepay_charges` AS charges
    JOIN multi_charge_periods
      ON multi_charge_periods.transaction_id = charges.transaction_id
     AND multi_charge_periods.Period = charges.installment_number
    WHERE charges.status = 'SUCCESSFUL'
      AND charges.service_provider = 'RABBIT_LENDING'
      AND NULLIF(TRIM(charges.third_party_id), '') IS NOT NULL
  ),

  later_source_events AS (
    SELECT
      orders.human_id AS OrderID,
      order_items.human_id AS OrderItem,
      order_items.product,
      transactions.payment_option,
      ranked_charges.Period,
      ranked_charges.charge_id,
      ranked_charges.InvoiceNo,
      ROUND(ranked_charges.amount / 100, 2) AS source_actual_received,
      ranked_charges.payment_method AS source_payment_method,
      ranked_charges.service_provider AS source_payment_channel,
      DATE(ranked_charges.payment_date, 'Asia/Bangkok') AS source_payment_date,
      ranked_charges.charge_rank
    FROM `pacific-plating-282708.careos.careos_orders` AS orders
    JOIN `pacific-plating-282708.careos.careos_order_items` AS order_items
      ON order_items.order_id = orders.id
    JOIN `pacific-plating-282708.careos.carepay_transactions` AS transactions
      ON CONCAT('transactions/', transactions.id) = orders.payment
     AND transactions.payment_option = 'RABBIT_CARE_INSTALLMENT'
    JOIN ranked_charges
      ON ranked_charges.transaction_id = transactions.id
     AND ranked_charges.charge_rank > 1
    WHERE order_items.product IN (
        'products/health-insurance',
        'products/travel-insurance'
      )
      AND order_items.motor_item_type IS NULL
      AND order_items.is_cancelled IS NOT TRUE
      AND order_items.cancel_time IS NULL
      AND GREATEST(
        DATE(orders.create_time, 'Asia/Bangkok'),
        COALESCE(
          DATE(order_items.policy_start_date, 'Asia/Bangkok'),
          DATE(orders.create_time, 'Asia/Bangkok')
        )
      ) >= DATE '2026-01-01'
      AND LOWER(TRIM(COALESCE(
        JSON_VALUE(orders.data, '$.policyHolder.firstName'),
        JSON_VALUE(orders.data, '$.policyHolder.policyAddress.companyName'),
        ''
      ))) != 'test'
      AND LOWER(TRIM(COALESCE(
        JSON_VALUE(orders.data, '$.policyHolder.lastName'), ''
      ))) != 'test'
  ),

  rcl_health_events AS (
    SELECT
      OrderItem,
      SAFE_CAST(Period AS INT64) AS Period,
      InvoiceNo,
      TransactionStatus,
      ExpectedReceived,
      ActualReceived,
      PaymentDate,
      PaymentMethod,
      PaymentChannel
    FROM `pacific-plating-282708.sap_data_engineer.RCL_HEALTH`
    WHERE LOWER(COALESCE(TransactionStatus, '')) = 'paid'
      AND NULLIF(TRIM(InvoiceNo), '') IS NOT NULL
  ),

  sap_periods AS (
    SELECT DISTINCT
      U_OrderItem AS OrderItem,
      SAFE_CAST(U_Period AS INT64) AS Period
    FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
    WHERE TransactionStatus IN ('Paid', 'paid')
  ),

  sap_events AS (
    SELECT DISTINCT
      U_OrderItem AS OrderItem,
      SAFE_CAST(U_Period AS INT64) AS Period,
      U_InvoiceNo AS InvoiceNo
    FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
    WHERE TransactionStatus IN ('Paid', 'paid')
      AND NULLIF(TRIM(U_InvoiceNo), '') IS NOT NULL
  ),

  wrapper_events AS (
    SELECT DISTINCT
      OrderItem,
      SAFE_CAST(Period AS INT64) AS Period,
      InvoiceNo
    FROM `pacific-plating-282708.sap_view.RCL_NonMotor_process_2_newpayment`
    WHERE LOWER(COALESCE(TransactionStatus, '')) = 'paid'
      AND NULLIF(TRIM(InvoiceNo), '') IS NOT NULL
  ),

  classified AS (
    SELECT
      later_source_events.*,
      sap_periods.OrderItem IS NOT NULL AS period_already_in_sap,
      sap_events.OrderItem IS NOT NULL AS exact_event_in_sap,
      rcl_health_events.OrderItem IS NOT NULL AS emitted_by_rcl_health,
      wrapper_events.OrderItem IS NOT NULL AS emitted_by_wrapper,
      rcl_health_events.ExpectedReceived AS upstream_expected_received,
      rcl_health_events.ActualReceived AS upstream_actual_received,
      rcl_health_events.PaymentDate AS upstream_payment_date,
      rcl_health_events.PaymentMethod AS upstream_payment_method,
      rcl_health_events.PaymentChannel AS upstream_payment_channel
    FROM later_source_events
    LEFT JOIN sap_periods
      ON sap_periods.OrderItem = later_source_events.OrderItem
     AND sap_periods.Period = later_source_events.Period
    LEFT JOIN sap_events
      ON sap_events.OrderItem = later_source_events.OrderItem
     AND sap_events.Period = later_source_events.Period
     AND sap_events.InvoiceNo = later_source_events.InvoiceNo
    LEFT JOIN rcl_health_events
      ON rcl_health_events.OrderItem = later_source_events.OrderItem
     AND rcl_health_events.Period = later_source_events.Period
     AND rcl_health_events.InvoiceNo = later_source_events.InvoiceNo
    LEFT JOIN wrapper_events
      ON wrapper_events.OrderItem = later_source_events.OrderItem
     AND wrapper_events.Period = later_source_events.Period
     AND wrapper_events.InvoiceNo = later_source_events.InvoiceNo
  )

SELECT
  CURRENT_TIMESTAMP() AS checked_at_utc,
  COUNT(*) AS later_distinct_source_events,
  COUNTIF(period_already_in_sap) AS period_already_in_sap_events,
  COUNTIF(emitted_by_rcl_health) AS emitted_by_rcl_health_events,
  COUNTIF(
    emitted_by_rcl_health
    AND COALESCE(upstream_expected_received, 0) = 0
    AND COALESCE(upstream_actual_received, 0) > 0
  ) AS upstream_valid_additional_payment_events,
  COUNTIF(exact_event_in_sap) AS exact_event_already_in_sap,
  COUNTIF(emitted_by_wrapper) AS exact_event_in_wrapper,
  COUNTIF(
    period_already_in_sap
    AND emitted_by_rcl_health
    AND COALESCE(upstream_expected_received, 0) = 0
    AND COALESCE(upstream_actual_received, 0) > 0
    AND NOT exact_event_in_sap
    AND NOT emitted_by_wrapper
  ) AS confirmed_missing_candidate_events,
  COUNT(DISTINCT IF(
    period_already_in_sap
    AND emitted_by_rcl_health
    AND COALESCE(upstream_expected_received, 0) = 0
    AND COALESCE(upstream_actual_received, 0) > 0
    AND NOT exact_event_in_sap
    AND NOT emitted_by_wrapper,
    OrderItem,
    NULL
  )) AS confirmed_missing_candidate_items,
  ARRAY_AGG(
    IF(
      period_already_in_sap
      AND emitted_by_rcl_health
      AND COALESCE(upstream_expected_received, 0) = 0
      AND COALESCE(upstream_actual_received, 0) > 0
      AND NOT exact_event_in_sap
      AND NOT emitted_by_wrapper,
      STRUCT(
        OrderID,
        OrderItem,
        Period,
        charge_id,
        InvoiceNo,
        source_actual_received,
        upstream_expected_received,
        upstream_actual_received,
        upstream_payment_date,
        upstream_payment_method,
        upstream_payment_channel
      ),
      NULL
    ) IGNORE NULLS
    ORDER BY OrderItem, Period, InvoiceNo
    LIMIT 30
  ) AS confirmed_samples
FROM classified;
