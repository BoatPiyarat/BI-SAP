"""Offline, reproducible join of the fixed monthly missing population to captured sap_view outputs.
Identity/status presence is NOT payload validity, scheduling, delivery, or SAP acknowledgement.
"""
from pathlib import Path
import csv,json,collections
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'docs/evidence/careos_scenario_routes_20260926'
OLD=ROOT/'docs/evidence/careos_month_audit_20260926'
def read(name):return json.loads((OUT/name).read_text(encoding='utf-8'))
def yes(value):return str(value).lower()=='true'
def csv_write(name, rows):
 with (OUT/name).open('w',encoding='utf-8-sig',newline='') as f:
  w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
rows=[]
for name in ['paid_missing.csv','cancellation_missing.csv']:
 with (OLD/name).open(encoding='utf-8-sig',newline='') as f:rows+=list(csv.DictReader(f))
assert len(rows)==1525
status=read('execution_status.json')
assert len(status)==10 and all(x['returncode']==0 for x in status)
outputs=[]
for x in status:outputs+=read(x['view']+'.result.json')
for x in read('cancel_cached_output.json'):
 outputs.append(dict(source_view=x['source_view'],OrderItem=x['OrderItem'],period=x['period'],invoice_no=x['invoice_no'],output_status=x['TransactionStatus'].lower(),OrderID=None,RefOrder=None))
byitem=collections.defaultdict(list)
for x in outputs:byitem[x['OrderItem']].append(x)
dims={x['order_item']:x for x in read('source_dimensions.json')}
gates={(x['charge_id'],x['order_item']):x for x in read('rcl_gate_diagnostic.json')}
cancel_gates={x['order_item']:x for x in read('cancel_gate_diagnostic.json')}
for a in rows:
 d=dims.get(a['order_item'],{});a['order_created_at']=d.get('order_created_at','');a['source_insurer']=d.get('source_insurer','')
 invs=json.loads(a['candidate_invoice_nos'])
 same=byitem[a['order_item']];period=[o for o in same if str(o['period'])==a['installment_period']]
 identity=[o for o in period if (o['invoice_no'] in invs if a['event_type']=='PAID' else (o['invoice_no'] or '')==a['raw_invoice_no'])]
 matching=[o for o in identity if o['output_status']=='paid'] if a['event_type']=='PAID' else [o for o in identity if o['output_status'].startswith('cancelled')]
 for key,data in [('sap_view_item_routes',same),('sap_view_period_routes',period),('sap_view_identity_routes',identity),('sap_view_matching_event_routes',matching)]:a[key]='|'.join(sorted({o['source_view'] for o in data}))
 a['sap_view_output_invoices']='|'.join(sorted({o['invoice_no'] or '<BLANK>' for o in period}))
 a['sap_view_coverage']='EVENT_IDENTITY_PRESENT' if matching else ('NO_CAREOS_ORDER' if a['reason_code']=='NO_CAREOS_ORDER' else 'EVENT_ABSENT')
 if a['event_type']=='CANCELLATION':a['scenario']='CANCEL_'+('PARTIAL_RETRY' if a['reason_code']=='CANCEL_PARTIALLY_APPLIED' else 'MULTI_RECEIPT_PERIOD' if a['reason_code']=='CANCEL_MULTIPLE_ROWS_SAME_PERIOD' else 'NO_SAP_PREDECESSOR' if a['reason_code']=='CANCEL_CREATE_MISSING_IN_SAP' else 'CHANGE_ORDER' if yes(a['is_change_order_old']) else 'STANDARD')
 else:a['scenario']='CHANGE_ORDER_RECEIPT' if yes(a['is_change_order_new']) else 'SAME_PERIOD_ADDITIONAL' if int(a['period_charge_rank'] or 0)>1 else 'NEW_ITEM_RECEIPT' if int(a['sap_item_rows'])==0 else 'SUBSEQUENT_INSTALLMENT' if int(a['installment_period'] or 0)>1 else 'EXISTING_ITEM_PERIOD1_RECEIPT'
 g=gates.get((a['charge_id'],a['order_item']),{});cg=cancel_gates.get(a['order_item'],{})
 a['latest_period_already_paid']=g.get('latest_period_already_paid','')
 a['event_period_already_paid']=g.get('event_period_already_paid','')
 a['cancel_stale_pending_paid']=cg.get('stale_pending_paid','')
 a['cancel_already_cancelled_flag']=cg.get('already_cancelled_flag','')
 if a['sap_view_coverage']=='NO_CAREOS_ORDER':root='UPSTREAM_NO_ORDER_LINK'
 elif matching:root='OUTPUT_IDENTITY_PRESENT_DELIVERY_NOT_PROVEN'
 elif a['event_type']=='CANCELLATION':
  if a['reason_code']=='CANCEL_CREATE_MISSING_IN_SAP':root='CANCEL_MISSING_CREATE_PREDECESSOR'
  elif a['reason_code']=='CANCEL_MULTIPLE_ROWS_SAME_PERIOD':root='CANCEL_COLLAPSES_RECEIPTS_TO_PERIOD'
  elif a['reason_code']=='CANCEL_PARTIALLY_APPLIED':root='CANCEL_ITEM_WIDE_ALREADY_CANCELLED_EXCLUSION'
  elif yes(cg.get('stale_pending_paid')):root='CANCEL_HOLD_UNSYNCED_SUCCESSFUL_PAYMENT'
  else:root='UNRESOLVED_CANCEL_ROUTE'
 elif yes(a['is_cancelled']):root='PAID_ON_CANCELLED_ITEM_REQUIRES_LIFECYCLE_REVIEW'
 elif a['flow']=='RCL' and a['business_type']=='Motor' and len(a['order_created_at'])>=10 and a['order_created_at'][:4].isdigit() and a['order_created_at'][:4]<'2026':root='RCL_MOTOR_ORDER_YEAR_2026_CUTOFF'
 elif a['flow']=='RCL' and a['business_type']=='NonMotor' and yes(a['is_change_order_new']):root='RCL_NONMOTOR_CREDITSHELL_FOLLOWUP_SOURCE_GAP'
 elif a['flow']=='RCL' and a['business_type']=='Motor' and yes(g.get('event_period_already_paid')):root='RCL_PAID_PERIOD_EXCLUDES_NEW_INVOICE'
 elif a['flow']=='RCB' and int(a['sap_item_rows'])>0:root='RCB_NO_EXISTING_ITEM_RECEIPT_ROUTE'
 else:root='UNRESOLVED_PAID_ROUTE'
 a['root_cause_group']=root
 a['blocker_attribution']='INVESTIGATION_SCENARIO_NOT_PROVEN_SINGLE_CAUSE' if root=='PAID_ON_CANCELLED_ITEM_REQUIRES_LIFECYCLE_REVIEW' else 'FIRST_APPLICABLE_OBSERVED_GROUP_NOT_EXHAUSTIVE'
 risks=[]
 for o in matching:
  flags=[]
  if a['event_type']=='PAID':
   if o.get('actual_received') is None:flags.append('PAID_ACTUAL_NULL')
   if o.get('expected_received') is None:flags.append('EXPECTED_NULL')
   channel=o.get('PaymentChannel') or ''
   if a['payment_method'] and a['payment_method']!='EDC' and channel=='RCB-EDC-KBANK':flags.append('SOURCE_NON_EDC_FORCED_TO_EDC_KBANK')
   if a['flow']=='RCL' and channel.startswith('RCB'):flags.append('RCL_SOURCE_IN_RCB_CHANNEL')
  if flags:risks.append({'view':o['source_view'],'invoice_no':o['invoice_no'],'flags':flags,'actual_received':o.get('actual_received'),'channel':o.get('PaymentChannel')})
 a['matching_output_risks']=json.dumps(risks,separators=(',',':'))
 a['matching_route_count']=len({o['source_view'] for o in matching})
 a['multiple_route_owners']=a['matching_route_count']>1
 a['identity_present_with_flagged_payload']=bool(risks)
 a['membership_limit']='Identity+status only; no scheduling/import or accounting allocation assertion. Cancellation does not prove per-DocEntry multiplicity.'
