# Authorized four-view release — 2026-09-28

See authorization.md and docs/reviews/2026-09-28-rcl-principal-independent.md.
User confirms additional-receipt principal = new charge amount for both principal fields.

Fresh metadata captured after reauthentication. Live definitions have no drift from the reviewed base.
Verbatim original bodies are in *_before.json; rollback/deploy SQL prepared from those bodies.
Fresh staged preflight rcl_release_preflight_20260928_001 completed successfully, 18,486,348,625 bytes
processed. Dry-run script estimate 0 is a scripting limitation, not a zero-cost claim. Safe wrapper
used the hard 20-GiB cap. All six failure metrics zero; 56/56/13/56 positional schemas unchanged.
Every final SELECT binds exactly to executed preflight after only temporary-table substitution.
Offline 12-case CASE-expression tests supplement the BigQuery checks; they do not replace them.

Source snapshot preflight output: baseline2474 -> candidate4036 rows. Snapshot output counts are not
SAP import counts. Existing carried SAP payloads are unchanged. No V3 or interface-file mutation.
Deployment and postcheck job records are added after successful execution.
