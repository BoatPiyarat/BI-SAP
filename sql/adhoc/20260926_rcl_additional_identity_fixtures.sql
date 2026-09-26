WITH fixture_charges AS (
SELECT 'new_period' AS id, 'new_period' AS transaction_id, 2 AS installment_number, 'n2' AS third_party_id, 'SUCCESSFUL' AS status, 'RABBIT_LENDING' AS service_provider, TIMESTAMP '2026-09-25' AS create_time, CURRENT_TIMESTAMP() AS update_time
UNION ALL
SELECT 'gap_period' AS id, 'gap_period' AS transaction_id, 2 AS installment_number, 'g2' AS third_party_id, 'SUCCESSFUL' AS status, 'RABBIT_LENDING' AS service_provider, TIMESTAMP '2026-09-25' AS create_time, CURRENT_TIMESTAMP() AS update_time
UNION ALL
SELECT 'topup' AS id, 'topup' AS transaction_id, 1 AS installment_number, 'extra' AS third_party_id, 'SUCCESSFUL' AS status, 'RABBIT_LENDING' AS service_provider, TIMESTAMP '2026-09-25' AS create_time, CURRENT_TIMESTAMP() AS update_time
UNION ALL
SELECT 'exact_paid' AS id, 'exact_paid' AS transaction_id, 1 AS installment_number, 'exact' AS third_party_id, 'SUCCESSFUL' AS status, 'RABBIT_LENDING' AS service_provider, TIMESTAMP '2026-09-25' AS create_time, CURRENT_TIMESTAMP() AS update_time
UNION ALL
SELECT 'raw_paid' AS id, 'raw_paid' AS transaction_id, 1 AS installment_number, 'raw' AS third_party_id, 'SUCCESSFUL' AS status, 'RABBIT_LENDING' AS service_provider, TIMESTAMP '2026-09-25' AS create_time, CURRENT_TIMESTAMP() AS update_time
UNION ALL
SELECT 'cancelled' AS id, 'cancelled' AS transaction_id, 1 AS installment_number, 'cancelled' AS third_party_id, 'SUCCESSFUL' AS status, 'RABBIT_LENDING' AS service_provider, TIMESTAMP '2026-09-25' AS create_time, CURRENT_TIMESTAMP() AS update_time
UNION ALL
SELECT 'change_cancelled' AS id, 'change_cancelled' AS transaction_id, 1 AS installment_number, 'change' AS third_party_id, 'SUCCESSFUL' AS status, 'RABBIT_LENDING' AS service_provider, TIMESTAMP '2026-09-25' AS create_time, CURRENT_TIMESTAMP() AS update_time
UNION ALL
SELECT 'blank' AS id, 'blank' AS transaction_id, 1 AS installment_number, '' AS third_party_id, 'SUCCESSFUL' AS status, 'RABBIT_LENDING' AS service_provider, TIMESTAMP '2026-09-25' AS create_time, CURRENT_TIMESTAMP() AS update_time
UNION ALL
SELECT 'null_invoice' AS id, 'null_invoice' AS transaction_id, 1 AS installment_number, NULL AS third_party_id, 'SUCCESSFUL' AS status, 'RABBIT_LENDING' AS service_provider, TIMESTAMP '2026-09-25' AS create_time, CURRENT_TIMESTAMP() AS update_time
UNION ALL
SELECT 'literal_null' AS id, 'literal_null' AS transaction_id, 1 AS installment_number, 'NULL' AS third_party_id, 'SUCCESSFUL' AS status, 'RABBIT_LENDING' AS service_provider, TIMESTAMP '2026-09-25' AS create_time, CURRENT_TIMESTAMP() AS update_time
UNION ALL
SELECT 'normal_paid' AS id, 'normal_paid' AS transaction_id, 1 AS installment_number, 'normal' AS third_party_id, 'SUCCESSFUL' AS status, 'RABBIT_LENDING' AS service_provider, TIMESTAMP '2026-09-25' AS create_time, CURRENT_TIMESTAMP() AS update_time
UNION ALL
SELECT 'other_item' AS id, 'other_item' AS transaction_id, 1 AS installment_number, 'shared' AS third_party_id, 'SUCCESSFUL' AS status, 'RABBIT_LENDING' AS service_provider, TIMESTAMP '2026-09-25' AS create_time, CURRENT_TIMESTAMP() AS update_time
UNION ALL
SELECT 'other_period' AS id, 'other_period' AS transaction_id, 2 AS installment_number, 'p2' AS third_party_id, 'SUCCESSFUL' AS status, 'RABBIT_LENDING' AS service_provider, TIMESTAMP '2026-09-25' AS create_time, CURRENT_TIMESTAMP() AS update_time
UNION ALL
SELECT 'period2_prefix' AS id, 'period2_prefix' AS transaction_id, 2 AS installment_number, '2_p2raw' AS third_party_id, 'SUCCESSFUL' AS status, 'RABBIT_LENDING' AS service_provider, TIMESTAMP '2026-09-25' AS create_time, CURRENT_TIMESTAMP() AS update_time
UNION ALL
SELECT 'missing_raw' AS id, 'missing_raw' AS transaction_id, 1 AS installment_number, NULL AS third_party_id, 'SUCCESSFUL' AS status, 'RABBIT_LENDING' AS service_provider, TIMESTAMP '2026-09-25' AS create_time, CURRENT_TIMESTAMP() AS update_time
UNION ALL
SELECT 'collision' AS id, 'collision' AS transaction_id, 1 AS installment_number, 'collision' AS third_party_id, 'SUCCESSFUL' AS status, 'RABBIT_LENDING' AS service_provider, TIMESTAMP '2026-09-25' AS create_time, CURRENT_TIMESTAMP() AS update_time
UNION ALL
SELECT 'collision-other', 'collision', 1, 'collision', 'SUCCESSFUL', 'RABBIT_LENDING', TIMESTAMP '2026-09-25', CURRENT_TIMESTAMP()
UNION ALL
SELECT 'tie' AS id, 'tie' AS transaction_id, 1 AS installment_number, 'tie' AS third_party_id, 'SUCCESSFUL' AS status, 'RABBIT_LENDING' AS service_provider, TIMESTAMP '2026-09-25' AS create_time, CURRENT_TIMESTAMP() AS update_time
UNION ALL
SELECT 'tie-other', 'tie', 1, 'different', 'SUCCESSFUL', 'RABBIT_LENDING', TIMESTAMP '2026-09-25', CURRENT_TIMESTAMP()
UNION ALL
SELECT 'null_expected' AS id, 'null_expected' AS transaction_id, 1 AS installment_number, 'null_exp' AS third_party_id, 'SUCCESSFUL' AS status, 'RABBIT_LENDING' AS service_provider, TIMESTAMP '2026-09-25' AS create_time, CURRENT_TIMESTAMP() AS update_time
UNION ALL
SELECT 'pending_not_topup' AS id, 'pending_not_topup' AS transaction_id, 1 AS installment_number, 'pending' AS third_party_id, 'SUCCESSFUL' AS status, 'RABBIT_LENDING' AS service_provider, TIMESTAMP '2026-09-25' AS create_time, CURRENT_TIMESTAMP() AS update_time
), fixture_orders AS (
SELECT 'new_period' AS id, 'transactions/new_period' AS payment
UNION ALL
SELECT 'gap_period' AS id, 'transactions/gap_period' AS payment
UNION ALL
SELECT 'topup' AS id, 'transactions/topup' AS payment
UNION ALL
SELECT 'exact_paid' AS id, 'transactions/exact_paid' AS payment
UNION ALL
SELECT 'raw_paid' AS id, 'transactions/raw_paid' AS payment
UNION ALL
SELECT 'cancelled' AS id, 'transactions/cancelled' AS payment
UNION ALL
SELECT 'change_cancelled' AS id, 'transactions/change_cancelled' AS payment
UNION ALL
SELECT 'blank' AS id, 'transactions/blank' AS payment
UNION ALL
SELECT 'null_invoice' AS id, 'transactions/null_invoice' AS payment
UNION ALL
SELECT 'literal_null' AS id, 'transactions/literal_null' AS payment
UNION ALL
SELECT 'normal_paid' AS id, 'transactions/normal_paid' AS payment
UNION ALL
SELECT 'other_item' AS id, 'transactions/other_item' AS payment
UNION ALL
SELECT 'other_period' AS id, 'transactions/other_period' AS payment
UNION ALL
SELECT 'period2_prefix' AS id, 'transactions/period2_prefix' AS payment
UNION ALL
SELECT 'missing_raw' AS id, 'transactions/missing_raw' AS payment
UNION ALL
SELECT 'collision' AS id, 'transactions/collision' AS payment
UNION ALL
SELECT 'tie' AS id, 'transactions/tie' AS payment
UNION ALL
SELECT 'null_expected' AS id, 'transactions/null_expected' AS payment
UNION ALL
SELECT 'pending_not_topup' AS id, 'transactions/pending_not_topup' AS payment
), fixture_order_items AS (
SELECT 'new_period' AS order_id, 'new_period-V1' AS human_id
UNION ALL
SELECT 'gap_period' AS order_id, 'gap_period-V1' AS human_id
UNION ALL
SELECT 'topup' AS order_id, 'topup-V1' AS human_id
UNION ALL
SELECT 'exact_paid' AS order_id, 'exact_paid-V1' AS human_id
UNION ALL
SELECT 'raw_paid' AS order_id, 'raw_paid-V1' AS human_id
UNION ALL
SELECT 'cancelled' AS order_id, 'cancelled-V1' AS human_id
UNION ALL
SELECT 'change_cancelled' AS order_id, 'change_cancelled-V1' AS human_id
UNION ALL
SELECT 'blank' AS order_id, 'blank-V1' AS human_id
UNION ALL
SELECT 'null_invoice' AS order_id, 'null_invoice-V1' AS human_id
UNION ALL
SELECT 'literal_null' AS order_id, 'literal_null-V1' AS human_id
UNION ALL
SELECT 'normal_paid' AS order_id, 'normal_paid-V1' AS human_id
UNION ALL
SELECT 'other_item' AS order_id, 'other_item-V1' AS human_id
UNION ALL
SELECT 'other_period' AS order_id, 'other_period-V1' AS human_id
UNION ALL
SELECT 'period2_prefix' AS order_id, 'period2_prefix-V1' AS human_id
UNION ALL
SELECT 'missing_raw' AS order_id, 'missing_raw-V1' AS human_id
UNION ALL
SELECT 'collision' AS order_id, 'collision-V1' AS human_id
UNION ALL
SELECT 'tie' AS order_id, 'tie-V1' AS human_id
UNION ALL
SELECT 'null_expected' AS order_id, 'null_expected-V1' AS human_id
UNION ALL
SELECT 'pending_not_topup' AS order_id, 'pending_not_topup-V1' AS human_id
), fixture_dashboard AS (
SELECT CAST(NULL AS STRING) AS CompanyDB, CAST('new_period' AS STRING) AS OrderID, CAST('new_period-V1' AS STRING) AS OrderItem, CAST('n2' AS STRING) AS InvoiceNo, CAST(NULL AS STRING) AS OrderDate, CAST(NULL AS STRING) AS InsuredID, CAST(NULL AS STRING) AS Title, CAST(NULL AS STRING) AS FirstName, CAST(NULL AS STRING) AS LastName, CAST(NULL AS STRING) AS InsurerCode, CAST(NULL AS STRING) AS InsuranceGroup, CAST(NULL AS STRING) AS InsuranceType, CAST(NULL AS STRING) AS InsuranceProduct, CAST(NULL AS STRING) AS ProductType, CAST(NULL AS STRING) AS PolicyType, CAST(NULL AS STRING) AS Endorse, CAST(NULL AS STRING) AS PolicyDate, CAST(NULL AS STRING) AS PolicyNo, CAST(NULL AS STRING) AS EndorsementNo, CAST(NULL AS STRING) AS ChassisNo, CAST(NULL AS STRING) AS LicensePlate, CAST(NULL AS FLOAT64) AS GrossPremium, CAST(NULL AS FLOAT64) AS StampDuty, CAST(NULL AS FLOAT64) AS VAT, CAST(NULL AS FLOAT64) AS TotalPremium, CAST(NULL AS FLOAT64) AS WHT, CAST(NULL AS FLOAT64) AS TotalEIR, CAST(NULL AS FLOAT64) AS TotalSBT, CAST(NULL AS FLOAT64) AS ProcessingFee, CAST(NULL AS FLOAT64) AS ProcessingFeeVat, CAST(NULL AS FLOAT64) AS ShippingFee, CAST(NULL AS FLOAT64) AS ShippingFeeVat, CAST(NULL AS FLOAT64) AS TotalAmount, CAST(NULL AS FLOAT64) AS Discount, CAST('paid' AS STRING) AS TransactionStatus, CAST(NULL AS STRING) AS SubmissionStatus, CAST(NULL AS STRING) AS ApprovalStatus, CAST(NULL AS STRING) AS PaymentStatus, CAST(100 AS FLOAT64) AS ExpectedReceived, CAST(100 AS FLOAT64) AS ActualReceived, CAST(NULL AS FLOAT64) AS InterestThisPeriod, CAST(NULL AS FLOAT64) AS PrincipleThisPeriod, CAST(NULL AS FLOAT64) AS InterestEIRThisPeriod, CAST(NULL AS FLOAT64) AS PrincipleEIRThisPeriod, CAST('26092026' AS STRING) AS PaymentDate, CAST(2 AS INT64) AS Period, CAST(3 AS INT64) AS TotalPeriods, CAST(NULL AS FLOAT64) AS PendingPayment, CAST(NULL AS STRING) AS PaymentMethod, CAST(NULL AS STRING) AS PaymentChannel, CAST(NULL AS STRING) AS ExpectedDate, CAST(NULL AS STRING) AS RefOrder, CAST(NULL AS FLOAT64) AS RefundAmountBeforeFee, CAST(NULL AS FLOAT64) AS RefundAmountAfterFee, CAST(NULL AS STRING) AS BillingAddress, CAST(NULL AS STRING) AS BatchRunDate
UNION ALL
SELECT CAST(NULL AS STRING) AS CompanyDB, CAST('gap_period' AS STRING) AS OrderID, CAST('gap_period-V1' AS STRING) AS OrderItem, CAST('g2' AS STRING) AS InvoiceNo, CAST(NULL AS STRING) AS OrderDate, CAST(NULL AS STRING) AS InsuredID, CAST(NULL AS STRING) AS Title, CAST(NULL AS STRING) AS FirstName, CAST(NULL AS STRING) AS LastName, CAST(NULL AS STRING) AS InsurerCode, CAST(NULL AS STRING) AS InsuranceGroup, CAST(NULL AS STRING) AS InsuranceType, CAST(NULL AS STRING) AS InsuranceProduct, CAST(NULL AS STRING) AS ProductType, CAST(NULL AS STRING) AS PolicyType, CAST(NULL AS STRING) AS Endorse, CAST(NULL AS STRING) AS PolicyDate, CAST(NULL AS STRING) AS PolicyNo, CAST(NULL AS STRING) AS EndorsementNo, CAST(NULL AS STRING) AS ChassisNo, CAST(NULL AS STRING) AS LicensePlate, CAST(NULL AS FLOAT64) AS GrossPremium, CAST(NULL AS FLOAT64) AS StampDuty, CAST(NULL AS FLOAT64) AS VAT, CAST(NULL AS FLOAT64) AS TotalPremium, CAST(NULL AS FLOAT64) AS WHT, CAST(NULL AS FLOAT64) AS TotalEIR, CAST(NULL AS FLOAT64) AS TotalSBT, CAST(NULL AS FLOAT64) AS ProcessingFee, CAST(NULL AS FLOAT64) AS ProcessingFeeVat, CAST(NULL AS FLOAT64) AS ShippingFee, CAST(NULL AS FLOAT64) AS ShippingFeeVat, CAST(NULL AS FLOAT64) AS TotalAmount, CAST(NULL AS FLOAT64) AS Discount, CAST('paid' AS STRING) AS TransactionStatus, CAST(NULL AS STRING) AS SubmissionStatus, CAST(NULL AS STRING) AS ApprovalStatus, CAST(NULL AS STRING) AS PaymentStatus, CAST(100 AS FLOAT64) AS ExpectedReceived, CAST(100 AS FLOAT64) AS ActualReceived, CAST(NULL AS FLOAT64) AS InterestThisPeriod, CAST(NULL AS FLOAT64) AS PrincipleThisPeriod, CAST(NULL AS FLOAT64) AS InterestEIRThisPeriod, CAST(NULL AS FLOAT64) AS PrincipleEIRThisPeriod, CAST('26092026' AS STRING) AS PaymentDate, CAST(2 AS INT64) AS Period, CAST(3 AS INT64) AS TotalPeriods, CAST(NULL AS FLOAT64) AS PendingPayment, CAST(NULL AS STRING) AS PaymentMethod, CAST(NULL AS STRING) AS PaymentChannel, CAST(NULL AS STRING) AS ExpectedDate, CAST(NULL AS STRING) AS RefOrder, CAST(NULL AS FLOAT64) AS RefundAmountBeforeFee, CAST(NULL AS FLOAT64) AS RefundAmountAfterFee, CAST(NULL AS STRING) AS BillingAddress, CAST(NULL AS STRING) AS BatchRunDate
UNION ALL
SELECT CAST(NULL AS STRING) AS CompanyDB, CAST('topup' AS STRING) AS OrderID, CAST('topup-V1' AS STRING) AS OrderItem, CAST('2_extra' AS STRING) AS InvoiceNo, CAST(NULL AS STRING) AS OrderDate, CAST(NULL AS STRING) AS InsuredID, CAST(NULL AS STRING) AS Title, CAST(NULL AS STRING) AS FirstName, CAST(NULL AS STRING) AS LastName, CAST(NULL AS STRING) AS InsurerCode, CAST(NULL AS STRING) AS InsuranceGroup, CAST(NULL AS STRING) AS InsuranceType, CAST(NULL AS STRING) AS InsuranceProduct, CAST(NULL AS STRING) AS ProductType, CAST(NULL AS STRING) AS PolicyType, CAST(NULL AS STRING) AS Endorse, CAST(NULL AS STRING) AS PolicyDate, CAST(NULL AS STRING) AS PolicyNo, CAST(NULL AS STRING) AS EndorsementNo, CAST(NULL AS STRING) AS ChassisNo, CAST(NULL AS STRING) AS LicensePlate, CAST(NULL AS FLOAT64) AS GrossPremium, CAST(NULL AS FLOAT64) AS StampDuty, CAST(NULL AS FLOAT64) AS VAT, CAST(NULL AS FLOAT64) AS TotalPremium, CAST(NULL AS FLOAT64) AS WHT, CAST(NULL AS FLOAT64) AS TotalEIR, CAST(NULL AS FLOAT64) AS TotalSBT, CAST(NULL AS FLOAT64) AS ProcessingFee, CAST(NULL AS FLOAT64) AS ProcessingFeeVat, CAST(NULL AS FLOAT64) AS ShippingFee, CAST(NULL AS FLOAT64) AS ShippingFeeVat, CAST(NULL AS FLOAT64) AS TotalAmount, CAST(NULL AS FLOAT64) AS Discount, CAST('paid' AS STRING) AS TransactionStatus, CAST(NULL AS STRING) AS SubmissionStatus, CAST(NULL AS STRING) AS ApprovalStatus, CAST(NULL AS STRING) AS PaymentStatus, CAST(0 AS FLOAT64) AS ExpectedReceived, CAST(22.04 AS FLOAT64) AS ActualReceived, CAST(NULL AS FLOAT64) AS InterestThisPeriod, CAST(NULL AS FLOAT64) AS PrincipleThisPeriod, CAST(NULL AS FLOAT64) AS InterestEIRThisPeriod, CAST(NULL AS FLOAT64) AS PrincipleEIRThisPeriod, CAST('26092026' AS STRING) AS PaymentDate, CAST(1 AS INT64) AS Period, CAST(3 AS INT64) AS TotalPeriods, CAST(NULL AS FLOAT64) AS PendingPayment, CAST(NULL AS STRING) AS PaymentMethod, CAST(NULL AS STRING) AS PaymentChannel, CAST(NULL AS STRING) AS ExpectedDate, CAST(NULL AS STRING) AS RefOrder, CAST(NULL AS FLOAT64) AS RefundAmountBeforeFee, CAST(NULL AS FLOAT64) AS RefundAmountAfterFee, CAST(NULL AS STRING) AS BillingAddress, CAST(NULL AS STRING) AS BatchRunDate
UNION ALL
SELECT CAST(NULL AS STRING) AS CompanyDB, CAST('exact_paid' AS STRING) AS OrderID, CAST('exact_paid-V1' AS STRING) AS OrderItem, CAST('2_exact' AS STRING) AS InvoiceNo, CAST(NULL AS STRING) AS OrderDate, CAST(NULL AS STRING) AS InsuredID, CAST(NULL AS STRING) AS Title, CAST(NULL AS STRING) AS FirstName, CAST(NULL AS STRING) AS LastName, CAST(NULL AS STRING) AS InsurerCode, CAST(NULL AS STRING) AS InsuranceGroup, CAST(NULL AS STRING) AS InsuranceType, CAST(NULL AS STRING) AS InsuranceProduct, CAST(NULL AS STRING) AS ProductType, CAST(NULL AS STRING) AS PolicyType, CAST(NULL AS STRING) AS Endorse, CAST(NULL AS STRING) AS PolicyDate, CAST(NULL AS STRING) AS PolicyNo, CAST(NULL AS STRING) AS EndorsementNo, CAST(NULL AS STRING) AS ChassisNo, CAST(NULL AS STRING) AS LicensePlate, CAST(NULL AS FLOAT64) AS GrossPremium, CAST(NULL AS FLOAT64) AS StampDuty, CAST(NULL AS FLOAT64) AS VAT, CAST(NULL AS FLOAT64) AS TotalPremium, CAST(NULL AS FLOAT64) AS WHT, CAST(NULL AS FLOAT64) AS TotalEIR, CAST(NULL AS FLOAT64) AS TotalSBT, CAST(NULL AS FLOAT64) AS ProcessingFee, CAST(NULL AS FLOAT64) AS ProcessingFeeVat, CAST(NULL AS FLOAT64) AS ShippingFee, CAST(NULL AS FLOAT64) AS ShippingFeeVat, CAST(NULL AS FLOAT64) AS TotalAmount, CAST(NULL AS FLOAT64) AS Discount, CAST('paid' AS STRING) AS TransactionStatus, CAST(NULL AS STRING) AS SubmissionStatus, CAST(NULL AS STRING) AS ApprovalStatus, CAST(NULL AS STRING) AS PaymentStatus, CAST(0 AS FLOAT64) AS ExpectedReceived, CAST(10 AS FLOAT64) AS ActualReceived, CAST(NULL AS FLOAT64) AS InterestThisPeriod, CAST(NULL AS FLOAT64) AS PrincipleThisPeriod, CAST(NULL AS FLOAT64) AS InterestEIRThisPeriod, CAST(NULL AS FLOAT64) AS PrincipleEIRThisPeriod, CAST('26092026' AS STRING) AS PaymentDate, CAST(1 AS INT64) AS Period, CAST(3 AS INT64) AS TotalPeriods, CAST(NULL AS FLOAT64) AS PendingPayment, CAST(NULL AS STRING) AS PaymentMethod, CAST(NULL AS STRING) AS PaymentChannel, CAST(NULL AS STRING) AS ExpectedDate, CAST(NULL AS STRING) AS RefOrder, CAST(NULL AS FLOAT64) AS RefundAmountBeforeFee, CAST(NULL AS FLOAT64) AS RefundAmountAfterFee, CAST(NULL AS STRING) AS BillingAddress, CAST(NULL AS STRING) AS BatchRunDate
UNION ALL
SELECT CAST(NULL AS STRING) AS CompanyDB, CAST('raw_paid' AS STRING) AS OrderID, CAST('raw_paid-V1' AS STRING) AS OrderItem, CAST('2_raw' AS STRING) AS InvoiceNo, CAST(NULL AS STRING) AS OrderDate, CAST(NULL AS STRING) AS InsuredID, CAST(NULL AS STRING) AS Title, CAST(NULL AS STRING) AS FirstName, CAST(NULL AS STRING) AS LastName, CAST(NULL AS STRING) AS InsurerCode, CAST(NULL AS STRING) AS InsuranceGroup, CAST(NULL AS STRING) AS InsuranceType, CAST(NULL AS STRING) AS InsuranceProduct, CAST(NULL AS STRING) AS ProductType, CAST(NULL AS STRING) AS PolicyType, CAST(NULL AS STRING) AS Endorse, CAST(NULL AS STRING) AS PolicyDate, CAST(NULL AS STRING) AS PolicyNo, CAST(NULL AS STRING) AS EndorsementNo, CAST(NULL AS STRING) AS ChassisNo, CAST(NULL AS STRING) AS LicensePlate, CAST(NULL AS FLOAT64) AS GrossPremium, CAST(NULL AS FLOAT64) AS StampDuty, CAST(NULL AS FLOAT64) AS VAT, CAST(NULL AS FLOAT64) AS TotalPremium, CAST(NULL AS FLOAT64) AS WHT, CAST(NULL AS FLOAT64) AS TotalEIR, CAST(NULL AS FLOAT64) AS TotalSBT, CAST(NULL AS FLOAT64) AS ProcessingFee, CAST(NULL AS FLOAT64) AS ProcessingFeeVat, CAST(NULL AS FLOAT64) AS ShippingFee, CAST(NULL AS FLOAT64) AS ShippingFeeVat, CAST(NULL AS FLOAT64) AS TotalAmount, CAST(NULL AS FLOAT64) AS Discount, CAST('paid' AS STRING) AS TransactionStatus, CAST(NULL AS STRING) AS SubmissionStatus, CAST(NULL AS STRING) AS ApprovalStatus, CAST(NULL AS STRING) AS PaymentStatus, CAST(0 AS FLOAT64) AS ExpectedReceived, CAST(10 AS FLOAT64) AS ActualReceived, CAST(NULL AS FLOAT64) AS InterestThisPeriod, CAST(NULL AS FLOAT64) AS PrincipleThisPeriod, CAST(NULL AS FLOAT64) AS InterestEIRThisPeriod, CAST(NULL AS FLOAT64) AS PrincipleEIRThisPeriod, CAST('26092026' AS STRING) AS PaymentDate, CAST(1 AS INT64) AS Period, CAST(3 AS INT64) AS TotalPeriods, CAST(NULL AS FLOAT64) AS PendingPayment, CAST(NULL AS STRING) AS PaymentMethod, CAST(NULL AS STRING) AS PaymentChannel, CAST(NULL AS STRING) AS ExpectedDate, CAST(NULL AS STRING) AS RefOrder, CAST(NULL AS FLOAT64) AS RefundAmountBeforeFee, CAST(NULL AS FLOAT64) AS RefundAmountAfterFee, CAST(NULL AS STRING) AS BillingAddress, CAST(NULL AS STRING) AS BatchRunDate
UNION ALL
SELECT CAST(NULL AS STRING) AS CompanyDB, CAST('cancelled' AS STRING) AS OrderID, CAST('cancelled-V1' AS STRING) AS OrderItem, CAST('2_cancelled' AS STRING) AS InvoiceNo, CAST(NULL AS STRING) AS OrderDate, CAST(NULL AS STRING) AS InsuredID, CAST(NULL AS STRING) AS Title, CAST(NULL AS STRING) AS FirstName, CAST(NULL AS STRING) AS LastName, CAST(NULL AS STRING) AS InsurerCode, CAST(NULL AS STRING) AS InsuranceGroup, CAST(NULL AS STRING) AS InsuranceType, CAST(NULL AS STRING) AS InsuranceProduct, CAST(NULL AS STRING) AS ProductType, CAST(NULL AS STRING) AS PolicyType, CAST(NULL AS STRING) AS Endorse, CAST(NULL AS STRING) AS PolicyDate, CAST(NULL AS STRING) AS PolicyNo, CAST(NULL AS STRING) AS EndorsementNo, CAST(NULL AS STRING) AS ChassisNo, CAST(NULL AS STRING) AS LicensePlate, CAST(NULL AS FLOAT64) AS GrossPremium, CAST(NULL AS FLOAT64) AS StampDuty, CAST(NULL AS FLOAT64) AS VAT, CAST(NULL AS FLOAT64) AS TotalPremium, CAST(NULL AS FLOAT64) AS WHT, CAST(NULL AS FLOAT64) AS TotalEIR, CAST(NULL AS FLOAT64) AS TotalSBT, CAST(NULL AS FLOAT64) AS ProcessingFee, CAST(NULL AS FLOAT64) AS ProcessingFeeVat, CAST(NULL AS FLOAT64) AS ShippingFee, CAST(NULL AS FLOAT64) AS ShippingFeeVat, CAST(NULL AS FLOAT64) AS TotalAmount, CAST(NULL AS FLOAT64) AS Discount, CAST('paid' AS STRING) AS TransactionStatus, CAST(NULL AS STRING) AS SubmissionStatus, CAST(NULL AS STRING) AS ApprovalStatus, CAST(NULL AS STRING) AS PaymentStatus, CAST(0 AS FLOAT64) AS ExpectedReceived, CAST(10 AS FLOAT64) AS ActualReceived, CAST(NULL AS FLOAT64) AS InterestThisPeriod, CAST(NULL AS FLOAT64) AS PrincipleThisPeriod, CAST(NULL AS FLOAT64) AS InterestEIRThisPeriod, CAST(NULL AS FLOAT64) AS PrincipleEIRThisPeriod, CAST('26092026' AS STRING) AS PaymentDate, CAST(1 AS INT64) AS Period, CAST(3 AS INT64) AS TotalPeriods, CAST(NULL AS FLOAT64) AS PendingPayment, CAST(NULL AS STRING) AS PaymentMethod, CAST(NULL AS STRING) AS PaymentChannel, CAST(NULL AS STRING) AS ExpectedDate, CAST(NULL AS STRING) AS RefOrder, CAST(NULL AS FLOAT64) AS RefundAmountBeforeFee, CAST(NULL AS FLOAT64) AS RefundAmountAfterFee, CAST(NULL AS STRING) AS BillingAddress, CAST(NULL AS STRING) AS BatchRunDate
UNION ALL
SELECT CAST(NULL AS STRING) AS CompanyDB, CAST('change_cancelled' AS STRING) AS OrderID, CAST('change_cancelled-V1' AS STRING) AS OrderItem, CAST('2_change' AS STRING) AS InvoiceNo, CAST(NULL AS STRING) AS OrderDate, CAST(NULL AS STRING) AS InsuredID, CAST(NULL AS STRING) AS Title, CAST(NULL AS STRING) AS FirstName, CAST(NULL AS STRING) AS LastName, CAST(NULL AS STRING) AS InsurerCode, CAST(NULL AS STRING) AS InsuranceGroup, CAST(NULL AS STRING) AS InsuranceType, CAST(NULL AS STRING) AS InsuranceProduct, CAST(NULL AS STRING) AS ProductType, CAST(NULL AS STRING) AS PolicyType, CAST(NULL AS STRING) AS Endorse, CAST(NULL AS STRING) AS PolicyDate, CAST(NULL AS STRING) AS PolicyNo, CAST(NULL AS STRING) AS EndorsementNo, CAST(NULL AS STRING) AS ChassisNo, CAST(NULL AS STRING) AS LicensePlate, CAST(NULL AS FLOAT64) AS GrossPremium, CAST(NULL AS FLOAT64) AS StampDuty, CAST(NULL AS FLOAT64) AS VAT, CAST(NULL AS FLOAT64) AS TotalPremium, CAST(NULL AS FLOAT64) AS WHT, CAST(NULL AS FLOAT64) AS TotalEIR, CAST(NULL AS FLOAT64) AS TotalSBT, CAST(NULL AS FLOAT64) AS ProcessingFee, CAST(NULL AS FLOAT64) AS ProcessingFeeVat, CAST(NULL AS FLOAT64) AS ShippingFee, CAST(NULL AS FLOAT64) AS ShippingFeeVat, CAST(NULL AS FLOAT64) AS TotalAmount, CAST(NULL AS FLOAT64) AS Discount, CAST('paid' AS STRING) AS TransactionStatus, CAST(NULL AS STRING) AS SubmissionStatus, CAST(NULL AS STRING) AS ApprovalStatus, CAST(NULL AS STRING) AS PaymentStatus, CAST(0 AS FLOAT64) AS ExpectedReceived, CAST(10 AS FLOAT64) AS ActualReceived, CAST(NULL AS FLOAT64) AS InterestThisPeriod, CAST(NULL AS FLOAT64) AS PrincipleThisPeriod, CAST(NULL AS FLOAT64) AS InterestEIRThisPeriod, CAST(NULL AS FLOAT64) AS PrincipleEIRThisPeriod, CAST('26092026' AS STRING) AS PaymentDate, CAST(1 AS INT64) AS Period, CAST(3 AS INT64) AS TotalPeriods, CAST(NULL AS FLOAT64) AS PendingPayment, CAST(NULL AS STRING) AS PaymentMethod, CAST(NULL AS STRING) AS PaymentChannel, CAST(NULL AS STRING) AS ExpectedDate, CAST(NULL AS STRING) AS RefOrder, CAST(NULL AS FLOAT64) AS RefundAmountBeforeFee, CAST(NULL AS FLOAT64) AS RefundAmountAfterFee, CAST(NULL AS STRING) AS BillingAddress, CAST(NULL AS STRING) AS BatchRunDate
UNION ALL
SELECT CAST(NULL AS STRING) AS CompanyDB, CAST('blank' AS STRING) AS OrderID, CAST('blank-V1' AS STRING) AS OrderItem, CAST('' AS STRING) AS InvoiceNo, CAST(NULL AS STRING) AS OrderDate, CAST(NULL AS STRING) AS InsuredID, CAST(NULL AS STRING) AS Title, CAST(NULL AS STRING) AS FirstName, CAST(NULL AS STRING) AS LastName, CAST(NULL AS STRING) AS InsurerCode, CAST(NULL AS STRING) AS InsuranceGroup, CAST(NULL AS STRING) AS InsuranceType, CAST(NULL AS STRING) AS InsuranceProduct, CAST(NULL AS STRING) AS ProductType, CAST(NULL AS STRING) AS PolicyType, CAST(NULL AS STRING) AS Endorse, CAST(NULL AS STRING) AS PolicyDate, CAST(NULL AS STRING) AS PolicyNo, CAST(NULL AS STRING) AS EndorsementNo, CAST(NULL AS STRING) AS ChassisNo, CAST(NULL AS STRING) AS LicensePlate, CAST(NULL AS FLOAT64) AS GrossPremium, CAST(NULL AS FLOAT64) AS StampDuty, CAST(NULL AS FLOAT64) AS VAT, CAST(NULL AS FLOAT64) AS TotalPremium, CAST(NULL AS FLOAT64) AS WHT, CAST(NULL AS FLOAT64) AS TotalEIR, CAST(NULL AS FLOAT64) AS TotalSBT, CAST(NULL AS FLOAT64) AS ProcessingFee, CAST(NULL AS FLOAT64) AS ProcessingFeeVat, CAST(NULL AS FLOAT64) AS ShippingFee, CAST(NULL AS FLOAT64) AS ShippingFeeVat, CAST(NULL AS FLOAT64) AS TotalAmount, CAST(NULL AS FLOAT64) AS Discount, CAST('paid' AS STRING) AS TransactionStatus, CAST(NULL AS STRING) AS SubmissionStatus, CAST(NULL AS STRING) AS ApprovalStatus, CAST(NULL AS STRING) AS PaymentStatus, CAST(0 AS FLOAT64) AS ExpectedReceived, CAST(10 AS FLOAT64) AS ActualReceived, CAST(NULL AS FLOAT64) AS InterestThisPeriod, CAST(NULL AS FLOAT64) AS PrincipleThisPeriod, CAST(NULL AS FLOAT64) AS InterestEIRThisPeriod, CAST(NULL AS FLOAT64) AS PrincipleEIRThisPeriod, CAST('26092026' AS STRING) AS PaymentDate, CAST(1 AS INT64) AS Period, CAST(3 AS INT64) AS TotalPeriods, CAST(NULL AS FLOAT64) AS PendingPayment, CAST(NULL AS STRING) AS PaymentMethod, CAST(NULL AS STRING) AS PaymentChannel, CAST(NULL AS STRING) AS ExpectedDate, CAST(NULL AS STRING) AS RefOrder, CAST(NULL AS FLOAT64) AS RefundAmountBeforeFee, CAST(NULL AS FLOAT64) AS RefundAmountAfterFee, CAST(NULL AS STRING) AS BillingAddress, CAST(NULL AS STRING) AS BatchRunDate
UNION ALL
SELECT CAST(NULL AS STRING) AS CompanyDB, CAST('null_invoice' AS STRING) AS OrderID, CAST('null_invoice-V1' AS STRING) AS OrderItem, CAST(NULL AS STRING) AS InvoiceNo, CAST(NULL AS STRING) AS OrderDate, CAST(NULL AS STRING) AS InsuredID, CAST(NULL AS STRING) AS Title, CAST(NULL AS STRING) AS FirstName, CAST(NULL AS STRING) AS LastName, CAST(NULL AS STRING) AS InsurerCode, CAST(NULL AS STRING) AS InsuranceGroup, CAST(NULL AS STRING) AS InsuranceType, CAST(NULL AS STRING) AS InsuranceProduct, CAST(NULL AS STRING) AS ProductType, CAST(NULL AS STRING) AS PolicyType, CAST(NULL AS STRING) AS Endorse, CAST(NULL AS STRING) AS PolicyDate, CAST(NULL AS STRING) AS PolicyNo, CAST(NULL AS STRING) AS EndorsementNo, CAST(NULL AS STRING) AS ChassisNo, CAST(NULL AS STRING) AS LicensePlate, CAST(NULL AS FLOAT64) AS GrossPremium, CAST(NULL AS FLOAT64) AS StampDuty, CAST(NULL AS FLOAT64) AS VAT, CAST(NULL AS FLOAT64) AS TotalPremium, CAST(NULL AS FLOAT64) AS WHT, CAST(NULL AS FLOAT64) AS TotalEIR, CAST(NULL AS FLOAT64) AS TotalSBT, CAST(NULL AS FLOAT64) AS ProcessingFee, CAST(NULL AS FLOAT64) AS ProcessingFeeVat, CAST(NULL AS FLOAT64) AS ShippingFee, CAST(NULL AS FLOAT64) AS ShippingFeeVat, CAST(NULL AS FLOAT64) AS TotalAmount, CAST(NULL AS FLOAT64) AS Discount, CAST('paid' AS STRING) AS TransactionStatus, CAST(NULL AS STRING) AS SubmissionStatus, CAST(NULL AS STRING) AS ApprovalStatus, CAST(NULL AS STRING) AS PaymentStatus, CAST(0 AS FLOAT64) AS ExpectedReceived, CAST(10 AS FLOAT64) AS ActualReceived, CAST(NULL AS FLOAT64) AS InterestThisPeriod, CAST(NULL AS FLOAT64) AS PrincipleThisPeriod, CAST(NULL AS FLOAT64) AS InterestEIRThisPeriod, CAST(NULL AS FLOAT64) AS PrincipleEIRThisPeriod, CAST('26092026' AS STRING) AS PaymentDate, CAST(1 AS INT64) AS Period, CAST(3 AS INT64) AS TotalPeriods, CAST(NULL AS FLOAT64) AS PendingPayment, CAST(NULL AS STRING) AS PaymentMethod, CAST(NULL AS STRING) AS PaymentChannel, CAST(NULL AS STRING) AS ExpectedDate, CAST(NULL AS STRING) AS RefOrder, CAST(NULL AS FLOAT64) AS RefundAmountBeforeFee, CAST(NULL AS FLOAT64) AS RefundAmountAfterFee, CAST(NULL AS STRING) AS BillingAddress, CAST(NULL AS STRING) AS BatchRunDate
UNION ALL
SELECT CAST(NULL AS STRING) AS CompanyDB, CAST('literal_null' AS STRING) AS OrderID, CAST('literal_null-V1' AS STRING) AS OrderItem, CAST('NULL' AS STRING) AS InvoiceNo, CAST(NULL AS STRING) AS OrderDate, CAST(NULL AS STRING) AS InsuredID, CAST(NULL AS STRING) AS Title, CAST(NULL AS STRING) AS FirstName, CAST(NULL AS STRING) AS LastName, CAST(NULL AS STRING) AS InsurerCode, CAST(NULL AS STRING) AS InsuranceGroup, CAST(NULL AS STRING) AS InsuranceType, CAST(NULL AS STRING) AS InsuranceProduct, CAST(NULL AS STRING) AS ProductType, CAST(NULL AS STRING) AS PolicyType, CAST(NULL AS STRING) AS Endorse, CAST(NULL AS STRING) AS PolicyDate, CAST(NULL AS STRING) AS PolicyNo, CAST(NULL AS STRING) AS EndorsementNo, CAST(NULL AS STRING) AS ChassisNo, CAST(NULL AS STRING) AS LicensePlate, CAST(NULL AS FLOAT64) AS GrossPremium, CAST(NULL AS FLOAT64) AS StampDuty, CAST(NULL AS FLOAT64) AS VAT, CAST(NULL AS FLOAT64) AS TotalPremium, CAST(NULL AS FLOAT64) AS WHT, CAST(NULL AS FLOAT64) AS TotalEIR, CAST(NULL AS FLOAT64) AS TotalSBT, CAST(NULL AS FLOAT64) AS ProcessingFee, CAST(NULL AS FLOAT64) AS ProcessingFeeVat, CAST(NULL AS FLOAT64) AS ShippingFee, CAST(NULL AS FLOAT64) AS ShippingFeeVat, CAST(NULL AS FLOAT64) AS TotalAmount, CAST(NULL AS FLOAT64) AS Discount, CAST('paid' AS STRING) AS TransactionStatus, CAST(NULL AS STRING) AS SubmissionStatus, CAST(NULL AS STRING) AS ApprovalStatus, CAST(NULL AS STRING) AS PaymentStatus, CAST(0 AS FLOAT64) AS ExpectedReceived, CAST(10 AS FLOAT64) AS ActualReceived, CAST(NULL AS FLOAT64) AS InterestThisPeriod, CAST(NULL AS FLOAT64) AS PrincipleThisPeriod, CAST(NULL AS FLOAT64) AS InterestEIRThisPeriod, CAST(NULL AS FLOAT64) AS PrincipleEIRThisPeriod, CAST('26092026' AS STRING) AS PaymentDate, CAST(1 AS INT64) AS Period, CAST(3 AS INT64) AS TotalPeriods, CAST(NULL AS FLOAT64) AS PendingPayment, CAST(NULL AS STRING) AS PaymentMethod, CAST(NULL AS STRING) AS PaymentChannel, CAST(NULL AS STRING) AS ExpectedDate, CAST(NULL AS STRING) AS RefOrder, CAST(NULL AS FLOAT64) AS RefundAmountBeforeFee, CAST(NULL AS FLOAT64) AS RefundAmountAfterFee, CAST(NULL AS STRING) AS BillingAddress, CAST(NULL AS STRING) AS BatchRunDate
UNION ALL
SELECT CAST(NULL AS STRING) AS CompanyDB, CAST('normal_paid' AS STRING) AS OrderID, CAST('normal_paid-V1' AS STRING) AS OrderItem, CAST('normal' AS STRING) AS InvoiceNo, CAST(NULL AS STRING) AS OrderDate, CAST(NULL AS STRING) AS InsuredID, CAST(NULL AS STRING) AS Title, CAST(NULL AS STRING) AS FirstName, CAST(NULL AS STRING) AS LastName, CAST(NULL AS STRING) AS InsurerCode, CAST(NULL AS STRING) AS InsuranceGroup, CAST(NULL AS STRING) AS InsuranceType, CAST(NULL AS STRING) AS InsuranceProduct, CAST(NULL AS STRING) AS ProductType, CAST(NULL AS STRING) AS PolicyType, CAST(NULL AS STRING) AS Endorse, CAST(NULL AS STRING) AS PolicyDate, CAST(NULL AS STRING) AS PolicyNo, CAST(NULL AS STRING) AS EndorsementNo, CAST(NULL AS STRING) AS ChassisNo, CAST(NULL AS STRING) AS LicensePlate, CAST(NULL AS FLOAT64) AS GrossPremium, CAST(NULL AS FLOAT64) AS StampDuty, CAST(NULL AS FLOAT64) AS VAT, CAST(NULL AS FLOAT64) AS TotalPremium, CAST(NULL AS FLOAT64) AS WHT, CAST(NULL AS FLOAT64) AS TotalEIR, CAST(NULL AS FLOAT64) AS TotalSBT, CAST(NULL AS FLOAT64) AS ProcessingFee, CAST(NULL AS FLOAT64) AS ProcessingFeeVat, CAST(NULL AS FLOAT64) AS ShippingFee, CAST(NULL AS FLOAT64) AS ShippingFeeVat, CAST(NULL AS FLOAT64) AS TotalAmount, CAST(NULL AS FLOAT64) AS Discount, CAST('paid' AS STRING) AS TransactionStatus, CAST(NULL AS STRING) AS SubmissionStatus, CAST(NULL AS STRING) AS ApprovalStatus, CAST(NULL AS STRING) AS PaymentStatus, CAST(100 AS FLOAT64) AS ExpectedReceived, CAST(100 AS FLOAT64) AS ActualReceived, CAST(NULL AS FLOAT64) AS InterestThisPeriod, CAST(NULL AS FLOAT64) AS PrincipleThisPeriod, CAST(NULL AS FLOAT64) AS InterestEIRThisPeriod, CAST(NULL AS FLOAT64) AS PrincipleEIRThisPeriod, CAST('26092026' AS STRING) AS PaymentDate, CAST(1 AS INT64) AS Period, CAST(3 AS INT64) AS TotalPeriods, CAST(NULL AS FLOAT64) AS PendingPayment, CAST(NULL AS STRING) AS PaymentMethod, CAST(NULL AS STRING) AS PaymentChannel, CAST(NULL AS STRING) AS ExpectedDate, CAST(NULL AS STRING) AS RefOrder, CAST(NULL AS FLOAT64) AS RefundAmountBeforeFee, CAST(NULL AS FLOAT64) AS RefundAmountAfterFee, CAST(NULL AS STRING) AS BillingAddress, CAST(NULL AS STRING) AS BatchRunDate
UNION ALL
SELECT CAST(NULL AS STRING) AS CompanyDB, CAST('other_item' AS STRING) AS OrderID, CAST('other_item-V1' AS STRING) AS OrderItem, CAST('2_shared' AS STRING) AS InvoiceNo, CAST(NULL AS STRING) AS OrderDate, CAST(NULL AS STRING) AS InsuredID, CAST(NULL AS STRING) AS Title, CAST(NULL AS STRING) AS FirstName, CAST(NULL AS STRING) AS LastName, CAST(NULL AS STRING) AS InsurerCode, CAST(NULL AS STRING) AS InsuranceGroup, CAST(NULL AS STRING) AS InsuranceType, CAST(NULL AS STRING) AS InsuranceProduct, CAST(NULL AS STRING) AS ProductType, CAST(NULL AS STRING) AS PolicyType, CAST(NULL AS STRING) AS Endorse, CAST(NULL AS STRING) AS PolicyDate, CAST(NULL AS STRING) AS PolicyNo, CAST(NULL AS STRING) AS EndorsementNo, CAST(NULL AS STRING) AS ChassisNo, CAST(NULL AS STRING) AS LicensePlate, CAST(NULL AS FLOAT64) AS GrossPremium, CAST(NULL AS FLOAT64) AS StampDuty, CAST(NULL AS FLOAT64) AS VAT, CAST(NULL AS FLOAT64) AS TotalPremium, CAST(NULL AS FLOAT64) AS WHT, CAST(NULL AS FLOAT64) AS TotalEIR, CAST(NULL AS FLOAT64) AS TotalSBT, CAST(NULL AS FLOAT64) AS ProcessingFee, CAST(NULL AS FLOAT64) AS ProcessingFeeVat, CAST(NULL AS FLOAT64) AS ShippingFee, CAST(NULL AS FLOAT64) AS ShippingFeeVat, CAST(NULL AS FLOAT64) AS TotalAmount, CAST(NULL AS FLOAT64) AS Discount, CAST('paid' AS STRING) AS TransactionStatus, CAST(NULL AS STRING) AS SubmissionStatus, CAST(NULL AS STRING) AS ApprovalStatus, CAST(NULL AS STRING) AS PaymentStatus, CAST(0 AS FLOAT64) AS ExpectedReceived, CAST(10 AS FLOAT64) AS ActualReceived, CAST(NULL AS FLOAT64) AS InterestThisPeriod, CAST(NULL AS FLOAT64) AS PrincipleThisPeriod, CAST(NULL AS FLOAT64) AS InterestEIRThisPeriod, CAST(NULL AS FLOAT64) AS PrincipleEIRThisPeriod, CAST('26092026' AS STRING) AS PaymentDate, CAST(1 AS INT64) AS Period, CAST(3 AS INT64) AS TotalPeriods, CAST(NULL AS FLOAT64) AS PendingPayment, CAST(NULL AS STRING) AS PaymentMethod, CAST(NULL AS STRING) AS PaymentChannel, CAST(NULL AS STRING) AS ExpectedDate, CAST(NULL AS STRING) AS RefOrder, CAST(NULL AS FLOAT64) AS RefundAmountBeforeFee, CAST(NULL AS FLOAT64) AS RefundAmountAfterFee, CAST(NULL AS STRING) AS BillingAddress, CAST(NULL AS STRING) AS BatchRunDate
UNION ALL
SELECT CAST(NULL AS STRING) AS CompanyDB, CAST('other_period' AS STRING) AS OrderID, CAST('other_period-V1' AS STRING) AS OrderItem, CAST('p2' AS STRING) AS InvoiceNo, CAST(NULL AS STRING) AS OrderDate, CAST(NULL AS STRING) AS InsuredID, CAST(NULL AS STRING) AS Title, CAST(NULL AS STRING) AS FirstName, CAST(NULL AS STRING) AS LastName, CAST(NULL AS STRING) AS InsurerCode, CAST(NULL AS STRING) AS InsuranceGroup, CAST(NULL AS STRING) AS InsuranceType, CAST(NULL AS STRING) AS InsuranceProduct, CAST(NULL AS STRING) AS ProductType, CAST(NULL AS STRING) AS PolicyType, CAST(NULL AS STRING) AS Endorse, CAST(NULL AS STRING) AS PolicyDate, CAST(NULL AS STRING) AS PolicyNo, CAST(NULL AS STRING) AS EndorsementNo, CAST(NULL AS STRING) AS ChassisNo, CAST(NULL AS STRING) AS LicensePlate, CAST(NULL AS FLOAT64) AS GrossPremium, CAST(NULL AS FLOAT64) AS StampDuty, CAST(NULL AS FLOAT64) AS VAT, CAST(NULL AS FLOAT64) AS TotalPremium, CAST(NULL AS FLOAT64) AS WHT, CAST(NULL AS FLOAT64) AS TotalEIR, CAST(NULL AS FLOAT64) AS TotalSBT, CAST(NULL AS FLOAT64) AS ProcessingFee, CAST(NULL AS FLOAT64) AS ProcessingFeeVat, CAST(NULL AS FLOAT64) AS ShippingFee, CAST(NULL AS FLOAT64) AS ShippingFeeVat, CAST(NULL AS FLOAT64) AS TotalAmount, CAST(NULL AS FLOAT64) AS Discount, CAST('paid' AS STRING) AS TransactionStatus, CAST(NULL AS STRING) AS SubmissionStatus, CAST(NULL AS STRING) AS ApprovalStatus, CAST(NULL AS STRING) AS PaymentStatus, CAST(0 AS FLOAT64) AS ExpectedReceived, CAST(10 AS FLOAT64) AS ActualReceived, CAST(NULL AS FLOAT64) AS InterestThisPeriod, CAST(NULL AS FLOAT64) AS PrincipleThisPeriod, CAST(NULL AS FLOAT64) AS InterestEIRThisPeriod, CAST(NULL AS FLOAT64) AS PrincipleEIRThisPeriod, CAST('26092026' AS STRING) AS PaymentDate, CAST(2 AS INT64) AS Period, CAST(3 AS INT64) AS TotalPeriods, CAST(NULL AS FLOAT64) AS PendingPayment, CAST(NULL AS STRING) AS PaymentMethod, CAST(NULL AS STRING) AS PaymentChannel, CAST(NULL AS STRING) AS ExpectedDate, CAST(NULL AS STRING) AS RefOrder, CAST(NULL AS FLOAT64) AS RefundAmountBeforeFee, CAST(NULL AS FLOAT64) AS RefundAmountAfterFee, CAST(NULL AS STRING) AS BillingAddress, CAST(NULL AS STRING) AS BatchRunDate
UNION ALL
SELECT CAST(NULL AS STRING) AS CompanyDB, CAST('period2_prefix' AS STRING) AS OrderID, CAST('period2_prefix-V1' AS STRING) AS OrderItem, CAST('2_p2raw' AS STRING) AS InvoiceNo, CAST(NULL AS STRING) AS OrderDate, CAST(NULL AS STRING) AS InsuredID, CAST(NULL AS STRING) AS Title, CAST(NULL AS STRING) AS FirstName, CAST(NULL AS STRING) AS LastName, CAST(NULL AS STRING) AS InsurerCode, CAST(NULL AS STRING) AS InsuranceGroup, CAST(NULL AS STRING) AS InsuranceType, CAST(NULL AS STRING) AS InsuranceProduct, CAST(NULL AS STRING) AS ProductType, CAST(NULL AS STRING) AS PolicyType, CAST(NULL AS STRING) AS Endorse, CAST(NULL AS STRING) AS PolicyDate, CAST(NULL AS STRING) AS PolicyNo, CAST(NULL AS STRING) AS EndorsementNo, CAST(NULL AS STRING) AS ChassisNo, CAST(NULL AS STRING) AS LicensePlate, CAST(NULL AS FLOAT64) AS GrossPremium, CAST(NULL AS FLOAT64) AS StampDuty, CAST(NULL AS FLOAT64) AS VAT, CAST(NULL AS FLOAT64) AS TotalPremium, CAST(NULL AS FLOAT64) AS WHT, CAST(NULL AS FLOAT64) AS TotalEIR, CAST(NULL AS FLOAT64) AS TotalSBT, CAST(NULL AS FLOAT64) AS ProcessingFee, CAST(NULL AS FLOAT64) AS ProcessingFeeVat, CAST(NULL AS FLOAT64) AS ShippingFee, CAST(NULL AS FLOAT64) AS ShippingFeeVat, CAST(NULL AS FLOAT64) AS TotalAmount, CAST(NULL AS FLOAT64) AS Discount, CAST('paid' AS STRING) AS TransactionStatus, CAST(NULL AS STRING) AS SubmissionStatus, CAST(NULL AS STRING) AS ApprovalStatus, CAST(NULL AS STRING) AS PaymentStatus, CAST(0 AS FLOAT64) AS ExpectedReceived, CAST(10 AS FLOAT64) AS ActualReceived, CAST(NULL AS FLOAT64) AS InterestThisPeriod, CAST(NULL AS FLOAT64) AS PrincipleThisPeriod, CAST(NULL AS FLOAT64) AS InterestEIRThisPeriod, CAST(NULL AS FLOAT64) AS PrincipleEIRThisPeriod, CAST('26092026' AS STRING) AS PaymentDate, CAST(2 AS INT64) AS Period, CAST(3 AS INT64) AS TotalPeriods, CAST(NULL AS FLOAT64) AS PendingPayment, CAST(NULL AS STRING) AS PaymentMethod, CAST(NULL AS STRING) AS PaymentChannel, CAST(NULL AS STRING) AS ExpectedDate, CAST(NULL AS STRING) AS RefOrder, CAST(NULL AS FLOAT64) AS RefundAmountBeforeFee, CAST(NULL AS FLOAT64) AS RefundAmountAfterFee, CAST(NULL AS STRING) AS BillingAddress, CAST(NULL AS STRING) AS BatchRunDate
UNION ALL
SELECT CAST(NULL AS STRING) AS CompanyDB, CAST('missing_raw' AS STRING) AS OrderID, CAST('missing_raw-V1' AS STRING) AS OrderItem, CAST('2_missing_raw-V1' AS STRING) AS InvoiceNo, CAST(NULL AS STRING) AS OrderDate, CAST(NULL AS STRING) AS InsuredID, CAST(NULL AS STRING) AS Title, CAST(NULL AS STRING) AS FirstName, CAST(NULL AS STRING) AS LastName, CAST(NULL AS STRING) AS InsurerCode, CAST(NULL AS STRING) AS InsuranceGroup, CAST(NULL AS STRING) AS InsuranceType, CAST(NULL AS STRING) AS InsuranceProduct, CAST(NULL AS STRING) AS ProductType, CAST(NULL AS STRING) AS PolicyType, CAST(NULL AS STRING) AS Endorse, CAST(NULL AS STRING) AS PolicyDate, CAST(NULL AS STRING) AS PolicyNo, CAST(NULL AS STRING) AS EndorsementNo, CAST(NULL AS STRING) AS ChassisNo, CAST(NULL AS STRING) AS LicensePlate, CAST(NULL AS FLOAT64) AS GrossPremium, CAST(NULL AS FLOAT64) AS StampDuty, CAST(NULL AS FLOAT64) AS VAT, CAST(NULL AS FLOAT64) AS TotalPremium, CAST(NULL AS FLOAT64) AS WHT, CAST(NULL AS FLOAT64) AS TotalEIR, CAST(NULL AS FLOAT64) AS TotalSBT, CAST(NULL AS FLOAT64) AS ProcessingFee, CAST(NULL AS FLOAT64) AS ProcessingFeeVat, CAST(NULL AS FLOAT64) AS ShippingFee, CAST(NULL AS FLOAT64) AS ShippingFeeVat, CAST(NULL AS FLOAT64) AS TotalAmount, CAST(NULL AS FLOAT64) AS Discount, CAST('paid' AS STRING) AS TransactionStatus, CAST(NULL AS STRING) AS SubmissionStatus, CAST(NULL AS STRING) AS ApprovalStatus, CAST(NULL AS STRING) AS PaymentStatus, CAST(0 AS FLOAT64) AS ExpectedReceived, CAST(10 AS FLOAT64) AS ActualReceived, CAST(NULL AS FLOAT64) AS InterestThisPeriod, CAST(NULL AS FLOAT64) AS PrincipleThisPeriod, CAST(NULL AS FLOAT64) AS InterestEIRThisPeriod, CAST(NULL AS FLOAT64) AS PrincipleEIRThisPeriod, CAST('26092026' AS STRING) AS PaymentDate, CAST(1 AS INT64) AS Period, CAST(3 AS INT64) AS TotalPeriods, CAST(NULL AS FLOAT64) AS PendingPayment, CAST(NULL AS STRING) AS PaymentMethod, CAST(NULL AS STRING) AS PaymentChannel, CAST(NULL AS STRING) AS ExpectedDate, CAST(NULL AS STRING) AS RefOrder, CAST(NULL AS FLOAT64) AS RefundAmountBeforeFee, CAST(NULL AS FLOAT64) AS RefundAmountAfterFee, CAST(NULL AS STRING) AS BillingAddress, CAST(NULL AS STRING) AS BatchRunDate
UNION ALL
SELECT CAST(NULL AS STRING) AS CompanyDB, CAST('collision' AS STRING) AS OrderID, CAST('collision-V1' AS STRING) AS OrderItem, CAST('2_collision' AS STRING) AS InvoiceNo, CAST(NULL AS STRING) AS OrderDate, CAST(NULL AS STRING) AS InsuredID, CAST(NULL AS STRING) AS Title, CAST(NULL AS STRING) AS FirstName, CAST(NULL AS STRING) AS LastName, CAST(NULL AS STRING) AS InsurerCode, CAST(NULL AS STRING) AS InsuranceGroup, CAST(NULL AS STRING) AS InsuranceType, CAST(NULL AS STRING) AS InsuranceProduct, CAST(NULL AS STRING) AS ProductType, CAST(NULL AS STRING) AS PolicyType, CAST(NULL AS STRING) AS Endorse, CAST(NULL AS STRING) AS PolicyDate, CAST(NULL AS STRING) AS PolicyNo, CAST(NULL AS STRING) AS EndorsementNo, CAST(NULL AS STRING) AS ChassisNo, CAST(NULL AS STRING) AS LicensePlate, CAST(NULL AS FLOAT64) AS GrossPremium, CAST(NULL AS FLOAT64) AS StampDuty, CAST(NULL AS FLOAT64) AS VAT, CAST(NULL AS FLOAT64) AS TotalPremium, CAST(NULL AS FLOAT64) AS WHT, CAST(NULL AS FLOAT64) AS TotalEIR, CAST(NULL AS FLOAT64) AS TotalSBT, CAST(NULL AS FLOAT64) AS ProcessingFee, CAST(NULL AS FLOAT64) AS ProcessingFeeVat, CAST(NULL AS FLOAT64) AS ShippingFee, CAST(NULL AS FLOAT64) AS ShippingFeeVat, CAST(NULL AS FLOAT64) AS TotalAmount, CAST(NULL AS FLOAT64) AS Discount, CAST('paid' AS STRING) AS TransactionStatus, CAST(NULL AS STRING) AS SubmissionStatus, CAST(NULL AS STRING) AS ApprovalStatus, CAST(NULL AS STRING) AS PaymentStatus, CAST(0 AS FLOAT64) AS ExpectedReceived, CAST(10 AS FLOAT64) AS ActualReceived, CAST(NULL AS FLOAT64) AS InterestThisPeriod, CAST(NULL AS FLOAT64) AS PrincipleThisPeriod, CAST(NULL AS FLOAT64) AS InterestEIRThisPeriod, CAST(NULL AS FLOAT64) AS PrincipleEIRThisPeriod, CAST('26092026' AS STRING) AS PaymentDate, CAST(1 AS INT64) AS Period, CAST(3 AS INT64) AS TotalPeriods, CAST(NULL AS FLOAT64) AS PendingPayment, CAST(NULL AS STRING) AS PaymentMethod, CAST(NULL AS STRING) AS PaymentChannel, CAST(NULL AS STRING) AS ExpectedDate, CAST(NULL AS STRING) AS RefOrder, CAST(NULL AS FLOAT64) AS RefundAmountBeforeFee, CAST(NULL AS FLOAT64) AS RefundAmountAfterFee, CAST(NULL AS STRING) AS BillingAddress, CAST(NULL AS STRING) AS BatchRunDate
UNION ALL
SELECT CAST(NULL AS STRING) AS CompanyDB, CAST('tie' AS STRING) AS OrderID, CAST('tie-V1' AS STRING) AS OrderItem, CAST('2_tie' AS STRING) AS InvoiceNo, CAST(NULL AS STRING) AS OrderDate, CAST(NULL AS STRING) AS InsuredID, CAST(NULL AS STRING) AS Title, CAST(NULL AS STRING) AS FirstName, CAST(NULL AS STRING) AS LastName, CAST(NULL AS STRING) AS InsurerCode, CAST(NULL AS STRING) AS InsuranceGroup, CAST(NULL AS STRING) AS InsuranceType, CAST(NULL AS STRING) AS InsuranceProduct, CAST(NULL AS STRING) AS ProductType, CAST(NULL AS STRING) AS PolicyType, CAST(NULL AS STRING) AS Endorse, CAST(NULL AS STRING) AS PolicyDate, CAST(NULL AS STRING) AS PolicyNo, CAST(NULL AS STRING) AS EndorsementNo, CAST(NULL AS STRING) AS ChassisNo, CAST(NULL AS STRING) AS LicensePlate, CAST(NULL AS FLOAT64) AS GrossPremium, CAST(NULL AS FLOAT64) AS StampDuty, CAST(NULL AS FLOAT64) AS VAT, CAST(NULL AS FLOAT64) AS TotalPremium, CAST(NULL AS FLOAT64) AS WHT, CAST(NULL AS FLOAT64) AS TotalEIR, CAST(NULL AS FLOAT64) AS TotalSBT, CAST(NULL AS FLOAT64) AS ProcessingFee, CAST(NULL AS FLOAT64) AS ProcessingFeeVat, CAST(NULL AS FLOAT64) AS ShippingFee, CAST(NULL AS FLOAT64) AS ShippingFeeVat, CAST(NULL AS FLOAT64) AS TotalAmount, CAST(NULL AS FLOAT64) AS Discount, CAST('paid' AS STRING) AS TransactionStatus, CAST(NULL AS STRING) AS SubmissionStatus, CAST(NULL AS STRING) AS ApprovalStatus, CAST(NULL AS STRING) AS PaymentStatus, CAST(0 AS FLOAT64) AS ExpectedReceived, CAST(10 AS FLOAT64) AS ActualReceived, CAST(NULL AS FLOAT64) AS InterestThisPeriod, CAST(NULL AS FLOAT64) AS PrincipleThisPeriod, CAST(NULL AS FLOAT64) AS InterestEIRThisPeriod, CAST(NULL AS FLOAT64) AS PrincipleEIRThisPeriod, CAST('26092026' AS STRING) AS PaymentDate, CAST(1 AS INT64) AS Period, CAST(3 AS INT64) AS TotalPeriods, CAST(NULL AS FLOAT64) AS PendingPayment, CAST(NULL AS STRING) AS PaymentMethod, CAST(NULL AS STRING) AS PaymentChannel, CAST(NULL AS STRING) AS ExpectedDate, CAST(NULL AS STRING) AS RefOrder, CAST(NULL AS FLOAT64) AS RefundAmountBeforeFee, CAST(NULL AS FLOAT64) AS RefundAmountAfterFee, CAST(NULL AS STRING) AS BillingAddress, CAST(NULL AS STRING) AS BatchRunDate
UNION ALL
SELECT CAST(NULL AS STRING) AS CompanyDB, CAST('null_expected' AS STRING) AS OrderID, CAST('null_expected-V1' AS STRING) AS OrderItem, CAST('2_null_exp' AS STRING) AS InvoiceNo, CAST(NULL AS STRING) AS OrderDate, CAST(NULL AS STRING) AS InsuredID, CAST(NULL AS STRING) AS Title, CAST(NULL AS STRING) AS FirstName, CAST(NULL AS STRING) AS LastName, CAST(NULL AS STRING) AS InsurerCode, CAST(NULL AS STRING) AS InsuranceGroup, CAST(NULL AS STRING) AS InsuranceType, CAST(NULL AS STRING) AS InsuranceProduct, CAST(NULL AS STRING) AS ProductType, CAST(NULL AS STRING) AS PolicyType, CAST(NULL AS STRING) AS Endorse, CAST(NULL AS STRING) AS PolicyDate, CAST(NULL AS STRING) AS PolicyNo, CAST(NULL AS STRING) AS EndorsementNo, CAST(NULL AS STRING) AS ChassisNo, CAST(NULL AS STRING) AS LicensePlate, CAST(NULL AS FLOAT64) AS GrossPremium, CAST(NULL AS FLOAT64) AS StampDuty, CAST(NULL AS FLOAT64) AS VAT, CAST(NULL AS FLOAT64) AS TotalPremium, CAST(NULL AS FLOAT64) AS WHT, CAST(NULL AS FLOAT64) AS TotalEIR, CAST(NULL AS FLOAT64) AS TotalSBT, CAST(NULL AS FLOAT64) AS ProcessingFee, CAST(NULL AS FLOAT64) AS ProcessingFeeVat, CAST(NULL AS FLOAT64) AS ShippingFee, CAST(NULL AS FLOAT64) AS ShippingFeeVat, CAST(NULL AS FLOAT64) AS TotalAmount, CAST(NULL AS FLOAT64) AS Discount, CAST('paid' AS STRING) AS TransactionStatus, CAST(NULL AS STRING) AS SubmissionStatus, CAST(NULL AS STRING) AS ApprovalStatus, CAST(NULL AS STRING) AS PaymentStatus, CAST(NULL AS FLOAT64) AS ExpectedReceived, CAST(10 AS FLOAT64) AS ActualReceived, CAST(NULL AS FLOAT64) AS InterestThisPeriod, CAST(NULL AS FLOAT64) AS PrincipleThisPeriod, CAST(NULL AS FLOAT64) AS InterestEIRThisPeriod, CAST(NULL AS FLOAT64) AS PrincipleEIRThisPeriod, CAST('26092026' AS STRING) AS PaymentDate, CAST(1 AS INT64) AS Period, CAST(3 AS INT64) AS TotalPeriods, CAST(NULL AS FLOAT64) AS PendingPayment, CAST(NULL AS STRING) AS PaymentMethod, CAST(NULL AS STRING) AS PaymentChannel, CAST(NULL AS STRING) AS ExpectedDate, CAST(NULL AS STRING) AS RefOrder, CAST(NULL AS FLOAT64) AS RefundAmountBeforeFee, CAST(NULL AS FLOAT64) AS RefundAmountAfterFee, CAST(NULL AS STRING) AS BillingAddress, CAST(NULL AS STRING) AS BatchRunDate
UNION ALL
SELECT CAST(NULL AS STRING) AS CompanyDB, CAST('pending_not_topup' AS STRING) AS OrderID, CAST('pending_not_topup-V1' AS STRING) AS OrderItem, CAST('2_pending' AS STRING) AS InvoiceNo, CAST(NULL AS STRING) AS OrderDate, CAST(NULL AS STRING) AS InsuredID, CAST(NULL AS STRING) AS Title, CAST(NULL AS STRING) AS FirstName, CAST(NULL AS STRING) AS LastName, CAST(NULL AS STRING) AS InsurerCode, CAST(NULL AS STRING) AS InsuranceGroup, CAST(NULL AS STRING) AS InsuranceType, CAST(NULL AS STRING) AS InsuranceProduct, CAST(NULL AS STRING) AS ProductType, CAST(NULL AS STRING) AS PolicyType, CAST(NULL AS STRING) AS Endorse, CAST(NULL AS STRING) AS PolicyDate, CAST(NULL AS STRING) AS PolicyNo, CAST(NULL AS STRING) AS EndorsementNo, CAST(NULL AS STRING) AS ChassisNo, CAST(NULL AS STRING) AS LicensePlate, CAST(NULL AS FLOAT64) AS GrossPremium, CAST(NULL AS FLOAT64) AS StampDuty, CAST(NULL AS FLOAT64) AS VAT, CAST(NULL AS FLOAT64) AS TotalPremium, CAST(NULL AS FLOAT64) AS WHT, CAST(NULL AS FLOAT64) AS TotalEIR, CAST(NULL AS FLOAT64) AS TotalSBT, CAST(NULL AS FLOAT64) AS ProcessingFee, CAST(NULL AS FLOAT64) AS ProcessingFeeVat, CAST(NULL AS FLOAT64) AS ShippingFee, CAST(NULL AS FLOAT64) AS ShippingFeeVat, CAST(NULL AS FLOAT64) AS TotalAmount, CAST(NULL AS FLOAT64) AS Discount, CAST('Pending' AS STRING) AS TransactionStatus, CAST(NULL AS STRING) AS SubmissionStatus, CAST(NULL AS STRING) AS ApprovalStatus, CAST(NULL AS STRING) AS PaymentStatus, CAST(0 AS FLOAT64) AS ExpectedReceived, CAST(10 AS FLOAT64) AS ActualReceived, CAST(NULL AS FLOAT64) AS InterestThisPeriod, CAST(NULL AS FLOAT64) AS PrincipleThisPeriod, CAST(NULL AS FLOAT64) AS InterestEIRThisPeriod, CAST(NULL AS FLOAT64) AS PrincipleEIRThisPeriod, CAST('26092026' AS STRING) AS PaymentDate, CAST(1 AS INT64) AS Period, CAST(3 AS INT64) AS TotalPeriods, CAST(NULL AS FLOAT64) AS PendingPayment, CAST(NULL AS STRING) AS PaymentMethod, CAST(NULL AS STRING) AS PaymentChannel, CAST(NULL AS STRING) AS ExpectedDate, CAST(NULL AS STRING) AS RefOrder, CAST(NULL AS FLOAT64) AS RefundAmountBeforeFee, CAST(NULL AS FLOAT64) AS RefundAmountAfterFee, CAST(NULL AS STRING) AS BillingAddress, CAST(NULL AS STRING) AS BatchRunDate
), fixture_sap AS (
SELECT 'gap_period-V1' AS U_OrderItem, 3 AS U_Period, 'old' AS U_InvoiceNo, 'Paid' AS TransactionStatus
UNION ALL
SELECT 'topup-V1' AS U_OrderItem, 1 AS U_Period, 'old' AS U_InvoiceNo, 'Paid' AS TransactionStatus
UNION ALL
SELECT 'exact_paid-V1' AS U_OrderItem, 1 AS U_Period, '2_exact' AS U_InvoiceNo, 'Paid' AS TransactionStatus
UNION ALL
SELECT 'raw_paid-V1' AS U_OrderItem, 1 AS U_Period, 'raw' AS U_InvoiceNo, 'Paid' AS TransactionStatus
UNION ALL
SELECT 'cancelled-V1' AS U_OrderItem, 1 AS U_Period, '2_cancelled' AS U_InvoiceNo, 'Cancelled' AS TransactionStatus
UNION ALL
SELECT 'change_cancelled-V1' AS U_OrderItem, 1 AS U_Period, '2_change' AS U_InvoiceNo, 'Cancelled (Change order / Rejected)' AS TransactionStatus
UNION ALL
SELECT 'blank-V1' AS U_OrderItem, 1 AS U_Period, 'old' AS U_InvoiceNo, 'Paid' AS TransactionStatus
UNION ALL
SELECT 'null_invoice-V1' AS U_OrderItem, 1 AS U_Period, 'old' AS U_InvoiceNo, 'Paid' AS TransactionStatus
UNION ALL
SELECT 'literal_null-V1' AS U_OrderItem, 1 AS U_Period, 'old' AS U_InvoiceNo, 'Paid' AS TransactionStatus
UNION ALL
SELECT 'normal_paid-V1' AS U_OrderItem, 1 AS U_Period, 'normal' AS U_InvoiceNo, 'Paid' AS TransactionStatus
UNION ALL
SELECT 'other_item-V1' AS U_OrderItem, 1 AS U_Period, 'old' AS U_InvoiceNo, 'Paid' AS TransactionStatus
UNION ALL
SELECT 'other_period-V1' AS U_OrderItem, 2 AS U_Period, 'old' AS U_InvoiceNo, 'Paid' AS TransactionStatus
UNION ALL
SELECT 'period2_prefix-V1' AS U_OrderItem, 2 AS U_Period, 'old' AS U_InvoiceNo, 'Paid' AS TransactionStatus
UNION ALL
SELECT 'missing_raw-V1' AS U_OrderItem, 1 AS U_Period, 'old' AS U_InvoiceNo, 'Paid' AS TransactionStatus
UNION ALL
SELECT 'collision-V1' AS U_OrderItem, 1 AS U_Period, 'old' AS U_InvoiceNo, 'Paid' AS TransactionStatus
UNION ALL
SELECT 'tie-V1' AS U_OrderItem, 1 AS U_Period, 'old' AS U_InvoiceNo, 'Paid' AS TransactionStatus
UNION ALL
SELECT 'null_expected-V1' AS U_OrderItem, 1 AS U_Period, 'old' AS U_InvoiceNo, 'Paid' AS TransactionStatus
UNION ALL
SELECT 'pending_not_topup-V1' AS U_OrderItem, 1 AS U_Period, 'old' AS U_InvoiceNo, 'Paid' AS TransactionStatus
UNION ALL
SELECT 'elsewhere-V1',1,'2_shared','Paid'
UNION ALL
SELECT 'other_period-V1',1,'p2','Paid'
UNION ALL
SELECT 'period2_prefix-V1',2,'p2raw','Paid'
), actual AS (
-- 2026-09-26 same-period payment correction. Source only; not deployed.
-- SELECT-only replacement for sap_integration_v2.RCL 05_newpayment.
-- Ordinary periods keep the existing paid-period exclusion.
-- Additional payments use immutable event identity, including the established
-- raw/2_ invoice alias for installment 1. No SAP values are rewritten.
WITH
  sap_paid_periods AS (
    SELECT DISTINCT U_OrderItem AS order_item, SAFE_CAST(U_Period AS INT64) AS period
    FROM fixture_sap
    WHERE TransactionStatus IN ('Paid', 'paid')
  ),
  sap_terminal_events AS (
    SELECT DISTINCT U_OrderItem AS order_item, SAFE_CAST(U_Period AS INT64) AS period,
      U_InvoiceNo AS invoice_no
    FROM fixture_sap
    WHERE LOWER(TRIM(TransactionStatus)) IN
      ('paid', 'cancelled', 'cancelled (change order / rejected)')
      AND NULLIF(TRIM(U_InvoiceNo), '') IS NOT NULL
      AND UPPER(TRIM(U_InvoiceNo)) != 'NULL'
  ),
  source_receipts AS (
    SELECT id, transaction_id, installment_number, third_party_id, create_time, update_time,
      COUNT(*) OVER (PARTITION BY transaction_id, installment_number, third_party_id) AS invoice_rows,
      COUNT(*) OVER (PARTITION BY transaction_id, installment_number, create_time) AS timestamp_rows
    FROM fixture_charges
    WHERE status = 'SUCCESSFUL' AND service_provider = 'RABBIT_LENDING'
  ),
  valid_additional_events AS (
    SELECT oi.human_id AS order_item, c.installment_number AS period,
      CASE WHEN c.installment_number = 1 THEN CONCAT('2_', c.third_party_id)
        ELSE c.third_party_id END AS invoice_no,
      MIN(c.update_time) AS raw_update_time
    FROM source_receipts c
    JOIN fixture_orders o
      ON o.payment = CONCAT('transactions/', c.transaction_id)
    JOIN fixture_order_items oi
      ON oi.order_id = o.id
    WHERE NULLIF(TRIM(c.id), '') IS NOT NULL
      AND NULLIF(TRIM(c.third_party_id), '') IS NOT NULL
      AND UPPER(TRIM(c.third_party_id)) != 'NULL'
      AND NULLIF(TRIM(oi.human_id), '') IS NOT NULL
      AND c.invoice_rows = 1 AND c.timestamp_rows = 1
    GROUP BY order_item, period, invoice_no
    HAVING COUNT(*) = 1
  ),
  interface AS (
    SELECT
      CompanyDB,
      OrderID,
      OrderItem,
      InvoiceNo,
      OrderDate,
      InsuredID,
      Title,
      FirstName,
      LastName,
      InsurerCode,
      InsuranceGroup,
      InsuranceType,
      InsuranceProduct,
      ProductType,
      PolicyType,
      Endorse,
      PolicyDate,
      PolicyNo,
      EndorsementNo,
      ChassisNo,
      LicensePlate,
      GrossPremium,
      StampDuty,
      VAT,
      TotalPremium,
      WHT,
      TotalEIR,
      TotalSBT,
      ProcessingFee,
      ProcessingFeeVat,
      ShippingFee,
      ShippingFeeVat,
      TotalAmount,
      Discount,
      TransactionStatus,
      SubmissionStatus,
      ApprovalStatus,
      PaymentStatus,
      ExpectedReceived,
      ActualReceived,
      InterestThisPeriod,
      PrincipleThisPeriod,
      InterestEIRThisPeriod,
      PrincipleEIRThisPeriod,
      PaymentDate,
      Period,
      TotalPeriods,
      PendingPayment,
      PaymentMethod,
      PaymentChannel,
      ExpectedDate,
      RefOrder,
      CAST(RefundAmountBeforeFee AS FLOAT64) AS RefundAmountBeforeFee,
      CAST(RefundAmountAfterFee AS FLOAT64) AS RefundAmountAfterFee,
      BillingAddress,
      BatchRunDate,
      SAFE_CAST(Period AS INT64) AS careos_installment,
      COALESCE(ExpectedReceived = 0, FALSE)
        AND COALESCE(ActualReceived, 0) > 0
        AND LOWER(TRIM(COALESCE(TransactionStatus, ''))) = 'paid'
        AS is_additional_payment
    FROM fixture_dashboard
  )
SELECT DISTINCT
  interface.CompanyDB,
  interface.OrderID,
  interface.OrderItem,
  interface.InvoiceNo,
  interface.OrderDate,
  interface.InsuredID,
  interface.Title,
  interface.FirstName,
  interface.LastName,
  interface.InsurerCode,
  interface.InsuranceGroup,
  interface.InsuranceType,
  interface.InsuranceProduct,
  interface.ProductType,
  interface.PolicyType,
  interface.Endorse,
  interface.PolicyDate,
  interface.PolicyNo,
  interface.EndorsementNo,
  interface.ChassisNo,
  interface.LicensePlate,
  interface.GrossPremium,
  interface.StampDuty,
  interface.VAT,
  interface.TotalPremium,
  interface.WHT,
  interface.TotalEIR,
  interface.TotalSBT,
  interface.ProcessingFee,
  interface.ProcessingFeeVat,
  interface.ShippingFee,
  interface.ShippingFeeVat,
  interface.TotalAmount,
  interface.Discount,
  interface.TransactionStatus,
  interface.SubmissionStatus,
  interface.ApprovalStatus,
  interface.PaymentStatus,
  interface.ExpectedReceived,
  interface.ActualReceived,
  interface.InterestThisPeriod,
  interface.PrincipleThisPeriod,
  interface.InterestEIRThisPeriod,
  interface.PrincipleEIRThisPeriod,
  interface.PaymentDate,
  interface.Period,
  interface.TotalPeriods,
  interface.PendingPayment,
  interface.PaymentMethod,
  interface.PaymentChannel,
  interface.ExpectedDate,
  interface.RefOrder,
  interface.RefundAmountBeforeFee,
  interface.RefundAmountAfterFee,
  interface.BillingAddress,
  interface.BatchRunDate
FROM interface
WHERE interface.careos_installment IS NOT NULL
  AND (
    (
      NOT interface.is_additional_payment
      AND NOT EXISTS (
        SELECT 1 FROM sap_paid_periods p
        WHERE p.order_item = interface.OrderItem
          AND p.period = interface.careos_installment
      )
    )
    OR (
      interface.is_additional_payment
      AND EXISTS (
        SELECT 1 FROM valid_additional_events v
        WHERE v.order_item = interface.OrderItem
          AND v.period = interface.careos_installment
          AND v.invoice_no = interface.InvoiceNo
      )
      AND NULLIF(TRIM(interface.InvoiceNo), '') IS NOT NULL
      AND UPPER(TRIM(interface.InvoiceNo)) != 'NULL'
      AND NOT EXISTS (
        SELECT 1 FROM sap_terminal_events e
        WHERE e.order_item = interface.OrderItem
          AND e.period = interface.careos_installment
          AND (
            e.invoice_no = interface.InvoiceNo
            OR (
              interface.careos_installment = 1
              AND STARTS_WITH(interface.InvoiceNo, '2_')
              AND e.invoice_no = SUBSTR(interface.InvoiceNo, 3)
            )
          )
      )
    )
  )
ORDER BY interface.OrderItem, interface.Period

), sap_after_posting AS (
SELECT U_OrderItem,U_Period,U_InvoiceNo,TransactionStatus FROM fixture_sap UNION ALL SELECT OrderItem,Period,InvoiceNo,TransactionStatus FROM actual
), replay AS (
-- 2026-09-26 same-period payment correction. Source only; not deployed.
-- SELECT-only replacement for sap_integration_v2.RCL 05_newpayment.
-- Ordinary periods keep the existing paid-period exclusion.
-- Additional payments use immutable event identity, including the established
-- raw/2_ invoice alias for installment 1. No SAP values are rewritten.
WITH
  sap_paid_periods AS (
    SELECT DISTINCT U_OrderItem AS order_item, SAFE_CAST(U_Period AS INT64) AS period
    FROM sap_after_posting
    WHERE TransactionStatus IN ('Paid', 'paid')
  ),
  sap_terminal_events AS (
    SELECT DISTINCT U_OrderItem AS order_item, SAFE_CAST(U_Period AS INT64) AS period,
      U_InvoiceNo AS invoice_no
    FROM sap_after_posting
    WHERE LOWER(TRIM(TransactionStatus)) IN
      ('paid', 'cancelled', 'cancelled (change order / rejected)')
      AND NULLIF(TRIM(U_InvoiceNo), '') IS NOT NULL
      AND UPPER(TRIM(U_InvoiceNo)) != 'NULL'
  ),
  source_receipts AS (
    SELECT id, transaction_id, installment_number, third_party_id, create_time, update_time,
      COUNT(*) OVER (PARTITION BY transaction_id, installment_number, third_party_id) AS invoice_rows,
      COUNT(*) OVER (PARTITION BY transaction_id, installment_number, create_time) AS timestamp_rows
    FROM fixture_charges
    WHERE status = 'SUCCESSFUL' AND service_provider = 'RABBIT_LENDING'
  ),
  valid_additional_events AS (
    SELECT oi.human_id AS order_item, c.installment_number AS period,
      CASE WHEN c.installment_number = 1 THEN CONCAT('2_', c.third_party_id)
        ELSE c.third_party_id END AS invoice_no,
      MIN(c.update_time) AS raw_update_time
    FROM source_receipts c
    JOIN fixture_orders o
      ON o.payment = CONCAT('transactions/', c.transaction_id)
    JOIN fixture_order_items oi
      ON oi.order_id = o.id
    WHERE NULLIF(TRIM(c.id), '') IS NOT NULL
      AND NULLIF(TRIM(c.third_party_id), '') IS NOT NULL
      AND UPPER(TRIM(c.third_party_id)) != 'NULL'
      AND NULLIF(TRIM(oi.human_id), '') IS NOT NULL
      AND c.invoice_rows = 1 AND c.timestamp_rows = 1
    GROUP BY order_item, period, invoice_no
    HAVING COUNT(*) = 1
  ),
  interface AS (
    SELECT
      CompanyDB,
      OrderID,
      OrderItem,
      InvoiceNo,
      OrderDate,
      InsuredID,
      Title,
      FirstName,
      LastName,
      InsurerCode,
      InsuranceGroup,
      InsuranceType,
      InsuranceProduct,
      ProductType,
      PolicyType,
      Endorse,
      PolicyDate,
      PolicyNo,
      EndorsementNo,
      ChassisNo,
      LicensePlate,
      GrossPremium,
      StampDuty,
      VAT,
      TotalPremium,
      WHT,
      TotalEIR,
      TotalSBT,
      ProcessingFee,
      ProcessingFeeVat,
      ShippingFee,
      ShippingFeeVat,
      TotalAmount,
      Discount,
      TransactionStatus,
      SubmissionStatus,
      ApprovalStatus,
      PaymentStatus,
      ExpectedReceived,
      ActualReceived,
      InterestThisPeriod,
      PrincipleThisPeriod,
      InterestEIRThisPeriod,
      PrincipleEIRThisPeriod,
      PaymentDate,
      Period,
      TotalPeriods,
      PendingPayment,
      PaymentMethod,
      PaymentChannel,
      ExpectedDate,
      RefOrder,
      CAST(RefundAmountBeforeFee AS FLOAT64) AS RefundAmountBeforeFee,
      CAST(RefundAmountAfterFee AS FLOAT64) AS RefundAmountAfterFee,
      BillingAddress,
      BatchRunDate,
      SAFE_CAST(Period AS INT64) AS careos_installment,
      COALESCE(ExpectedReceived = 0, FALSE)
        AND COALESCE(ActualReceived, 0) > 0
        AND LOWER(TRIM(COALESCE(TransactionStatus, ''))) = 'paid'
        AS is_additional_payment
    FROM fixture_dashboard
  )
SELECT DISTINCT
  interface.CompanyDB,
  interface.OrderID,
  interface.OrderItem,
  interface.InvoiceNo,
  interface.OrderDate,
  interface.InsuredID,
  interface.Title,
  interface.FirstName,
  interface.LastName,
  interface.InsurerCode,
  interface.InsuranceGroup,
  interface.InsuranceType,
  interface.InsuranceProduct,
  interface.ProductType,
  interface.PolicyType,
  interface.Endorse,
  interface.PolicyDate,
  interface.PolicyNo,
  interface.EndorsementNo,
  interface.ChassisNo,
  interface.LicensePlate,
  interface.GrossPremium,
  interface.StampDuty,
  interface.VAT,
  interface.TotalPremium,
  interface.WHT,
  interface.TotalEIR,
  interface.TotalSBT,
  interface.ProcessingFee,
  interface.ProcessingFeeVat,
  interface.ShippingFee,
  interface.ShippingFeeVat,
  interface.TotalAmount,
  interface.Discount,
  interface.TransactionStatus,
  interface.SubmissionStatus,
  interface.ApprovalStatus,
  interface.PaymentStatus,
  interface.ExpectedReceived,
  interface.ActualReceived,
  interface.InterestThisPeriod,
  interface.PrincipleThisPeriod,
  interface.InterestEIRThisPeriod,
  interface.PrincipleEIRThisPeriod,
  interface.PaymentDate,
  interface.Period,
  interface.TotalPeriods,
  interface.PendingPayment,
  interface.PaymentMethod,
  interface.PaymentChannel,
  interface.ExpectedDate,
  interface.RefOrder,
  interface.RefundAmountBeforeFee,
  interface.RefundAmountAfterFee,
  interface.BillingAddress,
  interface.BatchRunDate
FROM interface
WHERE interface.careos_installment IS NOT NULL
  AND (
    (
      NOT interface.is_additional_payment
      AND NOT EXISTS (
        SELECT 1 FROM sap_paid_periods p
        WHERE p.order_item = interface.OrderItem
          AND p.period = interface.careos_installment
      )
    )
    OR (
      interface.is_additional_payment
      AND EXISTS (
        SELECT 1 FROM valid_additional_events v
        WHERE v.order_item = interface.OrderItem
          AND v.period = interface.careos_installment
          AND v.invoice_no = interface.InvoiceNo
      )
      AND NULLIF(TRIM(interface.InvoiceNo), '') IS NOT NULL
      AND UPPER(TRIM(interface.InvoiceNo)) != 'NULL'
      AND NOT EXISTS (
        SELECT 1 FROM sap_terminal_events e
        WHERE e.order_item = interface.OrderItem
          AND e.period = interface.careos_installment
          AND (
            e.invoice_no = interface.InvoiceNo
            OR (
              interface.careos_installment = 1
              AND STARTS_WITH(interface.InvoiceNo, '2_')
              AND e.invoice_no = SUBSTR(interface.InvoiceNo, 3)
            )
          )
      )
    )
  )
ORDER BY interface.OrderItem, interface.Period

), expected AS (
SELECT 'new_period-V1' AS OrderItem, TRUE AS should_emit UNION ALL SELECT 'gap_period-V1' AS OrderItem, TRUE AS should_emit UNION ALL SELECT 'topup-V1' AS OrderItem, TRUE AS should_emit UNION ALL SELECT 'exact_paid-V1' AS OrderItem, FALSE AS should_emit UNION ALL SELECT 'raw_paid-V1' AS OrderItem, FALSE AS should_emit UNION ALL SELECT 'cancelled-V1' AS OrderItem, FALSE AS should_emit UNION ALL SELECT 'change_cancelled-V1' AS OrderItem, FALSE AS should_emit UNION ALL SELECT 'blank-V1' AS OrderItem, FALSE AS should_emit UNION ALL SELECT 'null_invoice-V1' AS OrderItem, FALSE AS should_emit UNION ALL SELECT 'literal_null-V1' AS OrderItem, FALSE AS should_emit UNION ALL SELECT 'normal_paid-V1' AS OrderItem, FALSE AS should_emit UNION ALL SELECT 'other_item-V1' AS OrderItem, TRUE AS should_emit UNION ALL SELECT 'other_period-V1' AS OrderItem, TRUE AS should_emit UNION ALL SELECT 'period2_prefix-V1' AS OrderItem, TRUE AS should_emit UNION ALL SELECT 'missing_raw-V1' AS OrderItem, FALSE AS should_emit UNION ALL SELECT 'collision-V1' AS OrderItem, FALSE AS should_emit UNION ALL SELECT 'tie-V1' AS OrderItem, FALSE AS should_emit UNION ALL SELECT 'null_expected-V1' AS OrderItem, FALSE AS should_emit UNION ALL SELECT 'pending_not_topup-V1' AS OrderItem, FALSE AS should_emit
)

SELECT CURRENT_TIMESTAMP() AS checked_at_utc,
 (SELECT COUNT(*) FROM expected) AS cases,
 (SELECT COUNT(*) FROM actual) AS emitted_rows,
 (SELECT COUNT(*) FROM expected e WHERE e.should_emit != EXISTS(SELECT 1 FROM actual a WHERE a.OrderItem=e.OrderItem)) AS membership_failures,
 (SELECT COUNT(*) FROM replay) AS replay_rows_after_posting,
 (SELECT COUNT(*) FROM (SELECT OrderItem,Period,InvoiceNo FROM actual GROUP BY 1,2,3 HAVING COUNT(*)>1)) AS duplicate_event_keys;
