-- Class A. Operator-facing event view; diagnostic only and never an SAP file contract.
-- The 56-column delivery table is a complete period spine. This view exposes only the exact
-- payment-event identities from the most recently started nightly run so operators can inspect
-- the actual new payments without mistaking Pending/context rows for current events.
CREATE OR REPLACE VIEW
  `pacific-plating-282708.sap_integration_v3.vw_v3_current_newpayment_events` AS
WITH latest_run AS (
  SELECT run_id,MAX(ended_at) AS unit5_completed_at
  FROM `pacific-plating-282708.sap_integration_v3.pipeline_run_log`
  WHERE run_type='NIGHTLY' AND step='UNITS_2_5_ARCHIVE' AND status='SUCCESS'
  GROUP BY run_id
  QUALIFY ROW_NUMBER() OVER (ORDER BY unit5_completed_at DESC,run_id DESC)=1
)
SELECT
  i.pipeline_run_id,
  i.order_item,
  i.period,
  i.charge_id,
  i.invoice_no,
  SAFE.PARSE_DATE('%d%m%Y',d.PaymentDate) AS payment_date,
  SAFE.PARSE_DATE('%d%m%Y',d.BatchRunDate) AS batch_run_date,
  d.TransactionStatus,
  d.PaymentMethod,
  d.PaymentChannel,
  i.payload_hash,
  i.built_at
FROM `pacific-plating-282708.sap_integration_v3.v3_unit5_payload_identity` i
JOIN latest_run r ON r.run_id=i.pipeline_run_id
LEFT JOIN `pacific-plating-282708.sap_integration_v3.v3_unit5_newpayment_delivery_ready` d
  ON d.OrderItem=i.order_item AND SAFE_CAST(d.Period AS INT64)=i.period
 AND d.InvoiceNo=i.invoice_no
WHERE i.file_role='NEWPAYMENT';
