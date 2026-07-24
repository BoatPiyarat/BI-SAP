-- BASELINE CAPTURE 2026-07-25 -- pulled verbatim from live BigQuery view definition
-- Object: sap_view.RCL_Motor_process_4_creditshell
-- Part of the 11 sap_view process views confirmed as real nightly production, that
-- read directly from sap_integration_v2.SAP_LIVE_FULL. Repointing to
-- sap_integration_v3.stg_sap_state (deduped, no duplicate (OrderItem,Period) rows).
-- See docs/knowledge/30_SAP_CHANGELOG.md 2026-07-25 entry.

--create NEW ORDER form credit shell--
SELECT
    *
FROM
    `pacific-plating-282708.sap_integration_v2.RCL 04_new order credit shell`
WHERE
    OrderItem NOT IN (
        SELECT
            U_OrderItem
        FROM
            `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
    )
    AND OrderID IN (
        SELECT
            current_human_id
        FROM
            `pacific-plating-282708.careos.cancelled_change_orders`
    )
    AND (OrderDate LIKE '%2025%'
    OR OrderDate LIKE '%2026%' )
    AND OrderID NOT IN (
'L79128866', --incorrect insurer id--
'L79217528', --incorrect insurer id--
'L79291428'  --incorrect insurer id--
    )

ORDER BY
    OrderItem,
    period;
