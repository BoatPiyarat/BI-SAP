# V3 promoter permission-rehearsal workflow deployment evidence

Date: 2026-08-27

Source commit: `6717412`

Predecessor revision: `000010-daf`

## Deployment result

- Operation: `operation-1787830778404-65a05ca771f77-504fc5e7-d80c342f`
- Live revision: `000011-291`, ACTIVE
- Revision create time: `2026-08-27T11:39:39.466202128Z`
- Service account:
  `919786098205-compute@developer.gserviceaccount.com`
- Delivery remains literal `false`; there is no literal `delivery_enabled:true`.

## Exact source and no-execution proof

At `2026-08-27T11:40:19.0435085Z`,
`scripts/verify_v3_workflow_deployment.ps1 -ExpectedRevision 000011-291` returned
`verification_passed:true`:

- live length and candidate length: `66,688`
- live SHA-256: `60fdaf3a8f3b9bc1de38068ca6f10de22504c853f98839114b21840a8d8d23a6`
- candidate SHA-256: `d7d2c19c8de6e1ace3ffe606f9e52fed607451d37f778c1ba8e77aa78218992a`
- exactly two character differences, both comment-only U+2014 em dashes serialized as `?`, at
  candidate lines 1 and 371
- source identity gate: PASS
- execution filter:
  `startTime>=2026-08-27T11:39:39.466202128Z`
- execution rows returned: `0`

## Preserved controls

At `2026-08-27T11:40:32.8423584Z`, the durable control-plane checker returned:

- safety: PASS
- control-plane configuration readiness: PASS
- Workflow revision: `000011-291`
- private promoter revision: `sap-delivery-promoter-00001-grm`
- Scheduler state: PAUSED
- delivery enabled: false
- permission rehearsal required: true
- readiness blockers: none

The deployment command did not execute the Workflow, invoke the promoter, export a file, mutate
GCS/BigQuery business data, trigger SAP extraction, resume Scheduler, or acknowledge SAP import.

## Next gate and rollback

Do not execute the permission rehearsal until this deployment evidence passes both Class-A review
axes and is committed. If rollback is required, redeploy source commit `8a420d7`, corresponding to
the prior delivery-disabled revision `000010-daf`; keep Scheduler PAUSED.

## Class-A result

- Standards / safety: **PASS**
- Spec: **PASS**
- Final verdict: **PASS** for committing this deployment checkpoint and proceeding to the separately
  bounded no-write permission rehearsal. Delivery and Scheduler activation remain forbidden.
