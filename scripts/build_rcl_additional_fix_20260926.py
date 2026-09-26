"""Regenerate reviewed SELECT-only replacements from the captured live definitions."""
import json
from pathlib import Path
def read_json(p):
 b=Path(p).read_bytes()
 try: return json.loads(b.decode('utf-8-sig'))
 except UnicodeDecodeError: return json.loads(b.decode('cp1252'))
defs=read_json('docs/evidence/rcl_additional_20260926/live_definitions.json')
live={x['table_name']:x['view_definition'].strip().rstrip(';') for x in defs}
fields=read_json('docs/evidence/rcl_additional_20260926/column_contract.json')
cols=[x['name'] for x in fields]
assert len(cols)==56
out=Path('sql/production/rcl_additional_20260926'); out.mkdir(parents=True,exist_ok=True)
evidence=Path('docs/evidence/rcl_additional_20260926'); evidence.mkdir(parents=True,exist_ok=True)
(evidence/'live_definitions.json').write_text(json.dumps(defs,ensure_ascii=False,indent=2),encoding='utf-8')
(evidence/'column_contract.json').write_text(json.dumps(fields,indent=2),encoding='utf-8')
dashboard=live['sap_dashboard_carepay_installment']
needle='AND (charges.charge_rank = 1 OR charges.charge_rank IS NULL)'
assert dashboard.count(needle)==1
dashboard=dashboard.replace(needle,'-- Keep every successful charge; rank > 1 has ExpectedReceived = 0.\n   ')
assert dashboard.count('AND charges.charge_rank = 1')==live['sap_dashboard_carepay_installment'].count('AND charges.charge_rank = 1')
# Carry charge identity internally so only newly exposed receipts bypass EIR
# schedule reconciliation. The public 56-column contract remains unchanged.
for marker,expr in [("'rcl_voluntary_installment_details' AS CTE_source,", "COALESCE(charges.charge_rank > 1, FALSE)"), ("'compulsary_installment_details' AS CTE_source,", "FALSE")]:
 assert dashboard.count(marker)==1
 dashboard=dashboard.replace(marker,marker+'\n    '+expr+' AS is_additional_receipt,')
dashboard=dashboard.replace('    CTE_source,','    CTE_source,\n    is_additional_receipt,')
dashboard=dashboard.replace('finish AS (\n  SELECT','finish AS (\n  SELECT\n  transformation.is_additional_receipt,')
dashboard=dashboard.replace('    WHEN (arrange.interest_amount', '    WHEN transformation.is_additional_receipt THEN 0\n    WHEN (arrange.interest_amount')
dashboard=dashboard.replace('    WHEN arrange_again.interest_amount', '    WHEN finish.is_additional_receipt THEN 0\n    WHEN arrange_again.interest_amount')
projection=',\n      '.join(('CAST('+c+' AS FLOAT64) AS '+c) if c in ['RefundAmountBeforeFee','RefundAmountAfterFee'] else c for c in cols)
result=',\n  '.join('interface.'+c for c in cols)
newpayment="""-- SELECT-only replacement for sap_integration_v2.RCL 05_newpayment.
-- Ordinary periods keep the existing paid-period exclusion.
-- Additional payments use immutable event identity, including the established
-- raw/2_ invoice alias for installment 1. No SAP values are rewritten.
WITH
  sap_paid_periods AS (
    SELECT DISTINCT U_OrderItem AS order_item, SAFE_CAST(U_Period AS INT64) AS period
    FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
    WHERE TransactionStatus IN ('Paid', 'paid')
  ),
  sap_terminal_events AS (
    SELECT DISTINCT U_OrderItem AS order_item, SAFE_CAST(U_Period AS INT64) AS period,
      U_InvoiceNo AS invoice_no
    FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`
    WHERE LOWER(TRIM(TransactionStatus)) IN
      ('paid', 'cancelled', 'cancelled (change order / rejected)')
      AND NULLIF(TRIM(U_InvoiceNo), '') IS NOT NULL
      AND UPPER(TRIM(U_InvoiceNo)) != 'NULL'
  ),
  source_receipts AS (
    SELECT id, transaction_id, installment_number, third_party_id, create_time, update_time,
      COUNT(*) OVER (PARTITION BY transaction_id, installment_number, third_party_id) AS invoice_rows,
      COUNT(*) OVER (PARTITION BY transaction_id, installment_number, create_time) AS timestamp_rows
    FROM `pacific-plating-282708.careos.carepay_charges`
    WHERE status = 'SUCCESSFUL' AND service_provider = 'RABBIT_LENDING'
  ),
  valid_additional_events AS (
    SELECT oi.human_id AS order_item, c.installment_number AS period,
      CASE WHEN c.installment_number = 1 THEN CONCAT('2_', c.third_party_id)
        ELSE c.third_party_id END AS invoice_no,
      MIN(c.update_time) AS raw_update_time
    FROM source_receipts c
    JOIN `pacific-plating-282708.careos.careos_orders` o
      ON o.payment = CONCAT('transactions/', c.transaction_id)
    JOIN `pacific-plating-282708.careos.careos_order_items` oi
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
      """+projection+""",
      SAFE_CAST(Period AS INT64) AS careos_installment,
      COALESCE(ExpectedReceived = 0, FALSE)
        AND COALESCE(ActualReceived, 0) > 0
        AND LOWER(TRIM(COALESCE(TransactionStatus, ''))) = 'paid'
        AS is_additional_payment
    FROM `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_installment`
  )
SELECT DISTINCT
  """+result+"""
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
"""
gate=live['RCL 05_paid by period']
addition=""",
additional_items AS (
  -- Only genuinely unsent additional events can reopen an already-paid item.
  SELECT DISTINCT OrderItem
  FROM `pacific-plating-282708.sap_integration_v2.RCL 05_newpayment` n
  JOIN `pacific-plating-282708.careos.careos_order_items` oi ON oi.human_id = n.OrderItem
  JOIN `pacific-plating-282708.careos.careos_orders` o ON o.id = oi.order_id
  JOIN `pacific-plating-282708.careos.carepay_charges` c
    ON o.payment = CONCAT('transactions/', c.transaction_id)
    AND c.installment_number = SAFE_CAST(n.Period AS INT64)
    AND n.InvoiceNo = CASE WHEN c.installment_number = 1
      THEN CONCAT('2_', c.third_party_id) ELSE c.third_party_id END
    AND c.status = 'SUCCESSFUL' AND c.service_provider = 'RABBIT_LENDING'
  WHERE ExpectedReceived = 0
    AND ActualReceived > 0
    AND LOWER(TRIM(TransactionStatus)) = 'paid'
    AND NULLIF(TRIM(InvoiceNo), '') IS NOT NULL
    AND UPPER(TRIM(InvoiceNo)) != 'NULL'
    AND DATE(c.update_time)
      BETWEEN DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 2 MONTH), MONTH)
      AND CURRENT_DATE()
)
"""
gate=gate.replace('\r\n','\n')
needle='\nSELECT DISTINCT\n  orders.human_id'
assert gate.count(needle)==1
gate=gate.replace(needle,addition+needle)
needle='WHERE 1=1'
assert gate.count(needle)==1
gate=gate.replace(needle,'LEFT JOIN additional_items AS additional\n  ON additional.OrderItem = oi.human_id\n'+needle)
needle="""  AND DATE(charges_ranking.update_time)
      BETWEEN DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 2 MONTH), MONTH)
      AND CURRENT_DATE()"""
