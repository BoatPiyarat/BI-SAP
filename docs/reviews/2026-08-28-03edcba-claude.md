# Review: DDL 058 delta — all Unit 5 item-level pre-export validations quarantined

Reviewer: Claude Code
Artifact: commit `03edcba` (delta from `37b5a9b`); `sql/ddl/058_v3_unit5_newpayment_shadow.sql`,
`scripts/check_v3_unit5_required_hold_fix.py`,
`sql/operator/20260827_verify_v3_unit5_required_hold_fixture.sql`
Request: `docs/reviews/2026-08-28-03edcba-claude-request.md`, queued as
`RQ-20260828-0056-v3-unit5-item-validation-quarantine-delta` (found already correctly queued this
time — first request this session that landed in `docs/REVIEW_QUEUE.md` without needing a backfill)
Prior review this closes: `docs/reviews/2026-08-27-37b5a9b-claude.md` (Note 1: `POLICYNO_TOO_LONG`
and Paid-completeness remained candidate-wide fail-closed aborts, not item-level quarantine)
Verdict: **PASS**

## Method note

Working tree state is currently diverged between local (unpushed commits from a separate automated
Claude invocation reviewing a different, smaller delta — commit `20809d1` — already recorded
locally) and remote (this artifact, `03edcba`, plus its own newer fix lineage). To review the exact
artifact commit without merging or otherwise mutating either branch, I created a detached
`git worktree` at `03edcba`, ran the offline checker there, and read the files from that isolated
checkout. No branch was merged, rebased, or pushed.

## Delta, read directly against `37b5a9b`

All eight item-level pre-export rules — `SPINE_INCOMPLETE`, `STATUS_INVALID`,
`DUPLICATE_PERIOD_INVOICE_IDENTITY`, `POLICYNO_TOO_LONG`, `PAID_REQUIRED_FIELD_BLANK`,
`REQUIRED_VALUE_NULL_OR_LITERAL_NULL`, `DATE_FORMAT_INVALID`, `PAYMENT_DATE_FORMAT_INVALID` — now
feed one unified `_candidate_validation_issue` table instead of five separate candidate-wide
`ASSERT`s that used to abort the whole procedure. Every wide `SELECT *`/`SELECT DISTINCT *` in DDL
058's positional builds and INSERTs (there were four: `_candidate`'s first branch,
`_candidate_release`, `v3_unit5_newpayment_ready`'s CTAS, and the three publish-time INSERTs) was
replaced with an explicit 56-column list. Missing/blank `OrderItem` correctly remains a hard
file-level abort — there is no durable item identity to quarantine against, and the request states
this plainly rather than pretending it was also converted.

## Review questions, answered directly

**1. Does every applicable item-level pre-export failure now produce one durable whole-item hold
without weakening file-level identity/schema/mapping assertions?** Yes. All eight rules populate
`_candidate_validation_issue`, grouped to one `_candidate_required_hold` row per `OrderItem` with a
`|`-joined `hold_reason` listing every triggered rule code (an item can carry more than one issue
at once — e.g. a bad spine and a blank Paid field — and this is preserved, not collapsed to the
first match). The unchanged file-level assertions — `p_pipeline_run_id` non-blank, exactly one
`OPEN` period, zero automation blockers, `_resolved` bijective resolution, NonMotor InsuranceGroup
presence, ONETIME-can't-resolve-RCL — are untouched; none of them were converted, none needed to
be, since they're either pipeline-identity gates or cross-item resolution invariants, not
per-item data-quality checks.

