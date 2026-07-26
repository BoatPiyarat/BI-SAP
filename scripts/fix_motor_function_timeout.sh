#!/usr/bin/env bash
# fix_motor_function_timeout.sh
#
# Raises the timeout on rcb-motor-order-payment-sap-bucket-1 from 300s to 540s (the gen1 max for
# event-triggered functions). This function has timed out every day for 5 straight days
# (2026-07-21 through 2026-07-25) while running its last step (RCL Motor newpayment), always
# killed around 296-299s - see 20_SAP_PROGRESS.md 2026-07-26 for the full investigation.
#
# WHY THIS SCRIPT AND NOT `gcloud functions deploy --timeout=540s`:
# `gcloud functions deploy` builds/uploads source from a local directory by default. Without a
# reachable copy of this function's actual deployed source (its original upload used a one-time
# signed URL, not a persistent archive path), running `deploy` risks replacing the function's real
# code with whatever happens to be in the current working directory - which would break ALL SIX
# daily export steps, not just fix the timeout on one.
#
# This script instead calls the Cloud Functions v1 REST API directly with `updateMask=timeout`,
# which is a documented partial-update: it changes ONLY the timeout field and leaves source code,
# environment variables, the Pub/Sub trigger, memory, and everything else exactly as they are.
#
# Requires: gcloud CLI authenticated as a principal with cloudfunctions.functions.update permission
# on this function (e.g. roles/cloudfunctions.developer or higher).
#
# Usage:
#   bash fix_motor_function_timeout.sh          # applies the fix (asks for confirmation first)
#   bash fix_motor_function_timeout.sh --dry-run # shows what would be sent, does not call the API

set -euo pipefail

PROJECT="pacific-plating-282708"
REGION="asia-southeast1"
FUNCTION="rcb-motor-order-payment-sap-bucket-1"
NEW_TIMEOUT="540s"

FUNCTION_PATH="projects/${PROJECT}/locations/${REGION}/functions/${FUNCTION}"
URL="https://cloudfunctions.googleapis.com/v1/${FUNCTION_PATH}?updateMask=timeout"
BODY="{\"timeout\": \"${NEW_TIMEOUT}\"}"

echo "About to PATCH:"
echo "  URL:  ${URL}"
echo "  Body: ${BODY}"
echo

if [[ "${1:-}" == "--dry-run" ]]; then
  echo "(dry run - not calling the API)"
  exit 0
fi

echo "Current config, before change:"
gcloud functions describe "${FUNCTION}" --region="${REGION}" --format="yaml(timeout,updateTime)"
echo

read -r -p "Apply this change to LIVE production? Type 'yes' to continue: " CONFIRM
if [[ "${CONFIRM}" != "yes" ]]; then
  echo "Aborted - no change made."
  exit 1
fi

TOKEN="$(gcloud auth print-access-token)"

curl -sS -X PATCH \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "${BODY}" \
  "${URL}"

echo
echo "PATCH submitted. This starts an async operation - verify below (may take a few seconds to apply):"
echo
sleep 5
gcloud functions describe "${FUNCTION}" --region="${REGION}" --format="yaml(timeout,updateTime,status)"
