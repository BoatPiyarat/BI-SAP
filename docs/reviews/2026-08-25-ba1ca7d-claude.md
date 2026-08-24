# Review: RQ-20260824-2358 installment-invoiceno-exact-live-deploy

Reviewer: Claude Code
Artifact: `ba1ca7d`; `docs/AGENT_RULES.md` (one-time legacy-view exception) and
`sql/production/20260824_deploy_installment_invoiceno_null_safety.sql`
Verdict: **PASS**

## Verification performed

Per protocol, metadata-only reads (`INFORMATION_SCHEMA.VIEWS`, `bq show`) plus local hashing and a
dry-run of the candidate file — not counted against the one-query budget per the established
metadata-read precedent, since none of these mutate anything.

- **Live definition hash: exact match.** `SELECT TO_HEX(SHA256(view_definition)) FROM
  sap_data_engineer.INFORMATION_SCHEMA.VIEWS WHERE table_name='sap_dashboard_carepay_installment'`
  returns `fa0a557260d99083b9bd3af1aa2a09d5f55828d8c15088235ff7a3cd071f1aa7` — matches the claimed
  "live query SHA-256" exactly.
- **`lastModifiedTime`: exact match.** `bq show` on the live view returns
  `lastModifiedTime=1786025613958` — matches exactly, and confirms the view hasn't changed since
  this artifact captured it (no drift between evidence and current live state).
- **Candidate hash: independently reproduced.** Extracted the query body from the local file
  (everything after `CREATE OR REPLACE VIEW ... AS`) and hashed it myself:
  `148813fb8035046a456a090b0cc76c982dc6b52fec0a89ae9bdad72fef2cf163` — matches the claimed candidate
  hash exactly.
- **Reverse-edit identity independently reproduced — the strongest check here.** I took the
  candidate body, mechanically reverted the two claimed predicate edits
  (`COALESCE(charges.status,'') <> 'SUCCESSFUL'` → `charges.status <> 'SUCCESSFUL'`;
  `COALESCE(TransactionStatus,'') <> 'SUCCESSFUL'` → `TransactionStatus <> 'SUCCESSFUL'`), rehashed,
  and got **exactly** `fa0a5572...` — byte-for-byte identical to the live definition. This proves,
  independent of trusting the diff description, that (a) the candidate really is derived from the
  current live object, and (b) nothing else in this 31,348-byte definition differs.
- **Predicate-count claims verified by direct grep**, not just narrative: exactly one
  `COALESCE(charges.status,'')` occurrence (voluntary fix), exactly one
  `COALESCE(TransactionStatus,'')` occurrence (transformation fix), exactly one bare
  `charges.status <> 'SUCCESSFUL'` (compulsory branch, correctly left untouched — the separate,
  out-of-scope bug already documented in the prior BLOCK review), and zero remaining unfixed bare
  `TransactionStatus <> 'SUCCESSFUL'` occurrences.
- **Compulsory branch's other known quirk also correctly untouched**: `CONCAT('2_',
  charges.third_party_id)` (no `COALESCE` around `third_party_id`) still appears exactly once,
  unchanged — the separate, already-documented, deliberately out-of-scope residual bug.
- **Dry-run independently reproduced**: 0 bytes, confirms both correct syntax and that the
  statement is metadata-only (a view replacement, no data scan).
- **Exactly one DDL statement in the file** (`grep -nE "CREATE |ALTER |DROP |INSERT |UPDATE |DELETE
  |MERGE "` returns only the single `CREATE OR REPLACE VIEW` line), targeting only the authorized
  object — no scope creep.
- **`AGENT_RULES.md` exception is narrowly scoped**: named to exactly one object, exactly the two
  reviewed predicates, and explicitly states "not a general exception for `sap_data_engineer` or any
  other legacy object" — consistent with `AGENT_RULES.md`'s existing DEPLOY GATE and SINGLE DEPLOYER
  rules (deployment still requires PASS + separate explicit Boat approval, and must run through
  Codex).

## Non-blocking note

No standalone rollback script is included (unlike the August-cutoff correction's paired rollback
file). It's fully recoverable in practice — the exact live definition is already captured and its
hash independently verified above, so redeploying it verbatim is the rollback — but a saved rollback
`.sql` (the current live text as its own file) would make that faster to execute under pressure.
Suggest adding one before or shortly after deployment, not a blocker to this PASS.

## Checklist 1–12

1 traceability PASS (every cited hash/timestamp independently reproduced from live objects, exact
matches); 2 provenance PASS (cites `a3d0305`/`0ac324f`/`18d0013` and the prior BLOCK's known
compulsory-branch residual correctly rather than re-deriving it); 3 NULL-safety PASS (both fixed
predicates now NULL-safe via `COALESCE`, verified directly in the file); 4 ordering N/A; 5 column
order N/A (behavior-only predicate change, not a new interface column set — reverse-edit proof shows
literally nothing else changed); 6 grain N/A; 7 distribution N/A (no row-count-based correctness
claim made here — that was already established in the earlier `18d0013` evidence); 8 knowledge PASS
(consistent with the new narrowly-scoped `AGENT_RULES.md` exception and Boat's recorded clearance);
9 scope PASS (exactly one DDL statement, exactly the authorized view, no other object touched); 10
rollback NOTE (recoverable via the already-hashed live definition, but no saved rollback file — see
above); 11 cost hygiene PASS (dry-run independently reproduced at 0 bytes); 12 honest labelling PASS
("No deployment occurred" is accurate — this artifact is source-only, and the file is clearly
headed "DO NOT RUN WITHOUT CLASS-A PASS + SEPARATE BOAT DEPLOY APPROVAL").

Summary: Checklist 1–12 reviewed; the reverse-edit hash proof is about as strong a guarantee as this
class of change can get — it independently establishes both correct derivation and that nothing
beyond the two authorized predicates differs. One non-blocking note: save a rollback file alongside
the deploy artifact. Deployment remains gated on a separate explicit Boat deploy approval, executed
by Codex per SINGLE DEPLOYER.
