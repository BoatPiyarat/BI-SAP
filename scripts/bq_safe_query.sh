#!/usr/bin/env bash
# scripts/bq_safe_query.sh
#
# Safety wrapper around `bq query`, per docs/COST_CONTROL.md §3.1:
#   - every non-metadata query gets --dry_run first, no exceptions
#   - if the dry-run's totalBytesProcessed exceeds 20 GiB, print a warning and STOP;
#     the real query only runs if the caller explicitly passes --force
#   - the real run always carries --maximum_bytes_billed=21474836480 (20 GiB) so a
#     query that slips past estimation fails fast instead of billing for it
#
# Usage:
#   scripts/bq_safe_query.sh [--force] [--project ID] "<SQL>"
#   scripts/bq_safe_query.sh [--force] [--project ID] -f path/to/query.sql
#   echo "SELECT ..." | scripts/bq_safe_query.sh [--force]
#   scripts/bq_safe_query.sh -f query.sql -- --format=csv --location=asia-southeast1
#
# Anything after a literal `--` is passed straight through to the real `bq query`
# invocation (e.g. --format=csv). It is never passed to the dry-run call, which
# always uses --format=json internally so bytes can be parsed reliably.
#
# Exit codes: 0 = ran (or dry-run-only informational stop below threshold was not
# requested); 1 = usage error; 2 = over threshold and --force not given (query was
# NOT run); 3 = bq itself failed.

set -euo pipefail

THRESHOLD_BYTES=21474836480   # 20 GiB, matches --maximum_bytes_billed below
MAX_BYTES_BILLED=21474836480

force=0
project=""
query_file=""
sql=""
passthrough_args=()

usage() {
  cat >&2 <<'EOF'
Usage:
  bq_safe_query.sh [--force] [--project ID] "<SQL>"
  bq_safe_query.sh [--force] [--project ID] -f path/to/query.sql
  echo "SELECT ..." | bq_safe_query.sh [--force]
  bq_safe_query.sh -f query.sql -- --format=csv

Options:
  --force            Run the real query even if dry-run estimates > 20 GiB.
                      Without this flag, an over-threshold query is NEVER run.
  --project ID       Passed through as --project_id to both dry-run and real bq calls.
  -f, --file PATH    Read the SQL from PATH instead of the trailing argument/stdin.
  --                 Everything after this is passed through verbatim to the real
                      `bq query` call only (e.g. --format=csv, --location=...).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)
      force=1
      shift
      ;;
    --project)
      project="${2:-}"
      [[ -z "$project" ]] && { echo "ERROR: --project requires a value" >&2; exit 1; }
      shift 2
      ;;
    -f|--file)
      query_file="${2:-}"
      [[ -z "$query_file" ]] && { echo "ERROR: --file requires a path" >&2; exit 1; }
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      passthrough_args=("$@")
      break
      ;;
    *)
      if [[ -n "$sql" ]]; then
        echo "ERROR: unexpected extra argument: $1 (query already set)" >&2
        usage
        exit 1
      fi
      sql="$1"
      shift
      ;;
  esac
done

if [[ -n "$query_file" ]]; then
  [[ -f "$query_file" ]] || { echo "ERROR: file not found: $query_file" >&2; exit 1; }
  sql="$(cat "$query_file")"
elif [[ -z "$sql" ]]; then
  if [[ -t 0 ]]; then
    echo "ERROR: no SQL given (positional arg, --file, or stdin) and stdin is a terminal" >&2
    usage
    exit 1
  fi
  sql="$(cat)"
fi

if [[ -z "${sql// /}" ]]; then
  echo "ERROR: empty query" >&2
  exit 1
fi

project_args=()
if [[ -n "$project" ]]; then
  project_args=(--project_id="$project")
fi

echo "== bq_safe_query: dry-run =========================================" >&2

dry_run_json="$(bq query --use_legacy_sql=false --dry_run --format=json "${project_args[@]}" "$sql" 2>&1)" || {
  echo "ERROR: dry-run itself failed:" >&2
  echo "$dry_run_json" >&2
  exit 3
}

if command -v jq >/dev/null 2>&1; then
  bytes="$(echo "$dry_run_json" | jq -r '(.statistics.totalBytesProcessed // .statistics.query.totalBytesProcessed // .totalBytesProcessed // "0")' 2>/dev/null || echo "0")"
else
  # Fallback without jq: grab the first "totalBytesProcessed": "NNN" occurrence.
  bytes="$(echo "$dry_run_json" | grep -o '"totalBytesProcessed"[[:space:]]*:[[:space:]]*"[0-9]*"' | head -1 | grep -o '[0-9]*$' || true)"
  bytes="${bytes:-0}"
fi

if ! [[ "$bytes" =~ ^[0-9]+$ ]]; then
  echo "ERROR: could not parse totalBytesProcessed from dry-run output:" >&2
  echo "$dry_run_json" >&2
  exit 3
fi

gib="$(awk -v b="$bytes" 'BEGIN { printf "%.3f", b / (1024*1024*1024) }')"
threshold_gib="$(awk -v b="$THRESHOLD_BYTES" 'BEGIN { printf "%.0f", b / (1024*1024*1024) }')"

echo "Dry-run estimate: ${bytes} bytes (~${gib} GiB)" >&2

if (( bytes > THRESHOLD_BYTES )); then
  echo "" >&2
  echo "⚠️  WARNING: dry-run estimate (~${gib} GiB) exceeds the ${threshold_gib} GiB threshold." >&2
  if (( force == 0 )); then
    echo "⚠️  NOT RUNNING. Re-run with --force if you have confirmed this cost is intended." >&2
    exit 2
  fi
  echo "⚠️  --force given — proceeding anyway." >&2
fi

echo "== bq_safe_query: real run (--maximum_bytes_billed=${MAX_BYTES_BILLED}) ===========" >&2

exec bq query --use_legacy_sql=false "${project_args[@]}" \
  --maximum_bytes_billed="${MAX_BYTES_BILLED}" \
  "${passthrough_args[@]}" \
  "$sql"
