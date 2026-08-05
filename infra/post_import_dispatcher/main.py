"""Private Pub/Sub push target for exactly-bound post-import Unit 1 refreshes."""

import base64
import hashlib
import json
import os
import re
from datetime import datetime

from flask import Flask, jsonify, request
from google.api_core.exceptions import BadRequest, Forbidden, NotFound
from google.cloud import bigquery
from google.cloud.workflows.executions_v1 import ExecutionsClient
from google.cloud.workflows.executions_v1.types import Execution

app = Flask(__name__)

_FILE_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*\.csv$")
_LOG_ID = re.compile(r"^[0-9]{1,20}$")
_RUN_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$")
_TERMINAL_IMPORT_STATUSES = {"success", "success with error"}


def configured(name):
    value = os.environ.get(name, "").strip()
    if not value:
        raise RuntimeError("missing required service configuration: " + name)
    return value


def required_string(payload, field):
    value = payload.get(field)
    if not isinstance(value, str) or not value.strip():
        raise ValueError("missing required event field: " + field)
    return value.strip()


def decode_event(envelope):
    if not isinstance(envelope, dict) or not isinstance(envelope.get("message"), dict):
        raise ValueError("request must be a Pub/Sub push envelope")
    encoded = envelope["message"].get("data")
    if not isinstance(encoded, str):
        raise ValueError("Pub/Sub message data is required")
    try:
        payload = json.loads(base64.b64decode(encoded, validate=True).decode("utf-8"))
    except (ValueError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ValueError("Pub/Sub message data must be base64 JSON") from error
    if not isinstance(payload, dict):
        raise ValueError("event data must be a JSON object")
    return payload


def validate_event(payload):
    event = {
        "log_id": required_string(payload, "log_id"),
        "export_run_id": required_string(payload, "export_run_id"),
        "sap_file_name": required_string(payload, "sap_file_name"),
        "import_status": required_string(payload, "import_status").lower(),
        "email_date": required_string(payload, "email_date"),
    }
    if not _LOG_ID.fullmatch(event["log_id"]):
        raise ValueError("log_id must be decimal digits")
    if not _RUN_ID.fullmatch(event["export_run_id"]):
        raise ValueError("export_run_id has an invalid shape")
    if not _FILE_NAME.fullmatch(event["sap_file_name"]):
        raise ValueError("sap_file_name must be a safe .csv basename")
    if event["import_status"] not in _TERMINAL_IMPORT_STATUSES:
        raise ValueError("import_status is not an admitted terminal result")
    try:
        parsed_date = datetime.fromisoformat(event["email_date"].replace("Z", "+00:00"))
    except ValueError as error:
        raise ValueError("email_date must be ISO-8601") from error
    if parsed_date.tzinfo is None:
        raise ValueError("email_date must include a timezone")
    return event


def claim_token(event):
    exact_key = "\0".join(
        (event["log_id"], event["export_run_id"], event["sap_file_name"])
    )
    return hashlib.sha256(exact_key.encode("utf-8")).hexdigest()[:32]


def call_procedure(client, sql, parameters):
    config = bigquery.QueryJobConfig(
        query_parameters=[
            bigquery.ScalarQueryParameter(name, "STRING", value)
            for name, value in parameters.items()
        ],
        maximum_bytes_billed=20 * 1024 * 1024 * 1024,
    )
    return list(client.query(sql, job_config=config, location=configured("BQ_LOCATION")).result())


def claim(client, event, token):
    rows = call_procedure(
        client,
        "CALL `{project}.{dataset}.sp_claim_v3_post_import_refresh`"
        "(@log_id,@export_run_id,@sap_file_name,@claim_token)".format(
            project=configured("PROJECT_ID"), dataset=configured("BQ_DATASET")
        ),
        {
            "log_id": event["log_id"],
            "export_run_id": event["export_run_id"],
            "sap_file_name": event["sap_file_name"],
            "claim_token": token,
        },
    )
    if len(rows) != 1:
        raise RuntimeError("claim returned an unexpected row count")
    return {
        "status": rows[0]["request_status"],
        "execution": rows[0]["workflow_execution_name"],
        "attempt_count": int(rows[0]["attempt_count"]),
    }


def release(client, event, token):
    call_procedure(
        client,
        "CALL `{project}.{dataset}.sp_release_v3_post_import_claim`"
        "(@log_id,@claim_token,@error_template)".format(
            project=configured("PROJECT_ID"), dataset=configured("BQ_DATASET")
        ),
        {
            "log_id": event["log_id"],
            "claim_token": token,
            "error_template": "WORKFLOW_EXECUTION_CREATE_FAILED",
        },
    )


@app.post("/dispatch")
def dispatch():
    try:
        event = validate_event(decode_event(request.get_json(silent=True)))
        token = claim_token(event)
        bq_client = bigquery.Client(project=configured("PROJECT_ID"))
        state = claim(bq_client, event, token)
        if state["status"] == "STARTED" and state["execution"]:
            return ("", 204)
        if state["status"] != "CLAIMED" or state["attempt_count"] > 3:
            raise RuntimeError("outbox claim returned a non-dispatchable state")

        parent = (
            f"projects/{configured('PROJECT_ID')}/locations/"
            f"{configured('WORKFLOW_LOCATION')}/workflows/{configured('WORKFLOW_NAME')}"
        )
        argument = json.dumps(
            {
                "post_import_log_id": event["log_id"],
                "post_import_claim_token": token,
            },
            sort_keys=True,
            separators=(",", ":"),
        )
        try:
            ExecutionsClient().create_execution(
                parent=parent, execution=Execution(argument=argument)
            )
        except (BadRequest, Forbidden, NotFound):
            release(bq_client, event, token)
            raise
        return ("", 204)
    except ValueError as error:
        return jsonify(error=str(error)), 400
    except Exception:
        app.logger.exception("post-import dispatch failed")
        return jsonify(error="post-import dispatch failed"), 500
