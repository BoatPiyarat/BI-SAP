# V3 delivery promoter production deployment evidence — 2026-08-27

## Outcome

`sap-delivery-promoter` is deployed as a private, internal-only Cloud Run service. It is staged,
not activated: the live workflow still has `delivery_enabled: false`, the recurring V3 Scheduler
job is absent, and no production delivery was invoked.

## Deployed identity

- Project / region: `pacific-plating-282708` / `asia-southeast1`
- Service / revision: `sap-delivery-promoter` / `sap-delivery-promoter-00001-grm`
- Build: `015cde0f-2513-4650-a901-dfcbdfd45b4d` (`SUCCESS`)
- Image digest: `sha256:4c85275466277cf3218f34a8f7ea55ee05070192b83438135efa991a2659535f`
- Runtime identity: `data-extraction@pacific-plating-282708.iam.gserviceaccount.com`
- Ingress: `internal`
- Authentication: required; the service IAM policy contains no bindings
- Environment: `ARCHIVE_BUCKET=rcb-bronze-zone`, `PRODUCTION_BUCKET=interface-file`,
  `PRODUCTION_PREFIX=RCB_MOTOR`

## Safety verification

- Cloud Run reported Ready with 100% traffic on the single private revision.
- The live control-plane checker completed at `2026-08-27T06:54:48.7139437Z` after making its
  empty-IAM-policy handling tolerant of an absent `bindings` property. It reported promoter
  revision `sap-delivery-promoter-00001-grm`, the expected runtime identity, workflow revision
  `000009-e96`, `delivery_enabled: false`, and `scheduler_state: null`. Overall
  `safety_passed:false` and `control_plane_ready:false` are expected at this stage: the old
  workflow lacks the three new two-name markers and the PAUSED recurring Scheduler is absent.
- An authenticated invalid-body POST from outside the internal ingress returned HTTP `404`; no
  valid promoter request was accepted.
- At `2026-08-27T06:53:25.3993102Z`, the following read-only Cloud Audit Logs query against
  project `pacific-plating-282708` returned zero rows (format
  `value(timestamp,protoPayload.methodName)`, limit 100):

  ```text
  timestamp>="2026-08-27T06:40:00Z"
  AND protoPayload.authenticationInfo.principalEmail="data-extraction@pacific-plating-282708.iam.gserviceaccount.com"
  AND resource.type="gcs_bucket"
  AND (protoPayload.methodName="storage.objects.create"
       OR protoPayload.methodName="storage.objects.delete"
       OR protoPayload.methodName="storage.objects.update")
  ```

  This proves that the runtime identity produced no audit-visible GCS create/update/delete event
  between deployment and that check; it does not prove the absence of mutations by other actors.
- The deploy command contained no IAM-policy, workflow, Scheduler, BigQuery, SAP, delivery-marker,
  or ACK mutation operation. Read-only postchecks directly observed an empty service IAM policy,
  the unchanged old workflow revision with delivery disabled, and the recurring Scheduler absent.
  No broader no-mutation claim is made for systems not covered by those postchecks.

## Current hold state

At the recorded postcheck, the recurring V3 Scheduler job was absent. The old workflow revision
`000009-e96` remained deployed with `delivery_enabled: false` and did not yet contain the reviewed
two-name delivery contract. Replacing that workflow is a separate deployment and must receive its
own post-deploy progress/evidence update before any later deployment begins.

## Rollback boundary

The pre-deployment state was that the Cloud Run service did not exist. Deleting the staged service
would restore that state, but deletion is destructive and was not performed. Leaving this private,
uninvoked revision staged preserves the fail-closed production state.

## Review

The final checker fix and bounded deployment evidence received local two-axis Class-A PASS for
both Standards/Safety and Spec. The initial review BLOCKed an untraceable zero count, broad
negative claims, and a contradiction between the invalid probe and “no request”; all three were
corrected before PASS. See
`docs/reviews/2026-08-27-v3-promoter-deploy-evidence-class-a.md`.
