# AGENT_REVIEW_PROTOCOL.md — mutual review, both directions, all work
Added 2026-07-29 by Boat's instruction ("ให้ 2 ตัว review กันและกัน ทั้งหมด ไม่เฉพาะ deploy OK")
Referenced by `docs/AGENT_TEAMING.md`. Supersedes the earlier "review only before deploy" rule.

## Why (evidence from this project, not theory)
Every expensive mistake so far was a **conclusion that looked finished but wasn't verified**:
production broken by a moved column; a stale number (419 vs 296) driving instructions; the wrong
field pair compared; a string-sorted date keeping 44,781 stale rows; the same NULL-unsafe predicate
shipped three times. None of these needed a smarter agent — they needed a second reader.

## Cost rule first (this protocol must not double the bill)
- **The reviewer reads artifacts. The reviewer does not redo the work.**
  Read: the diff, the evidence table, the session note, the commit message. That's the job.
- The reviewer may run **at most one targeted query** — only when a specific claim cannot be judged
  from the artifacts. Exploratory scanning by a reviewer is prohibited.
- Review output ≤ 1 page. No restating what the author already wrote.
- Review is **asynchronous through files** — never two agents live in the same tree (Rule 0 stands).

---

## Review classes (what needs how much)

| Class | Applies to | Review |
|---|---|---|
| **A — BLOCKING** | SQL intended for deployment; numbers intended for FA/Aware; production-object changes or behavioral conclusions; anything writing to GCS | Must PASS before the author proceeds with that Class-A unit |
| **B — NON-BLOCKING** | docs, findings, design, and runbook work that contains no Class-A element | Author continues immediately; reviewer comments become fixes |
| **C — NO REVIEW** | changelog, session log, bookkeeping, formatting, rename, `.gitignore`, typo, file moves | Record only; no review request required |

Class is assigned from the highest-risk element in a mixed artifact. A docs commit containing a
deployable SQL change, FA/Aware number, or production-object conclusion remains Class A. If unsure,
treat it as A. Misclassifying downward is worse than waiting.

---

## The checklist (reviewer must answer all 12 explicitly)
Every item derived from a real failure in this project.

1. **Traceability** — is every number tied to a named table + query + timestamp? (419 vs 296; MISSING 576 vs 749)
2. **Provenance over repetition** — does it cite commit hashes instead of re-deriving proven facts?
3. **NULL-safety** — every comparison on a nullable column NULL-safe? (bug class A2, seen 3×)
4. **Ordering** — no string-sorted dates; `SAFE.PARSE_DATE` before `ORDER BY`; deterministic tiebreak? (44,781 keys)
5. **Column order** — for anything feeding an interface file: `INFORMATION_SCHEMA.COLUMNS` diffed before/after; no `SELECT * EXCEPT(col), expr AS col`? (2026-07-26 incident)
6. **Grain stated** — item vs order vs document declared explicitly, and the join respects it? (the 3,352 miscount)
7. **Distribution, not row count** — parity of counts is never offered as proof of correctness?
8. **No contradiction with knowledge** — does it conflict with `10_SAP_CONTEXT` / ADDENDUM / confirmed decisions? If a chat instruction conflicts, was that raised rather than silently followed? (3-field vs 2-field)
9. **Scope** — did the author stay inside its domain and its approval? (`sql/**` vs `docs/knowledge/**`)
10. **Rollback** — for anything deployed: previous definition kept verbatim, rollback stated, < 5 min?
11. **Cost hygiene** — dry-run evidence, `--maximum_bytes_billed`, one query many metrics, no `SELECT *` on wide tables?
12. **Honest labelling** — anything unverified marked `UNVERIFIED`; nothing rounded up to "done"?

**Anti-rubber-stamp rule:** the reviewer must either name at least one specific risk/gap, or write
verbatim *"Checklist 1–12 reviewed; no gap found"* — and that sentence is auditable. Vague approval
("looks good") is not a review and must be re-done.

---

## Mechanics
1. Author finishes a unit of work → commits → writes/updates `docs/sessions/<date>-<agent>.md`
   → appends a request to `docs/REVIEW_QUEUE.md` for Class A/B work:
