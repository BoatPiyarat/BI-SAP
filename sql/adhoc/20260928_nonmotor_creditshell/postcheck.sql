WITH payload AS (
SELECT 'RCL' AS wrapper, OrderID,OrderItem,InsuranceGroup,InsurerCode,Period,TotalPeriods,TransactionStatus,ExpectedReceived,ActualReceived,PaymentDate,PaymentChannel,InvoiceNo FROM `pacific-plating-282708.sap_view.RCL_Motor_process_4_creditshell`
UNION ALL
SELECT 'RCB',OrderID,OrderItem,InsuranceGroup,InsurerCode,Period,TotalPeriods,TransactionStatus,ExpectedReceived,ActualReceived,PaymentDate,PaymentChannel,InvoiceNo FROM `pacific-plating-282708.sap_view.RCB_Motor_process_4_creditshell`
)
SELECT CURRENT_TIMESTAMP() AS observed_at,wrapper,InsuranceGroup,InsurerCode,TransactionStatus,COUNT(*) AS row_count,COUNT(DISTINCT OrderItem) AS items,
COUNTIF(InsuranceGroup IN ('Health','TA') AND NOT STARTS_WITH(IFNULL(InsurerCode,''),'N')) AS insurer_failures,
COUNTIF(LOWER(TransactionStatus)='pending' AND ActualReceived IS DISTINCT FROM ExpectedReceived) AS pending_amount_wrong,
COUNTIF(LOWER(TransactionStatus)='paid' AND SAFE.PARSE_DATE('%d%m%Y',PaymentDate)<DATE_TRUNC(CURRENT_DATE('Asia/Bangkok'),MONTH)) AS prior_month_paid,
ARRAY_AGG(STRUCT(OrderID,OrderItem,Period,TotalPeriods,ExpectedReceived,ActualReceived,PaymentDate,PaymentChannel,InvoiceNo) LIMIT 3) AS samples
FROM payload GROUP BY wrapper,InsuranceGroup,InsurerCode,TransactionStatus ORDER BY wrapper,InsuranceGroup,InsurerCode,TransactionStatus;