**2. Can any held item leak into producer hash/count, ready rows, event identity, DDL 059, or
archive?** No, and this delta adds a *second*, independent leak-proof: beyond the unchanged
structural guarantees I verified in the prior review (producer hash computed from
`_candidate_release` only; `v3_unit5_payload_identity` insert filtered to released OrderItems), this
commit adds `ASSERT (SELECT COUNT(*) FROM _candidate_validation_issue i WHERE EXISTS (SELECT 1 FROM
_candidate_release r WHERE r.OrderItem=i.order_item))=0 AS 'Released NEWPAYMENT item still has a
validation issue'` — a direct, positive check that no released item has *any* recorded issue, not
just an inference from set construction. DDL 059/archive were not touched in this diff; they
consume `newpayment_ready`, which remains confirmed clean.

**3. Are release + hold item sets conserved for ordinary, zero-held, and zero-released
populations?** Yes, confirmed by direct read of the fixture (not just trusted from the request):
the `MIXED` case holds all 7 deliberately-broken items and releases exactly the 1 clean 2-period
item (2 rows); `ZERO_HELD` holds 0 and releases 1; `ZERO_RELEASED` holds 1 and releases 0. The
fixture also carries the same no-leak assertion as production (`a held item leaked into fixture
release`). Population conservation (`COUNT(DISTINCT OrderItem)` on the full candidate equals
released plus held) is unchanged from the prior revision and still present.

**4. Are issue and field aggregations PII-safe, deterministic, and at exact OrderItem grain?**
Yes. `_candidate_invalid_field` is grouped to one row per `order_item` (`ARRAY_AGG(DISTINCT
field_name ORDER BY field_name)` — deterministic ordering); `_candidate_required_hold` groups
`_candidate_validation_issue` by `order_item` and LEFT JOINs that single pre-aggregated row per
item rather than re-aggregating inline — this is exactly the fix for the self-reported
"non-decorrelatable field-array subquery" the request's evidence describes hitting and correcting.
None of the eight rules' `field_name` values can ever be a real data value — `STATUS_INVALID`,
`PAID_REQUIRED_FIELD_BLANK`, `POLICYNO_TOO_LONG`, `DATE_FORMAT_INVALID`,
`PAYMENT_DATE_FORMAT_INVALID` all emit a hardcoded column-name literal; `SPINE_INCOMPLETE` and
`DUPLICATE_PERIOD_INVOICE_IDENTITY` emit `NULL`; `REQUIRED_VALUE_NULL_OR_LITERAL_NULL` uses the
same regex-captured-JSON-key mechanism verified safe in the prior review.

**5. Are all positional 56-column projections and INSERTs explicit and order-preserving?** Yes,
confirmed by direct read of the diff — every one of the four wide-projection sites now lists all 56
columns by name in the DDL's own established column order, and I independently confirmed via the
worktree checkout that `grep -nE "SELECT\s+(DISTINCT\s+)?\*"` returns zero matches in the file.

**6. Are transaction claim, hold publication, ready publication, and identity publication
replay-safe and atomic?** Yes, unchanged from the prior revision — same
`BEGIN TRANSACTION`/run-state-claim-MERGE/`COMMIT TRANSACTION` structure, only the hold-table
column list in the publish INSERT changed (to match the renamed `invalid_period_count` column and
the explicit-column-list convention). The checker's own build-order assertion now additionally
verifies `_candidate_validation_issue` is built before `_candidate_required_hold` before
`_candidate_release`, in addition to the existing hold-before-ready-before-commit ordering.

**7. Does the fixture materially exercise each newly item-scoped rule and the prior Paid-before-hold
defect?** Yes, read the fixture in full: one hand-built row per failure mode
(`BAD-LAST-V1`/SQL NULL, `BAD-LITERAL-V1`/literal `"NULL"`, `BAD-PAID-BLANK-V1`/blank required
field on Paid, `BAD-STATUS-V1`/lowercase `'paid'`, `BAD-SPINE-V1`/broken period range,
`BAD-DATE-V1`/malformed date, `BAD-DUP-V1`/duplicate period+invoice), plus the `ZERO_HELD` and
`ZERO_RELEASED` edge cases. Explicit assertions check both the *aggregate* counts and that specific
items landed in the *correct* hold reason (e.g. `BAD-LITERAL-V1` must show
`REQUIRED_VALUE_NULL_OR_LITERAL_NULL` in its `hold_reason`).

