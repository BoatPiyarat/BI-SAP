-- Read-only minimization of the single Scenario 3 required-value hold. No PII values returned.
DECLARE v_run_id STRING DEFAULT 'V3NIGHTLY-2026-08-26T13:23:38-e830fff2';

WITH held AS (
  SELECT order_item
  FROM `pacific-plating-282708.sap_integration_v3.v3_rcl_later_newpayment_hold`
  WHERE pipeline_run_id=v_run_id AND hold_code='HOLD_SPINE_REQUIRED_VALUE_INVALID'
), payload AS (
  SELECT p.Period,p.TransactionStatus,p.CompanyDB,p.OrderID,p.OrderItem,p.InsurerCode,
    p.FirstName,p.InsuranceGroup,p.InsuranceProduct,p.ProductType,p.PolicyType,p.PolicyDate,
    p.PolicyNo,p.ExpectedDate,p.BillingAddress,p.InvoiceNo,p.PaymentDate,p.PaymentMethod,
    p.PaymentChannel,p.EndorsementNo,p.RefOrder
  FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_run_snapshot` p
  JOIN held h ON h.order_item=p.OrderItem
  WHERE p.pipeline_run_id=v_run_id
)
SELECT SAFE_CAST(Period AS INT64) AS period,TransactionStatus,
  REGEXP_EXTRACT_ALL(TO_JSON_STRING(p),r'"([^"]+)":(?:null|"NULL")')
    AS null_field_names,
  ARRAY(SELECT field_name FROM UNNEST([
    STRUCT('JSON_NULL_OR_LITERAL_NULL' AS field_name,
      REGEXP_CONTAINS(TO_JSON_STRING(p),r':null|:"NULL"') AS bad),
    ('CompanyDB',NULLIF(TRIM(CompanyDB),'') IS NULL),
    ('OrderID',NULLIF(TRIM(OrderID),'') IS NULL),
    ('OrderItem',NULLIF(TRIM(OrderItem),'') IS NULL),
    ('InsurerCode',NULLIF(TRIM(InsurerCode),'') IS NULL),
    ('FirstName',NULLIF(TRIM(FirstName),'') IS NULL),
    ('InsuranceGroup',NULLIF(TRIM(InsuranceGroup),'') IS NULL),
    ('InsuranceProduct',NULLIF(TRIM(InsuranceProduct),'') IS NULL),
    ('ProductType',NULLIF(TRIM(ProductType),'') IS NULL),
    ('PolicyType',NULLIF(TRIM(PolicyType),'') IS NULL),
    ('PolicyDate',NULLIF(TRIM(PolicyDate),'') IS NULL),
    ('PolicyNo',NULLIF(TRIM(PolicyNo),'') IS NULL),
    ('ExpectedDate',NULLIF(TRIM(ExpectedDate),'') IS NULL),
    ('BillingAddress',NULLIF(TRIM(BillingAddress),'') IS NULL),
    ('Paid.InvoiceNo',TransactionStatus='Paid' AND NULLIF(TRIM(InvoiceNo),'') IS NULL),
    ('Paid.PaymentDate',TransactionStatus='Paid' AND NULLIF(TRIM(PaymentDate),'') IS NULL),
    ('Paid.PaymentMethod',TransactionStatus='Paid' AND NULLIF(TRIM(PaymentMethod),'') IS NULL),
    ('Paid.PaymentChannel',TransactionStatus='Paid' AND NULLIF(TRIM(PaymentChannel),'') IS NULL)
  ]) WHERE bad) AS failing_contract_labels
FROM payload p
ORDER BY period;
