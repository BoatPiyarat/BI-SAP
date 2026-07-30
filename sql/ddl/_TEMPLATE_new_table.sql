-- sql/ddl/_TEMPLATE_new_table.sql
-- Convention template for every NEW table created in sap_integration_v3 from now on.
-- Not runnable as-is (placeholders throughout) - copy into a numbered file and fill in.
-- Leading underscore keeps this out of the numbered sequence in sql/ddl/README.md, same
-- convention as the existing _backfill_* one-off objects.

-- ============================================================================
-- RULE (added 2026-07-30, Boat): every diag_*/scratch table is a NEW table only.
-- If the name starts with diag_ or scratch (or is otherwise a throwaway diagnostic/
-- exploration object, per docs/COST_CONTROL.md §3.3 "ตาราง diag_*/scratch"), it MUST
-- carry a self-expiring OPTIONS clause in its CREATE TABLE. No exceptions, no follow-up
-- ALTER needed - set it at creation time.
-- ============================================================================

CREATE TABLE `pacific-plating-282708.sap_integration_v3.diag_REPLACE_ME`
(
  -- columns here
)
OPTIONS (
  expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 30 DAY),
  description = "diagnostic/scratch table - self-expires 30 days after creation, per docs/COST_CONTROL.md §3.3"
);

-- ============================================================================
-- ⚠️ DO NOT apply expiration_timestamp (or any ALTER, cleanup, dedup, or delete) to the
-- 7 pre-existing tables below. They predate this convention, are explicitly OUT OF SCOPE,
-- and are waiting on a separate, reviewed retention decision - not this template's rule:
--
--   _backfill_rcl_motor_20260725b
--   _backfill_rcl_motor_newpayment_20260725
--   _backfill_rcl_nonmotor_20260725b
--   _backfill_rcl_nonmotor_newpayment_20260725
--   manual_close_20260726_motor_newpayment_gap
--   manual_close_20260726_rcb_creditshell
--   manual_close_20260726_rcl_creditshell
--
-- This list mirrors the same "no cleanup before a reviewed retention decision" principle
-- already governing the SAP_LIVE bloat incident (docs/knowledge/20_SAP_PROGRESS.md,
-- docs/knowledge/30_SAP_CHANGELOG.md) - do not extend that principle's scope, and do not
-- narrow it, without a separate explicit decision.
-- ============================================================================

-- Non-diagnostic, permanent tables (control tables, mirrors, staging, etc.) do NOT take an
-- expiration_timestamp - only diag_*/scratch objects self-expire. When in doubt whether a
-- new table counts as diag_*/scratch, ask before naming/creating it, since the naming
-- itself is what triggers this rule.

-- Always dry-run first (per docs/COST_CONTROL.md §3.1): use scripts/bq_safe_query.sh for
-- every query against real data, including the exploration query that led to this table.
