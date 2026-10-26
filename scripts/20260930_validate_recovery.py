"""Validate immutable live-view recovery snapshots. No upload; no business-value repairs.
Required-value failures quarantine the entire OrderItem. Run from SAP repo root.
"""
import json,collections,hashlib,datetime,csv
from decimal import Decimal,InvalidOperation
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]; META=ROOT/'.tmp-bq/20260930'; DATA=Path('C:/dev/sap-recovery-20260930')
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def dec(x):return Decimal(str(x))
def aliases(inv,flow,period):
 return {inv,inv[2:]} if flow=='RCL' and period==1 and inv.startswith('2_') else {inv}
cols=read(META/'live_columns.json'); contract=[x['column_name'] for x in sorted([x for x in cols if x['table_name']=='RCB_Motor_process_create'],key=lambda x:int(x['ordinal_position']))]
assert len(contract)==56
m=read(META/'missing_candidates.json'); prior=read(DATA/'membership.json'); prior_idx={(x['charge_id'],x['OrderItem'],x['Period'],x['InvoiceNo']):x for x in prior}
for x in m:x['covering_views']=prior_idx.get((x['charge_id'],x['OrderItem'],x['Period'],x['InvoiceNo']),{}).get('covering_views',[]);x['snapshot_state_drift']=(x['charge_id'],x['OrderItem'],x['Period'],x['InvoiceNo']) not in prior_idx
source=read(META/'source_candidate_evidence.json');sap=read(META/'sap_candidate_evidence.json');masters=read(META/'accepted_mappings.json')
source_by_item=collections.defaultdict(list);sap_by_item=collections.defaultdict(list)
for x in source:source_by_item[x['OrderItem']].append(x)
for x in sap:sap_by_item[x['OrderItem']].append(x)
payment_masters={(x['PaymentMethod'],x['PaymentChannel'],x['InsuranceGroup']) for x in masters}
insurer_masters={(str(x['InsurerCode']).rsplit('-',1)[-1],x['InsuranceGroup']) for x in masters}
view_rows={p.name.replace('.rows.json',''):read(p) for p in DATA.glob('*.rows.json')}
view_groups={}
for v,rows in view_rows.items():
 g=collections.defaultdict(list)
 for r in rows:g[r['OrderItem']].append(r)
 view_groups[v]=g
# Prefer owning view. Never choose a different conflicting transport merely because it passes.
selected={};uncovered=[]
for x in m:
 if not x['covering_views']:uncovered.append(x);continue
 priority=x['expected_legacy_view'].split(' / ')
 v=next((v for v in priority if v in x['covering_views']),x['covering_views'][0])
 selected.setdefault((v,x['OrderItem']),[]).append(x)
# Cross-item allocation checked using immutable primary RCB create view, once per source invoice.
rcb_alloc=collections.defaultdict(Decimal)
for r in view_rows.get('RCB_Motor_process_create',[]):
 try:rcb_alloc[str(r['InvoiceNo'])]+=dec(r['ActualReceived'])
 except InvalidOperation:pass
