CREATE TEMP TABLE target AS
SELECT OrderItem, Period, InvoiceNo, ExpectedReceived, ActualReceived, InterestThisPeriod, InterestEIRThisPeriod
FROM (SELECT * FROM `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_installment`)
WHERE OrderItem IN ('L80570054-V1','L79109956-V1');
ASSERT (SELECT COUNT(*) FROM target WHERE OrderItem='L80570054-V1' AND InvoiceNo='2_chrg_68ve8ufva4h1iil7wrn' AND ExpectedReceived=0 AND ActualReceived=22.04)=1 AS 'L80570054 extra';
ASSERT (SELECT COUNT(*) FROM target WHERE OrderItem='L79109956-V1' AND InvoiceNo='2_chrg_68w87npgw0hbvid58ho' AND ExpectedReceived=0 AND ActualReceived=645.21)=1 AS 'L79109956 extra';
ASSERT NOT EXISTS(SELECT 1 FROM target GROUP BY OrderItem,Period,InvoiceNo HAVING COUNT(*)>1) AS 'No duplicate receipt';
SELECT * FROM target ORDER BY OrderItem,Period,InvoiceNo;
