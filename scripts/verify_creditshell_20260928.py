"""Verify final CreditShell candidate, execution binding and release invariants offline."""
from pathlib import Path
import json,hashlib
p=Path('docs/evidence/nonmotor_creditshell_20260928');out=Path('sql/production/nonmotor_creditshell_20260928')
def read(n):return json.loads((p/n).read_text(encoding='utf-8'))
def verify():
 j=read('release_preflight_job.json');assert j['status']=={'state':'DONE'}
 assert j['jobReference']['jobId']=='creditshell_preflight_20260928_004'
 query=j['configuration']['query']['query'];assert query.strip()==Path('sql/adhoc/20260928_nonmotor_creditshell/preflight.sql').read_text(encoding='utf-8').strip()
 assert int(j['statistics']['totalBytesProcessed'])<=21474836480
 hashes={}
 base=(p/'producer_before.sql').read_text(encoding='utf-8');marker='\nfinal AS (';idx=base.index(marker)+1
 candidate=(out/'producer.sql').read_text(encoding='utf-8');assert candidate[:candidate.index(marker)+1]==base[:idx]
 prefix=base[:idx];common=prefix[:prefix.rfind('),')+1]+'\nSELECT * FROM combined;';assert 'CREATE TEMP TABLE shared_combined AS\n'+common in query
 objects={'producer':'sap_integration_v2.RCL 04_new order credit shell','rcl_wrapper':'sap_view.RCL_Motor_process_4_creditshell','rcb_wrapper':'sap_view.RCB_Motor_process_4_creditshell'}
 for name,obj in objects.items():
  s=(out/(name+'.sql')).read_text(encoding='utf-8').strip().rstrip(';');hashes[name]=hashlib.sha256(s.encode()).hexdigest()
  ddl=(p/(name+'_deploy.sql')).read_text(encoding='utf-8');assert ddl=='CREATE OR REPLACE VIEW `pacific-plating-282708.'+obj+'` AS\n'+s+';\n'
  if name=='producer':test='WITH combined AS (SELECT * FROM shared_combined),\n'+s[s.index(marker)+1:]
  else:test=s.replace('`pacific-plating-282708.sap_integration_v2.RCL 04_new order credit shell`','after_producer').replace('`pacific-plating-282708.sap_integration_v2.SAP_LIVE_FULL`','sap_items').replace('`pacific-plating-282708.careos.cancelled_change_orders`','change_orders')
  assert 'CREATE TEMP TABLE after_'+name+' AS\n'+test+';' in query,name
 for i in [9,10,11]:
  m=read('release_preflight_'+str(i)+'_result.json')[0]
  assert m['before_rows']==m['after_rows']
  for k in ['added_motor','removed_motor','added_other_fields','removed_other_fields','pending_amount_failures','insurer_failures']:assert int(m[k])==0,(i,k,m[k])
  if i!=9:assert int(m['prior_month_paid'])==0
 for i in [13,14,15]:
  m=read('release_preflight_'+str(i)+'_result.json')[0]
  for k in ['paid_actual_failures','preserved_date_failures','receipt_multiplicity_failures']:assert int(m[k])==0,(i,k,m[k])
 schemas=read('schema_preflight.json');assert len(schemas)==3 and all(x['match'] and x['columns']==56 and x['source_job']==j['jobReference']['jobId'] for x in schemas)
 return hashes
if __name__=='__main__':
 hashes=verify();(p/'verified_candidate_hashes.json').write_text(json.dumps(hashes,indent=2),encoding='utf-8');print('PASS exact-source binding, schema56x3, zero regression failures; candidate hashes saved.')
