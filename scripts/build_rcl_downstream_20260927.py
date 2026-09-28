"""Build downstream-only candidates against captured deployed dashboard; no DDL."""
from pathlib import Path
import json,hashlib
base=Path('docs/evidence/rcl_downstream_20260927')
out=Path('sql/production/rcl_downstream_20260927');out.mkdir(parents=True,exist_ok=True)
tests=Path('sql/adhoc/20260927_rcl_downstream');tests.mkdir(parents=True,exist_ok=True)
def read(p):return Path(p).read_text(encoding='utf-8-sig').strip().rstrip(';')
def once(s,a,b):
 assert s.count(a)==1,repr(a)
 return s.replace(a,b)
new=read('sql/production/rcl_additional_20260926/RCL_05_newpayment.sql')
new=once(new,'WHERE interface.careos_installment IS NOT NULL',"""WHERE IF(
  interface.source_event_rows IS NULL AND COALESCE(interface.ActualReceived, 0) != 0
  AND NOT EXISTS (
    SELECT 1 FROM sap_terminal_events e
    WHERE e.order_item=interface.OrderItem AND e.period=interface.careos_installment
      AND (e.invoice_no=interface.InvoiceNo OR (interface.careos_installment=1
        AND STARTS_WITH(interface.InvoiceNo,'2_') AND e.invoice_no=SUBSTR(interface.InvoiceNo,3)))
  ),
  ERROR('RCL_MISSING_PAID_RECEIPT_LINEAGE: run downstream receipt diagnostics before export'),
  interface.careos_installment IS NOT NULL""")
new=once(new,'ORDER BY interface.OrderItem, interface.Period',')\nORDER BY interface.OrderItem, interface.Period')
gate=read('sql/production/rcl_additional_20260926/RCL_05_paid_by_period.sql')
gate='-- Receipt-aware eligibility: retain legacy latest-period path and reopen for any recent unsent receipt.\n'+gate[gate.index('WITH charges AS ('):]
gate=gate.replace('additional_items','outstanding_receipt_items').replace('AS additional','AS outstanding').replace('additional.OrderItem','outstanding.OrderItem')
gate=once(gate,'Only genuinely unsent additional events can reopen an already-paid item.','Any recent unsent receipt can reopen an item, even if a later period is Paid.')
gate=once(gate,'AND c.source_charge_rank > 1','AND c.source_charge_rank >= 1')
gate=once(gate,"THEN CONCAT('2_', c.third_party_id) ELSE c.third_party_id END", "THEN CONCAT('2_', IF(c.source_charge_rank=1, COALESCE(c.third_party_id,oi.human_id),c.third_party_id)) ELSE IF(c.source_charge_rank=1,COALESCE(c.third_party_id,oi.human_id),c.third_party_id) END")
gate=once(gate,'WHERE ExpectedReceived = 0\n    AND ActualReceived > 0','WHERE ActualReceived > 0')
gate=once(gate,'PARTITION BY transaction_id ORDER BY installment_number DESC','PARTITION BY transaction_id ORDER BY installment_number DESC, update_time DESC, create_time DESC, id DESC')
wrapper=read(base/'wrapper.sql')
wrapper=once(wrapper,"WHERE SAFE.PARSE_DATE('%d%m%Y', interface.OrderDate) >= DATE '2026-01-01'",'WHERE TRUE -- Payment recency belongs to the receipt gate, not order creation year.')
wrapper=once(wrapper,'source.PaymentDate DESC',"SAFE.PARSE_DATE('%d%m%Y', source.PaymentDate) DESC,\n          TO_JSON_STRING(source) DESC")
# Preserve existing cancellation, product and immutable SAP payload rules.
for name,q in [('RCL_05_newpayment',new),('RCL_05_paid_by_period',gate),('RCL_Motor_process_2_newpayment',wrapper)]:
 (out/(name+'.sql')).write_text('-- 2026-09-27 downstream candidate; SELECT only, NOT DEPLOYED.\n'+q+';\n',encoding='utf-8')
