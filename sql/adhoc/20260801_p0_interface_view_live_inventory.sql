-- Metadata-only live-definition inventory for the 12 legacy interface process views.
-- Source of truth is INFORMATION_SCHEMA.VIEWS, never the repository baseline.
SELECT
  table_name,
  view_definition,
  REGEXP_CONTAINS(
    view_definition,
    r"(?i)FORMAT_DATE\s*\(\s*'%d%m%Y'\s*,\s*CURRENT_DATE\s*\(\s*\)\s*\)"
  ) AS batch_run_date_uses_current_date,
  REGEXP_CONTAINS(view_definition, r"(?i)OrderDate\s+NOT\s+LIKE\s+'%2023%'")
    AS has_orderdate_not_like_2023,
  REGEXP_CONTAINS(view_definition, r"(?i)OrderDate\s+NOT\s+LIKE\s+'%2024%'")
    AS has_orderdate_not_like_2024,
  REGEXP_CONTAINS(view_definition, r"(?i)(OrderItem|order_item)\s+NOT\s+IN\s*\(")
    AS has_hardcoded_orderitem_not_in
FROM `pacific-plating-282708.sap_view.INFORMATION_SCHEMA.VIEWS`
WHERE REGEXP_CONTAINS(table_name, r'_process_')
ORDER BY table_name;
