#!/usr/bin/env bash
# scripts/bq_safe_query.sh
#
# Safety wrapper around `bq query`, per docs/COST_CONTROL.md §3.1:
#   - every non-metadata query gets --dry_run first, no exceptions
#   - the dry-run's totalBytesProcessed MUST be present and numeric, or this is an
#     ERROR (never silently treated as 0 bytes) - a parser that can't read the
#     estimate must refuse to run the real query, not assume it's cheap
#   - 20 GiB (21,474,836,480 bytes) is a HARD CEILING. There is no --force and no
#     override. A query estimated above it is never run by this script; redesign
#     the query (partition filter, narrower date range, sampling) instead.
#   - the real run always carries --maximum_bytes_billed=21474836480 (20 GiB) so a
#     query that slips past estimation fails fast instead of billing for it
#
# ============================================================================
# Fixed 2026-07-30 per class-A BLOCK docs/reviews/2026-07-30-a56f6d1-codex.md:
#   1. Byte parsing previously fell back to "0" on ANY unparseable/missing shape,
#      which let a query past the guardrail with zero cost check performed. Fixed:
#      absent/unparseable totalBytesProcessed is now always an error (exit 3).
#      An explicit "0" in the dry-run JSON is the only way to get 0 bytes.
#   2. --force previously still capped the real run at 20 GiB, so it could never
#      actually do what its help text promised (run an over-threshold query).
#      Resolved by removing --force entirely: 20 GiB is a hard ceiling, no
#      exceptions, matching docs/AGENT_RULES.md's "Mandatory query path" language.
#   3. Added --self-test: runs 7 offline parser cases with no BigQuery calls
#      (current JSON shape, nested JSON shape, explicit zero, missing field,
#      malformed value, threshold equality, threshold+1). Run before every commit
#      that touches this file.
# ============================================================================
#
# Usage:
#   scripts/bq_safe_query.sh [--project ID] "<SQL>"
#   scripts/bq_safe_query.sh [--project ID] -f path/to/query.sql
#   echo "SELECT ..." | scripts/bq_safe_query.sh
#   scripts/bq_safe_query.sh -f query.sql -- --format=csv --location=asia-southeast1
#   scripts/bq_safe_query.sh --self-test
#
# Anything after a literal `--` is passed straight through to the real `bq query`
# invocation (e.g. --format=csv). It is never passed to the dry-run call, which
# always uses --format=json internally so bytes can be parsed reliably.
#
# Exit codes: 0 = ran; 1 = usage error; 2 = over the 20 GiB ceiling (query was NOT
# run, no override exists); 3 = bq itself failed, or the dry-run's byte estimate
# could not be read (also NOT run - fail closed, not open).

set -euo pipefail

THRESHOLD_BYTES=21474836480   # 20 GiB, matches --maximum_bytes_billed below
MAX_BYTES_BILLED=21474836480

