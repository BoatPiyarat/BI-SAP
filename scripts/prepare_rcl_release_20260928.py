"""Prepare the authorized four-view release. Metadata reads only; never executes DDL.
Run --capture after Google Cloud authentication; then run generated preflight through bq_safe_query.
"""
from pathlib import Path
import json,subprocess,datetime,hashlib,argparse
args=argparse.ArgumentParser();args.add_argument('--capture',action='store_true');args=args.parse_args()
e=Path('docs/evidence/rcl_downstream_deploy_20260928');e.mkdir(parents=True,exist_ok=True)
p=Path('sql/production/rcl_downstream_deploy_20260928');t=Path('sql/adhoc/20260928_rcl_release');t.mkdir(parents=True,exist_ok=True)
objects={'dashboard':'sap_data_engineer.sap_dashboard_carepay_installment','newpayment':'sap_integration_v2.RCL 05_newpayment','gate':'sap_integration_v2.RCL 05_paid by period','wrapper':'sap_view.RCL_Motor_process_2_newpayment','paid':'sap_integration_v2.RCL 05_paid'}
names={'dashboard':'sap_dashboard_carepay_installment','newpayment':'RCL_05_newpayment','gate':'RCL_05_paid_by_period','wrapper':'RCL_Motor_process_2_newpayment'}
if args.capture:
 for key,obj in objects.items():
  r=subprocess.run(['bq.cmd','show','--format=prettyjson','pacific-plating-282708:'+obj],capture_output=True,text=True,encoding='utf-8')
  if r.returncode:raise RuntimeError((r.stdout+r.stderr)[:1200])
  j=json.loads(r.stdout);(e/(key+'_before.json')).write_text(json.dumps(j,indent=2),encoding='utf-8')
 (e/'capture_time.json').write_text(json.dumps({'captured_at':datetime.datetime.now(datetime.timezone.utc).isoformat()},indent=2))
live={}
for key in objects:
 src=e/(key+'_before.json')
 if not src.exists():raise SystemExit('Fresh metadata absent. Complete sign-in and run this script with --capture.')
 j=json.loads(src.read_text(encoding='utf-8-sig'));old=json.loads((Path('docs/evidence/rcl_downstream_20260927')/(key+'.json')).read_text(encoding='utf-8-sig'))
 if j['view']['query']!=old['view']['query']:raise SystemExit('LIVE DEFINITION DRIFT: '+objects[key]+'; rebase/review before release.')
 live[key]=j['view']['query'].strip().rstrip(';')
 if key in names:
  (e/(key+'_rollback.sql')).write_text('CREATE OR REPLACE VIEW `pacific-plating-282708.'+objects[key]+'` AS\n'+live[key]+';\n',encoding='utf-8')
  body=(p/(names[key]+'.sql')).read_text(encoding='utf-8').strip().rstrip(';')
  (e/(key+'_deploy.sql')).write_text('CREATE OR REPLACE VIEW `pacific-plating-282708.'+objects[key]+'` AS\n'+body+';\n',encoding='utf-8')
# Build a fresh, staged comparison with canonical SAP captured once.
q=Path('sql/adhoc/20260926_rcl_additional_staged_validation.sql').read_text(encoding='utf-8').split('\n',1)[0]+'\n'
q+='CREATE TEMP TABLE live_dashboard AS '+live['dashboard']+';\n'
q+='CREATE TEMP TABLE candidate_dashboard AS '+(p/'sap_dashboard_carepay_installment.sql').read_text(encoding='utf-8').strip().rstrip(';')+';\n'
def rw(s,mode):
 refs={'sap_integration_v2.SAP_LIVE_FULL':'evidence_sap','sap_data_engineer.sap_dashboard_carepay_installment':'live_dashboard' if mode=='baseline' else 'candidate_dashboard','sap_integration_v2.RCL 05_paid':'evidence_paid','sap_integration_v2.RCL 05_newpayment':mode+'_newpayment','sap_integration_v2.RCL 05_paid by period':mode+'_gate'}
 for a,b in refs.items():s=s.replace('`pacific-plating-282708.'+a+'`',b)
 return s
