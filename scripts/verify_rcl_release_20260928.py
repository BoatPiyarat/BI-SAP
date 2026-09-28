"""Verify recorded preflight, four successful view replacements and live postcheck."""
from pathlib import Path
import json
from decimal import Decimal
p=Path('docs/evidence/rcl_downstream_deploy_20260928')
def read(n):return json.loads((p/n).read_text(encoding='utf-8-sig'))
def normalized(s):
 lines=s.strip().rstrip(';').splitlines()
 while lines and (not lines[0].strip() or lines[0].lstrip().startswith('--')):lines.pop(0)
 return '\n'.join(lines).split()
m=read('preflight_11_result.json')[0]
for k in ['additional_principal_mismatches','duplicate_event_keys','incomplete_spines','removed_first_receipt_payloads','removed_nonprincipal_dashboard_payloads','removed_wrapper_payloads']:assert int(m[k])==0,(k,m[k])
assert all(x['names_types_order_match'] for x in read('schema_preflight.json'))
results=read('deployment_results.json');assert len(results)==4
for x in results:assert x['status']=='DONE' and x['definition_matches'] and x['schema_matches'],x
for name in ['dashboard','newpayment','gate','wrapper']:
 assert read(name+'_deploy_job.json')['status']=={'state':'DONE'}
 after=read(name+'_after.json');before=read(name+'_before.json')
 assert [(f['name'],f['type']) for f in after['schema']['fields']]==[(f['name'],f['type']) for f in before['schema']['fields']]
 ddl=(p/(name+'_deploy.sql')).read_text(encoding='utf-8').split(' AS\n',1)[1].strip().rstrip(';')
 assert normalized(after['view']['query'])==normalized(ddl)
assert read('postcheck_job.json')['status']=={'state':'DONE'}
a=read('postcheck_result.json')[0]
for k in ['duplicate_event_keys','incomplete_spines','target_principal_failures']:assert int(a[k])==0,(k,a[k])
for k in read('principal_target_keys.json'):
 match=[r for r in a['principal_targets'] if r['OrderItem']==k['OrderItem'] and int(r['Period'])==k['Period'] and r['InvoiceNo']==k['InvoiceNo']]
 assert len(match)==1,k
 r=match[0];assert Decimal(r['ActualReceived'])==Decimal(k['ActualReceived'])==Decimal(r['PrincipleThisPeriod'])==Decimal(r['PrincipleEIRThisPeriod'])
 assert Decimal(r['ExpectedReceived'])==0
for oid,amount in [('L80570054','22.04'),('L79109956','645.21')]:
 assert any(r['OrderID']==oid and Decimal(r['ActualReceived'])==Decimal(amount) for r in a['emitted_reported_extras'])
print('PASS: four live definitions/schemas, successful DDL jobs, zero live duplicate/spine/principal failures, 10 principal targets and both reported extras.')
print('View deployment verified. SAP file import/posting is not asserted.')
