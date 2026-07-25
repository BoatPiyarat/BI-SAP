-- 015_fn_invoice_no.sql
-- P2 build (Boat, 2026-07-25: "start building" V3 P1-P3).
-- Implements SAP_INTERFACE_REDESIGN_V3.md §2.5's intent - "InvoiceNo กติกาเดียวทั้งระบบ", a single
-- central function every flow calls instead of each one inventing its own prefixing convention
-- (B1: "InvoiceNo convention ชนกัน 2 flow" - BI's CONCAT('2_', id) vs raw charge id - was the
-- actual root cause of "Cannot change InvoiceNo when status Paid" import errors).
--
-- Standard confirmed by Boat 2026-07-25: "invoiceno can be raw thirdpartyid, 2_ prefix on SAP
-- stays for new payment and cancel(mirror SAP)". Since third_party_id is the charge's own unique
-- ID (not something that collides across different charges), no rank-based collision prefix is
-- needed on top of it - the original design doc's charge_rank scheme was solving a different,
-- no-longer-relevant problem (BI's separate prefixing scheme colliding with the raw-id scheme
-- when both were used inconsistently, not charges colliding with each other).
--
-- Any NEW create-flow logic (P2 engine, future views) should call this instead of writing its own
-- CONCAT/prefix logic - that's what actually prevents B1 from recurring. Existing newpayment/
-- cancel flows that mirror an already-Paid SAP row must NOT call this - they pass through
-- whatever InvoiceNo SAP already has verbatim (immutable), including legacy 2_-prefixed values.

CREATE OR REPLACE FUNCTION `pacific-plating-282708.sap_integration_v3.fn_invoice_no`(third_party_id STRING)
RETURNS STRING
AS (
  third_party_id
);