# ============================================================================
# parse_bytes_processed - the one place dry-run JSON gets turned into a byte
# count. Takes the raw dry-run JSON text on stdin. Prints the byte count (a
# plain non-negative integer) on stdout and returns 0, OR prints nothing and
# returns 1 if the value is absent, non-numeric, or the JSON itself is
# unreadable. Callers MUST treat a non-zero return as a hard error, never as 0.
# ============================================================================
parse_bytes_processed() {
  local json="$1"
  local value

  if command -v jq >/dev/null 2>&1; then
    # jq's `//` alternative operator only falls through on `null`/`false`, so an
    # actual JSON/string "0" for totalBytesProcessed is preserved as "0", not
    # treated as absent - only a truly missing path reaches the "MISSING" sentinel.
    value="$(printf '%s' "$json" | jq -r '
      (.statistics.totalBytesProcessed
       // .statistics.query.totalBytesProcessed
       // .totalBytesProcessed
       // "MISSING")
    ' 2>/dev/null || printf 'JQ_FAILED')"
  else
    # No-jq fallback: look for the field textually. Cannot reliably distinguish
    # "present as JSON number 0" from "absent" as precisely as jq, but still
    # must not silently invent a 0 - absence of the pattern is MISSING.
    value="$(printf '%s' "$json" | grep -o '"totalBytesProcessed"[[:space:]]*:[[:space:]]*"\{0,1\}[0-9]\{1,\}"\{0,1\}' | head -1 | grep -o '[0-9]\{1,\}' || true)"
    [[ -z "$value" ]] && value="MISSING"
  fi

  if [[ "$value" == "MISSING" || "$value" == "JQ_FAILED" ]]; then
    return 1
  fi
  if ! [[ "$value" =~ ^[0-9]+$ ]]; then
    return 1
  fi
  printf '%s' "$value"
  return 0
}

run_self_test() {
  local failures=0

  check() {
    local name="$1" input="$2" expect_ok="$3" expect_value="${4:-}"
    local got rc
    if got="$(parse_bytes_processed "$input")"; then
      rc=0
    else
      rc=1
      got=""
    fi
    if [[ "$expect_ok" == "ok" ]]; then
      if [[ $rc -eq 0 && "$got" == "$expect_value" ]]; then
        echo "PASS: $name"
      else
        echo "FAIL: $name (expected ok/$expect_value, got rc=$rc value='$got')"
        failures=$((failures + 1))
      fi
    else
      if [[ $rc -ne 0 ]]; then
        echo "PASS: $name"
      else
        echo "FAIL: $name (expected error, got ok/value='$got')"
        failures=$((failures + 1))
      fi
    fi
  }

  # 1. current JSON shape - flat .statistics.totalBytesProcessed
  check "current JSON shape" \
    '{"statistics":{"totalBytesProcessed":"12345"}}' \
    ok "12345"

  # 2. nested JSON shape - .statistics.query.totalBytesProcessed
  check "nested JSON shape" \
    '{"statistics":{"query":{"totalBytesProcessed":"67890"}}}' \
    ok "67890"

  # 3. explicit zero - a real 0-byte dry-run must NOT be treated as an error
  check "explicit zero" \
    '{"statistics":{"totalBytesProcessed":"0"}}' \
    ok "0"

  # 4. missing field entirely - must be an ERROR, not fall back to 0
  check "missing field" \
    '{"statistics":{"totalBytesBilled":"111"}}' \
    error

  # 5. malformed value - non-numeric string - must be an ERROR
  check "malformed value" \
    '{"statistics":{"totalBytesProcessed":"not-a-number"}}' \
    error

  # 6. threshold equality - exactly 20 GiB, must parse fine (the threshold
  #    comparison itself, > not >=, is exercised in the main script logic, not
  #    here - this only proves the parser handles the exact boundary value)
  check "threshold equality value parses" \
    '{"statistics":{"totalBytesProcessed":"21474836480"}}' \
    ok "21474836480"

  # 7. threshold+1 - one byte over, must parse fine (threshold DECISION is
  #    made by the caller comparing the parsed integer, not by this function)
  check "threshold+1 value parses" \
    '{"statistics":{"totalBytesProcessed":"21474836481"}}' \
    ok "21474836481"

  echo ""
  if (( failures == 0 )); then
    echo "SELF-TEST: 7/7 passed"
    return 0
  else
    echo "SELF-TEST: ${failures} FAILURE(S)"
    return 1
  fi
}

usage() {
  cat >&2 <<'EOF'
Usage:
  bq_safe_query.sh [--project ID] "<SQL>"
  bq_safe_query.sh [--project ID] -f path/to/query.sql
  echo "SELECT ..." | bq_safe_query.sh
  bq_safe_query.sh -f query.sql -- --format=csv
  bq_safe_query.sh --self-test

Options:
  --project ID       Passed through as --project_id to both dry-run and real bq calls.
  -f, --file PATH    Read the SQL from PATH instead of the trailing argument/stdin.
  --self-test        Run 7 offline parser test cases (no BigQuery calls) and exit.
  --                 Everything after this is passed through verbatim to the real
                      `bq query` call only (e.g. --format=csv, --location=...).

20 GiB (21,474,836,480 bytes) is a hard ceiling. There is no override flag. A
query estimated above it is never run - redesign it (partition filter, narrower
date range, TABLESAMPLE) instead of trying to force it through.
EOF
}

project=""
query_file=""
sql=""
passthrough_args=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --self-test)
      run_self_test
      exit $?
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

if ! bytes="$(parse_bytes_processed "$dry_run_json")"; then
  echo "ERROR: could not read totalBytesProcessed from dry-run output (absent or" >&2
  echo "unparseable) - refusing to run the real query. This is a hard failure, not" >&2
  echo "a 0-byte assumption. Raw dry-run output:" >&2
  echo "$dry_run_json" >&2
  exit 3
fi

gib="$(awk -v b="$bytes" 'BEGIN { printf "%.3f", b / (1024*1024*1024) }')"
threshold_gib="$(awk -v b="$THRESHOLD_BYTES" 'BEGIN { printf "%.0f", b / (1024*1024*1024) }')"

echo "Dry-run estimate: ${bytes} bytes (~${gib} GiB)" >&2

if (( bytes > THRESHOLD_BYTES )); then
  echo "" >&2
  echo "⚠️  BLOCKED: dry-run estimate (~${gib} GiB) exceeds the ${threshold_gib} GiB hard ceiling." >&2
  echo "⚠️  There is no override. Redesign the query (partition filter, narrower date" >&2
  echo "⚠️  range, TABLESAMPLE) and re-run." >&2
  exit 2
fi

echo "== bq_safe_query: real run (--maximum_bytes_billed=${MAX_BYTES_BILLED}) ===========" >&2

exec bq query --use_legacy_sql=false "${project_args[@]}" \
  --maximum_bytes_billed="${MAX_BYTES_BILLED}" \
  "${passthrough_args[@]}" \
  "$sql"
