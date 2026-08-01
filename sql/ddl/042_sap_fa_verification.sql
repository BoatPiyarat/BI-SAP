-- 042_sap_fa_verification.sql
-- Durable FA/Aware evidence register for SAP posting and correction decisions.
-- SOURCE ONLY. Class A. Not deployed. Deployment requires review and Boat approval.
--
-- This table records evidence, not a derived candidate population. A row is valid only when its
-- business grain and evidence provenance are explicit. Raw email bodies, screenshots, names,
-- identity numbers, or other PII must not be copied into this table or this source file; retain a
-- controlled source URI/reference instead.
-- INCONCLUSIVE may retain partial SAP/import evidence because it records an unresolved
-- investigation. NOT_FOUND and REJECTED_NEVER_POSTED are fail-closed below so they cannot carry
-- contradictory evidence that a SAP document/status/JE exists.

CREATE TABLE IF NOT EXISTS `pacific-plating-282708.sap_integration_v3.sap_fa_verification` (
  verification_id STRING NOT NULL,
  incident_or_finding_id STRING NOT NULL,
  order_id STRING NOT NULL,
  order_item STRING NOT NULL,
  period INT64 NOT NULL,
  sap_doc_entry INT64,
  sap_status STRING,
  je_reference STRING,
  import_log_id STRING,
  -- Controlled values when present: SUCCESS | REJECTED | UNKNOWN
  import_outcome STRING,
  import_evidence STRING,
  verifier STRING NOT NULL,
  -- Controlled values: POSTED_CORRECT | POSTED_WRONG | REJECTED_NEVER_POSTED |
  --                  NOT_FOUND | INCONCLUSIVE
  decision STRING NOT NULL,
  evidence_timestamp TIMESTAMP NOT NULL,
  captured_at TIMESTAMP NOT NULL,
  source_uri STRING NOT NULL,
  source_note STRING
)
PARTITION BY DATE(evidence_timestamp)
CLUSTER BY incident_or_finding_id, order_id, order_item;

-- All writes should use this procedure. It supplies the controlled-value and evidence guards that
-- BigQuery table constraints cannot enforce. Reusing verification_id is rejected so corrections
-- to evidence remain an explicit new audit record rather than an invisible overwrite.
CREATE OR REPLACE PROCEDURE `pacific-plating-282708.sap_integration_v3.sp_record_fa_verification`(
  p_verification_id STRING,
  p_incident_or_finding_id STRING,
  p_order_id STRING,
  p_order_item STRING,
  p_period INT64,
  p_sap_doc_entry INT64,
  p_sap_status STRING,
  p_je_reference STRING,
  p_import_log_id STRING,
  p_import_outcome STRING,
  p_import_evidence STRING,
  p_verifier STRING,
  p_decision STRING,
  p_evidence_timestamp TIMESTAMP,
  p_source_uri STRING,
  p_source_note STRING
)
BEGIN
  ASSERT p_verification_id IS NOT NULL AND TRIM(p_verification_id) != ''
    AS 'verification_id is required';
  ASSERT p_incident_or_finding_id IS NOT NULL AND TRIM(p_incident_or_finding_id) != ''
    AS 'incident_or_finding_id is required';
  ASSERT p_order_id IS NOT NULL AND TRIM(p_order_id) != ''
    AS 'order_id is required';
  ASSERT p_order_item IS NOT NULL AND TRIM(p_order_item) != ''
    AS 'order_item is required';
  ASSERT p_period IS NOT NULL AND p_period > 0
    AS 'period must be a positive integer';
  ASSERT p_verifier IS NOT NULL AND TRIM(p_verifier) != ''
    AS 'verifier is required';
  ASSERT p_decision IN (
    'POSTED_CORRECT',
    'POSTED_WRONG',
    'REJECTED_NEVER_POSTED',
    'NOT_FOUND',
    'INCONCLUSIVE'
  ) AS 'decision is not an allowed sap_fa_verification value';
  ASSERT p_evidence_timestamp IS NOT NULL
    AS 'evidence_timestamp is required';
  ASSERT p_source_uri IS NOT NULL AND TRIM(p_source_uri) != ''
    AS 'source_uri is required';
  ASSERT p_import_outcome IS NULL OR p_import_outcome IN ('SUCCESS', 'REJECTED', 'UNKNOWN')
    AS 'import_outcome is not an allowed sap_fa_verification value';
  ASSERT NOT EXISTS (
    SELECT 1
    FROM `pacific-plating-282708.sap_integration_v3.sap_fa_verification`
    WHERE verification_id = p_verification_id
  ) AS 'verification_id already exists; append a new evidence record instead of overwriting';

  -- A positive posting decision is not supported by status alone. It requires the SAP document,
  -- JE, and successful-import evidence as one evidence chain.
  ASSERT p_decision NOT IN ('POSTED_CORRECT', 'POSTED_WRONG') OR (
    p_sap_doc_entry IS NOT NULL
    AND p_sap_status IS NOT NULL AND TRIM(p_sap_status) != ''
    AND p_je_reference IS NOT NULL AND TRIM(p_je_reference) != ''
    AND p_import_log_id IS NOT NULL AND TRIM(p_import_log_id) != ''
    AND p_import_outcome = 'SUCCESS'
    AND p_import_evidence IS NOT NULL AND TRIM(p_import_evidence) != ''
  ) AS 'posted decisions require DocEntry, SAP status, JE, import LogID, and success evidence';

  -- NOT_FOUND cannot simultaneously claim that SAP document or JE evidence exists.
  ASSERT p_decision != 'NOT_FOUND' OR (
    p_sap_doc_entry IS NULL
    AND (p_je_reference IS NULL OR TRIM(p_je_reference) = '')
  ) AS 'NOT_FOUND decisions require no DocEntry/JE';

  -- A rejected decision must identify the import attempt and its rejection evidence, but must not
  -- pretend that a SAP document, SAP status, or JE exists.
  ASSERT p_decision != 'REJECTED_NEVER_POSTED' OR (
    p_sap_doc_entry IS NULL
    AND (p_sap_status IS NULL OR TRIM(p_sap_status) = '')
    AND (p_je_reference IS NULL OR TRIM(p_je_reference) = '')
    AND p_import_log_id IS NOT NULL AND TRIM(p_import_log_id) != ''
    AND p_import_outcome = 'REJECTED'
    AND p_import_evidence IS NOT NULL AND TRIM(p_import_evidence) != ''
  ) AS 'rejected decisions require import rejection evidence and no DocEntry/SAP status/JE';

  INSERT INTO `pacific-plating-282708.sap_integration_v3.sap_fa_verification` (
    verification_id,
    incident_or_finding_id,
    order_id,
    order_item,
    period,
    sap_doc_entry,
    sap_status,
    je_reference,
    import_log_id,
    import_outcome,
    import_evidence,
    verifier,
    decision,
    evidence_timestamp,
    captured_at,
    source_uri,
    source_note
  ) VALUES (
    p_verification_id,
    p_incident_or_finding_id,
    p_order_id,
    p_order_item,
    p_period,
    p_sap_doc_entry,
    p_sap_status,
    p_je_reference,
    p_import_log_id,
    p_import_outcome,
    p_import_evidence,
    p_verifier,
    p_decision,
    p_evidence_timestamp,
    CURRENT_TIMESTAMP(),
    p_source_uri,
    p_source_note
  );
END;

-- The two former seed rows are intentionally not inserted. Their prose is useful as a
-- known-answer lead, but it lacks the complete order-item-period and SAP/JE/import provenance
-- required above. Backfill only after the evidence owner supplies every required field.
