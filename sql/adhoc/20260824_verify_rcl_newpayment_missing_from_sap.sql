-- 20260824_verify_rcl_newpayment_missing_from_sap.sql
-- READ-ONLY VERIFICATION ONLY. No CREATE/INSERT/UPDATE/DELETE, no gs://** write, no procedure CALL.
-- Must run through scripts/bq_safe_query.sh (mandatory query path) - dry-run first per COST_CONTROL.md.
--
-- Source: user-reported list, pasted directly in chat 2026-08-24, 43 (order_id, period) pairs
-- described as "RCL new period payment did not interface to SAP" (all period >= 2, i.e. an
-- ONGOING installment payment on an already-existing RCL schedule, not the order's first period).
-- This checks the CURRENT LIVE production (V2/legacy) path these items actually go through -
-- it is deliberately independent of the concurrent V3 Unit-5 NEWPAYMENT qualifier work
-- (commit 5afb5ff, RQ-20260824-1217), which queries a stale, not-yet-production V3 shadow run and
-- does not explain today's real V2 gap.
--
-- order_id here is bare (no -V1/-M1 suffix), matching the 20260817_verify_mo_1-15aug precedent's
-- input shape, so it is mapped to order_item via stg_payment_events(order_id, period) same as
-- that script. Ongoing RCL periods only ever land on the voluntary (-V1) item per
-- sql/ddl/013_stg_payment_events.sql's own comment ("Compulsory items never carry a real
-- per-period schedule"), so an order resolving to more than one order_item for a given period is
-- itself a finding, not expected, and is surfaced as AMBIGUOUS_MAPPING rather than guessed at.

WITH reported_pairs AS (
  SELECT * FROM UNNEST([
    STRUCT('L78710141' AS order_id, 2 AS period),
    STRUCT('L80385996' AS order_id, 2 AS period),
    STRUCT('L80391048' AS order_id, 2 AS period),
    STRUCT('L80399700' AS order_id, 2 AS period),
    STRUCT('L80399744' AS order_id, 2 AS period),
    STRUCT('L80400031' AS order_id, 2 AS period),
    STRUCT('L80401659' AS order_id, 2 AS period),
    STRUCT('L80404037' AS order_id, 2 AS period),
    STRUCT('L80407354' AS order_id, 2 AS period),
    STRUCT('L80409682' AS order_id, 2 AS period),
    STRUCT('L80409758' AS order_id, 2 AS period),
    STRUCT('L80410554' AS order_id, 2 AS period),
    STRUCT('L80415229' AS order_id, 2 AS period),
    STRUCT('L80415308' AS order_id, 2 AS period),
    STRUCT('L80415310' AS order_id, 2 AS period),
    STRUCT('L80416405' AS order_id, 2 AS period),
    STRUCT('L80417258' AS order_id, 2 AS period),
    STRUCT('L80417469' AS order_id, 2 AS period),
    STRUCT('L80421374' AS order_id, 2 AS period),
    STRUCT('L80421378' AS order_id, 2 AS period),
    STRUCT('L80422758' AS order_id, 2 AS period),
    STRUCT('L80423766' AS order_id, 2 AS period),
    STRUCT('L80428041' AS order_id, 2 AS period),
    STRUCT('L80429468' AS order_id, 2 AS period),
    STRUCT('L80429605' AS order_id, 2 AS period),
    STRUCT('L80429606' AS order_id, 2 AS period),
    STRUCT('L80438560' AS order_id, 2 AS period),
    STRUCT('L80438618' AS order_id, 2 AS period),
    STRUCT('L80440602' AS order_id, 2 AS period),
    STRUCT('L80440818' AS order_id, 2 AS period),
    STRUCT('L80447777' AS order_id, 2 AS period),
    STRUCT('L80448678' AS order_id, 2 AS period),
    STRUCT('L80456658' AS order_id, 2 AS period),
    STRUCT('L80462072' AS order_id, 2 AS period),
    STRUCT('L80473258' AS order_id, 2 AS period),
    STRUCT('L80555253' AS order_id, 2 AS period),
    STRUCT('L80577344' AS order_id, 2 AS period),
    STRUCT('L79361881' AS order_id, 3 AS period),
    STRUCT('L80445725' AS order_id, 3 AS period),
    STRUCT('L80463842' AS order_id, 3 AS period),
    STRUCT('L78322384' AS order_id, 4 AS period),
    STRUCT('L79770471' AS order_id, 4 AS period),
    STRUCT('L79586489' AS order_id, 7 AS period)
  ])
),

-- Same "real invoice" definition sql/ddl/005_recon_all_charges.sql uses for sap_invoiced.
sap_invoiced AS (
  SELECT U_OrderItem, U_Period
  FROM `pacific-plating-282708.sap_integration_v3.stg_sap_state`
  WHERE IFNULL(U_InvoiceNo, '') != ''
),

pair_mapping AS (
  SELECT
    r.order_id, r.period,
    p.order_item,
    COUNT(DISTINCT p.order_item) OVER (PARTITION BY r.order_id, r.period) AS item_count
  FROM reported_pairs r
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.stg_payment_events` p
    ON p.order_id = r.order_id AND p.period = r.period
),

classified AS (
  SELECT
    m.order_id, m.period, m.order_item, m.item_count,
    CASE WHEN si.U_OrderItem IS NOT NULL THEN TRUE ELSE FALSE END AS now_in_sap,
    excl.rule_code AS excluded_rule_code,
    val.check_name AS validation_check_name
  FROM pair_mapping m
  LEFT JOIN sap_invoiced si ON si.U_OrderItem = m.order_item AND si.U_Period = m.period
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.sap_excluded_records` excl
    ON excl.order_item = m.order_item AND excl.period = m.period
  LEFT JOIN `pacific-plating-282708.sap_integration_v3.sap_validation_error` val
    ON val.order_item = m.order_item AND val.period = m.period
),

-- Schedule/flow context per resolved item, independent of any dashboard candidate row -
-- distinguishes "never even scheduled this period" from "scheduled, but no export row exists".
schedule_ctx AS (
  SELECT order_id, order_item,
    ANY_VALUE(flow) AS flow,
    ANY_VALUE(total_periods) AS total_periods,
    COUNT(DISTINCT period) AS periods_in_schedule
  FROM `pacific-plating-282708.sap_integration_v3.stg_schedule`
  GROUP BY order_id, order_item
),

schedule_period_check AS (
  SELECT s.order_id, s.order_item, s.period
  FROM `pacific-plating-282708.sap_integration_v3.stg_schedule` s
),

-- Candidate export row (if any) from the same dashboard view the RCL interface views read.
candidate AS (
  SELECT SAFE_CAST(d.Period AS INT64) AS PeriodInt, d.*
  FROM `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_installment` d
),

result AS (
  SELECT
    c.order_id, c.period, c.order_item, c.item_count,
    c.now_in_sap, c.excluded_rule_code, c.validation_check_name,
    sc.flow, sc.total_periods, sc.periods_in_schedule,
    (spc.order_item IS NOT NULL) AS period_in_schedule,
    cand.OrderItem IS NOT NULL AS has_candidate_row,
    LOWER(cand.TransactionStatus) AS candidate_status,
    cand.InvoiceNo AS candidate_invoice_no,
    cand.PaymentDate AS candidate_payment_date,
    CASE
      WHEN c.order_item IS NULL THEN 'NO_STG_PAYMENT_EVENT_FOR_THIS_ORDER_PERIOD'
      WHEN c.item_count > 1 THEN 'AMBIGUOUS_MAPPING_MULTIPLE_ITEMS'
      WHEN c.now_in_sap THEN 'ALREADY_IN_SAP'
      WHEN c.excluded_rule_code IS NOT NULL THEN 'EXCLUDED_BY_RULE'
      WHEN c.validation_check_name IS NOT NULL THEN 'FAILED_VALIDATION'
      WHEN spc.order_item IS NULL THEN 'PERIOD_NOT_IN_SCHEDULE'
      WHEN cand.OrderItem IS NULL THEN 'NO_CANDIDATE_ROW_IN_DASHBOARD_VIEW'
      WHEN LOWER(cand.TransactionStatus) NOT IN ('paid', 'pending') THEN 'CANDIDATE_INVALID_STATUS'
      WHEN LOWER(cand.TransactionStatus) = 'paid'
        AND (NULLIF(TRIM(CAST(cand.InvoiceNo AS STRING)), '') IS NULL
          OR LENGTH(IFNULL(CAST(cand.PaymentDate AS STRING), '')) != 8)
        THEN 'CANDIDATE_MISSING_REQUIRED_PAID_FIELDS'
      ELSE 'CANDIDATE_LOOKS_CLEAN_BUT_NOT_IN_SAP'
    END AS diagnosis
  FROM classified c
  LEFT JOIN schedule_ctx sc ON sc.order_id = c.order_id AND sc.order_item = c.order_item
  LEFT JOIN schedule_period_check spc
    ON spc.order_id = c.order_id AND spc.order_item = c.order_item AND spc.period = c.period
  LEFT JOIN candidate cand ON cand.OrderItem = c.order_item AND cand.PeriodInt = c.period
)

SELECT
  order_id, period, order_item, flow, total_periods, periods_in_schedule,
  period_in_schedule, has_candidate_row, candidate_status, candidate_invoice_no,
  candidate_payment_date, excluded_rule_code, validation_check_name, diagnosis
FROM result
ORDER BY diagnosis, order_id, period;
