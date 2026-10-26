-- 20260823_verify_gsheet_missing_items.sql
-- READ-ONLY VERIFICATION ONLY. No CREATE/INSERT/UPDATE/DELETE, no gs://** write, no procedure CALL.
-- Must run through scripts/bq_safe_query.sh (mandatory query path) - dry-run first per COST_CONTROL.md.
--
-- Source: user-provided list, pasted directly in chat 2026-08-23, said to originate from a Google
-- Sheet the user has authorization for (link given, not fetched/verified here — this script only
-- verifies the item IDs, which is all it needs). List as pasted contained 183 lines; 182 unique
-- after dropping one exact duplicate ('L78026080-M1' appeared twice). One entry does NOT match the
-- `L<digits>-[VM]<digit>` item_id shape used everywhere else: 'L7903333-1' (looks like a truncated/
-- mistyped order number and/or suffix — needs the source sheet re-checked, not guessed at here). It
-- is left in the UNNEST list below so this query surfaces its true state (almost certainly "not
-- found anywhere") rather than silently dropping it.
--
-- Unlike the 20260817_verify_mo_1-15aug_missing_from_sap.sql precedent (which took bare order_id +
-- period pairs from a sheet and had to map them to order_item via stg_payment_events), every ID
-- here already carries its item suffix (-V1 voluntary / -M1 compulsory — see
-- docs/FINDINGS_MOTOR_MISROUTING_AND_MISSING_INTERFACE_20260805.md; the suffix is a product-type
-- tag, NOT an RCB/RCL flow indicator, so flow below is resolved via stg_schedule, never parsed from
-- the string). No period was supplied per item, so this checks ALL periods known to
-- stg_schedule/sap_dashboard_* for each item, not one specific period.
--
-- This script only classifies and quality-gates the reported population (in SAP already? excluded
-- by rule? flagged by validation? RCB or RCL? passes the same row-contract checks the interface
-- views enforce?). It does NOT regenerate or write the SAP interface file — per
-- sql/ddl/028_column_contract_guard.sql and the note at the foot of the 0817 precedent, a nonzero
-- "preliminary pass" population still requires exact 56-column name/type/ordinal validation,
-- InvoiceNo immutability, numeric/source reconciliation, master and exclusion checks,
-- successful-charge conservation, immutable snapshot hashing, and Class-A PASS before anything is
-- fed into the sql/sap_view/*.sql interface views for real.

WITH reported_items AS (
  SELECT DISTINCT order_item FROM UNNEST([
    STRUCT('L77728242-M1' AS order_item),
    STRUCT('L77984942-V1' AS order_item),
    STRUCT('L77986029-V1' AS order_item),
    STRUCT('L78026080-M1' AS order_item),
    STRUCT('L78296702-V1' AS order_item),
    STRUCT('L78359124-V1' AS order_item),
    STRUCT('L78444249-M1' AS order_item),
    STRUCT('L78459212-M1' AS order_item),
    STRUCT('L78548651-M1' AS order_item),
    STRUCT('L78562226-M1' AS order_item),
    STRUCT('L78570507-M1' AS order_item),
    STRUCT('L78593081-M1' AS order_item),
    STRUCT('L78599573-M1' AS order_item),
    STRUCT('L78600185-M1' AS order_item),
    STRUCT('L78605019-M1' AS order_item),
    STRUCT('L78605621-V1' AS order_item),
    STRUCT('L78611038-M1' AS order_item),
    STRUCT('L78625498-M1' AS order_item),
    STRUCT('L78629872-M1' AS order_item),
    STRUCT('L78632186-M1' AS order_item),
    STRUCT('L78637011-M1' AS order_item),
    STRUCT('L78642883-M1' AS order_item),
    STRUCT('L78646885-M1' AS order_item),
    STRUCT('L78661333-V1' AS order_item),
    STRUCT('L78661702-M1' AS order_item),
    STRUCT('L78664390-M1' AS order_item),
    STRUCT('L78664472-M1' AS order_item),
    STRUCT('L78670766-M1' AS order_item),
    STRUCT('L78675020-M1' AS order_item),
    STRUCT('L78677232-M1' AS order_item),
    STRUCT('L78678511-M1' AS order_item),
    STRUCT('L78680506-M1' AS order_item),
    STRUCT('L78680682-M1' AS order_item),
    STRUCT('L78684596-M1' AS order_item),
    STRUCT('L78685136-M1' AS order_item),
    STRUCT('L78687465-M1' AS order_item),
    STRUCT('L78701781-M1' AS order_item),
    STRUCT('L78701856-M1' AS order_item),
    STRUCT('L78702522-M1' AS order_item),
    STRUCT('L78703143-M1' AS order_item),
    STRUCT('L78704391-M1' AS order_item),
    STRUCT('L78706544-M1' AS order_item),
    STRUCT('L78707986-V1' AS order_item),
    STRUCT('L78708744-M1' AS order_item),
    STRUCT('L78711929-M1' AS order_item),
    STRUCT('L78719293-M1' AS order_item),
    STRUCT('L78723453-V1' AS order_item),
    STRUCT('L78727150-M1' AS order_item),
    STRUCT('L78727561-M1' AS order_item),
    STRUCT('L78727582-M1' AS order_item),
    STRUCT('L78727647-M1' AS order_item),
    STRUCT('L78727842-M1' AS order_item),
    STRUCT('L78728148-M1' AS order_item),
    STRUCT('L78728202-M1' AS order_item),
    STRUCT('L78728239-M1' AS order_item),
    STRUCT('L78728239-V1' AS order_item),
    STRUCT('L78728777-M1' AS order_item),
    STRUCT('L78731491-M1' AS order_item),
    STRUCT('L78731651-M1' AS order_item),
    STRUCT('L78732226-M1' AS order_item),
    STRUCT('L78733158-M1' AS order_item),
    STRUCT('L78733223-M1' AS order_item),
    STRUCT('L78733226-M1' AS order_item),
    STRUCT('L78734229-M1' AS order_item),
    STRUCT('L78734259-M1' AS order_item),
    STRUCT('L78734288-M1' AS order_item),
    STRUCT('L78734346-M1' AS order_item),
    STRUCT('L78736219-M1' AS order_item),
    STRUCT('L78736519-M1' AS order_item),
    STRUCT('L78737287-M1' AS order_item),
    STRUCT('L78737387-M1' AS order_item),
    STRUCT('L78737409-M1' AS order_item),
    STRUCT('L78739181-M1' AS order_item),
    STRUCT('L78739925-M1' AS order_item),
    STRUCT('L78744773-M1' AS order_item),
    STRUCT('L78749574-M1' AS order_item),
    STRUCT('L78751212-M1' AS order_item),
    STRUCT('L78751330-V1' AS order_item),
    STRUCT('L78753909-V1' AS order_item),
    STRUCT('L78754716-V1' AS order_item),
    STRUCT('L78754753-M1' AS order_item),
    STRUCT('L78755580-M1' AS order_item),
    STRUCT('L78758279-M1' AS order_item),
    STRUCT('L78759291-M1' AS order_item),
    STRUCT('L78763574-M1' AS order_item),
    STRUCT('L78763574-V1' AS order_item),
    STRUCT('L78764246-M1' AS order_item),
    STRUCT('L78772497-M1' AS order_item),
    STRUCT('L78775962-M1' AS order_item),
    STRUCT('L78775971-M1' AS order_item),
    STRUCT('L78775971-V1' AS order_item),
    STRUCT('L78775980-M1' AS order_item),
    STRUCT('L78780595-M1' AS order_item),
    STRUCT('L78780824-M1' AS order_item),
    STRUCT('L78780829-M1' AS order_item),
    STRUCT('L78784489-M1' AS order_item),
    STRUCT('L78791314-M1' AS order_item),
    STRUCT('L78792104-M1' AS order_item),
    STRUCT('L78794615-M1' AS order_item),
    STRUCT('L78795415-M1' AS order_item),
    STRUCT('L78796107-M1' AS order_item),
    STRUCT('L78796478-M1' AS order_item),
    STRUCT('L78799344-M1' AS order_item),
    STRUCT('L78815444-M1' AS order_item),
    STRUCT('L78821401-M1' AS order_item),
    STRUCT('L78825823-M1' AS order_item),
    STRUCT('L78830121-M1' AS order_item),
    STRUCT('L78834996-M1' AS order_item),
    STRUCT('L78870848-M1' AS order_item),
    STRUCT('L78872165-M1' AS order_item),
    STRUCT('L78885103-V1' AS order_item),
    STRUCT('L78886090-M1' AS order_item),
    STRUCT('L78899651-M1' AS order_item),
    STRUCT('L79013355-V1' AS order_item),
    STRUCT('L79016701-V1' AS order_item),
    STRUCT('L7903333-1' AS order_item),
    STRUCT('L79087765-V1' AS order_item),
    STRUCT('L79443149-V1' AS order_item),
    STRUCT('L79475067-V1' AS order_item),
    STRUCT('L79504851-M1' AS order_item),
    STRUCT('L79504851-V1' AS order_item),
    STRUCT('L79523728-V1' AS order_item),
    STRUCT('L79601099-V1' AS order_item),
    STRUCT('L79624490-M1' AS order_item),
    STRUCT('L79655638-V1' AS order_item),
    STRUCT('L79670062-M1' AS order_item),
    STRUCT('L79680002-V1' AS order_item),
    STRUCT('L79804707-M1' AS order_item),
    STRUCT('L79804840-M1' AS order_item),
    STRUCT('L79915904-V1' AS order_item),
    STRUCT('L80011564-V1' AS order_item),
    STRUCT('L80323637-M1' AS order_item),
    STRUCT('L80335345-M1' AS order_item),
    STRUCT('L80366711-M1' AS order_item),
    STRUCT('L80421357-M1' AS order_item),
    STRUCT('L80442770-M1' AS order_item),
    STRUCT('L80451154-M1' AS order_item),
    STRUCT('L80463853-M1' AS order_item),
    STRUCT('L80476940-M1' AS order_item),
    STRUCT('L80482628-M1' AS order_item),
    STRUCT('L80489637-M1' AS order_item),
    STRUCT('L80490109-M1' AS order_item),
    STRUCT('L80505560-M1' AS order_item),
    STRUCT('L80506335-M1' AS order_item),
    STRUCT('L80520170-M1' AS order_item),
    STRUCT('L80522000-V1' AS order_item),
    STRUCT('L80526872-M1' AS order_item),
    STRUCT('L80527809-V1' AS order_item),
    STRUCT('L80538079-M1' AS order_item),
    STRUCT('L80538812-M1' AS order_item),
    STRUCT('L80541140-V1' AS order_item),
    STRUCT('L80541683-M1' AS order_item),
    STRUCT('L80541683-V1' AS order_item),
    STRUCT('L80542542-M1' AS order_item),
    STRUCT('L80543385-M1' AS order_item),
    STRUCT('L80545763-M1' AS order_item),
    STRUCT('L80546291-M1' AS order_item),
    STRUCT('L80551458-M1' AS order_item),
    STRUCT('L80551458-V1' AS order_item),
    STRUCT('L80556789-M1' AS order_item),
    STRUCT('L80561672-M1' AS order_item),
    STRUCT('L80563347-V1' AS order_item),
    STRUCT('L80563651-M1' AS order_item),
    STRUCT('L80569777-M1' AS order_item),
    STRUCT('L80569801-M1' AS order_item),
    STRUCT('L80570435-V1' AS order_item),
    STRUCT('L80570929-M1' AS order_item),
    STRUCT('L80572586-M1' AS order_item),
    STRUCT('L80575603-M1' AS order_item),
    STRUCT('L80580088-V1' AS order_item),
    STRUCT('L80587589-M1' AS order_item),
    STRUCT('L80588889-M1' AS order_item),
    STRUCT('L80591812-M1' AS order_item),
    STRUCT('L80593559-M1' AS order_item),
    STRUCT('L80594836-M1' AS order_item),
    STRUCT('L80602556-M1' AS order_item),
    STRUCT('L80604467-M1' AS order_item),
    STRUCT('L80607250-M1' AS order_item),
    STRUCT('L80617190-M1' AS order_item),
    STRUCT('L80620217-M1' AS order_item),
    STRUCT('L80620993-M1' AS order_item),
    STRUCT('L80637076-M1' AS order_item)
  ])
),

-- Same "real invoice" definition sql/ddl/005_recon_all_charges.sql uses for sap_invoiced:
-- a period counts as in SAP only if it has a real invoice, not just any row/status.
sap_invoiced AS (
  SELECT U_OrderItem, U_Period
  FROM `pacific-plating-282708.sap_integration_v3.stg_sap_state`
  WHERE IFNULL(U_InvoiceNo, '') != ''
),

-- Per-item flow + expected period spine, from the same source stg_schedule the production
-- interface views key off. An item with zero rows here doesn't exist in careos at all under this
-- exact ID (typo/wrong ID/never created) and needs source-sheet follow-up, not a SQL fix.
schedule_summary AS (
  SELECT
    s.order_item,
    STRING_AGG(DISTINCT s.flow, ',' ORDER BY s.flow) AS flows,
    COUNT(DISTINCT s.period) AS periods_in_schedule
  FROM `pacific-plating-282708.sap_integration_v3.stg_schedule` s
  GROUP BY s.order_item
),

invoiced_summary AS (
  SELECT U_OrderItem AS order_item, COUNT(DISTINCT U_Period) AS periods_invoiced
  FROM sap_invoiced
  GROUP BY U_OrderItem
),

excluded_summary AS (
  SELECT order_item, STRING_AGG(DISTINCT rule_code, ',' ORDER BY rule_code) AS rule_codes
  FROM `pacific-plating-282708.sap_integration_v3.sap_excluded_records`
  GROUP BY order_item
),

validation_summary AS (
  SELECT order_item, STRING_AGG(DISTINCT check_name, ',' ORDER BY check_name) AS check_names
  FROM `pacific-plating-282708.sap_integration_v3.sap_validation_error`
  GROUP BY order_item
),

classified AS (
  SELECT
    r.order_item,
    sc.flows,
    IFNULL(sc.periods_in_schedule, 0) AS periods_in_schedule,
    IFNULL(inv.periods_invoiced, 0) AS periods_invoiced,
    ex.rule_codes AS excluded_rule_codes,
    val.check_names AS validation_check_names
  FROM reported_items r
  LEFT JOIN schedule_summary sc ON sc.order_item = r.order_item
  LEFT JOIN invoiced_summary inv ON inv.order_item = r.order_item
  LEFT JOIN excluded_summary ex ON ex.order_item = r.order_item
  LEFT JOIN validation_summary val ON val.order_item = r.order_item
),

-- IMPORTANT — stg_schedule.flow does NOT determine which dashboard view an item's row lives in.
-- Confirmed wrong by direct query 2026-08-23: 'L78359124-V1' carries flow='ONETIME' in
-- stg_schedule yet its real row is in sap_dashboard_carepay_installment, not fully_paid. flow is a
-- business classification of payment_option + motor_item_type (e.g. a credit-card installment plan
-- is force-mapped to 'ONETIME' because the bank pays in full up front, per
-- sql/ddl/012_stg_schedule.sql lines 8-10) — it is orthogonal to the raw
-- carepay_transaction_snapshots.number_of_installment value each dashboard view actually filters
-- on (=1 for fully_paid, >1 for installment). Neither view dedupes transaction-snapshot history,
-- so the same order_item can legitimately appear in both views, or in neither. The only reliable
-- way to route an item is to check both views directly by OrderItem, which is what this does.
installment_rows AS (
  SELECT d.*
  FROM `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_installment` d
  JOIN reported_items r ON r.order_item = d.OrderItem
),

fully_paid_rows AS (
  SELECT d.*
  FROM `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_fully_paid` d
  JOIN reported_items r ON r.order_item = d.OrderItem
),

view_membership AS (
  SELECT
    r.order_item,
    EXISTS(SELECT 1 FROM installment_rows i WHERE i.OrderItem = r.order_item) AS in_installment_view,
    EXISTS(SELECT 1 FROM fully_paid_rows f WHERE f.OrderItem = r.order_item) AS in_fully_paid_view
  FROM reported_items r
),

-- Route only clean, single-view items into a case-type gate. Excluded/validation-flagged items,
-- and items appearing in both or neither view, are quarantined for manual review rather than
-- gated, exactly as the 0817 precedent does for its own edge cases.
routable AS (
  SELECT cl.*, vm.in_installment_view, vm.in_fully_paid_view
  FROM classified cl
  JOIN view_membership vm ON vm.order_item = cl.order_item
  WHERE cl.excluded_rule_codes IS NULL
    AND cl.validation_check_names IS NULL
),

rcl_candidate AS (
  SELECT i.*
  FROM installment_rows i
  JOIN routable r ON r.order_item = i.OrderItem
    AND r.in_installment_view AND NOT r.in_fully_paid_view
),

rcl_item_gate AS (
  SELECT c.OrderItem,
    COUNT(*) AS row_count,
    COUNT(DISTINCT SAFE_CAST(c.Period AS INT64)) AS period_count,
    MIN(SAFE_CAST(c.Period AS INT64)) AS first_period,
    MAX(SAFE_CAST(c.Period AS INT64)) AS last_period,
    MAX(SAFE_CAST(c.TotalPeriods AS INT64)) AS total_periods,
    COUNTIF(LOWER(c.TransactionStatus) NOT IN ('paid','pending') OR c.TransactionStatus IS NULL)
      AS invalid_status_rows,
    COUNTIF(REGEXP_CONTAINS(TO_JSON_STRING(c), r':null(?:,|})')) AS sql_null_rows,
    COUNTIF(REGEXP_CONTAINS(UPPER(TO_JSON_STRING(c)), r'"NULL"')) AS literal_null_rows,
    COUNTIF(LOWER(c.TransactionStatus)='paid' AND (
      NULLIF(TRIM(CAST(c.InvoiceNo AS STRING)), '') IS NULL
      OR LENGTH(IFNULL(CAST(c.PaymentDate AS STRING), '')) != 8
      OR SAFE.PARSE_DATE('%d%m%Y', CAST(c.PaymentDate AS STRING)) IS NULL)) AS paid_required_rows,
    COUNTIF(LENGTH(IFNULL(CAST(c.OrderDate AS STRING), '')) != 8
      OR SAFE.PARSE_DATE('%d%m%Y', CAST(c.OrderDate AS STRING)) IS NULL
      OR LENGTH(IFNULL(CAST(c.PolicyDate AS STRING), '')) != 8
      OR SAFE.PARSE_DATE('%d%m%Y', CAST(c.PolicyDate AS STRING)) IS NULL) AS invalid_date_rows
  FROM rcl_candidate c
  GROUP BY c.OrderItem
),

rcl_result AS (
  SELECT
    OrderItem AS order_item,
    'RCL' AS flow,
    (total_periods IS NOT NULL AND first_period = 1 AND last_period = total_periods
      AND row_count = total_periods AND period_count = total_periods) AS complete_spine,
    -- sql_null_rows/literal_null_rows deliberately excluded here: they scan every column on the
    -- dashboard view, including EndorsementNo/RefOrder/RefundAmountBeforeFee/RefundAmountAfterFee,
    -- which are legitimately NULL on ordinary non-endorsement, non-refund records (confirmed by
    -- inspecting a real paid row 2026-08-23) — treating that as a failure produced false positives
    -- on essentially every candidate, unlike the 0817 precedent's own reported population.
    (invalid_status_rows = 0 AND paid_required_rows = 0 AND invalid_date_rows = 0)
      AS row_contract_pass
  FROM rcl_item_gate
),

rcb_candidate AS (
  SELECT f.*
  FROM fully_paid_rows f
  JOIN routable r ON r.order_item = f.OrderItem
    AND r.in_fully_paid_view AND NOT r.in_installment_view
),

-- RCB TotalPeriods is always the literal 1 (not a real spine length, see
-- sql/production/sap_dashboard_carepay_fully_paid.sql), so "complete" here just means exactly one
-- row exists for the item (zero = orphan reported ID / not yet a candidate row anywhere; more than
-- one = duplicate needing separate investigation), not a 1..N spine walk.
rcb_item_gate AS (
  SELECT c.OrderItem,
    COUNT(*) AS row_count,
    COUNTIF(LOWER(c.TransactionStatus) NOT IN ('paid','pending') OR c.TransactionStatus IS NULL)
      AS invalid_status_rows,
    COUNTIF(REGEXP_CONTAINS(TO_JSON_STRING(c), r':null(?:,|})')) AS sql_null_rows,
    COUNTIF(REGEXP_CONTAINS(UPPER(TO_JSON_STRING(c)), r'"NULL"')) AS literal_null_rows,
    COUNTIF(LOWER(c.TransactionStatus)='paid' AND (
      NULLIF(TRIM(CAST(c.InvoiceNo AS STRING)), '') IS NULL
      OR LENGTH(IFNULL(CAST(c.PaymentDate AS STRING), '')) != 8
      OR SAFE.PARSE_DATE('%d%m%Y', CAST(c.PaymentDate AS STRING)) IS NULL)) AS paid_required_rows,
    COUNTIF(LENGTH(IFNULL(CAST(c.OrderDate AS STRING), '')) != 8
      OR SAFE.PARSE_DATE('%d%m%Y', CAST(c.OrderDate AS STRING)) IS NULL
      OR LENGTH(IFNULL(CAST(c.PolicyDate AS STRING), '')) != 8
      OR SAFE.PARSE_DATE('%d%m%Y', CAST(c.PolicyDate AS STRING)) IS NULL) AS invalid_date_rows
  FROM rcb_candidate c
  GROUP BY c.OrderItem
),

rcb_result AS (
  SELECT
    OrderItem AS order_item,
    'RCB' AS flow,
    (row_count = 1) AS complete_spine,
    -- Same exclusion of the whole-row null scan as rcl_result, and for the same reason.
    (invalid_status_rows = 0 AND paid_required_rows = 0 AND invalid_date_rows = 0)
      AS row_contract_pass
  FROM rcb_item_gate
),

gated AS (
  SELECT * FROM rcl_result
  UNION ALL
  SELECT * FROM rcb_result
)

-- Per-item detail: this is the actionable output. Anything landing in
-- quarantine_reason NOT NULL needs eyes before it can go anywhere near the interface views;
-- anything with preliminary_status = 'PASS' is the population worth feeding into the existing
-- sql/sap_view/*.sql interface-generation queries for its case type next — this script does not do
-- that step itself.
SELECT
  cl.order_item,
  cl.flows,
  cl.periods_in_schedule,
  cl.periods_invoiced,
  cl.excluded_rule_codes,
  cl.validation_check_names,
  vm.in_installment_view,
  vm.in_fully_paid_view,
  g.complete_spine,
  g.row_contract_pass,
  CASE
    WHEN cl.periods_in_schedule = 0 THEN 'NOT_FOUND_IN_CAREOS_SCHEDULE'
    WHEN cl.excluded_rule_codes IS NOT NULL THEN 'EXCLUDED_BY_RULE'
    WHEN cl.validation_check_names IS NOT NULL THEN 'FAILED_VALIDATION'
    WHEN cl.periods_invoiced >= cl.periods_in_schedule THEN 'ALREADY_IN_SAP'
    WHEN vm.in_installment_view AND vm.in_fully_paid_view THEN 'APPEARS_IN_BOTH_VIEWS'
    WHEN NOT vm.in_installment_view AND NOT vm.in_fully_paid_view
      THEN 'NO_CANDIDATE_ROW_IN_EITHER_VIEW'
    WHEN g.order_item IS NULL THEN 'NO_GATE_RESULT'
    WHEN NOT g.complete_spine THEN 'INCOMPLETE_SPINE'
    WHEN NOT g.row_contract_pass THEN 'ROW_CONTRACT_FAIL'
    ELSE 'PASS'
  END AS preliminary_status
FROM classified cl
JOIN view_membership vm ON vm.order_item = cl.order_item
LEFT JOIN gated g ON g.order_item = cl.order_item
ORDER BY preliminary_status, cl.order_item;

-- This result is preliminary only. A nonzero PASS population still requires exact 56-column
-- name/type/ordinal validation, InvoiceNo immutability, numeric/source reconciliation, master and
-- exclusion checks, successful-charge conservation, immutable snapshot hashing, and Class-A PASS
-- before any shadow GCS write — same bar as the 0817 precedent, not lowered here.
