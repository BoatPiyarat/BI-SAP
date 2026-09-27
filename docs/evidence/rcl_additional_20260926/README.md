# Evidence index

Final source binding: source_sha256.json. Final fully composed target execution:
target_eir_final.json + target_eir_job.json. Corrected full-field staged regression:
eir_regression.json + eir_job.json. Remaining two source deltas: remaining_diff.json
and tie_diagnostic.json. schema_comparison.json compares final physical schemas.
Identity fixtures: identity_fixtures_final.json; raw recency: date_fixture.json.

Historical/red evidence retained: full_payload_diff.json and dashboard_diff.json
show the pre-correction EIR regression; population_validation.json/population_job.json
record the superseded failed run, not successful validation. Other earlier target
and candidate-schema files are superseded where final_* / target_eir_* exists.

BQ temporary relations referenced by diagnostic SQL expire automatically. No row-level
customer PII is saved here. Source definitions and schemas contain column names only;
result evidence uses order identifiers, amounts, dates and diagnostic counts.

## Evening review delta

Final source hashes: review_delta_source_sha256.json; exact final native execution:
review_composed_final_binding.json and review_composed_target_final.json.
Final behavior: review_delta_fixtures.json (26 cases); old-source red test has24 cases.
Final full-payload evidence: review_final_children.json plus review_final_metrics.json;
physical schemas: review_final_candidate_*_schema.json. Correct all-charge ledger:
review_charge_ledger_final.jsonl and review_population_summary.json.

Superseded/error evidence: review_population.json is the capped job; review_population_final.json
and review_population_ledger.json used the wrong product enum grouping. Their totals are historical,
not the final product split. review_final_checks.json records the later diagnostic alias failure;
its completed child tables/results survive separately. All final claims use the exact-source native
job or the documented completed children and corrected continuation. See review-delta findings.
