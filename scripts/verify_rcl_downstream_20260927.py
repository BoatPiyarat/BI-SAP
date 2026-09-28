"""Offline verification of captured downstream test results; no cloud access."""
import hashlib,json
from pathlib import Path
p=Path('docs/evidence/rcl_downstream_20260927')
def read(n):return json.loads((p/n).read_text(encoding='utf-8-sig'))
f=read('fixtures_final_132_result.json');assert len(f)==26
errors={'blank-V1','literal_null-V1','null_invoice-V1'}
for x in f:
 if x['OrderItem'] in errors:
  assert (x['error'] or '').startswith('Query error: RCL_MISSING_PAID_RECEIPT_LINEAGE:'),x
 else:
  assert not x['error'],x
  assert (str(x['should_emit']).lower()=='true')==(int(x['emitted'])>0),x
  assert int(x['replayed'])==0,x
for x in read('gate_fixtures.json'):assert x['want']==x['observed'],x
assert len(read('gate_fixtures.json'))==5
m=read('final_3_result.json')[0]
for n in ['removed_wrapper_payloads','removed_newpayment_payloads','duplicate_event_keys','incomplete_spines']:assert int(m[n])==0,(n,m[n])
for oid,amount in [('L80570054',22.04),('L79109956',645.21)]:
 assert any(r['OrderID']==oid and float(r['ExpectedReceived'])==0 and float(r['ActualReceived'])==amount for r in m['target_rows'])
for x in read('schema_comparison.json'):assert x['names_order_types_equal'],x
risk=read('consumer_risks_1_result.json')[0]
assert int(risk['old_paid_not_verbatim_sap_context'])==0
assert not risk['live_create_issues']
# Bind the final executed script to exact production candidates after only table-reference substitution.
job=read('final_job.json');assert job['status']=={'state':'DONE'}
executed=job['configuration']['query']['query']
cache='pacific-plating-282708._script7c6faf4dc1f287623ae26f66d20de48b274328dd'
refs={'sap_integration_v2.SAP_LIVE_FULL':f'`{cache}.evidence_sap`','sap_data_engineer.sap_dashboard_carepay_installment':f'`{cache}.live_dashboard`','sap_integration_v2.RCL 05_paid':f'`{cache}.evidence_paid`','sap_integration_v2.RCL 05_newpayment':'candidate_newpayment','sap_integration_v2.RCL 05_paid by period':'candidate_gate'}
for name,digest in read('candidate_hashes.json').items():
 source=Path('sql/production/rcl_downstream_20260927')/name
 assert hashlib.sha256(source.read_bytes()).hexdigest()==digest,name
 s=source.read_text(encoding='utf-8').strip().rstrip(';')
 for a,b in refs.items():s=s.replace('`pacific-plating-282708.'+a+'`',b)
 assert s in executed,'Final job does not bind source '+name
print('PASS: 26 receipt scenarios; 5 eligibility scenarios; exact-source binding; schemas; payload parity; targets; SAP-context preservation.')
print('DEPLOYMENT BLOCKED: '+str(len(risk['additional_principal_review']))+' later-period principal mappings; import idempotency and operational holds are not proven by these tests.')
