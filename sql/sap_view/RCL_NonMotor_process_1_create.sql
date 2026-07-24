-- BASELINE CAPTURE 2026-07-25 -- pulled verbatim from live BigQuery view definition
-- Object: sap_view.RCL_NonMotor_process_1_create
-- Part of the 11 sap_view process views confirmed as real nightly production, that
-- read directly from sap_integration_v2.SAP_LIVE_FULL. Repointing to
-- sap_integration_v3.stg_sap_state (deduped, no duplicate (OrderItem,Period) rows).
-- See docs/knowledge/30_SAP_CHANGELOG.md 2026-07-25 entry.

--Create new order--
WITH
    sap as (
        SELECT
            sap.U_OrderItem
        FROM
             `pacific-plating-282708.sap_integration_v3.stg_sap_state` sap 
    )
SELECT
    non.*
FROM
    `pacific-plating-282708.sap_data_engineer.RCL_HEALTH` non
    LEFT JOIN sap ON sap.U_OrderItem = non.OrderItem
WHERE
    sap.U_OrderItem IS NULL
    AND ActualReceived IS NOT NULL
    AND LOWER(FirstName) <> 'test'
Order BY
    OrderItem,

    Period;