optional_null={'EndorsementNo','RefOrder'}
numeric=['GrossPremium','StampDuty','VAT','TotalPremium','WHT','TotalEIR','TotalSBT','ProcessingFee','ProcessingFeeVat','ShippingFee','ShippingFeeVat','TotalAmount','Discount','ExpectedReceived','ActualReceived','InterestThisPeriod','PrincipleThisPeriod','InterestEIRThisPeriod','PrincipleEIRThisPeriod','PendingPayment','RefundAmountBeforeFee','RefundAmountAfterFee']
required_nonblank=['CompanyDB','OrderID','OrderItem','InsuredID','FirstName','LastName','InsurerCode','InsuranceGroup','InsuranceType','InsuranceProduct','ProductType','PolicyType','PolicyNo']
run_date=datetime.date(2026,9,30);outcomes=[];ready=[]
for (v,item),obligations in sorted(selected.items()):
 rows=view_groups[v][item];reasons=set();flow=obligations[0]['expected_owner'];evidence=source_by_item[item]
 physical=[x['column_name'] for x in sorted([x for x in cols if x['table_name']==v],key=lambda x:int(x['ordinal_position']))]
 if physical!=contract:reasons.add('PHYSICAL_SCHEMA_MISMATCH')
 if any(x['snapshot_state_drift'] for x in obligations):reasons.add('SAP_STATE_DRIFT')
 if not evidence or any(x['lead_status']!='LEAD_STATUS_PURCHASED' for x in evidence):reasons.add('LEAD_NOT_PURCHASED')
 if any(x['is_cancelled'] in (True,'true') or x['cancel_time'] is not None for x in evidence):reasons.add('CANCELLED_LIFECYCLE')
 if 'creditshell' in v.lower() or 'change' in v.lower() or 'cancel' in v.lower():reasons.add('CHANGE_CREDITSHELL_PREDECESSOR_REVIEW_REQUIRED')
 if flow=='RCB' and sap_by_item[item]:reasons.add('EXISTING_SAP_ITEM_REQUIRES_EVENT_REVIEW')
 periods=[];totals=[];keys=[];serialized=[]
 for raw in rows:
  r=dict(raw);status=str(r['TransactionStatus']);pending=status=='Pending'
  # CSV's canonical empty representation for documented optional and Pending payment fields.
  for k in optional_null:
   if r[k] is None:r[k]=''
  if pending:
   for k in ('InvoiceNo','PaymentDate'):
    if r[k] is None:r[k]=''
  for k,val in r.items():
   if val is None or str(val).strip().upper()=='NULL':reasons.add('REQUIRED_NULL:'+k)
  for k in required_nonblank:
   if not str(r[k] or '').strip():reasons.add('REQUIRED_BLANK:'+k)
  if str(r['CompanyDB'])!='RCB':reasons.add('COMPANY_CODE')
  if any(str(r[k] or '').strip().lower()=='test' for k in ['FirstName','LastName']):reasons.add('TEST_CUSTOMER')
  if len(str(r['PolicyNo'] or ''))>50 or len(str(r['InvoiceNo'] or ''))>30 or len(str(r['OrderItem']))>30:reasons.add('IDENTIFIER_LENGTH')
  try:
   period=int(r['Period']);total=int(r['TotalPeriods']);periods.append(period);totals.append(total)
  except (ValueError,TypeError):reasons.add('INVALID_PERIOD');continue
  keys.append((period,str(r['InvoiceNo'] or '')))
  if flow=='RCL' and status not in ('Paid','Pending'):reasons.add('RCL_STATUS_NOT_CANONICAL')
  if flow=='RCB' and status not in ('Paid','paid'):reasons.add('RCB_STATUS_INVALID')
  if flow=='RCB' and (period!=1 or total!=1):reasons.add('RCB_NOT_ONETIME')
  if pending:
   if any(str(r[k] or '')!='' for k in ['InvoiceNo','PaymentDate','PaymentMethod','PaymentChannel']):reasons.add('PENDING_PAYMENT_FIELDS')
  else:
   if any(not str(r[k] or '').strip() for k in ['InvoiceNo','PaymentDate','PaymentMethod','PaymentChannel']):reasons.add('PAID_COMPLETENESS')
   if not str(r['PaymentChannel'] or '').startswith(flow):reasons.add('FLOW_MISMATCH')
   if (r['PaymentMethod'],r['PaymentChannel'],r['InsuranceGroup']) not in payment_masters:reasons.add('PAYMENT_MASTER_UNVERIFIED')
   if 'EDC' in str(r['PaymentChannel']) and r['PaymentChannel']!='RCB-EDC-KBANK':reasons.add('EDC_BANK_UNAPPROVED')
  if (str(r['InsurerCode']),r['InsuranceGroup']) not in insurer_masters:reasons.add('INSURER_MASTER_UNVERIFIED')
  dates={}
  for k in ['OrderDate','PolicyDate','PaymentDate','ExpectedDate','BatchRunDate']:
   val=str(r[k] or '')
   if k=='PaymentDate' and pending and not val:continue
   try:
    assert len(val)==8 and val.isdigit();dates[k]=datetime.datetime.strptime(val,'%d%m%Y').date()
   except (AssertionError,ValueError):reasons.add('INVALID_DATE:'+k)
  if 'OrderDate' in dates and 'PolicyDate' in dates and max(dates['OrderDate'],dates['PolicyDate']).year!=2026:reasons.add('POLICY_YEAR_NOT_2026')
  if dates.get('BatchRunDate')!=run_date:reasons.add('BATCH_DATE_NOT_RUN_DATE')
  carried_paid=any(int(z['Period'])==period and z['InvoiceNo']==r['InvoiceNo'] and str(z['TransactionStatus']).lower()=='paid' for z in sap_by_item[item])
  if not pending and not carried_paid and 'PaymentDate' in dates and not datetime.date(2026,9,1)<=dates['PaymentDate']<=run_date:reasons.add('NEW_PAYMENT_OUTSIDE_CURRENT_MONTH')
  for k in numeric:
   try:
    d=dec(r[k]);assert d.is_finite();assert d==d.quantize(Decimal('.01'))
   except (InvalidOperation,AssertionError):reasons.add('INVALID_NUMERIC:'+k)
  if flow=='RCB':
   try:
    if dec(r['TotalEIR'])!=0:reasons.add('RCB_EIR_NONZERO')
    if abs(dec(r['ExpectedReceived'])-dec(r['ActualReceived']))>Decimal('10'):reasons.add('PAYMENT_AMOUNT_VARIANCE')
   except InvalidOperation:pass
  serialized.append(r)
 if len(keys)!=len(set(keys)):reasons.add('DUPLICATE_EVENT_KEY')
 if len(set(totals))!=1 or not totals or set(periods)!=set(range(1,max(totals)+1)):reasons.add('INCOMPLETE_SPINE')
 if flow=='RCL' and len(periods)!=len(set(periods)):reasons.add('MULTIPLE_EVENTS_PER_PERIOD_REQUIRES_REVIEW')
 # New obligations must match exactly one source charge; never release an event inferred from period alone.
 for x in obligations:
  rawinv=x['InvoiceNo'][2:] if flow=='RCL' and x['Period']==1 and x['InvoiceNo'].startswith('2_') else x['InvoiceNo']
  ev=[e for e in evidence if e['charge_id']==x['charge_id'] and e['third_party_id']==rawinv]
  if len(ev)!=1:reasons.add('SOURCE_EVENT_IDENTITY')
  if any(e['charge_id']!=x['charge_id'] and e['third_party_id']==rawinv for e in evidence):reasons.add('DUPLICATE_SOURCE_INVOICE')
  if any(s['InvoiceNo'] in aliases(x['InvoiceNo'],flow,x['Period']) and int(s['Period'])==x['Period'] for s in sap_by_item[item]):reasons.add('SAP_RECEIPT_ALREADY_PRESENT')
  if flow=='RCB' and ev:
   if abs(rcb_alloc[rawinv]-dec(ev[0]['amount'])/100)>Decimal('.01'):reasons.add('CHARGE_ALLOCATION_NOT_CONSERVED')
 if flow=='RCL':
  # All immutable carried Paid receipts must retain stored invoice and amount.
  for r in rows:
   if r['TransactionStatus']!='Paid':continue
   exact=[s for s in sap_by_item[item] if int(s['Period'])==int(r['Period']) and s['InvoiceNo']==r['InvoiceNo'] and str(s['TransactionStatus']).lower()=='paid']
   if exact and any(dec(s['ActualReceived'])!=dec(r['ActualReceived']) for s in exact):reasons.add('CARRIED_SAP_AMOUNT_CHANGED')
 outcome={'view':v,'OrderItem':item,'flow':flow,'rows':len(rows),'obligations':len(obligations),'status':'HOLD' if reasons else 'PASS','reasons':sorted(reasons)}
 outcomes.append(outcome)
 if not reasons:ready.append({'view':v,'OrderItem':item,'flow':flow,'rows':serialized,'obligations':obligations})
(DATA/'validation_outcomes.json').write_text(json.dumps(outcomes,indent=2),encoding='utf-8')
(DATA/'validated_candidates.json').write_text(json.dumps(ready,ensure_ascii=False),encoding='utf-8')
(DATA/'membership_final.json').write_text(json.dumps(m,indent=2),encoding='utf-8')
print('views',collections.Counter((x['view'],x['status']) for x in outcomes))
print('holds',collections.Counter(r for x in outcomes for r in x['reasons']))
print('PASS items',len(ready),'rows',sum(len(x['rows']) for x in ready),'obligations',sum(len(x['obligations']) for x in ready))
print('uncovered',len(uncovered),'source/SAP drift',sum(x['snapshot_state_drift'] for x in m))
