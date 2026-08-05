# Post-import automation deployment and rehearsal

Status: source plan only. Nothing in this document authorizes an unreviewed deploy or enables
`POST_IMPORT_REFRESH_TOPIC`.

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
