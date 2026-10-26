import json
from pathlib import Path
from decimal import Decimal
base = Path(__file__).resolve().parents[1] / 'docs/evidence/rcl_same_period_20260925'
def read(name):
    return json.loads((base / ('rcl_same_period_' + name + '_20260925.json')).read_text(encoding='utf-8'))
src, dashboard, sap, probe = [read(n) for n in ['source','dashboard','sap','rank_probe']]
assert read('newpayment') == [], 'Wrapper no longer empty; re-evaluate finding'
missing = {'L80570054':'22.04', 'L79109956':'645.21'}
for order, amount in missing.items():
    charges = sorted([r for r in src if r['OrderID']==order and r['charge_status']=='SUCCESSFUL'], key=lambda r:r['create_time'])
    assert len(charges)==2 and all(r['Period']=='1' for r in charges)
    event=charges[1]
    assert Decimal(event['amount_thb']) == Decimal(amount)
    identities={event['raw_invoice_no'], '2_'+event['raw_invoice_no']}
    assert not any(r['OrderID']==order and r['InvoiceNo'] in identities for r in dashboard)
    assert not any(r['OrderID']==order and r['InvoiceNo'] in identities for r in sap)
    recovered=[r for r in probe if r['OrderItem']==order+'-V1' and r['InvoiceNo'] in identities]
    assert len(recovered)==1
    assert Decimal(recovered[0]['ExpectedReceived'])==0
    assert Decimal(recovered[0]['ActualReceived'])==Decimal(amount)
    assert any(r['OrderItem']==order+'-V1' and r['Period']=='1' and r['TransactionStatus'].lower()=='paid' for r in sap)
    print(order+': missing from live dashboard/mirror; SELECT-only probe recovers '+amount+'; period-only gate blocks')
keys=['OrderID','OrderItem','Period','InvoiceNo','TransactionStatus','ExpectedReceived','ActualReceived','PaymentDate']
old=[tuple(r.get(k) for k in keys) for r in dashboard if r['Period']=='1']
new=[tuple(r.get(k) for k in keys) for r in probe]
assert all(new.count(row)==old.count(row) for row in set(old)), 'Existing first-payment row changed'
assert len(new)==len(old)+2
print('PASS: 2 missing additional events reproduced; exactly 2 recovered; original period-1 rows unchanged')

