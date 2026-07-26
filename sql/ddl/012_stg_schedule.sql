-- 012_stg_schedule.sql
-- P1 build (Boat, 2026-07-25: "start building" V3 P1-P3; "you can start next phase without
-- waiting me... anything need confirmation you can skip to other tasks").
-- Implements SAP_INTERFACE_REDESIGN_V3.md §2.3/§2.4: the "spine" - one row per (order_item,
-- period) driven by successful charges, not by follow_ups/snapshot presence (fixes A3, A4: those
-- LEFT-joined-but-treated-as-mandatory fields used to silently drop whole periods). Also encodes
-- the L3 router's total_periods/flow decision per order_item (§2.4), confirmed today:
--   - FULL_PAYMENT, CREDIT_CARD_INSTALLMENT, unknown/empty -> ONETIME, TotalPeriods = 1
--     (Boat 2026-07-25: "CREDIT_CARD_INSTALLMENT, remains the same. only change to Onetime(RCB)" -
--     the bank pays in full; their installment plan is not SAP's concern)
--   - RABBIT_CARE_INSTALLMENT + MOTOR_TYPE_COMPULSORY -> RCL_CMI, TotalPeriods = 1
--     (compulsory items only ever get one period, full premium - confirmed live earlier this
--     session: an M1 item had zero SAP rows while its sibling V1 had a full paid schedule)
--   - RABBIT_CARE_INSTALLMENT + not compulsory (NULL-safe, matches the A2 fix) -> RCL,
--     TotalPeriods = spine formula below
--
-- IMPORTANT - checked against real data before building, not the design doc's literal text:
-- the doc's router table names a "RABBIT_LENDING" payment_option for the compulsory case: this
-- value DOES NOT EXIST in carepay_transactions (only FULL_PAYMENT / RABBIT_CARE_INSTALLMENT /
-- CREDIT_CARD_INSTALLMENT / PAYMENT_OPTION_UNKNOWN / empty are real). The actual compulsory/
-- voluntary split is driven by motor_item_type, confirmed empirically this session - not a
-- distinct payment_option value.
--
-- CORRECTED 2026-07-26 (Boat): `careos.cancelled_change_orders` identifies Credit-Shell
-- change-order chains - old_human_id is the superseded order (should interface to SAP as
-- Cancelled (Change order)), current_human_id is the real replacement order (should interface as
-- Paid with PaymentChannel "RCB Credit-Shell"). The original version of this file had this
-- backwards: it excluded current_human_id (the real, active order) and did NOT exclude
-- old_human_id (the superseded one) - meaning ~20k real paid order_items were invisible to this
-- entire spine/expected_state/delta_export pipeline, while ~25k superseded order_items were
-- flowing through as if they were normal active schedules. Caught only after a live backfill
-- (021) picked up 11 old_human_id rows and generated wrong newpayment interface rows for them -
-- corrected before the vendor's pull, see 30_SAP_CHANGELOG.md 2026-07-26 entries.
-- Fix: exclude old_human_id only. current_human_id orders now flow through normally as regular
-- schedule rows - NOT yet specially flagged with a distinct Credit-Shell flow/channel marker
-- (stg_schedule doesn't carry PaymentChannel at all), which is still a real gap if a future
-- Credit-Shell-aware export step needs to emit "RCB Credit-Shell" specifically.
--
-- total_periods formula (§2.3): GREATEST across 3 independent signals, never trust
-- number_of_installment alone (A5) - matches installment_details actual max period, the current
-- transaction snapshot's stated installment count, and the transaction's own installments field.

CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_refresh_stg_schedule`()
BEGIN
  CREATE OR REPLACE TABLE `pacific-plating-282708.sap_integration_v3.stg_schedule`
  CLUSTER BY order_item AS
  WITH latest_snapshot AS (
    SELECT * EXCEPT(rn) FROM (
      SELECT *, ROW_NUMBER() OVER (PARTITION BY transaction_id ORDER BY update_time DESC, id DESC) AS rn
      FROM `pacific-plating-282708.careos.carepay_transaction_snapshots`
    ) WHERE rn = 1
  ),
  spine_periods AS (
    SELECT
      t.id AS transaction_id,
      GREATEST(
        COALESCE(MAX(d.period), 0),
        COALESCE(ANY_VALUE(s.number_of_installment), 0),
        COALESCE(ANY_VALUE(t.installments), 0),
        1
      ) AS spine_total_periods
    FROM `pacific-plating-282708.careos.carepay_transactions` t
    LEFT JOIN latest_snapshot s ON s.transaction_id = t.id
    LEFT JOIN `pacific-plating-282708.careos.carepay_transaction_snapshot_installment_details` d
      ON d.snapshot_id = s.id
    GROUP BY t.id
  ),
  order_txn AS (
    -- one row per order_item that has ever had a real transaction attached, via the order's
    -- payment reference (same join pattern as recon_careos_charges, already verified this session)
    SELECT
      oi.human_id AS order_item,
      o.human_id AS order_id,
      t.id AS transaction_id,
      t.payment_option,
      oi.motor_item_type
    FROM `pacific-plating-282708.careos.careos_order_items` oi
    JOIN `pacific-plating-282708.careos.careos_orders` o ON o.id = oi.order_id
    JOIN `pacific-plating-282708.careos.carepay_transactions` t
      ON CONCAT('transactions/', t.id) = o.payment
    WHERE o.human_id NOT IN (
      -- exclude only the superseded (old_human_id) side of a Credit-Shell change-order chain -
      -- current_human_id is the real, active replacement order and must NOT be excluded
      SELECT old_human_id FROM `pacific-plating-282708.careos.cancelled_change_orders`
    )
  ),
  routed AS (
    SELECT
      ot.*,
      sp.spine_total_periods,
      CASE
        WHEN ot.payment_option = 'RABBIT_CARE_INSTALLMENT'
             AND ot.motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN 'RCL_CMI'
        WHEN ot.payment_option = 'RABBIT_CARE_INSTALLMENT'
             AND (ot.motor_item_type != 'MOTOR_TYPE_COMPULSORY' OR ot.motor_item_type IS NULL) THEN 'RCL'
        ELSE 'ONETIME'
      END AS flow,
      CASE
        WHEN ot.payment_option = 'RABBIT_CARE_INSTALLMENT'
             AND (ot.motor_item_type != 'MOTOR_TYPE_COMPULSORY' OR ot.motor_item_type IS NULL)
          THEN sp.spine_total_periods
        ELSE 1  -- ONETIME (incl. CREDIT_CARD_INSTALLMENT) and RCL_CMI both get exactly 1 period
      END AS total_periods
    FROM order_txn ot
    LEFT JOIN spine_periods sp ON sp.transaction_id = ot.transaction_id
  )
  SELECT
    order_item, order_id, transaction_id, p AS period, total_periods, flow, payment_option,
    motor_item_type, CURRENT_TIMESTAMP() AS computed_at
  FROM routed, UNNEST(GENERATE_ARRAY(1, total_periods)) AS p;
END;
