# Fixed September missing scenarios versus sap_view

Read docs/FINDINGS_CAREOS_SCENARIO_ROOT_CAUSES_20260926.md. Population is prior audit missing-evidence rows only, not REVIEW.

scenario_details.csv: all 1,525 links/documents; absent_from_sap_view.csv: 253 event-absent rows; scenario_summary.csv/json: mutually exclusive primary groups; output_payload_review.csv: payload/ownership flags, not missing-event counts.

Reproduce offline with scripts/analyze_month_scenario_routes_20260926.py. The script reads prior monthly CSVs plus captured route outputs. No live query or mutation is needed. Query source hashes and successful job bindings are in successful_jobs_and_bindings.json. .result.json files contain only selected non-PII payload columns. Definition SQL is whitespace-normalized; inventory JSON retains exact definition strings.

Cancelled-output cache comes from the earlier audit (see ../careos_month_audit_20260926/final_jobs.json), not a fresh all-view simultaneous snapshot. Definitions were checked unchanged. Adhoc SQL uses expiring BigQuery temporary tables and is a forensic artifact; refresh monthly population and rebind before future reruns.

Membership is item+period+invoice+status; it is not payload validation, route ownership, scheduling, export or SAP import proof. Cancellation identity membership does not prove one-to-one DocEntry multiplicity. Fourteen cancelled-item payment rows are an investigation scenario rather than a single proven predicate cause. Primary blocker assignment is exclusive, not exhaustive.