q+='CREATE TEMP TABLE evidence_paid AS '+rw(live['paid'],'baseline')+';\n'
for mode in ['baseline','candidate']:
 for key in ['newpayment','gate','wrapper']:
  body=live[key] if mode=='baseline' else (p/(names[key]+'.sql')).read_text(encoding='utf-8').strip().rstrip(';')
  q+='CREATE TEMP TABLE '+mode+'_'+key+' AS '+rw(body,mode)+';\n'
np=(p/'RCL_05_newpayment.sql').read_text(encoding='utf-8')
prefix=np.split('SELECT DISTINCT\n  interface.CompanyDB',1)[0]
q+='CREATE TEMP TABLE lineage AS '+rw(prefix,'candidate')+'SELECT OrderItem,Period,InvoiceNo,source_charge_rank,source_event_rows FROM interface;\n'
q+="""SELECT CURRENT_TIMESTAMP() AS checked_at_utc,
(SELECT COUNT(*) FROM baseline_wrapper) AS baseline_rows,
(SELECT COUNT(*) FROM candidate_wrapper) AS candidate_rows,
(SELECT COUNT(*) FROM (SELECT TO_JSON_STRING((SELECT AS STRUCT b.* EXCEPT(PrincipleThisPeriod,PrincipleEIRThisPeriod))) FROM live_dashboard b EXCEPT DISTINCT SELECT TO_JSON_STRING((SELECT AS STRUCT c.* EXCEPT(PrincipleThisPeriod,PrincipleEIRThisPeriod))) FROM candidate_dashboard c)) AS removed_nonprincipal_dashboard_payloads,
(SELECT COUNT(*) FROM candidate_dashboard d JOIN lineage l ON l.OrderItem=d.OrderItem AND l.Period=d.Period AND l.InvoiceNo IS NOT DISTINCT FROM d.InvoiceNo WHERE l.source_charge_rank>1 AND (d.PrincipleThisPeriod IS DISTINCT FROM d.ActualReceived OR d.PrincipleEIRThisPeriod IS DISTINCT FROM d.ActualReceived)) AS additional_principal_mismatches,
(SELECT COUNT(*) FROM (SELECT TO_JSON_STRING(b) FROM live_dashboard b JOIN lineage l ON l.OrderItem=b.OrderItem AND l.Period=b.Period AND l.InvoiceNo IS NOT DISTINCT FROM b.InvoiceNo WHERE l.source_charge_rank=1 EXCEPT DISTINCT SELECT TO_JSON_STRING(c) FROM candidate_dashboard c)) AS removed_first_receipt_payloads,
(SELECT COUNT(*) FROM (SELECT TO_JSON_STRING(b) FROM baseline_wrapper b EXCEPT DISTINCT SELECT TO_JSON_STRING(c) FROM candidate_wrapper c)) AS removed_wrapper_payloads,
(SELECT COUNT(*) FROM (SELECT OrderItem,Period,InvoiceNo FROM candidate_wrapper GROUP BY 1,2,3 HAVING COUNT(*)>1)) AS duplicate_event_keys,
(SELECT COUNT(*) FROM (SELECT OrderItem FROM candidate_wrapper GROUP BY OrderItem HAVING COUNT(DISTINCT Period)!=MAX(TotalPeriods) OR MIN(Period)!=1 OR MAX(Period)!=MAX(TotalPeriods))) AS incomplete_spines,
ARRAY(SELECT AS STRUCT OrderID,OrderItem,Period,InvoiceNo,ExpectedReceived,ActualReceived,PrincipleThisPeriod,PrincipleEIRThisPeriod FROM candidate_wrapper WHERE OrderID IN ('L80570054','L79109956')) AS target_rows;
"""
(t/'preflight.sql').write_text(q,encoding='utf-8')
(e/'candidate_hashes.json').write_text(json.dumps({x.name:hashlib.sha256(x.read_bytes()).hexdigest() for x in p.glob('*.sql')},indent=2))
print('Prepared fresh rollback/deploy SQL and read-only staged preflight. No DDL executed.')