**8. Is rollback exact and safe given the new table is absent before deployment?** Yes. The delta
is structural/additive to the already-additive `37b5a9b` change; nothing about existing table
definitions changed incompatibly. The request states live prestate is still the pre-`37b5a9b`
definition and the hold table doesn't exist yet — rollback to `6354d5b` remains a clean revert, and
an unused hold table (if ever created ahead of a later rollback) stays inert, consistent with the
same non-destructive-rollback posture from the prior review.

## Verified locally (not just trusted from the request)

- `python scripts/check_v3_unit5_required_hold_fix.py --git-ref 1f5c20c` (run inside the isolated
  `03edcba` worktree) → **RED**, confirmed.
- `python scripts/check_v3_unit5_required_hold_fix.py` (current) → **PASS**, confirmed — including
  the checker's own new positive assertion that all five *old* candidate-wide abort strings
  (including the exact two I flagged in the prior review) are now absent from the DDL, and that no
  wide `SELECT *` remains.
- Read the full updated fixture and confirmed its 7-held/1-released/zero-held/zero-released
  assertions match the request's claimed evidence exactly, by tracing the logic, not by executing
  it live (no BigQuery access this session).

## Notes (non-blocking)

1. This review was performed against an isolated `git worktree`, not the primary working
   directory, because the primary directory's branch has diverged from origin (unpushed local
   commits from what appears to be a separate automated Claude invocation, reviewing a different,
   smaller `20809d1` delta that is not this artifact). This divergence is a real, session-visible
   instance of the concurrent-write risk this project's `AGENT_REVIEW_PROTOCOL.md` explicitly warns
   against ("never two agents live in the same tree"). Worth Codex/Boat resolving which of the two
   local/remote lineages is authoritative before further work lands, since `docs/REVIEW_QUEUE.md`
   itself currently has different content on each side.

## Checklist 1–12 (delta review — items touched by this change)

1. **Traceability — PASS.** Fixture counts (7 held / 1 released / 0 / 0) are named and directly
   traceable to specific `OrderItem` test rows.
2. **Provenance — PASS.** Reuses the `37b5a9b` transaction/publish machinery; does not re-derive it.
3. **NULL-safety — PASS.** Central subject of this delta; verified above.
5. **Column order — PASS.** All four wide-projection sites now explicit; independently grepped for
   zero remaining `SELECT *`.
6. **Grain — PASS.** `OrderItem` grain for hold/release stated and held consistently through issue
   aggregation, hold publication, and the new no-leak assertion.
7. **Distribution — PASS.** `hold_reason` records every triggered rule per item (not just the
   first), and `invalid_fields` records every affected column.
8. **Knowledge consistency — PASS.** Matches Boat's whole-item quarantine rule at its full stated
   scope, closing the gap the prior review's Note 1 identified.
9. **Scope — PASS.** No `EXPORT DATA`/`gs://`/Scheduler/promoter change in the diff; confined to
   DDL 058, its checker, and its fixture.
10. **Rollback — PASS.** See question 8.
11. **Cost hygiene — PASS.** Authenticated dry-run cited at 0 bytes; fixture job cited at 6,007
    bytes processed / ~189 MB billed (a real, small, isolated temp-table exercise, not a production
    scan) — not independently re-verified live this session.
12. **Honest labelling — PASS.** Request states plainly that missing-OrderItem remains a file-level
    abort by necessity, and that a PASS authorizes neither deployment nor a CALL.
Items 4 — N/A, no date-string ordering in this delta.

No BLOCK found. This closes Note 1 from the prior review in full. Recommend a second reviewer pass
before redeploying DDL 058, and recommend resolving the local/remote branch divergence (Note 1
above) before either lineage is treated as authoritative.
