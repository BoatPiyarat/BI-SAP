-- 038_orderitem_alias_and_adj_invoice_minting.sql
-- Boat D9 (2026-07-29/30), credit-shell remediation design (Method 2 = Cancel + resend Paid under a
-- NEW OrderItem generation, since a Paid/Cancelled item is immutable in SAP).
-- SOURCE ONLY. NOT DEPLOYED. Nothing in this file has been run against BigQuery.
--
-- ============================================================================
-- PRECONDITION CHECK (done first, per Boat's explicit "เช็คก่อนอย่างอื่น"):
-- Does CareOS already use -M2/-V2/-M3 as a real, different-meaning suffix?
-- Verified live 2026-07-29/30:
--   SELECT REGEXP_EXTRACT(human_id, r'-([A-Z]*\d+)$') suffix, COUNT(*) FROM careos_order_items
--   GROUP BY 1  ->  V1: 478,955 | M1: 175,346 | '1': 77,340 | '2': 23,455 | M2: 1,019
-- -M2 IS real, live production data (1,019 rows) - sampled 5: every one is
-- motor_item_type = MOTOR_TYPE_COMPULSORY, on an order with exactly 2 items (an M2 + a V1, with NO
-- M1 present at all in the sampled cases) - a genuinely different real item, not "M1 revision 2."
-- CONFIRMED: cannot reuse "M2" as a revision-generation suffix. V2 and M3 do not appear in current
-- data (0 rows) but that only means "not observed today," not "reserved as safe forever."
--
-- Proposed non-colliding convention (per Boat's own suggested shape): append "R{generation}" to the
-- ORIGINAL suffix, never renumber the base digit - e.g. `L80524847-M1` (generation 1, unchanged)
-- becomes `L80524847-M1R2` for the Method-2 replacement (generation 2). Verified this pattern is
-- currently unused anywhere: `SELECT COUNT(*) FROM careos_order_items WHERE REGEXP_CONTAINS(human_id, r'R\d+$')`
-- -> 0 rows. **This naming choice is a PROPOSAL ONLY - waiting on Boat's explicit confirmation
-- before anything downstream is built to depend on the exact string format.** Everything below uses
-- `-M1R2`-shaped values as a placeholder to illustrate the design; the alias table itself does not
-- hardcode the format (see below), so confirming a different string later does not require
-- redesigning the table.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Item 2: sap_orderitem_alias - the one place CareOS<->SAP order_item identity is recorded.
-- Every join between a CareOS order_item and a SAP-side OrderItem key MUST go through this table
-- once Method 2 exists - otherwise the new generation (e.g. -M1R2) is an orphan in SAP-facing
-- recon (nothing expects it) and the old generation (-M1) reads as a permanent false MISSING
-- (expected_state/delta_export would still look for -M1's future periods forever, since nothing
-- tells them -M1 was superseded by -M1R2 for periods going forward).
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.sap_orderitem_alias` (
  careos_order_item STRING,   -- the CareOS-side human_id AS IT WOULD naturally be derived (e.g. the
                               -- pre-incident base item, `L80524847-M1`) - what recon logic would
                               -- compute if it never knew about this remediation
  sap_order_item STRING,      -- the actual OrderItem value used/expected in SAP for this generation
                               -- (e.g. `L80524847-M1R2` once Method 2 runs) - what SAP-side tables
                               -- (sap_mirror_state, SAP_LIVE_FULL) will actually contain
  generation INT64,            -- 1 = original/unaffected; 2+ = created by a remediation round
  reason STRING,               -- e.g. 'CREDITSHELL_DUPLICATE_20260729' - free text, cite the FINDINGS/incident
  audit_case_id STRING,        -- ties back to a specific row in the incident's case list (once built,
                               -- see item 4) - lets one alias row be traced to exactly which case
                               -- justified minting it, not just "some incident happened"
  created_at TIMESTAMP
)
CLUSTER BY careos_order_item;

-- Downstream integration this implies (NOT done in this file - each is its own deploy-gated change
-- to an existing consumer-read object, listed here so the blast radius is visible before Boat signs
-- off on the alias approach itself):
--   - `034`/`037`'s `sp_refresh_expected_state`: any join keyed on order_item (stg_schedule,
--     stg_order_dim, sap_mirror_state) would need to resolve through this alias first, so a
--     generation-2 item's periods compute against the RIGHT SAP-side key.
--   - `018_delta_export.sql` (`sp_refresh_delta_export`): the join to `stg_sap_state` on
--     `U_OrderItem` needs the same resolution.
--   - `030_interface_daily_status.sql`: same join pattern, same requirement.
--   - Any future recon/reconciliation query built on `sap_mirror_doc`/`sap_mirror_state` directly.
-- None of these are touched here - each is a separate, reviewable change once the alias table and
-- naming convention are both confirmed.

-- ----------------------------------------------------------------------------
-- Item 5: ADJ{n} invoice minting, scoped per ORDER (Q8a resolved: InvoiceNo uniqueness = per order,
-- not per order_item). Must check the order's EXISTING invoices (from `sap_mirror_doc`, the
-- authoritative per-document mirror) before minting, so the chosen n never collides with anything
-- already used under that order - including a prior ADJ mint, per Boat's explicit ask.
-- fn_invoice_no itself is currently `third_party_id` verbatim (a pure identity passthrough) and
-- cannot do this - identity has no way to consult existing invoices. This is therefore a NEW,
-- separate function, not a change to fn_invoice_no's existing behavior for normal (non-remediation)
-- rows.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION `pacific-plating-282708.sap_integration_v3.fn_mint_adj_invoice`(
  p_order_id STRING, p_sap_order_item STRING
) AS (
  CONCAT(
    'ADJ',
    CAST(
      (
        SELECT IFNULL(MAX(SAFE_CAST(REGEXP_EXTRACT(m.U_InvoiceNo, r'^ADJ(\d+)_') AS INT64)), 0) + 1
        FROM `pacific-plating-282708.sap_integration_v3.sap_mirror_doc` m
        WHERE m.U_OrderID = p_order_id
          AND REGEXP_CONTAINS(m.U_InvoiceNo, r'^ADJ\d+_')
      ) AS STRING
    ),
    '_', p_sap_order_item
  )
);

-- Unit test / collision-case verification - RUN 2026-07-30, read-only, against the regex/aggregate
-- logic directly (the function itself is not deployed, so these test the expression, not a live
-- function call):
--
--   Case A (no prior ADJ invoice): REGEXP_EXTRACT('ADJ1_L00000001-M1R2', r'^ADJ(\d+)_')
--     -> '1'. Confirms the base extraction works.
--   Case B (non-contiguous prior invoices ADJ1_.../ADJ3_..., simulating a partial prior
--     remediation round), via a 3-row scratch table (2 ADJ invoices + 1 unrelated
--     'ADJUSTMENT_unrelated' row) for one fake OrderID:
--     MAX(...)+1 over that set -> **4** (correctly MAX+1, not "fill the gap at 2"; correctly ignored
--     the unrelated row).
--   Case C (similar-looking non-ADJ invoice, 'ADJUSTMENT_L00000001-M1R2'):
--     REGEXP_EXTRACT(..., r'^ADJ(\d+)_') -> NULL, REGEXP_CONTAINS(..., r'^ADJ\d+_') -> false.
--     Confirms no digit immediately after "ADJ" means no false match - "ADJUSTMENT" does not get
--     miscounted as a prior ADJ{n} mint.
--
-- All three cases verified with the expected result. The function has NOT been deployed - this
-- only confirms the expression logic is sound before it's created live.