```
## RQ-YYYYMMDD-HHMM-<slug>
Status: OPEN
Reviewer: Codex | Claude Code
Class: A | B | C
Artifact: <commit hash(es) / files / table(s)>
Opened: YYYY-MM-DDTHH:MM:SS+07:00
Claim: <what the author asserts, in one or two sentences>
Evidence: <where the reviewer can check it — query, table, session-note section>
```
2. Reviewer writes `docs/reviews/<date>-<artifact>-<reviewer>.md`:
   verdict **PASS** / **PASS WITH NOTES** / **BLOCK**, plus the 12-item result, plus the required
   risk statement. Marks the queue entry `REVIEWED`.
3. **One round only.** Author answers each BLOCK item once. Still disagreeing → escalate to Boat with
   both positions in ≤ 5 lines each. **No ping-pong** — a second disagreement round is a human decision.
4. Class A cannot proceed while a BLOCK stands. Class B proceeds without waiting; the note becomes
   a follow-up task. Class C does not enter the review queue.
5. Reviewer read-access: **read-only BigQuery is allowed for verification**, one targeted query max.
   Reviewers never deploy, never write, never edit the author's files — findings go in the review file.

## Self-triggering session checklist

### Session start — before other work

1. `git pull --ff-only`.
2. Read `docs/REVIEW_QUEUE.md` and run `bash scripts/review_status.sh`.
3. If any **Class A** entry has `Status: OPEN` and `Reviewer:` equal to the current agent, review
   those entries before starting other Class-A work. Class B/C never blocks progress.
4. If a new human instruction conflicts with clearing the review debt first, state the conflict and
   ask the human which takes priority. Never skip an assigned OPEN review silently.

### Session end — review loop closure

1. Commit and push the completed work.
2. For every class-A unit just completed, append a machine-parseable `REVIEW REQUEST` immediately;
   do not wait for Boat or the reviewer to ask.
3. Clear the current agent's remaining assigned OPEN reviews, subject to the one-round/escalation
   rule above.
4. Run `bash scripts/review_status.sh` and report exactly:
   `Review debt: <total OPEN> OPEN (mine: <current-agent OPEN>)`.

The request fields below are mandatory, one per line, in this exact spelling. Additional
`Claim:`/`Evidence:` text may follow.

`Opened:` and the `HHMM` portion of the request ID must come from a real git commit timestamp,
never from a wall-clock estimate or a manually chosen label. Prefer the commit that first adds the
review request; for a reconstructed legacy request with no separate request commit, use the
artifact commit. Obtain it with `git show -s --format=%aI <commit>`, retain the seconds and offset
in `Opened:`, and derive `HHMM` from that same timestamp.

```text
## RQ-YYYYMMDD-HHMM-<slug>
Status: OPEN
Reviewer: Codex | Claude Code
Class: A | B | C
Artifact: <commit(s), files, objects>
Opened: YYYY-MM-DDTHH:MM:SS+07:00
```

## Optional pre-push hook — proposal only

After levels 1–2 above have run for one week, Boat may choose whether to install an optional
pre-push hook that runs `scripts/review_status.sh` and warns when:

- a class-A commit has no review request;
- the current agent has OPEN review debt.

The hook is **not installed by this change**. It must allow `git push --no-verify` for genuine
emergencies, but every bypass must be recorded immediately in the session note and CHANGELOG with
the reason, commit, operator, and follow-up review owner. Revisit after one week of normal use
before deciding whether warning-only should become blocking.

## Reciprocity
Both directions, no exceptions:
- **Codex reviews** Claude Code's SQL, DDL, deployments, quantifications, investigations.
- **Claude Code reviews** Codex's knowledge edits, rule changes, folded evidence, INPUTS_NEEDED updates
  — specifically: does the doc now say something the evidence doesn't support?
Lack of domain context is not an excuse to skip: a reviewer without context can still check
traceability, contradiction, grain, labelling — items 1, 2, 6, 8, 12 need no domain expertise at all.

## Measurement (revisit 2026-08-12)
Track in `docs/reviews/_SCORECARD.md`, per agent:
- reviews performed / BLOCKs raised / BLOCKs upheld after author's answer
- issues caught by the reviewer that the author had missed
- rework caused by a missed issue that review should have caught
- self-caught errors (author found own mistake before review)
- approximate cost per reviewed item

**If a reviewer raises zero BLOCKs and zero notes for two weeks, the review is theatre** — either the
protocol is being rubber-stamped or the class thresholds are wrong. Report it; don't keep paying for it.
