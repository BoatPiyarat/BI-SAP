-- 042_sap_fa_verification.sql
-- Boat D16 (2026-07-30) item 3: a small control table recording FA (Mo)'s own verified cases, so
-- every future query has a durable, checkable known-answer test for posted-state classification
-- instead of re-deriving it by hand each time. SOURCE ONLY. Not deployed. No live object created.

CREATE TABLE `pacific-plating-282708.sap_integration_v3.sap_fa_verification` (
  order_id STRING,
  order_item STRING,
  verified_by STRING,
  verification_date DATE,
  has_cmi_sibling BOOL,
  -- posted_state: 'POSTED_CORRECT' | 'POSTED_WRONG' | 'REJECTED_NEVER_POSTED'
  posted_state STRING,
  notes STRING,
  created_at TIMESTAMP
)
CLUSTER BY order_id;

-- Seed rows: exactly the 2 cases Mo (FA) supplied directly. Any query classifying posted-state
-- must reproduce both of these, or the query is wrong - same discipline as the existing
-- known-answer tests (e.g. L80524847 for the MISPOSTING shape).

INSERT INTO `pacific-plating-282708.sap_integration_v3.sap_fa_verification`
  (order_id, order_item, verified_by, verification_date, has_cmi_sibling, posted_state, notes, created_at)
VALUES
  ('L79871659', 'L79871659-V1', 'Mo (FA)', DATE('2026-07-30'), FALSE, 'POSTED_CORRECT',
   'No CMI sibling item (single item order, MOTOR_TYPE_1). Booked correctly since March 2026 - '
   'FA confirmed directly. Must NEVER appear in a CMI-cause population, and its delta (whatever '
   'it is) is not this incident''s mechanism.',
   CURRENT_TIMESTAMP()),
  ('L80524847', 'L80524847-M1', 'Mo (FA)', DATE('2026-07-30'), TRUE, 'REJECTED_NEVER_POSTED',
   'No JE - entire import file (LogID 21090, 26/26 rows) rejected outright, "Sequence of Period '
   'invalid". Confirmed independently: zero rows in sap_mirror_doc for this order. Must NEVER be '
   'proposed for a correction line - there is nothing posted to correct. Kept as a known-answer '
   'test for generating-bug/rejection-detection logic only, not for correction-formula validation.',
   CURRENT_TIMESTAMP());

-- Usage pattern for any future quantification query:
--   LEFT JOIN sap_fa_verification fa ON fa.order_id = <candidate>.OrderID
--   -- assert: fa.order_id = 'L79871659' never appears in the output population
--   -- assert: fa.order_id = 'L80524847' never appears in a POSTED_WRONG/correction-eligible bucket
