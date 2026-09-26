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
