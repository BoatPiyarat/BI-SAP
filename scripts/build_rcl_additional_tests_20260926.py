from pathlib import Path
import json
import runpy
runpy.run_path('scripts/build_rcl_additional_fix_20260926.py')
fields=json.loads(Path('docs/evidence/rcl_additional_20260926/column_contract.json').read_text())
cases=[
 ('new_period',2,'n2',100,100,'paid',True),
 ('gap_period',2,'g2',100,100,'paid',True),
 ('compulsory_zero_first_missing_invoice',1,None,0,10,'paid',True),
 ('compulsory_first_missing_invoice',1,None,100,100,'paid',True),
 ('zero_first_missing_invoice',1,'2_zero_first_missing_invoice-V1',0,10,'paid',True),
 ('zero_first_tied',1,'2_zero_first_tied',0,10,'paid',True),
 ('invalid_extra_pending',1,'2_invalid_extra_pending-V1',0,10,'Pending',False),
 ('zero_expected_first_paid',1,'2_zero_first_paid',0,10,'paid',False),
 ('zero_expected_first_new',1,'2_zero_first_new',0,10,'paid',True),
 ('topup',1,'2_extra',0,22.04,'paid',True),
 ('exact_paid',1,'2_exact',0,10,'paid',False),
 ('raw_paid',1,'2_raw',0,10,'paid',False),
 ('cancelled',1,'2_cancelled',0,10,'paid',False),
 ('change_cancelled',1,'2_change',0,10,'paid',False),
 ('blank',1,'',0,10,'paid',False),
 ('null_invoice',1,None,0,10,'paid',False),
 ('literal_null',1,'NULL',0,10,'paid',False),
 ('normal_paid',1,'normal',100,100,'paid',False),
 ('other_item',1,'2_shared',0,10,'paid',True),
 ('other_period',2,'p2',0,10,'paid',True),
 ('period2_prefix',2,'2_p2raw',0,10,'paid',True),
 ('missing_raw',1,'2_missing_raw-V1',0,10,'paid',False),
 ('collision',1,'2_collision',0,10,'paid',False),
 ('tie',1,'2_tie',0,10,'paid',False),
 ('null_expected',1,'2_null_exp',None,10,'paid',False),
 ('pending_not_topup',1,'2_pending',0,10,'Pending',False),
]
def lit(x):
 if x is None:return 'NULL'
 if isinstance(x,str):return "'"+x.replace("'","''")+"'"
 return str(x)
fixture=[]
for name,period,inv,expected,actual,status,want in cases:
 vals={'OrderID':name,'OrderItem':name+'-V1','Period':period,'TotalPeriods':3,'InvoiceNo':inv,'ExpectedReceived':expected,'ActualReceived':actual,'TransactionStatus':status,'PaymentDate':'26092026'}
 types={'INTEGER':'INT64','FLOAT':'FLOAT64','STRING':'STRING','NUMERIC':'NUMERIC'}
 fixture.append('SELECT '+', '.join('CAST('+lit(vals.get(f['name']))+' AS '+types.get(f['type'],f['type'])+') AS '+f['name'] for f in fields))
sap=[]
for name,period,inv,expected,actual,status,want in cases:
 if name in ['new_period','zero_expected_first_new','zero_first_missing_invoice','zero_first_tied','invalid_extra_pending','compulsory_zero_first_missing_invoice','compulsory_first_missing_invoice']:continue
 terminal_inv={'exact_paid':'2_exact','raw_paid':'raw','cancelled':'2_cancelled','change_cancelled':'2_change','normal_paid':'normal'}.get(name,'old')
 terminal_status={'cancelled':'Cancelled','change_cancelled':'Cancelled (Change order / Rejected)'}.get(name,'Paid')
 sap.append('SELECT '+lit(name+'-V1')+' AS U_OrderItem, '+str(3 if name=='gap_period' else period)+' AS U_Period, '+lit(terminal_inv)+' AS U_InvoiceNo, '+lit(terminal_status)+' AS TransactionStatus')
sap += ["SELECT 'elsewhere-V1',1,'2_shared','Paid'","SELECT 'other_period-V1',1,'p2','Paid'","SELECT 'period2_prefix-V1',2,'p2raw','Paid'"]
body=Path('sql/production/rcl_additional_20260926/RCL_05_newpayment.sql').read_text(encoding='utf-8').strip().rstrip(';')