assert gate.count(needle)==1
gate=gate.replace(needle,"""  AND (
    DATE(charges_ranking.update_time)
      BETWEEN DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 2 MONTH), MONTH)
      AND CURRENT_DATE()
    OR additional.OrderItem IS NOT NULL
  )""")
needle="""  AND NOT EXISTS (
    SELECT 1
    FROM sap_paid_periods p
    WHERE p.order_item = oi.human_id
      AND p.period = charges_ranking.installment_number
  )"""
assert gate.count(needle)==1
gate=gate.replace(needle,"""  AND (
    NOT EXISTS (
      SELECT 1
      FROM sap_paid_periods p
      WHERE p.order_item = oi.human_id
        AND p.period = charges_ranking.installment_number
    )
    OR additional.OrderItem IS NOT NULL
  )""")
for n,q in [('sap_dashboard_carepay_installment',dashboard),('RCL_05_newpayment',newpayment),('RCL_05_paid_by_period',gate)]:
 (out/(n+'.sql')).write_text('-- 2026-09-26 same-period payment correction. Source only; not deployed.\n'+q+';\n',encoding='utf-8')
wrapper=live['RCL_Motor_process_2_newpayment']
def body(name): return (out/(name+'.sql')).read_text(encoding='utf-8').strip().rstrip(';')
pipeline='WITH candidate_dashboard AS (\n'+body('sap_dashboard_carepay_installment')+'\n),\ncandidate_newpayment AS (\n'+body('RCL_05_newpayment').replace('`pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_installment`','candidate_dashboard')+'\n),\ncandidate_gate AS (\n'+body('RCL_05_paid_by_period').replace('`pacific-plating-282708.sap_integration_v2.RCL 05_newpayment`','candidate_newpayment')+'\n),\ncandidate_wrapper AS (\n'+wrapper.replace('`pacific-plating-282708.sap_integration_v2.RCL 05_newpayment`','candidate_newpayment').replace('`pacific-plating-282708.sap_integration_v2.RCL 05_paid by period`','candidate_gate')+'\n)\n'
Path('sql/adhoc/20260926_rcl_additional_target_validation.sql').write_text(pipeline+"""
SELECT CURRENT_TIMESTAMP() AS checked_at_utc, OrderID, OrderItem, Period, TotalPeriods,
InvoiceNo, TransactionStatus, ExpectedReceived, ActualReceived, PaymentDate, PaymentMethod, PaymentChannel
FROM candidate_wrapper
WHERE OrderID IN ('L80570054','L79109956')
ORDER BY OrderItem, Period, InvoiceNo;
""",encoding='utf-8')

print('Built three source-only replacements and composed real-pipeline target validation.')


# Refresh candidate definitions in the standalone baseline/candidate regression.
staged=Path('sql/adhoc/20260926_rcl_additional_staged_validation.sql')
if staged.exists():
 text=staged.read_text(encoding='utf-8')
 for temp,name,next_temp in [('candidate_dashboard','sap_dashboard_carepay_installment','candidate_newpayment'),('candidate_newpayment','RCL_05_newpayment','candidate_gate')]:
  start=text.index('CREATE TEMP TABLE '+temp+' AS')
  end=text.index('CREATE TEMP TABLE '+next_temp+' AS',start)
  query=body(name).replace('`pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_installment`','candidate_dashboard').replace('`pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`','evidence_sap')
  text=text[:start]+'CREATE TEMP TABLE '+temp+' AS '+query+';\n'+text[end:]
 staged.write_text(text,encoding='utf-8')
