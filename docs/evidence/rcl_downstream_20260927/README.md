# Downstream repair evidence — 2026-09-27

Source-only; no production replacement, SAP write, GCS write, scheduler change or V3 mutation.
Metadata capture timestamp and object mapping: capture.json. Original SELECTs and schemas are retained
as dashboard/newpayment/gate/wrapper/create/paid_reader/paid SQL+JSON. paid was captured immediately afterward.

Authoritative final evidence: final_job.json, final_children.json, final_3_result.json,
schema_comparison.json, fixtures_final_132_result.json, gate_fixtures.json,
consumer_risks_1_result.json, candidate_hashes.json. Verify with
`python scripts/verify_rcl_downstream_20260927.py`.

The first staged script FAILED in a reporting SELECT referencing baseline_dashboard after materializing
all regression inputs and executing the first metrics SELECT. It is not a successful whole job.
Its exact SQL/error is retained in staged_job.json. Continuations reused its completed temporary tables.
The final job succeeded and embeds exact final candidate SQL after only captured-table substitution;
the verifier checks this binding. The standalone staged_regression.sql is corrected for future rebuilds.

Fixture v1 reused CREATE TEMP names in a loop; its caught errors are invalid evidence. v2 fixes isolation;
v3 also exempts already-terminal identities from the runtime lineage assertion. Only final v3 verdicts
support the final source. Each unexpected error fails the offline verifier.

BigQuery script dry runs report zero estimated bytes because of temporary-table scripting semantics;
this is not a zero-cost claim. Every execution used the safe wrapper and hard 20-GiB maximum billed cap.
Actual bytes are in saved job metadata. No cap was raised. Fixtures read synthetic inputs only.

Temp datasets expire; continuation SQL is forensic, not a permanent operational job. Full rebuild SQL
reads captured definitions and current underlying sources. Snapshot is not transactionally atomic across
CareOS/SAP. All counts are output candidates/identity comparisons, never proof of SAP import or GL posting.

596 older Paid rows added to the wrapper are verbatim carried SAP context. They are not new historical
receipts. 185 broad lineage diagnostic rows are not equivalent to 185 runtime failures or missing receipts:
65 ambiguous +120 invalid additional identity. The runtime assertion is narrower and exempts terminal
identities; diagnostics retain them. These files are durable audit evidence, not a recurring hold service.

principal_review.csv contains 8 later-period additional receipts requiring an accounting decision.
No principal formula has been inferred. V3 remains held; source review does not authorize deployment.

Readability copies of captured SQL and CLI output have normalized whitespace. Verbatim view bodies
remain in captured metadata JSON; source candidates bind to the final executed query via the verifier.
