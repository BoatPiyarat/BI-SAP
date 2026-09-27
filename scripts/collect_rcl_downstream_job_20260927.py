import json,subprocess,sys,hashlib
from pathlib import Path
jobid=sys.argv[1];label=sys.argv[2];p=Path('docs/evidence/rcl_downstream_20260927')
def bq(args):
 r=subprocess.run(['bq.cmd']+args,capture_output=True,text=True,encoding='utf-8')
 if r.returncode:raise RuntimeError((r.stdout+r.stderr)[:1500])
 return json.loads(r.stdout)
j=bq(['show','--format=prettyjson','--job=true','--location=asia-southeast1',jobid])
(p/(label+'_job.json')).write_text(json.dumps(j,indent=2),encoding='utf-8')
c=bq(['ls','--jobs=true','--format=prettyjson','--max_results=1000','--parent_job_id='+jobid])
slim=[]
for x in c:
 query=x.get('configuration',{}).get('query',{});dest=query.get('destinationTable');sql=query.get('query','')
 slim.append({'jobReference':x.get('jobReference'),'status':x.get('status'),'destinationTable':dest,'query_sha256':hashlib.sha256(sql.encode()).hexdigest(),'query_prefix':sql[:80]})
 if dest and sql.lstrip().upper().startswith(('SELECT','WITH')):
  ref=dest['projectId']+':'+dest['datasetId']+'.'+dest['tableId']
  result=bq(['head','--format=prettyjson','--max_rows=1000',ref])
  (p/(label+'_'+x['jobReference']['jobId'].rsplit('_',1)[-1]+'_result.json')).write_text(json.dumps(result,indent=2),encoding='utf-8')
  print('result',x['jobReference']['jobId'],len(result))
(p/(label+'_children.json')).write_text(json.dumps(slim,indent=2),encoding='utf-8')
print(jobid,j['status'],'bytes',j.get('statistics',{}).get('totalBytesProcessed'))
