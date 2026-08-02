# AGENT_TEAMING.md — running Claude Code and Codex in parallel
Added 2026-07-29. Referenced by `docs/AGENT_RULES.md` §Multi-agent discipline.
Reason this exists: both agents were pointed at the same checkout and blocked each other; one had
deployed live BigQuery objects whose source was still uncommitted.

## Rule 0 — one working tree per agent, always
Never point two agents at the same folder. Use a second git worktree (same history, separate files):

**Gate 0.3 evidence (Boat + Claude approved 2026-07-31):** Codex runs from a separate clone whose
repository top-level differs from Claude Code's checkout, with `origin` set to
`https://github.com/BoatPiyarat/BI-SAP.git`; repository fsck is clean (a dangling blob is benign)
and no OneDrive conflicted copy exists. Boat decided on 2026-08-01 that this Codex clone remains at
its current OneDrive path until V3 is complete. This provides filesystem isolation even though both
clones currently use branch `p0/stg-sap-state`.

### OneDrive session gate (mandatory)

Before every session run `git status --short --branch`, `git fsck --no-progress`, recursively scan
for `*-DESKTOP-*`, and recursively scan for `*conflicted*`. Any conflicted copy is a hard stop:
report it to Boat and do not edit. A dangling blob by itself is benign. If a git operation fails
with a permission/lock error, allow OneDrive 30 seconds to sync and retry once; never force and
never remove `.git/index.lock` manually. Push every completed work unit to the private GitHub
remote because OneDrive has only the latest file state, not the recoverable audit history.

PII-bearing `.mbox`, `.eml`, `.csv`, `.xlsx`, `sap_import_logs/`, and `delta_out/` must never be
placed anywhere under OneDrive. Keep such local evidence under `C:\dev\` only and never commit it.

```bash
# from the main repo
git worktree add ../repo-codex chore/docs-governance
```
- **Claude Code** stays in the original checkout, branch `feat/v3-sql`
- **Codex** works in `../repo-codex`, branch `chore/docs-governance`
Both push to the same remote; integration happens through PRs, never through a shared folder.

## Rule 1 — ownership by domain (not by task)
Boat reassigned the lanes again on 2026-08-01. Both agents may commit and push to
`p0/stg-sap-state`; fetch and rebase on `origin/p0/stg-sap-state` immediately before every push.
On rejection, fetch + rebase and retry; never force-push.

| Domain | Owner | Notes |
|---|---|---|
| `sql/**`, `docs/knowledge/**`, `docs/design/**`, `docs/FINDINGS_*`, `AGENT_RULES.md`, `CLAUDE.md`, this file | **Codex** | Main implementation and knowledge owner; one batched query plan |
| `docs/reviews/*-claude.md` and Claude's review commits | **Claude Code** | Commits and pushes its own reviews; Codex reads but never edits these files |
| Approved deployment | **Codex only** | Boat decision 2026-08-02; still requires scoped Boat deploy authorization and Class A PASS. Claude Code reviews/hands off but never deploys |

**File-level single-writer principle:** ownership is by file domain, not by branch. Claude Code
commits its own review files directly; Codex must not wait for or copy them. Both writers rebase
before push. Cross-role requests and requested fixes go through Rule 2.

## Rule 2 — cross-domain requests go in a queue, not in the other agent's files
Append to `docs/HANDOFF_QUEUE.md`:
```
## [YYYY-MM-DD HH:MM] FROM <agent> TO <agent>
Request: <what needs to change, in which file/object>
Why: <evidence / link to finding>
Status: OPEN | DONE (<commit>)
```
The receiving agent reads the queue at session start, does the work in its own domain, marks DONE.

## Rule 3 — reviews, handoff, and knowledge edits
Claude Code commits and pushes its reviews under `docs/reviews/*-claude.md` and places requested
fixes in `docs/HANDOFF_QUEUE.md`; Codex reads both after fetch/rebase. Codex never edits Claude's
review files. Claude Code does not directly edit `docs/knowledge/**`; Codex folds confirmed findings
into `10_SAP_CONTEXT` / `20_SAP_PROGRESS` / `30_SAP_CHANGELOG`. This keeps evidence attributable
while allowing two writers on the shared branch.

For every production release, Claude Code's final handoff must identify the reviewed commit,
verdict, dry-run/evidence, exact deploy command or runbook, and rollback boundary. Codex verifies
that handoff against the repository and is the only agent that executes the production step.

## Rule 4 — source must exist before an object goes live
Any object deployed to BigQuery must have its DDL committed **in the same session** it was deployed.
"Deployed but uncommitted" is treated as an incident: the running system has no reproducible source.
Before ending a session: `git status` must show no untracked/modified files under `sql/`.

## Rule 5 — unexpected changes mid-task
- A new commit from another agent that touches only that agent's domain is normal
  (`Claude Code = sql/**, docs/sessions/**`). Pull/fast-forward, read the session note when relevant,
  and continue without asking.
- An unrelated new untracked file is non-destructive: report it and continue. Do not edit, delete,
  or stage it unless the task places it in scope.

Stop only in these two cases:
1. someone changes a file in this agent's owned domain that this agent did not change; or
2. a file this agent is actively editing changes externally.

When stopping, list the exact overlapping files and ask for reconciliation.

## Rule 6 — integration protocol
1. Each agent commits on its own branch with the usual evidence (dry-run, validation proof).
2. Merge via PR into the shared integration branch; whoever merges resolves conflicts.
3. After merge, both agents run `git pull` at session start and reconcile with `20_SAP_PROGRESS`.
4. Never rebase or force-push a branch the other agent has checked out.
5. Mutual review for every work unit follows `docs/AGENT_REVIEW_PROTOCOL.md`; requests and verdicts
   are tracked in `docs/REVIEW_QUEUE.md` and `docs/reviews/`.

## Rule 7 — cost-controlled lane protocol
1. Single-agent by default; use a second agent only for two genuinely non-overlapping lanes.
2. Codex does not query BigQuery in normal operation. It batches required metrics and provenance
   requests in `docs/HANDOFF_QUEUE.md`; Claude Code runs them together.
3. Claude Code does not edit `docs/knowledge/**`; it writes
   `docs/sessions/<YYYY-MM-DD>-claude.md` for Codex to fold.
4. Batch data requests into one query returning multiple metrics; do not issue one query per question.
5. One investigation has one agent. Cutover/production writes have one agent and a human watcher.
6. At session start run `git log --oneline -10` and read today's `docs/sessions/`; do not repeat
   existing evidence.

## When NOT to use two agents
- Any single-threaded investigation where both would query the same tables and reason about the same
  numbers (e.g. the `SAP_LIVE` bloat analysis) — one agent, one conclusion. Two agents produce two
  half-verified stories that then have to be reconciled, which costs more than it saves.
- During cutover or any production write. One hand on the controls.
