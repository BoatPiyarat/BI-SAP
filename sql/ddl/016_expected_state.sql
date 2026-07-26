-- 016_expected_state.sql
-- P2 build (Boat, 2026-07-25: "start building" V3 P1-P3).
-- Implements SAP_INTERFACE_REDESIGN_V3.md's L3 Engine: "route: payment_option -> flow rules
-- [already resolved in stg_schedule]; InvoiceNo: กติกาเดียว (UDF กลาง)". This is the first table
-- that represents "what SAP SHOULD show" as a single, computed truth - the thing L5 Delta Export
-- (future) diffs against stg_sap_state, and L4 Validation (future) checks before export.
--
-- Grain: one row per (order_item, period), left-joining the spine (stg_schedule) against actual
-- money-in events (stg_payment_events) - a period with no matching event is expected Pending,
-- exactly per the confirmed rule (Boat, earlier this session): "the installment (total periods)
-- is created once and status is paid at 1st installment, other period can be pending. Next
-- payment successful, we need to interface paid 2 periods and pending the rest."
--
-- InvoiceNo goes through fn_invoice_no(third_party_id) - the single central function - never
-- inlined here, so this can never drift into its own prefixing convention (the actual root cause
-- of B1).
--
-- Compulsory-item fix, found by checking real data before trusting this table: the item_rank
-- de-fanout in stg_payment_events (prefer non-compulsory item on a bundled charge - correct, and
-- needed to stop fake period-2+ showing up on compulsory items) has a side effect - it attributes
-- ALL of an order's charges to the voluntary sibling, including the compulsory item's own
-- legitimate period-1 payment, which then never gets recognized at all. Verified on L73191102-2:
-- its 4 real successful charges (installments 1/4/5/6) all landed on sibling L73191102-1 in
-- stg_payment_events, leaving the compulsory item permanently "Pending" even though it was paid.
-- Compulsory items need order-level recognition ("was anything paid on this order's transaction
-- at all"), not the item-attributed join used for the real per-period voluntary schedule.
--
-- WIDENED 2026-07-25 (caught via delta_export's UNEXPECTED_ALREADY_PAID category): the first fix
-- only special-cased flow = 'RCL_CMI', but compulsory items can also route to ONETIME (e.g.
-- FULL_PAYMENT bundles that include a compulsory item) - motor_item_type = 'MOTOR_TYPE_COMPULSORY'
-- is the actual underlying condition, independent of flow. Verified: L80385949-M1, L78292154-M1,
-- L78331526-M1 all showed expected_status=Pending while SAP already correctly shows Paid - all
-- three are -M1 (compulsory) items classified as ONETIME, not RCL_CMI, so the narrower fix missed
-- them entirely.

CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_refresh_expected_state`()
BEGIN
  CREATE OR REPLACE TABLE `pacific-plating-282708.sap_integration_v3.expected_state`
  CLUSTER BY order_item AS
  WITH payment_events_dedup AS (
    -- PK_DUP fix, found by the validation layer: a single (order_item, period) can have multiple
    -- SUCCESSFUL charges (verified live: L74421938-V1 period 1 had 10 distinct successful
    -- charges - retries/re-attempts, not 10 real payments). Pick the earliest as canonical - the
    -- first time this period was actually paid - not every attempt.
    SELECT * EXCEPT(rn) FROM (
      SELECT *, ROW_NUMBER() OVER (
        PARTITION BY order_item, period ORDER BY charge_time ASC
      ) AS rn
      FROM `pacific-plating-282708.sap_integration_v3.stg_payment_events`
    ) WHERE rn = 1
  ),
  order_txn_any_paid AS (
    -- order-level signal for compulsory items: does this transaction have ANY successful charge
    -- at all, regardless of which sibling item stg_payment_events attributed it to. Keyed by
    -- motor_item_type, not flow - a compulsory item can route to ONETIME or RCL_CMI depending on
    -- the order's overall payment_option, but either way it needs this same order-level check.
    SELECT DISTINCT
      s.transaction_id,
      FIRST_VALUE(c.id) OVER (
        PARTITION BY s.transaction_id ORDER BY c.update_time ASC
      ) AS first_charge_id,
      FIRST_VALUE(COALESCE(c.third_party_id, s.order_item)) OVER (
        PARTITION BY s.transaction_id ORDER BY c.update_time ASC
      ) AS first_third_party_id,
      FIRST_VALUE(c.update_time) OVER (
        PARTITION BY s.transaction_id ORDER BY c.update_time ASC
      ) AS first_charge_time
    FROM `pacific-plating-282708.sap_integration_v3.stg_schedule` s
    JOIN `pacific-plating-282708.careos.carepay_charges` c
      ON c.transaction_id = s.transaction_id AND c.status = 'SUCCESSFUL'
    WHERE s.motor_item_type = 'MOTOR_TYPE_COMPULSORY'
  )
  SELECT
    s.order_item,
    s.order_id,
    s.period,
    s.total_periods,
    s.flow,
    s.payment_option,
    CASE
      WHEN s.motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN IF(otp.transaction_id IS NOT NULL, 'Paid', 'Pending')
      ELSE IF(pe.charge_id IS NOT NULL, 'Paid', 'Pending')
    END AS expected_status,
    CASE
      WHEN s.motor_item_type = 'MOTOR_TYPE_COMPULSORY' AND otp.transaction_id IS NOT NULL THEN
        `pacific-plating-282708.sap_integration_v3.fn_invoice_no`(otp.first_third_party_id)
      WHEN s.motor_item_type != 'MOTOR_TYPE_COMPULSORY' AND pe.charge_id IS NOT NULL THEN
        `pacific-plating-282708.sap_integration_v3.fn_invoice_no`(pe.third_party_id)
      ELSE NULL
    END AS expected_invoice_no,
    CASE
      WHEN s.motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN DATE(otp.first_charge_time)
      ELSE DATE(pe.charge_time)
    END AS expected_payment_date,
    COALESCE(IF(s.motor_item_type = 'MOTOR_TYPE_COMPULSORY', otp.first_charge_id, NULL), pe.charge_id) AS charge_id,
    pe.amount AS charge_amount,
    CURRENT_TIMESTAMP() AS computed_at
  FROM `pacific-plating-282708.sap_integration_v3.stg_schedule` s
  LEFT JOIN payment_events_dedup pe
    ON pe.order_item = s.order_item AND pe.period = s.period
  LEFT JOIN order_txn_any_paid otp
    ON s.motor_item_type = 'MOTOR_TYPE_COMPULSORY' AND otp.transaction_id = s.transaction_id;
END;
