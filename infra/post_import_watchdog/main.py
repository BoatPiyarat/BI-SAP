"""Scheduled watchdog for post-import claims and child Workflows executions."""

import json
import os
import time
from datetime import datetime, timezone

from google.cloud import bigquery, pubsub_v1
from google.cloud.workflows.executions_v1 import ExecutionsClient
from google.cloud.workflows.executions_v1.types import Execution


def configured(name):
    value = os.environ.get(name, "").strip()
    if not value:
        raise RuntimeError("missing required configuration: " + name)
    return value


def configured_seconds(name, minimum, maximum):
    try:
        value = int(configured(name))
    except ValueError as error:
        raise RuntimeError(name + " must be an integer") from error
    if value < minimum or value > maximum:
        raise RuntimeError(f"{name} must be between {minimum} and {maximum}")
    return value


def call_procedure(client, sql, parameters):
    config = bigquery.QueryJobConfig(
        query_parameters=[
            bigquery.ScalarQueryParameter(name, "STRING", value)
            for name, value in parameters.items()
        ],
        maximum_bytes_billed=20 * 1024 * 1024 * 1024,
    )
    return list(
        client.query(
            sql, job_config=config, location=configured("BQ_LOCATION")
        ).result()
    )


def release_claim(client, row):
    call_procedure(
        client,
        "CALL `{project}.{dataset}.sp_release_v3_post_import_claim`"
        "(@log_id,@claim_token,@error_template)".format(
            project=configured("PROJECT_ID"), dataset=configured("BQ_DATASET")
        ),
        {
            "log_id": row["log_id"],
            "claim_token": row["claim_token"],
            "error_template": "STALE_CLAIM_WITHOUT_EXECUTION",
        },
    )


def complete(client, row, terminal_status, error_template):
    call_procedure(
        client,
        "CALL `{project}.{dataset}.sp_complete_v3_post_import_refresh`"
        "(@log_id,@workflow_execution_name,@terminal_status,@error_template)".format(
            project=configured("PROJECT_ID"), dataset=configured("BQ_DATASET")
        ),
        {
            "log_id": row["log_id"],
            "workflow_execution_name": row["workflow_execution_name"],
            "terminal_status": terminal_status,
            "error_template": error_template,
        },
    )


def publish_alert(publisher, row, state, template):
    body = json.dumps(
        {
            "component": "post-import-watchdog",
            "log_id": row["log_id"],
            "attempt_count": row["attempt_count"],
            "workflow_state": state,
            "error_template": template,
        },
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    publisher.publish(configured("ALERT_TOPIC"), body).result(timeout=30)


def terminal_state(execution):
    return Execution.State(execution.state).name


def cancel_until_terminal(client, name, wait_seconds):
    client.cancel_execution(name=name)
    deadline = time.monotonic() + wait_seconds
    while time.monotonic() < deadline:
        execution = client.get_execution(name=name)
        state = terminal_state(execution)
        if state not in {"ACTIVE", "QUEUED"}:
            return state
        time.sleep(5)
    raise RuntimeError("workflow cancellation did not reach a terminal state")


def main():
    claim_timeout = configured_seconds("CLAIM_TIMEOUT_SECONDS", 60, 3600)
    execution_timeout = configured_seconds("EXECUTION_TIMEOUT_SECONDS", 300, 7200)
    cancel_wait = configured_seconds("CANCEL_WAIT_SECONDS", 30, 600)
    project = configured("PROJECT_ID")
    dataset = configured("BQ_DATASET")
    location = configured("BQ_LOCATION")
    now = datetime.now(timezone.utc)

    bq_client = bigquery.Client(project=project)
    workflow_client = ExecutionsClient()
    publisher = pubsub_v1.PublisherClient()
    query = f"""
      SELECT log_id,claim_token,request_status,workflow_execution_name,attempt_count,claimed_at
      FROM `{project}.{dataset}.v3_post_import_refresh_outbox`
      WHERE request_status IN ('CLAIMED','STARTED')
      ORDER BY claimed_at
      LIMIT 100
    """
    rows = list(bq_client.query(query, location=location).result())
    actions = 0
    for row in rows:
        age_seconds = (now - row["claimed_at"]).total_seconds()
        if row["request_status"] == "CLAIMED":
            if age_seconds < claim_timeout:
                continue
            release_claim(bq_client, row)
            actions += 1
            if row["attempt_count"] >= 3:
                publish_alert(
                    publisher, row, "NO_EXECUTION", "STALE_CLAIM_ATTEMPTS_EXHAUSTED"
                )
            continue

        execution = workflow_client.get_execution(
            name=row["workflow_execution_name"]
        )
        state = terminal_state(execution)
        if state in {"ACTIVE", "QUEUED"} and age_seconds < execution_timeout:
            continue
        if state in {"ACTIVE", "QUEUED"}:
            state = cancel_until_terminal(
                workflow_client, row["workflow_execution_name"], cancel_wait
            )
            terminal = "TIMEOUT"
            template = "WORKFLOW_EXECUTION_TIMEOUT"
        else:
            terminal = "HUMAN_ACTION"
            template = "WORKFLOW_TERMINAL_WITHOUT_OUTBOX_COMPLETION"
        complete(bq_client, row, terminal, template)
        publish_alert(publisher, row, state, template)
        actions += 1

    print(json.dumps({"open_rows": len(rows), "actions": actions}, sort_keys=True))


if __name__ == "__main__":
    main()
