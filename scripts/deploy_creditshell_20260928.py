"""Deploy only after recorded exact-source validation, review, and drift checks."""
import json,subprocess,datetime
from pathlib import Path
p=Path('docs/evidence/nonmotor_creditshell_20260928')
objects={'producer':'sap_integration_v2.RCL 04_new order credit shell','rcl_wrapper':'sap_view.RCL_Motor_process_4_creditshell','rcb_wrapper':'sap_view.RCB_Motor_process_4_creditshell'}
def bq(args):
 r=subprocess.run(['bq.cmd']+args,capture_output=True,text=True,encoding='utf-8')
 if r.returncode: raise RuntimeError(r.stdout+r.stderr)
 return json.loads(r.stdout)
def norm(s):
 a=s.strip().rstrip(';').splitlines()
 while a and (not a[0].strip() or a[0].lstrip().startswith('--')):a.pop(0)
 return '\n'.join(a).strip()
def schema(d):return [(f['name'],f['type']) for f in d['schema']['fields']]
def read(n):return json.loads((p/n).read_text(encoding='utf-8'))
assert read('preflight_final_job.json')['status']=={'state':'DONE'}
assert all(x['match'] for x in read('schema_preflight.json'))
assert Path('docs/reviews/2026-09-28-creditshell-independent.md').exists()
for name,obj in objects.items():
 current=bq(['show','--format=prettyjson','pacific-plating-282708:'+obj]);before=read(name+'_before.json')
 assert norm(current['view']['query'])==norm(before['view']['query']),('drift',obj)
 assert schema(current)==schema(before)
results=[]
for name,obj in objects.items():
 job='creditshell_deploy_'+name+'_20260928_001'
 cmd=['C:/Program Files/Git/bin/bash.exe','../codex_bootstrap/scripts/bq_safe_query.sh','--project','pacific-plating-282708','-f',str(p/(name+'_deploy.sql')),'--','--format=json','--location=asia-southeast1','--job_id='+job]
 r=subprocess.run(cmd,capture_output=True,text=True,encoding='utf-8')
 (p/(name+'_deploy_execution.log')).write_text(r.stdout+r.stderr,encoding='utf-8')
 if r.returncode:raise RuntimeError(name+' deployment failed; see saved log')
 j=bq(['show','--format=prettyjson','--job=true','--location=asia-southeast1',job]);(p/(name+'_deploy_job.json')).write_text(json.dumps(j,indent=2),encoding='utf-8');assert j['status']=={'state':'DONE'}
 after=bq(['show','--format=prettyjson','pacific-plating-282708:'+obj]);(p/(name+'_after.json')).write_text(json.dumps(after,indent=2),encoding='utf-8')
 candidate=Path('sql/production/nonmotor_creditshell_20260928',name+'.sql').read_text(encoding='utf-8')
 assert norm(after['view']['query'])==norm(candidate),('definition mismatch',name)
 assert schema(after)==schema(read(name+'_before.json')),('schema mismatch',name)
 results.append({'object':obj,'job':job,'status':'DONE','definition_matches':True,'schema_matches':True,'verified_at':datetime.datetime.now(datetime.timezone.utc).isoformat()})
 (p/'deployment_results.json').write_text(json.dumps(results,indent=2),encoding='utf-8');print(name,'DONE',flush=True)
