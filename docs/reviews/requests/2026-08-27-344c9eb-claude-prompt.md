Perform a read-only Class-A review of exact commit 344c9eb, scoped to the revised private promoter
deployment proposal. Do not edit, deploy, build remotely, mutate IAM, access GCS objects, or run a
workflow/Scheduler.

Read AGENTS.md, docs/AGENT_REVIEW_PROTOCOL.md,
docs/V3_PROMOTER_DEPLOYMENT_PROPOSAL_20260827.md, the prior promoter source review
docs/reviews/2026-08-27-65bd74a-promoter-claude.md, and the local test evidence. The user authorized
reuse of a legacy service account but stated they cannot grant a role.

Read-only live IAM evidence supplied by Codex:

- `data@rabbit.co.th`: project roles/editor.
- V3 workflow caller `919786098205-compute@developer.gserviceaccount.com`: project roles/editor.
- authoritative roles/editor definition contains run.services.create,
  iam.serviceAccounts.actAs, and run.routes.invoke.
- legacy `data-extraction@pacific-plating-282708.iam.gserviceaccount.com`: project
  roles/storage.objectAdmin, roles/bigquery.dataViewer, roles/bigquery.user; direct
  roles/storage.legacyBucketOwner on gs://interface-file.
- that same legacy identity runs the existing sap-interface-pipeline workflow and
  demo-nonmotor-bucket Cloud Run service.

Review whether the proposed single `gcloud run deploy` can safely reuse data-extraction as runtime
identity with no IAM changes, while the existing default Compute workflow identity invokes it.
Assess archive read / create-only production write capability, internal ingress, authenticated
invocation, honest description of pre-existing broad permissions, rollback, and whether any
unmentioned permission or IAM mutation is required. Return Markdown with explicit PASS,
PASS WITH NOTES, or BLOCK and concrete required corrections. This is a proposal review only.
