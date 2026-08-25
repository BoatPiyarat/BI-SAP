-- Run only after Boat manually copied and independently verified the exact production generation.
DECLARE production_generation STRING DEFAULT 'REPLACE_WITH_PRODUCTION_GENERATION';

ASSERT production_generation!='REPLACE_WITH_PRODUCTION_GENERATION'
  AND REGEXP_CONTAINS(production_generation,r'^[1-9][0-9]*$')
  AS 'Replace the production generation placeholder with exact post-copy metadata';
ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.export_archive`
  WHERE export_run_id='V3DAILY-20260825-143823-0c1c161f'
    AND delivery_status='ARCHIVED_PENDING_OBJECT_METADATA')=641
  AS 'Archive ledger is no longer the reviewed 641-identity pending-delivery set';
ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.export_file_manifest`
  WHERE export_run_id='V3DAILY-20260825-143823-0c1c161f')=0
  AS 'Export file manifest already exists; refusing replay';
ASSERT (SELECT COUNT(*)
  FROM `pacific-plating-282708.sap_integration_v3.sap_delivery_manifest_v3`
  WHERE export_run_id='V3DAILY-20260825-143823-0c1c161f')=0
  AS 'SAP delivery manifest already exists; refusing replay';

CALL `pacific-plating-282708.sap_integration_v3.sp_mark_v3_exact_delivery`(
  'V3NIGHTLY-2026-08-25T14:32:37-0ce16d45',
  'V3DAILY-20260825-143823-0c1c161f',
  'gs://rcb-bronze-zone/sap-interface-archive/2026/08/25/V3DAILY-20260825-143823-0c1c161f/INSURANCE_RCB_06_V3_DAILY_NEWPAYMENT_20260825_V3DAILY-20260825-143823-0c1c161f_000000000000.csv',
  '1787668717202105',
  'gs://interface-file/RCB_MOTOR/INSURANCE_RCB_06_V3_DAILY_NEWPAYMENT_20260825_V3DAILY-20260825-143823-0c1c161f_000000000000.csv',
  production_generation,
  2640970,
  'MDIjTg==',
  56,
  4288,
  'INSURANCE_RCB_06_V3_DAILY_NEWPAYMENT_20260825_V3DAILY-20260825-143823-0c1c161f_000000000000.csv',
  'RCB_MOTOR_INSURANCE_RCB_06_V3_DAILY_NEWPAYMENT_20260825_V3DAILY-20260825-143823-0c1c161f_000000000000.csv',
  '0e02ea0267e063d75fdb9092b65783b76f2abd059b8098e3ad4bd38b1cec37cc'
);
