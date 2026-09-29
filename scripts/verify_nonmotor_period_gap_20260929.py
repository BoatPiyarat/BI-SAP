"""Verify immutable gap-fix evidence; never writes an interface CSV on a failed gate."""
import json, sys, hashlib
from pathlib import Path
from collections import defaultdict
root=Path(sys.argv[1])
def read(name): return json.loads((root/name).read_text(encoding='utf-8-sig'))
rows=read('release_rows.json')
old=read('comparison_rows.json')
meta=read('candidate_metadata.json')
original=read('before_newpayment.json')
names=[x['name'] for x in original['schema']['fields']]
assert [(x['name'],x['type']) for x in meta['schema']['fields']]==[(x['name'],x['type']) for x in original['schema']['fields']]
groups=defaultdict(list)
for row in rows: groups[row['OrderItem']].append(row)
for item, rs in groups.items():
    totals={int(r['TotalPeriods']) for r in rs}
    assert len(totals)==1, item
    n=next(iter(totals))
    assert sorted(int(r['Period']) for r in rs)==list(range(1,n+1)), item
    assert all(r['TransactionStatus'] in ('Paid','Pending') for r in rs), item
for item, period, n in [('L79180940-1',5,8),('L79949677-1',4,10)]:
    assert len(groups[item])==n
    assert any(int(r['Period'])==period and r['TransactionStatus']=='Paid' for r in groups[item])
oldpaid=[r for r in old if r['variant']=='before' and r['OrderItem'] in groups and r['TransactionStatus'].lower()=='paid']
for r in oldpaid:
    assert any(x['InvoiceNo']==r['InvoiceNo'] and float(x['ActualReceived'])==float(r['ActualReceived']) and int(x['Period'])==int(r['Period']) for x in groups[r['OrderItem']])
evidence=[dict(source=x['source'], **json.loads(x['payload'])) for x in read('target_reconcile.json')]
targets=[r for r in rows if r['OrderItem'] in ('L79180940-1','L79949677-1')]
for r in targets:
    if r['TransactionStatus']!='Paid': continue
    sap=[x for x in evidence if x['source']=='sap' and x['item']==r['OrderItem'] and int(x['period_no'])==int(r['Period']) and x['status'].lower()=='paid']
    charge=[x for x in evidence if x['source']=='charges' and x['item']==r['OrderItem'] and int(x['period_no'])==int(r['Period'])]
    if sap: assert any(x['invoice']==r['InvoiceNo'] and float(x['actual'])==float(r['ActualReceived']) for x in sap)
    else: assert len(charge)==1 and charge[0]['canonical_invoice']==r['InvoiceNo'] and float(charge[0]['actual'])==float(r['ActualReceived'])
issues=[]
for r in targets:
    for name in names:
        if r[name] is None or str(r[name]).strip().upper()=='NULL': issues.append({'item':r['OrderItem'],'period':int(r['Period']),'rule':'NULL_VALUE','field':name})
locks=[json.loads(x['payload']) for x in read('control_inputs.json') if x['source']=='period_lock']
if not any(x['period']=='2026-09' and x['locked_at'] is None for x in locks): issues.append({'rule':'SEPTEMBER_PERIOD_UNCONFIRMED'})
result={'sql_regression':'PASS','rows':len(rows),'items':len(groups),'historical_paid_rows_preserved':len(oldpaid),'target_rows':len(targets),'target_invoice_amount_reconciliation':'PASS','candidate_sha256':hashlib.sha256((root/'release_rows.json').read_bytes()).hexdigest(),'export_gate':'BLOCK' if issues else 'PARTIAL_CHECKS_PASS','issues':issues,'csv_written':False,'note':'No CSV writer invoked. Additional canonical gates/review required before release.'}
(root/'validation_result.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps({k:v for k,v in result.items() if k!='issues'}))
print('Export blocking issues:',len(issues))
