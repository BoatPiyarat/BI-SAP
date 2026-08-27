# Review: private delivery promoter Cloud Run candidate

Reviewer: Claude Code
Artifact: `infra/sap_delivery_promoter/` at `65bd74a` (source delta `daa9331..65bd74a`) plus
`docs/V3_PROMOTER_DEPLOYMENT_PROPOSAL_20260827.md` (commit `337ccc5`)
Verdict: **PASS**

## Session limitation, stated up front

No live BigQuery/Cloud Run access in this session; Flask/GCS test dependencies aren't installed
here either (the requester disclosed the same gap). This is a static read of the Python source and
the deployment proposal, not a live test run or deployment.

## Verifying the two-name contract against the workflow that calls it

I compared `main.py`'s request/response fields directly against
`infra/v3_nightly_orchestrator.workflows.yaml`'s `promote_daily_archive` (reviewed separately in
`docs/reviews/2026-08-27-8a420d7-full-delta-claude.md`, which flagged this exact service as an
unverified external dependency):

- Request: workflow sends `production_file_name` (not the old `sap_file_name`); `main.py` requires
  exactly that key (`required_string(payload, "production_file_name")`, line 95) and rejects the
  legacy one-name payload — confirmed by `test_legacy_one_name_payload_is_rejected`.
- Response: `main.py` returns `production_file_name`, `header_column_count`, and `data_row_count`
  (lines 148-151) — the exact three fields the workflow's `inspect_promotion`/`gate_promotion` steps
  read via `map.get(promotion, ...)`. This closes the dependency gap I flagged as unverifiable from
  this repo in the earlier review.
- Canonical 56-column header (lines 21-33) is byte-identical, same order, to the column list I
  already verified against `v3_unit5_newpayment_delivery_ready` in the DDL 100 review.

## Correctness of the create-only, exact-generation copy

- `source = client.bucket(...).blob(archive_object, generation=int(archive_generation))` pins the
  read to one immutable GCS generation; GCS generations are immutable once written, so there is no
  TOCTOU window between computing `file_sha256`/`csv_shape_for_blob` from this pinned generation and
  the later `destination.rewrite(source, ...)` server-side copy — the bytes read and the bytes
  copied are guaranteed identical by the platform, not by application-level locking.
- `destination.rewrite(source, token=rewrite_token, if_generation_match=0)` is the correct GCS
  precondition for "must not already exist"; `PreconditionFailed` maps to `409` with a clear
  "already exists" message rather than silently overwriting.
- Post-copy, `destination.size`/`destination.crc32c` are compared against the same pinned source
  object's values (not re-read from the destination's own independent computation) — combined with
  the SHA-256 computed directly from the pinned source bytes, this is real integrity evidence, not
  a rubber-stamped success response.
- `csv_shape_for_blob` validates UTF-8, exactly 56 columns per data row, exact canonical header
  order, and at least one data row — all *before* the copy is attempted, so a malformed source
  object fails closed without ever touching the production bucket.
- Bucket/prefix names are validated against `os.environ` configuration rather than trusted from the
  caller, so even an internal caller mistake can't redirect the copy to an unconfigured bucket.

## Deployment proposal

- `--ingress internal`, `--no-allow-unauthenticated`, and an explicit invoker binding scoped to one
  service account — no `allUsers`/`allAuthenticatedUsers` path exists in the proposed commands.
- Environment variables in the `gcloud run deploy` command match `main.py`'s three required
  `configured_name()` calls (`ARCHIVE_BUCKET`, `PRODUCTION_BUCKET`, `PRODUCTION_PREFIX`) exactly.
- Rollback section correctly identifies that deleting a Cloud Run service plus its IAM binding is
  itself a destructive action requiring separate approval, and that leaving an unreferenced private
  service deployed is lower-risk than an unapproved deletion — consistent with `delivery_enabled`
  staying hardcoded `false` regardless of whether this service exists.
- Runtime identity is the project's default Compute Engine service account
  (`919786098205-compute@...`), which is broader than a dedicated least-privilege SA would be — but
  this repo already has a standing accepted workaround for that exact constraint
  (`docs/design/DEFAULT_COMPUTE_SA_AUTOMATION_WORKAROUND.md`), so I'm not treating it as a new risk
  introduced here.

## Checklist 1–12

1. **Traceability — N/A.** Source only; no deploy/CALL performed by this artifact.
2. **Provenance — PASS.** Builds on the already-reviewed two-name delta rather than inventing a new
   filename contract.
3. **NULL-safety — PASS.** `required_string` rejects missing/non-string/empty fields before use;
   `configured_name` fails loudly on missing environment configuration rather than defaulting.
4. **Ordering — N/A.**
5. **Column order — PASS.** `_CANONICAL_HEADER` is checked via exact tuple equality
   (`tuple(header) != _CANONICAL_HEADER`), not a set/membership check — a reordered header is
   correctly rejected, not silently accepted.
6. **Grain — N/A.** No row-grain logic in this service; it validates and copies a whole file.
7. **Distribution — PASS.** `data_row_count` is a real per-row width check (56 columns each), not a
   bare file-size or total-row-count proxy.
8. **Knowledge consistency — PASS.** Matches `FINDINGS_LOG21183_FILENAME_BINDING_GAP_20260805.md`'s
   two-name requirement exactly, and closes the specific external-dependency gap my own prior
   review flagged as unverifiable from source.
9. **Scope — PASS.** Changes confined to `infra/sap_delivery_promoter/`.
10. **Rollback — PASS.** Correctly identified as destructive service deletion, gated separately.
11. **Cost hygiene — N/A.** Not a BigQuery artifact.
12. **Honest labelling — PASS.** Proposal doc states "PROPOSED / NOT EXECUTED" and explicitly notes
    deploying this service does not enable delivery or create a schedule.

## Minor note (not a blocker)

`sha256_for_blob` and `csv_shape_for_blob` each independently `blob.open("rb")` and stream the full
source object once — two full downloads per promotion instead of one. Correctness is unaffected
(both reads are pinned to the same immutable generation), but for a large file this doubles
promoter latency and egress. Worth a follow-up optimization, not a blocking issue.

No BLOCK. This closes the external-dependency gap flagged in the earlier workflow-replacement
review; the remaining sequencing item from that review is deploying this service (still pending,
per the proposal's own "PROPOSED / NOT EXECUTED" status) alongside DDL 067's transaction-wrapper fix
noted separately.
