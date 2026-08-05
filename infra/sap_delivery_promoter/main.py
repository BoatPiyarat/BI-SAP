"""Create-only exact-generation GCS promotion with SHA-256 evidence.

This service is intentionally not a scheduler and has no SAP or BigQuery access.  It is invoked
only by the delivery-disabled workflow once a separately approved deployment enables that gate.
"""

import hashlib
import os
import re

from flask import Flask, jsonify, request
from google.api_core.exceptions import PreconditionFailed
from google.cloud import storage

app = Flask(__name__)

_FILENAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*\.csv$")
_GENERATION = re.compile(r"^[1-9][0-9]*$")


def required_string(payload, field):
    value = payload.get(field)
    if not isinstance(value, str) or not value:
        raise ValueError("missing required field: " + field)
    return value


def configured_name(name):
    value = os.environ.get(name, "")
    if not value:
        raise RuntimeError("missing required service configuration: " + name)
    return value


def sha256_for_blob(blob):
    digest = hashlib.sha256()
    with blob.open("rb") as source:
        while chunk := source.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


@app.post("/promote")
def promote():
    payload = request.get_json(silent=True)
    if not isinstance(payload, dict):
        return jsonify(error="request body must be a JSON object"), 400

    try:
        archive_bucket_name = required_string(payload, "archive_bucket")
        archive_object = required_string(payload, "archive_object")
        archive_generation = required_string(payload, "archive_generation")
        production_bucket_name = required_string(payload, "production_bucket")
        production_object = required_string(payload, "production_object")
        production_file_name = required_string(payload, "production_file_name")

        if not _GENERATION.fullmatch(archive_generation):
            raise ValueError("archive_generation must be a positive decimal generation")
        if not _FILENAME.fullmatch(production_file_name):
            raise ValueError("production_file_name must be a safe .csv basename")
        if archive_bucket_name != configured_name("ARCHIVE_BUCKET"):
            raise ValueError("archive_bucket does not match service configuration")
        if production_bucket_name != configured_name("PRODUCTION_BUCKET"):
            raise ValueError("production_bucket does not match service configuration")
        prefix = configured_name("PRODUCTION_PREFIX").rstrip("/") + "/"
        if production_object != prefix + production_file_name:
            raise ValueError(
                "production_object must be the configured prefix plus production_file_name"
            )
        if archive_object.startswith("/") or ".." in archive_object.split("/"):
            raise ValueError("archive_object is not a safe object name")
    except (RuntimeError, ValueError) as error:
        return jsonify(error=str(error)), 400

    client = storage.Client()
    source = client.bucket(archive_bucket_name).blob(
        archive_object, generation=int(archive_generation)
    )
    destination = client.bucket(production_bucket_name).blob(production_object)
    try:
        source.reload()
        if not source.size or not source.crc32c:
            raise ValueError("source object lacks nonzero size or CRC32C metadata")
        file_sha256 = sha256_for_blob(source)
        rewrite_token = None
        while True:
            rewrite_token, _, _ = destination.rewrite(
                source, token=rewrite_token, if_generation_match=0
            )
            if rewrite_token is None:
                break
        destination.reload()
        if destination.size != source.size or destination.crc32c != source.crc32c:
            raise ValueError("destination size or CRC32C differs from source generation")
    except PreconditionFailed:
        return jsonify(error="production destination already exists; create-only promotion refused"), 409
    except ValueError as error:
        return jsonify(error=str(error)), 409

    return jsonify(
        archive_uri="gs://" + archive_bucket_name + "/" + archive_object,
        archive_generation=str(source.generation),
        production_uri="gs://" + production_bucket_name + "/" + production_object,
        production_generation=str(destination.generation),
        size_bytes=destination.size,
        crc32c=destination.crc32c,
        production_file_name=production_file_name,
        file_sha256=file_sha256,
    )
