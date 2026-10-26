"""Fetch immutable current-view candidates for a completed charge reconciliation.
Runs SELECT-only SQL through bq_safe_query.sh; never exports or uploads.
Usage: python scripts/20260930_capture_recovery_candidates.py RESULT_JSON OUTPUT_DIR
"""
import sys,json,subprocess,concurrent.futures
from pathlib import Path
root=Path(__file__).resolve().parents[1]
src=Path(sys.argv[1]); out=Path(sys.argv[2]); out.mkdir(exist_ok=True,parents=True)
data=json.loads(src.read_text(encoding='utf-8-sig'))
if data and isinstance(data[-1],list): data=data[-1]
rows=[json.loads(x['payload']) for x in data if x['record_type']=='EXCEPTION']
summary=next(json.loads(x['payload']) for x in data if x['record_type']=='SUMMARY')
(out/'exceptions.json').write_text(json.dumps(rows))
(out/'summary.json').write_text(json.dumps(summary,indent=2))
candidates=[x for x in rows if x['assurance_status'] in ('MISSING_FROM_SAP_REQUIRES_VIEW_CHECK','KNOWN_SCENARIO')]
(out/'missing_candidates.json').write_text(json.dumps(candidates))
cols=json.loads((out/'live_columns.json').read_text(encoding='utf-8-sig'))
views=sorted(set(x['table_name'] for x in cols)-{'RCB_Motor_process_2_cancel_new','RCL_Motor_process_3_cancel'})
# Full item spines, not only the missing paid row. Cross-route checks prevent false omissions.
items=sorted(set(x['OrderItem'] for x in candidates if x['OrderItem']))
assert all("'" not in x and '\\' not in x for x in items)
ids=','.join("'"+x+"'" for x in items)
def run(view):
 names=[x['column_name'] for x in sorted([x for x in cols if x['table_name']==view],key=lambda x:int(x['ordinal_position']))]
 assert len(names)==56
 q='SELECT '+', '.join('`'+n+'`' for n in names)+' FROM `pacific-plating-282708.sap_view.'+view+'` WHERE OrderItem IN UNNEST(['+ids+'])'
 sql=out/(view+'.query.sql');sql.write_text(q)
 result=out/(view+'.rows.json');log=out/(view+'.run.log')
 with result.open('w',encoding='utf-8') as f,log.open('w',encoding='utf-8') as e:
  cmd=['C:/Program Files/Git/bin/bash.exe','scripts/bq_safe_query.sh','--project','pacific-plating-282708','-f',sql.as_posix(),'--','--format=json','--max_rows=100000']
  r=subprocess.run(cmd,cwd=root,stdout=f,stderr=e)
 print(view,'exit',r.returncode,flush=True)
 return view,r.returncode
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
 status=list(pool.map(run,views))
(out/'capture_status.json').write_text(json.dumps(status))
if any(code for _,code in status):sys.exit(1)