# Keep producer and diagnostic classifications byte-identical.
prefix=new.split('SELECT DISTINCT\n  interface.CompanyDB',1)[0]
(tests/'lineage_diagnostics.sql').write_text(prefix+"""SELECT CURRENT_TIMESTAMP() AS checked_at_utc, OrderID,OrderItem,Period,InvoiceNo,ActualReceived,
CASE WHEN source_event_rows IS NULL THEN 'RCL_MISSING_PAID_RECEIPT_LINEAGE'
WHEN source_event_rows > 1 THEN 'RCL_AMBIGUOUS_RECEIPT_LINEAGE'
WHEN NOT additional_identity_valid THEN 'RCL_INVALID_ADDITIONAL_IDENTITY'
ELSE 'RCL_INVALID_ADDITIONAL_SHAPE' END AS rule_code
FROM interface WHERE (source_event_rows IS NULL AND COALESCE(ActualReceived,0)!=0)
OR source_event_rows>1 OR (source_charge_rank>1 AND (NOT additional_identity_valid OR NOT has_additional_shape));
""",encoding='utf-8')
def subst(s,sap):
 for real,fixture in [('sap_data_engineer.sap_dashboard_carepay_installment','fixture_dashboard'),('sap_integration_v2.SAP_LIVE_FULL',sap),('careos.carepay_charges','fixture_charges'),('careos.careos_orders','fixture_orders'),('careos.careos_order_items','fixture_order_items')]:s=s.replace('`pacific-plating-282708.'+real+'`',fixture)
 return s
fixture=read('sql/adhoc/20260926_rcl_additional_identity_fixtures.sql')
old=read('sql/production/rcl_additional_20260926/RCL_05_newpayment.sql')
# Per-case execution proves both membership/replay and the runtime assertion.
fixture_prefix=fixture.split('), actual AS (',1)[0]+')'
setup=fixture_prefix+' SELECT 1'
# Materialize fixture CTEs once, then isolate each OrderItem (same real query seam).
script=''
for table in ['fixture_charges','fixture_orders','fixture_order_items','fixture_dashboard','fixture_sap']:
 script+='CREATE TEMP TABLE '+table.replace('fixture_dashboard','all_dashboard')+' AS '+fixture_prefix+' SELECT * FROM '+table+';\n'
expected=fixture.split('), expected AS (',1)[1].split(')\n',1)[0].strip()
script+='CREATE TEMP TABLE expected AS '+expected+';\nCREATE TEMP TABLE verdicts (OrderItem STRING, should_emit BOOL, emitted INT64, replayed INT64, error STRING);\n'
script+="""FOR c IN (SELECT OrderItem,should_emit FROM expected) DO
 BEGIN
 CREATE OR REPLACE TEMP TABLE fixture_dashboard AS SELECT * FROM all_dashboard WHERE OrderItem=c.OrderItem;
 CREATE OR REPLACE TEMP TABLE actual AS """+subst(new,'fixture_sap')+""";
 CREATE OR REPLACE TEMP TABLE sap_after_posting AS SELECT U_OrderItem,U_Period,U_InvoiceNo,TransactionStatus FROM fixture_sap
 UNION ALL SELECT OrderItem,Period,InvoiceNo,TransactionStatus FROM actual;
 CREATE OR REPLACE TEMP TABLE replay AS """+subst(new,'sap_after_posting')+""";
 INSERT verdicts SELECT c.OrderItem,c.should_emit,(SELECT COUNT(*) FROM actual),(SELECT COUNT(*) FROM replay),NULL;
 EXCEPTION WHEN ERROR THEN
 INSERT verdicts VALUES(c.OrderItem,c.should_emit,NULL,NULL,@@error.message);
 END;
END FOR;
SELECT * FROM verdicts ORDER BY OrderItem;
"""
(tests/'receipt_fixtures.sql').write_text(script,encoding='utf-8')
(base/'candidate_hashes.json').write_text(json.dumps({p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in out.glob('*.sql')},indent=2))
print('Built downstream candidates, lineage diagnostics and 26 per-case real-query fixtures.')
