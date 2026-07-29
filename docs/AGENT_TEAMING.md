# AGENT_TEAMING.md — running Claude Code and Codex in parallel
Added 2026-07-29. Referenced by `docs/AGENT_RULES.md` §Multi-agent discipline.
Reason this exists: both agents were pointed at the same checkout and blocked each other; one had
deployed live BigQuery objects whose source was still uncommitted.

## Rule 0 — one working tree per agent, always
Never point two agents at the same folder. Use a second git worktree (same history, separate files):

```bash
# from the main repo
git worktree add ../repo-codex chore/docs-governance
```
- **Claude Code** stays in the original checkout, branch `feat/v3-sql`
- **Codex** works in `../repo-codex`, branch `chore/docs-governance`
Both push to the same remote; integration happens through PRs, never through a shared folder.

## Rule 1 — ownership by domain (not by task)
| Domain | Owner | Notes |
|---|---|---|
| `sql/**`, all BigQuery objects in `sap_integration_v3`, deployments | **Claude Code** | It holds the context for 032–034 and the live deployments |
| `docs/knowledge/**`, `docs/design/**`, `AGENT_RULES.md`, `INPUTS_NEEDED.md`, CHANGELOG, PROGRESS | **Codex** | Single writer for knowledge = no merge conflicts |
| `docs/findings/**`, `docs/sessions/**` | whoever produced the finding | Own file per session, never a shared file |
| Alerts / scheduler / Cloud Run config | **Claude Code** | Same deploy-gate rules apply |

**Single-writer principle:** only the owner edits files in its domain. Cross-domain needs go through
Rule 2 — never "just quickly fix" a file in the other agent's domain.

## Rule 2 — cross-domain requests go in a queue, not in the other agent's files
Append to `docs/HANDOFF_QUEUE.md`:
```
## [YYYY-MM-DD HH:MM] FROM <agent> TO <agent>
Request: <what needs to change, in which file/object>
Why: <evidence / link to finding>
Status: OPEN | DONE (<commit>)
```
The receiving agent reads the queue at session start, does the work in its own domain, marks DONE.

## Rule 3 — session notes instead of direct knowledge edits
Claude Code (and any non-owner) writes findings to `docs/sessions/<YYYY-MM-DD>-<agent>.md`.
Codex, as knowledge steward, folds them into `10_SAP_CONTEXT` / `20_SAP_PROGRESS` /
`30_SAP_CHANGELOG` and cites the session file. This keeps append-at-top CHANGELOG conflicts at zero.

## Rule 4 — source must exist before an object goes live
Any object deployed to BigQuery must have its DDL committed **in the same session** it was deployed.
"Deployed but uncommitted" is treated as an incident: the running system has no reproducible source.
Before ending a session: `git status` must show no untracked/modified files under `sql/`.

## Rule 5 — unexpected changes mid-task
Pause, list the affected files, and ask whether they are human-provided or from another agent.
- **Human-provided** (owner copying in docs/fixtures): legitimate — verify nothing was lost, continue.
- **Another agent's concurrent work in the same tree**: stop and report; that means Rule 0 was broken.
The human should not copy files into a repo while an agent is mid-task.

## Rule 6 — integration protocol
1. Each agent commits on its own branch with the usual evidence (dry-run, validation proof).
2. Merge via PR into the shared integration branch; whoever merges resolves conflicts.
3. After merge, both agents run `git pull` at session start and reconcile with `20_SAP_PROGRESS`.
4. Never rebase or force-push a branch the other agent has checked out.

## When NOT to use two agents
- Any single-threaded investigation where both would query the same tables and reason about the same
  numbers (e.g. the `SAP_LIVE` bloat analysis) — one agent, one conclusion. Two agents produce two
  half-verified stories that then have to be reconciled, which costs more than it saves.
- During cutover or any production write. One hand on the controls.
