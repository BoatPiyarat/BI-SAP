-- Zero-byte executable contract test for the reviewed RCB Motor two-name policy.
-- No production table is read or written.

DECLARE production_file_name STRING DEFAULT
  'INSURANCE_RCB_06_V3_DAILY_NEWPAYMENT_20260803_V3DAILY-20260803-113257-55042e7c_000000000000.csv';
DECLARE sap_result_file_name STRING DEFAULT
  'RCB_MOTOR_INSURANCE_RCB_06_V3_DAILY_NEWPAYMENT_20260803_V3DAILY-20260803-113257-55042e7c_000000000000.csv';
DECLARE production_uri STRING DEFAULT CONCAT(
  'gs://interface-file/RCB_MOTOR/', production_file_name);

ASSERT REGEXP_CONTAINS(
  production_file_name,
  r'^INSURANCE_RCB_[A-Za-z0-9._-]*[.]csv$'
) AS 'real LogID 21183 production basename must satisfy the production contract';

ASSERT REGEXP_CONTAINS(
  sap_result_file_name,
  r'^RCB_MOTOR_INSURANCE_RCB_[A-Za-z0-9._-]*[.]csv$'
) AS 'real LogID 21183 email filename must satisfy the SAP-result contract';

ASSERT REGEXP_EXTRACT(production_uri, r'([^/]+)$') = production_file_name
  AS 'production URI basename must equal the production filename';
ASSERT sap_result_file_name = CONCAT('RCB_MOTOR_', production_file_name)
  AS 'SAP-result filename must equal the approved BU reporting prefix plus production filename';
ASSERT production_file_name != sap_result_file_name
  AS 'the two immutable filename identities must not collapse';

ASSERT NOT REGEXP_CONTAINS(
  sap_result_file_name,
  r'^INSURANCE_RCB_[A-Za-z0-9._-]*[.]csv$'
) AS 'BU-prefixed SAP-result name must not be admitted as a production basename';

ASSERT NOT REGEXP_CONTAINS(
  production_file_name,
  r'^RCB_MOTOR_INSURANCE_RCB_[A-Za-z0-9._-]*[.]csv$'
) AS 'production basename must not be admitted as the SAP-result name';

SELECT
  production_file_name,
  sap_result_file_name,
  production_uri,
  TRUE AS two_name_policy_passed;
