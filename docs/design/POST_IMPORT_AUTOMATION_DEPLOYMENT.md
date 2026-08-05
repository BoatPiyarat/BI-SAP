# Post-import automation deployment and rehearsal

Status: source plan only. Nothing in this document authorizes an unreviewed deploy or enables
`POST_IMPORT_REFRESH_TOPIC`.

## Activation evidence — 2026-08-05 20:31 ICT

The reviewed foundation is now partly deployed but intentionally inert:

- DDL 072 original job `bqjob_r2275791741e4aa6a_0000019fd20b3076_1`, corrected canonical
  execution-name job `bqjob_r44f87f4cfafffe4b_0000019fd23dd027_1`;
- DDL 073 job `bqjob_r26029521d6ea2cf0_0000019fd20bb351_1`;
- DDL 074 rehearsal-fixture procedure job
  `bqjob_r2732ec7e5e42097_0000019fd23b665a_1` (procedure exists but was not called);
- workflow revision `000009-e96`, ACTIVE with canonical project-number self-binding and
  `delivery_enabled: false`;
- private/internal dispatcher revision `sap-post-import-dispatcher-00001-qd4`, with no invoker;
- unscheduled watchdog job `sap-post-import-watchdog`, Ready, never executed;
- topics `sap-post-import-refresh` and `sap-post-import-refresh-dlq`;
- evidence subscription `sap-post-import-refresh-dlq-retain`, 14-day retention and no expiration;
- dedicated service accounts `sap-post-import-dispatch`, `sap-post-import-watchdog`, and
  `sap-post-import-push`.

The recorded watchdog values are claim timeout 600 seconds, execution timeout 900 seconds, and
cancel wait 120 seconds. The 900-second bound is 2.85 times the longest of the five available
historical full-workflow durations (315.4 seconds); a healthy post-import Unit-1 measurement is
still required during rehearsal. Proposed but not activated values are a two-minute watchdog
schedule, five Pub/Sub delivery attempts, and a 600-second acknowledgement deadline.

No push subscription, watchdog scheduler, Gmail publisher setting, workflow execution, GCS
delivery, or SAP action exists from this activation work.

## IAM stop and required administrator actions

`data@rabbit.co.th` created the three service accounts and runtime resources but cannot complete
IAM:

- `iam.roles.create` was denied while creating the create-only and get/cancel-only Workflows
  custom roles;
- `run.services.setIamPolicy` was denied while granting the push identity `run.invoker` on the one
  dispatcher service;
- the inactive `piyaratt@rabbit.co.th` credential is expired and requires interactive login.

Do not substitute the predefined `roles/workflows.invoker`: it combines create, get, and cancel
and breaks the reviewed dispatcher/watchdog separation. An administrator must create and bind a
create-only role (`workflows.executions.create`) for the dispatcher and a monitor role
(`workflows.executions.get`, `workflows.executions.cancel`) for the watchdog, restricted to
`v3-nightly-orchestrator`. The same administrator must grant:

- `roles/run.invoker` to `sap-post-import-push@...` on only
  `sap-post-import-dispatcher`;
- `roles/pubsub.publisher` to `sap-post-import-watchdog@...` on only
  `v3-orchestrator-alerts`;
- `roles/iam.serviceAccountTokenCreator` to the Pub/Sub service agent on only the push service
  account.

BigQuery remains deliberately ungranted. Both runtimes require project-level
`roles/bigquery.jobUser`. The current watchdog also directly reads the outbox, and both runtimes
call procedures that modify it. Granting table-level `roles/bigquery.dataEditor` on only
`v3_post_import_refresh_outbox` is operationally sufficient but permits direct DML outside the
procedures; it requires Boat's explicit informed approval. The safer authorized-routine model
requires the routine to be in a different dataset from the protected table, conflicting with the
current rule that all DDL stays in `sap_integration_v3`; that alternative therefore requires a
separate design/rule decision and review.

## Reviewed artifact order

Deploy only after each named Class-A request records PASS:

1. DDL 072 outbox transitions.
2. DDL 073 row reconciliation.
3. Updated Unit-1 workflow revision.
4. Private post-import dispatcher.
5. Scheduled post-import watchdog.
6. Apps Script publisher configuration and authenticated Pub/Sub delivery resources.

Record the deployed revision/job/resource name at each step. If a later step fails, keep the Apps
Script topic blank and roll back the workflow to its prior revision; DDL tables/procedures may
remain unused.

## Dedicated identities

Use separate service accounts:

- dispatcher: BigQuery job creation plus dataset-scoped procedure/table access, and
  `workflows.executions.create` on the one Unit-1 workflow;
- watchdog: BigQuery job creation plus dataset-scoped procedure/table access,
  `workflows.executions.get`, `workflows.executions.cancel`, and publisher on the existing
  human-tested orchestrator alert topic;
- Pub/Sub push: only `run.invoker` on the private dispatcher service.

Do not use the default Compute Engine service account. Do not grant project-wide Editor or Owner.
The Unit-1 workflow account additionally needs dataset access for DDL 072/073 procedures.

## Resource configuration

Required resources are one post-import topic, one dead-letter topic, one authenticated push
subscription targeting `/dispatch`, one private dispatcher service, one watchdog Cloud Run Job,
and one scheduler invocation for that job. Configure finite Pub/Sub delivery attempts and retain
the dead-letter subscription long enough for operator diagnosis.

The following values are required deployment inputs and must be recorded from approved/measured
configuration, not silently defaulted:

- claim timeout seconds;
- Unit-1 execution timeout seconds, greater than measured healthy Unit-1 duration with margin;
- cancellation terminal-wait seconds;
- watchdog schedule, materially shorter than the claim timeout;
- Pub/Sub maximum delivery attempts and acknowledgement deadline.

## Synthetic rehearsal before enabling Gmail publication

Use a synthetic non-production LogID/export/filename binding that cannot select a production
delivery manifest or invoke SAP. Prove:

1. one event creates one CLAIMED → STARTED child execution;
2. a duplicate event creates no second active Unit-1 run;
3. the child execution binds its own complete server-assigned resource name before Unit 1;
4. post-import mode returns before Units 2–5 and delivery;
5. a zero-residual fixture reaches `SUCCEEDED`;
6. an exact rejected-row fixture reaches row-level `REJECTED_BY_SAP`;
7. a residual fixture reaches `HUMAN_ACTION`, publishes an alert that reaches Boat, and fails;
8. an overdue execution is cancelled and observed terminal before `TIMEOUT`;
9. a stale claim retries no more than three times, then alerts;
10. malformed Pub/Sub data reaches retry/dead-letter handling without a workflow execution.

Capture BigQuery rows, execution names/revisions/states, Pub/Sub message IDs, Cloud Run revision/job
names, and human alert receipt timestamps. Do not use LogID 21153 or replay any production file.

## Activation and rollback

Only after the rehearsal passes:

1. set the Apps Script `POST_IMPORT_REFRESH_TOPIC`;
2. run one bounded mailbox poll and confirm outbox → execution → Unit 1 → reconciliation;
3. enable the watchdog schedule;
4. observe one full daily production cycle before declaring unattended operation.

Rollback is configuration-first: blank `POST_IMPORT_REFRESH_TOPIC`, pause the watchdog scheduler
and Pub/Sub subscription, and restore the prior workflow revision if its normal nightly path is
affected. Do not delete evidence tables, messages, manifests, or execution history during rollback.