assert not any(x['root_cause_group'].startswith('UNRESOLVED') for x in rows)
assert sum(x['event_type']=='PAID' and x['sap_view_coverage']=='EVENT_ABSENT' for x in rows)==203
assert sum(x['event_type']=='CANCELLATION' and x['sap_view_coverage']=='EVENT_ABSENT' for x in rows)==50
csv_write('scenario_details.csv',rows)
csv_write('absent_from_sap_view.csv',[x for x in rows if x['sap_view_coverage']=='EVENT_ABSENT'])
csv_write('output_payload_review.csv',[x for x in rows if x['identity_present_with_flagged_payload'] or x['multiple_route_owners']])
groups=collections.defaultdict(list)
for a in rows:groups[(a['event_type'],a['root_cause_group'],a['flow'],a['business_type'])].append(a)
summary=[]
for k,v in sorted(groups.items()):
 x=dict(zip(['event_type','root_cause_group','flow','business_type'],k));x.update({'rows':len(v),'items':len({a['order_item'] for a in v if a['order_item']}),'charges':len({a['charge_id'] for a in v if a['charge_id']}),'examples':'|'.join(list(dict.fromkeys(a['order_item'] or a['transaction_id'] for a in v))[:3])});summary.append(x)
csv_write('scenario_summary.csv',summary)
(OUT/'scenario_summary.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
print(json.dumps(summary))
print('Paid payload-risk links',sum(x['event_type']=='PAID' and x['identity_present_with_flagged_payload'] for x in rows))
print('Multiple-route links',sum(x['multiple_route_owners'] for x in rows))