raw=[]; orders=[]; items=[]
for name,period,inv,ex,ac,status,want in cases:
 raw_inv=inv[2:] if inv and period==1 and inv.startswith('2_') else inv
 if name in ['missing_raw','zero_first_missing_invoice','invalid_extra_pending','compulsory_zero_first_missing_invoice','compulsory_first_missing_invoice']:raw_inv=None
 raw.append('SELECT '+lit(name)+' AS id, '+lit(name)+' AS transaction_id, '+str(period)+' AS installment_number, '+lit(raw_inv)+' AS third_party_id, \'SUCCESSFUL\' AS status, \'RABBIT_LENDING\' AS service_provider, TIMESTAMP \'2026-09-25\' AS create_time, CURRENT_TIMESTAMP() AS update_time')
 orders.append('SELECT '+lit(name)+' AS id, '+lit('transactions/'+name)+' AS payment')
 items.append('SELECT '+lit(name)+' AS order_id, '+lit(name+'-V1')+' AS human_id, '+lit('MOTOR_TYPE_COMPULSORY' if name.startswith('compulsory_') else 'MOTOR_TYPE_VOLUNTARY')+' AS motor_item_type')
 if name not in ['new_period','gap_period','normal_paid','zero_expected_first_paid','zero_expected_first_new','zero_first_missing_invoice','zero_first_tied','compulsory_zero_first_missing_invoice','compulsory_first_missing_invoice']:
  raw.append('SELECT '+lit(name+'-first')+', '+lit(name)+', '+str(period)+', '+lit('prior_'+name)+", 'SUCCESSFUL', 'RABBIT_LENDING', TIMESTAMP '2026-09-24', CURRENT_TIMESTAMP()")
 if name in ['collision','tie','zero_first_tied']:
  extra_inv='different' if name in ['tie','zero_first_tied'] else raw_inv
  raw.append('SELECT '+lit(name+'-other')+', '+lit(name)+', '+str(period)+', '+lit(extra_inv)+", 'SUCCESSFUL', 'RABBIT_LENDING', TIMESTAMP '2026-09-25', CURRENT_TIMESTAMP()")
def query(sapname):
 q=body.replace('`pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_installment`','fixture_dashboard').replace('`pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`',sapname)
 for name in ['charges','orders','order_items']:
  tab={'charges':'carepay_charges','orders':'careos_orders','order_items':'careos_order_items'}[name]
  q=q.replace('`pacific-plating-282708.careos.'+tab+'`','fixture_'+name)
 return q
q='WITH fixture_charges AS (\n'+'\nUNION ALL\n'.join(raw)+'\n), fixture_orders AS (\n'+'\nUNION ALL\n'.join(orders)+'\n), fixture_order_items AS (\n'+'\nUNION ALL\n'.join(items)+'\n), fixture_dashboard AS (\n'+'\nUNION ALL\n'.join(fixture)+'\n), fixture_sap AS (\n'+'\nUNION ALL\n'.join(sap)+'\n), actual AS (\n'+query('fixture_sap')+'\n), sap_after_posting AS (\nSELECT U_OrderItem,U_Period,U_InvoiceNo,TransactionStatus FROM fixture_sap UNION ALL SELECT OrderItem,Period,InvoiceNo,TransactionStatus FROM actual\n), replay AS (\n'+query('sap_after_posting')+'\n), expected AS (\n'+' UNION ALL '.join('SELECT '+lit(name+'-V1')+' AS OrderItem, '+str(want).upper()+' AS should_emit' for name,_,_,_,_,_,want in cases)+'\n)\n'
q+="""
SELECT CURRENT_TIMESTAMP() AS checked_at_utc,
 (SELECT COUNT(*) FROM expected) AS cases,
 (SELECT COUNT(*) FROM actual) AS emitted_rows,
 (SELECT COUNT(*) FROM expected e WHERE e.should_emit != EXISTS(SELECT 1 FROM actual a WHERE a.OrderItem=e.OrderItem)) AS membership_failures,
 (SELECT COUNT(*) FROM replay) AS replay_rows_after_posting,
 (SELECT COUNT(*) FROM (SELECT OrderItem,Period,InvoiceNo FROM actual GROUP BY 1,2,3 HAVING COUNT(*)>1)) AS duplicate_event_keys;
"""
Path('sql/adhoc/20260926_rcl_additional_identity_fixtures.sql').write_text(q,encoding='utf-8')
print('Generated',len(cases),'behavioral fixture cases with acknowledged-payment replay.')
