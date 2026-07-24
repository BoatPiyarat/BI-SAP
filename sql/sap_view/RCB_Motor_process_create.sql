-- BASELINE CAPTURE 2026-07-25 -- pulled verbatim from live BigQuery view definition
-- Object: sap_view.RCB_Motor_process_create
-- Part of the 11 sap_view process views confirmed as real nightly production, that
-- read directly from sap_integration_v2.SAP_LIVE_FULL. Repointing to
-- sap_integration_v3.stg_sap_state (deduped, no duplicate (OrderItem,Period) rows).
-- See docs/knowledge/30_SAP_CHANGELOG.md 2026-07-25 entry.

--new create order--
WITH
    sap AS (
        SELECT
            U_OrderItem
        FROM
            `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
        WHERE
            TransactionStatus in ('Paid', 'paid')
            AND (
                PaymentChannel like '%RCB%'
                OR PaymentChannel like '%Credit Shell%'
            )
    )
SELECT distinct
    interface.*
FROM
    `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_fully_paid` interface
    LEFT JOIN sap s ON interface.OrderItem = s.U_OrderItem
WHERE
    s.U_OrderItem IS NULL
    AND ExpectedReceived IS NOT NULL
    AND FirstName <> 'Test'
    AND OrderItem NOT IN (
        'L77057350-V1',
        'L77073984-M1',
        'L77073984-V1',
        'L77260066-M1',
        'L77260066-V1',
        'L78097418-V1',
        'L78100617-M1',
        'L78100617-V1',
        'L78337914-V1',
        'L78639783-V1', -- insurer/22 BKI code 646000 iCare
        'L77440810-M1',
        'L77436355-M1',
        'L78605792-V1', -- RCL
        'L77651459-M1', --InsuredID
        'L77651459-V1', --InsuredID
        -- 45 TIP no purchase anymore
        'L77046189-V1', 'L77899595-V1', 'L79110049-V1', 'L79304822-V1',
        -- MITI rabbit did not sell this insurance
        'L77838729-V1',
        -- 49 is for non-motor orders (Muang Thai Life Assurance PCL)
        'L77754026-V1', 'L77790667-V1', 'L78913826-V1', 'L78913834-V1', 'L79201106-V1', 'L79322195-V1'
    )
ORDER BY
    interface.OrderID,
    OrderItem;
