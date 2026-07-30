#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
queue="$repo_root/docs/REVIEW_QUEUE.md"
since="${REVIEW_AUDIT_SINCE:-2026-07-29T00:00:00+07:00}"
current_reviewer="${REVIEWER_NAME:-${1:-}}"

if [[ ! -f "$queue" ]]; then
  echo "ERROR: $queue not found" >&2
  exit 1
fi

now_epoch="$(date +%s)"
tmp_entries="$(mktemp)"
trap 'rm -f "$tmp_entries"' EXIT

awk '
  /^## RQ-/ {
    if (id != "") print id "\t" status "\t" reviewer "\t" class "\t" artifact "\t" opened
    id=$2; status=""; reviewer=""; class=""; artifact=""; opened=""
    next
  }
  id != "" && /^Status: /   { if (status=="")   status=substr($0,9); next }
  id != "" && /^Reviewer: / { if (reviewer=="") reviewer=substr($0,11); next }
  id != "" && /^Class: /    { if (class=="")    class=substr($0,8); next }
  id != "" && /^Artifact: / { if (artifact=="") artifact=substr($0,11); next }
  id != "" && /^Opened: /   { if (opened=="")   opened=substr($0,9); next }
  END {
    if (id != "") print id "\t" status "\t" reviewer "\t" class "\t" artifact "\t" opened
  }
' "$queue" > "$tmp_entries"

echo "OPEN reviews"
open_total=0
declare -A reviewer_counts=()
while IFS=$'\t' read -r id status reviewer class artifact opened; do
  [[ "$status" == "OPEN" ]] || continue
  open_total=$((open_total + 1))
  reviewer_counts["$reviewer"]=$(( ${reviewer_counts["$reviewer"]:-0} + 1 ))
  opened_epoch="$(date -d "$opened" +%s 2>/dev/null || true)"
  if [[ -n "$opened_epoch" ]]; then
    age_seconds=$((now_epoch - opened_epoch))
    (( age_seconds < 0 )) && age_seconds=0
    age_hours=$((age_seconds / 3600))
    age="${age_hours}h"
  else
    age="UNKNOWN"
  fi
  printf '%s | reviewer=%s | class=%s | age=%s | artifact=%s\n' \
    "$id" "$reviewer" "$class" "$age" "$artifact"
done < "$tmp_entries"

echo
echo "OPEN by reviewer"
if (( open_total == 0 )); then
  echo "none"
else
  while IFS= read -r reviewer; do
    printf '%s: %s\n' "$reviewer" "${reviewer_counts[$reviewer]}"
  done < <(printf '%s\n' "${!reviewer_counts[@]}" | sort)
fi
echo "TOTAL: $open_total"
if [[ -n "$current_reviewer" ]]; then
  mine="${reviewer_counts[$current_reviewer]:-0}"
  echo "Review debt: $open_total OPEN (mine: $mine)"
fi

echo
echo "⚠️ commits touching sql/ddl/** or docs/knowledge/** without a REVIEW REQUEST reference"
missing=0
while IFS='|' read -r full_hash short_hash committed_at subject; do
  if ! grep -Eq "(^|[^0-9a-f])(${full_hash}|${short_hash})([^0-9a-f]|$)" "$queue"; then
    printf '⚠️ %s | %s | %s\n' "$short_hash" "$committed_at" "$subject"
    missing=$((missing + 1))
  fi
done < <(git log --since="$since" --format='%H|%h|%cI|%s' -- sql/ddl docs/knowledge)

if (( missing == 0 )); then
  echo "none"
fi
