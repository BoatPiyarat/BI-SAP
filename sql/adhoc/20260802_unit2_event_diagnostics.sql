-- Read-only diagnostics for Unit 2 event outcome correction. Dry-run first.
SELECT 'MATCHING_DOC_STATUS' diagnostic,
  CONCAT(e.outcome,';status=',IFNULL(matching_invoice_status,'<NULL>')) value,
  COUNT(*) records, COUNT(DISTINCT order_id) distinct_orders, SUM(charge_amount) amount
FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_event_shadow` e
LEFT JOIN (
  SELECT U_OrderItem,U_Period,U_InvoiceNo,TransactionStatus matching_invoice_status,
    ROW_NUMBER() OVER(PARTITION BY U_OrderItem,U_Period,U_InvoiceNo
      ORDER BY UpdateDate DESC,UpdateTime DESC,DocEntry DESC) rn
  FROM `pacific-plating-282708.sap_integration_v3.sap_mirror_doc`
) m ON m.U_OrderItem=e.order_item AND m.U_Period=e.period
  AND IFNULL(m.U_InvoiceNo,'')=IFNULL(e.invoice_no,'') AND m.rn=1
WHERE e.pipeline_run_id='V3NIGHTLY-2026-08-02T09:02:26-b36e1712'
  AND e.outcome_reason='matching LIVE DocEntry and InvoiceNo found'
  AND e.outcome IN ('HELD_VALIDATION','HELD_CLASSIFICATION_UNKNOWN')
GROUP BY 2
UNION ALL
SELECT 'INCOMPLETE_IDENTITY',
  CONCAT('order_item_null=',order_item IS NULL,';period_null=',period IS NULL,
    ';invoice_null=',invoice_no IS NULL),
  COUNT(*),COUNT(DISTINCT order_id),SUM(charge_amount)
FROM `pacific-plating-282708.sap_integration_v3.v3_unit2_event_shadow`
WHERE pipeline_run_id='V3NIGHTLY-2026-08-02T09:02:26-b36e1712'
  AND outcome_reason='event identity incomplete'
GROUP BY 2
ORDER BY diagnostic,value;
