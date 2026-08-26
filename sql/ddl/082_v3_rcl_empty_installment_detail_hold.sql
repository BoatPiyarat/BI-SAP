-- 082_v3_rcl_empty_installment_detail_hold.sql
-- Source only / Class A. Runtime dependency of the reviewed Unit 5 producer in DDL 058.
-- docs/FINDINGS_EMPTY_INSTALLMENT_DETAILS_20260825.md.
--
-- Problem: a `careos.carepay_transaction_snapshots` row can declare `number_of_installment > 1`
-- while its child `careos.carepay_transaction_snapshot_installment_details` table has ZERO rows
-- (an upstream CareOS data gap - the per-period breakdown was never generated). For ONETIME-flow
-- items this is already silently rescued by `050_v3_onetime_payload_source.sql`, which never
-- touches installment_details. RCL-flow items have no equivalent rescue: Unit 5
-- (`058_v3_unit5_newpayment_shadow.sql`) still sources RCL rows from the legacy
-- `sap_data_engineer.sap_dashboard_carepay_installment` view, which derives `Period` from the
-- (possibly empty) installment_details table. When empty, `Period` is NULL for every row, and the
-- target order_item silently disappears at 058's `_resolved` join (Period=NULL can never match a
-- real integer period) - before ever reaching an ASSERT. It never fails loudly; it just vanishes,
-- leaving zero trace in sap_errors_logging/sap_excluded_records/sap_validation_error.
--
-- This file detects and names the condition (HOLD_EMPTY_INSTALLMENT_DETAILS, following the
-- house HOLD_* convention from 081_v3_creditshell_flow_router.sql and the
-- 20260824_qualify_v3_normal_motor_newpayment.sql adhoc qualifier). DDL 058 stages this view's
-- exact rows and publishes its run-scoped durable holds atomically with the Unit 5 producer claim.
--
-- Population scan (read-only, 2026-08-25): flow='RCL' + total_periods>1 + zero installment_details
-- rows currently affected 2 known order_items, both already separately reached SAP by another
-- path (see docs/FINDINGS_EMPTY_INSTALLMENT_DETAILS_20260825.md). Zero RCL items are actively
-- stuck by this defect today; this view exists so a FUTURE occurrence is visible instead of silent.

CREATE OR REPLACE VIEW `pacific-plating-282708.sap_integration_v3.vw_v3_rcl_empty_installment_detail_hold` AS
WITH latest_snapshot AS (
  SELECT * EXCEPT(rn) FROM (
    SELECT *, ROW_NUMBER() OVER (
      PARTITION BY transaction_id ORDER BY update_time DESC, id DESC) AS rn
    FROM `pacific-plating-282708.careos.carepay_transaction_snapshots`
  ) WHERE rn = 1
),
detail_counts AS (
  SELECT s.transaction_id, s.id AS snapshot_id, s.number_of_installment,
    COUNT(d.id) AS detail_row_count
  FROM latest_snapshot s
  LEFT JOIN `pacific-plating-282708.careos.carepay_transaction_snapshot_installment_details` d
    ON d.snapshot_id = s.id
  GROUP BY 1,2,3
)
SELECT DISTINCT
  ss.order_item,
  ss.order_id,
  ss.transaction_id,
  dc.snapshot_id,
  ss.total_periods AS declared_total_periods,
  dc.number_of_installment,
  dc.detail_row_count,
  'HOLD_EMPTY_INSTALLMENT_DETAILS' AS rule_code,
  CURRENT_TIMESTAMP() AS detected_at
FROM `pacific-plating-282708.sap_integration_v3.stg_schedule` ss
JOIN detail_counts dc ON dc.transaction_id = ss.transaction_id
WHERE ss.flow = 'RCL'              -- excludes RCL_CMI (always 1 period) and ONETIME (rescued by 050)
  AND ss.total_periods > 1
  AND dc.detail_row_count = 0;

-- Durable, run-scoped hold record populated atomically by the reviewed DDL 058 producer.
CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.v3_unit5_installment_detail_hold` (
  pipeline_run_id STRING NOT NULL,
  order_item STRING NOT NULL,
  order_id STRING NOT NULL,
  transaction_id STRING NOT NULL,
  snapshot_id STRING NOT NULL,
  declared_total_periods INT64,
  number_of_installment INT64,
  detail_row_count INT64,
  rule_code STRING NOT NULL,
  detected_at TIMESTAMP NOT NULL
)
PARTITION BY DATE(detected_at)
CLUSTER BY pipeline_run_id, order_item;
