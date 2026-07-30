# AGENT_RULES.md — single source of rules for ALL coding agents
Canonical. `CLAUDE.md` and `AGENTS.md` are pointers to this file. Never duplicate rules into them.
Last updated: 2026-07-30

Project: CareOS ⟷ SAP Business One integration | Owner: Boat (BI Manager, RabbitCare)
GCP project `pacific-plating-282708` | region `asia-southeast1` | auth: data@rabbit.co.th

## Read before any task (in this order)
1. `docs/knowledge/00_AI_BOOTSTRAP.md` — file map & update rules
2. `docs/knowledge/10_SAP_CONTEXT.md` — business rules. **Read the ADDENDUM sections at the end first; they override anything above them.**
3. `docs/knowledge/20_SAP_PROGRESS.md` — current state, in-flight work, pending decisions
4. `docs/AS_BUILT_V3.md` — what actually exists in `sap_integration_v3` (check this BEFORE building anything, to avoid rebuilding what's there)
5. `docs/INPUTS_NEEDED.md` — open questions owned by humans; do not re-derive these
6. Task-specific docs in `docs/design/` and `docs/tasks/`

## Behavioral guidelines (LLM coding, source: andrej-karpathy-skills)
Bias toward caution over speed; use judgment on trivial tasks.

### 1. Think Before Coding
Don't assume. Don't hide confusion. Surface tradeoffs. State assumptions explicitly; if uncertain,
ask. If multiple interpretations exist, present them — don't pick silently. If a simpler approach
exists, say so and push back when warranted. If something is unclear, stop, name what's confusing,
and ask.

### 2. Simplicity First
Minimum code that solves the problem. Nothing speculative. No features beyond what was asked, no
abstractions for single-use code, no unrequested "flexibility," no error handling for impossible
scenarios. If you write 200 lines and it could be 50, rewrite it. Ask: "Would a senior engineer say
this is overcomplicated?" If yes, simplify.

### 3. Surgical Changes
Touch only what you must. Clean up only your own mess. Don't "improve" adjacent code, comments, or
formatting; don't refactor things that aren't broken; match existing style even if you'd do it
differently. If you notice unrelated dead code, mention it — don't delete it. When your changes
create orphans, remove imports/variables/functions that YOUR changes made unused; don't remove
pre-existing dead code unless asked. Test: every changed line should trace directly to the user's
request.

### 4. Goal-Driven Execution
Define success criteria; loop until verified. Transform tasks into verifiable goals ("Add
validation" → "write tests for invalid inputs, then make them pass"; "Fix the bug" → "write a test
that reproduces it, then make it pass"). For multi-step tasks, state a brief plan with a verify
step per line. Strong success criteria let you loop independently; weak criteria ("make it work")
require constant clarification.

## Hard rules (non-negotiable)
- **BigQuery Standard SQL only.** Deliver full runnable files; repo diffs are fine, "here's a snippet" is not.
- **DDL only in `sap_integration_v3`.** Never CREATE/ALTER/DROP in `sap_integration_v2`, `SAP`, or `careos`.
- **Never write to `gs://interface-file/**`.** That is production; SAP pulls it every 15 minutes. Shadow prefixes only.
- **DEPLOY GATE:** replacing anything existing consumers read (views, tables, procedures — even inside v3) requires: dry-run evidence + a one-paragraph change summary + explicit human "deploy OK" in that session. Building/testing *new* objects needs no approval.
- **SAP truth = `sap_integration_v2.SAP_LIVE_FULL`** (use `stg_sap_state` / `sap_mirror_state` when you need one row per (OrderItem, Period)). `raw_sap_live` never existed. The deployed extract path is `gs://rcb-bronze-zone/SAP/production_database/` and control path is `gs://rcb-bronze-zone/SAP/_extract_control/`; the old bucket name found in historical plans was never real.
- Never derive status or InvoiceNo from `SAP_LIVE`, `SAP_LIVE_2024`, `SAP_LIVE_2025`, or `SAP_LIVE_2026` directly; those are raw per-year shards unioned by `SAP_LIVE_FULL`.
- **Never bypass validation before export.** Anything written to a production interface path must pass the validation stage, including urgent work.
- **InvoiceNo is immutable in SAP.** Rows already Paid/Cancelled: mirror the stored value verbatim. Generate only via `fn_invoice_no`.
- **Column ORDER matters** — SAP import is positional. Never use `SELECT * EXCEPT(col), expr AS col` (it moves the column to the end); use `SELECT * REPLACE(expr AS col)`. Verify with `INFORMATION_SCHEMA.COLUMNS` before deploying any interface-feeding view.
- **Charge-driven principle:** every SUCCESSFUL charge must end in SAP or in `sap_validation_error` / `sap_excluded_records`. Silent drops are the #1 historical bug class.
- **EXCLUDED ≠ DELETED:** filtered rows go to `sap_excluded_records` with a rule_code and get counted in the morning report.
- **Secrets:** never print/echo/commit credentials. SAP DB creds live in Secret Manager. Passwords may contain `&`/`\` — use `read -s` or files, never inline in shell.
- **NULL-safe filters always** (e.g. `(motor_item_type != 'MOTOR_TYPE_COMPULSORY' OR motor_item_type IS NULL)`).
- Interface dates are `DDMMYYYY` strings. CarePay amounts are satang (÷100), ROUND(...,2).
- Destructive ops (DROP/DELETE/overwrite, `gcloud ... delete`, scheduler enable/disable, IAM changes): propose first, wait for approval. **Never enable/disable a schedule someone else may have paused deliberately.**
- **Do not touch vendor-owned components:** WireGuard tunnel configuration, the SAP hourly pull, the `gs://interface-file` pull cadence, or the SAP-side import program (Aware owns these).
- **Never guess the date.** Run `date` before naming files or writing CHANGELOG entries.

## Workflow efficiency rules
- **Session start review gate:** run `git pull --ff-only`, read `docs/REVIEW_QUEUE.md`, and run
  `bash scripts/review_status.sh`. Any `Status: OPEN` assigned to the current agent is done before
  other work. If a human instruction conflicts, report the conflict and ask; never skip silently.
- Before every work item, run `git log --oneline -10` and read today's files under `docs/sessions/`. Do not repeat verification that already has evidence; cite the commit hash instead.
- **Lane-specific read-only self-service:** Claude Code freely runs required read-only lookups (`bq show/ls/head/query`, `INFORMATION_SCHEMA`, `gcloud describe/list`, `gsutil ls`) without approval. Codex does not query BigQuery in the normal docs lane and batches needed numbers in `docs/HANDOFF_QUEUE.md`; as a reviewer, Codex may run at most one targeted read-only BigQuery query per review when an artifact claim cannot otherwise be judged. Exploratory reviewer queries are prohibited. Approval remains for writes/deploys only.
- Before flagging an open question, check `20_SAP_PROGRESS` §DECISIONS PENDING and `INPUTS_NEEDED.md`. Reference known items; don't re-derive them.
- Maintain `docs/INPUTS_NEEDED.md` as the one living checklist of human-only inputs. Update it; don't regenerate a fresh request list each session.
- When a decision is made mid-session, edit the affected design doc **in the same session**. Docs are truth; conversation is not.
- When chat supplies a definition, taxonomy, or business rule, write it into the canonical document
  immediately. Never leave it only in chat and force the next agent to infer it.
- If a chat instruction conflicts with canonical knowledge, stop implementation and reconcile/update the knowledge decision explicitly first; never follow the conflicting chat instruction silently.
- Verify the current evidence and upstream commit state before committing. A fast follow-up correction is not a substitute: stale commit `0c74639` required `7e98d39` ten minutes later, doubling reviewer reading and commit history.
- Check `ls sql/ddl/` before naming a new file — numbers must not collide.
- Every query change goes through branch → PR → validation evidence (zero-row diff or documented delta) before merge.
- The nightly anchor is the 20:30 ICT `sap-extract-schedule`; downstream work should chain from it rather than wait on independent clocks. Operational steps and incident handling live in `docs/design/SAP_RUNBOOK_v3.md`.
- One task at a time; report before moving on. Don't chain into a second substantial build without a checkpoint.
- End every session by pushing the completed commits to the configured Git remote. A local commit
  is not a completed handoff; report explicitly if push fails.
- **Session end review gate:** after commit+push, create a REVIEW REQUEST for every class-A unit
  just completed without waiting to be asked; clear assigned OPEN reviews; rerun
  `scripts/review_status.sh`; report `Review debt: n OPEN (mine: n)`.
- Review-queue `Opened:` and ID time labels must be copied from `git show -s --format=%aI <commit>`
  (request commit when present; artifact commit only for reconstructed legacy requests), never
  invented from the current clock.

## Cost-control guardrails (canonical; source rationale in `docs/COST_CONTROL.md`)

### BigQuery/query cost
- **Mandatory query path:** every non-metadata BigQuery query must run through
  `scripts/bq_safe_query.sh`; direct `bq query` is prohibited. Metadata-only operations include
  `bq show/ls/head` and queries limited to `INFORMATION_SCHEMA`/`__TABLES__`. Enforcement source
  was introduced by Claude Code in `a56f6d1`; that version's class-A review was BLOCKED in
  `docs/reviews/2026-07-30-a56f6d1-codex.md` for a fail-open parser gap and a `--force` flag that
  didn't do what it claimed. **Fixed** (2026-07-30, pending its own class-A review in
  `REVIEW_QUEUE.md`): absent/unparseable `totalBytesProcessed` is now always a hard error (never
  falls back to 0); `--force` is removed entirely — 20 GiB is a hard ceiling with no override; a
  `--self-test` mode runs 7 offline parser cases with no BigQuery calls. Re-run
  `bash scripts/bq_safe_query.sh --self-test` before trusting the wrapper again if this file is
  touched further.
- Every non-metadata query must be dry-run first. If estimated bytes exceed 20 GB, stop and ask before running it.
- Default every `bq query` to `--maximum_bytes_billed=21474836480` (20 GiB).
- Count rows from metadata (`INFORMATION_SCHEMA.TABLE_STORAGE` / `__TABLES__.row_count`) instead of `COUNT(*)`; do not `COUNT(*)` a large view.
- Never use `SELECT *` or `SELECT DISTINCT *` on wide tables; select only required columns.
- Combine related diagnostics into one query returning multiple metrics/STRUCTs instead of rescanning the same table repeatedly.
- Explore with `TABLESAMPLE SYSTEM (1 PERCENT)` before a full run when sampling can answer the shape question.
- Materialize repeatedly cited diagnostics as small `sap_integration_v3.diag_*` tables instead of rescanning CareOS; this is a BigQuery write and still follows ownership/deploy rules.
- Cite existing commit evidence instead of re-verifying it.
- Dashboards/Looker must read scheduled summary tables, not views that rescan large tables on every open.

### Agent-token cost
- Read only what the task needs: hot tier (00/10/20), `AS_BUILT_V3`, and the task doc. Do not load all of `docs/design/**` unless the task requires it.
- Keep sessions short: finish a work unit, commit, write/fold the session note, then start a fresh session.
- Put long results in files; return only the compact verification tail in chat.
- No verbose retry loops: after two failures under the same hypothesis, change method or ask.
- Never assign two agents to the same investigation.

### Storage
- **Google Drive is backup only; never use it as a knowledge source.** Read from the repository.
  A Drive folder may be incomplete or stale and has previously caused incorrect analysis.
- Every working repository must have a configured Git remote. A local/OneDrive-only repository is
  a single point of failure; treat a missing remote as a same-day operational risk.
- `SAP_LIVE` is append-only audit history. Daily BQ-row/SQL-source-row amplification measured
  289.623× (07-26), 2,036.103× (07-27), and 25.000× (07-28); fix future ingestion, but
  do not clean, deduplicate, truncate, rebuild, or delete historical rows before the incident is
  closed and a reviewed preservation/retention decision exists.
- Every new `diag_*` or scratch table must declare `expiration_timestamp` at creation (7–30 days);
  use `sql/ddl/_TEMPLATE_new_table.sql`. No undocumented exception.
- Partition and cluster large v3 tables and require partition filters in every query that touches them.

## Verification discipline (this project has been burned by all of these)
- Row counts staying the same is **not** proof of correctness — compare distributions (e.g. `delta_type` before/after).
- `COUNT(DISTINCT x)` silently drops NULLs. Check NULL counts separately.
- Never trust a number you haven't sampled at row level. Anything unverified must be labelled UNVERIFIED.
- Every reported number must name its source table/object and source timestamp. Never report or cite a bare number. If the query timestamp was not captured, say so and label the number PROVISIONAL.
- Before reporting a number to any stakeholder, prove the population from SAP-side evidence—not
  BI output, an export candidate, or an error XLSX. Error XLSX contains rejected rows. Posted-state
  claims require mirror + successful status + JE/import-success evidence.
- FA/Aware verification must be captured in the `sap_fa_verification` control table, not only chat
  or docs. Until the control exists and evidence is recorded, treat the claim as unverified and do
  not ask the stakeholder to reconstruct prior evidence from memory.
- If a metric looks impossible (too big, too round, 100%), assume your own query is wrong before assuming the data is.
- For a new incident, record symptom → hypotheses tested → root cause → fix → lessons. When SAP import errors return, parse the import log before theorizing.
- Money or accounting impact discovered → write it to `docs/FINDINGS_*` + `INPUTS_NEEDED.md` and **stop**. Do not fix, do not notify anyone outside the team.

## Confirmed decisions (do not re-litigate; change only on Boat's instruction)
- ProcessingFee: RCL `/103.3` confirmed. Onetime `/107` **unconfirmed — keep as-is and flag**.
- `CREDIT_CARD_INSTALLMENT` = ONETIME flow (bank pays in full), TotalPeriods=1, channel `RCB-EDC-<bank>` (KBANK confirmed; other banks pending Finance).
- Year scope: ≤2024 untouched | 2025 = cancel only, and only for orders already present in SAP | 2026+ normal. Date basis = `GREATEST(OrderDate, PolicyDate)`.
- Revised D1 (Boat 2026-07-29): canonical cancellation uses only `careos.careos_order_items.is_cancelled IS TRUE OR careos.careos_order_items.cancel_time IS NOT NULL`; never use `careos_orders.is_cancelled`, and never fan cancellation out to active siblings.
- D10 (Boat 2026-07-30): Method-2 replacement naming is not decided; real `-M2` rows exist, so
  naming must be configuration-driven and must wait for Aware Q4.
- D11 (Boat 2026-07-30): pilot B1 with Method 1 because it has the fewest dependencies; the two
  already-Cancelled B3 cases go to Aware for manual correction, with no new infrastructure.
- D12/D13 (Boat 2026-07-29/30): amount-variance tolerance is ±฿10 **per order**, aggregated before
  comparison. `MISPOSTING` has no buffer and remains a defect even when the order nets to zero.
- D14 (Boat 2026-07-30): Class 1 and Class 2 both use Method 1; Class 2 adjustments are per item.
  Method 2 naming/alias/Aware-Q4 dependencies apply only to B2 where Expected itself is wrong.
  Amount reconciliation does not prove GL correctness; require pilot GL/JE verification.
- Test customers: exact match `LOWER(TRIM(FirstName|LastName)) = 'test'` only. Phone `0999999999` = corroborating signal, **report-only** for now.
- PolicyNo > 50 chars = BLOCK (never truncate) + report in the morning email.
- Date fields: exactly 8 chars and parseable; empty allowed **only** for PaymentDate on pending rows.
- Validation failure policy: item-level quarantine (rest continues) — provisional, pending Boat's final word.

## Current state (2026-07-29)
- V3 produces **no** interface file yet. All files SAP receives still come from the legacy `sap_view.*` path.
- **Phase B/C are ON HOLD** while `INCIDENT-SAP-MIRROR-20260726` remains open. `SAP_LIVE` had
  8,324,155 rows at 2026-07-30 13:53:09 UTC (already stale after Boat's 21:53 ICT manual run).
  Root cause is structural re-extraction after BI interface imports plus plain append—not a loader
  crash-loop. Baselines remain suspect, and the append-only audit trail must not be cleaned before
  incident closure.
- `sap-extract-schedule` may still be failing (401). If extract isn't scheduled, Boat presses EXECUTE manually; a missed-extract alert covers forgotten nights.
- Alert delivery: must reach **piyaratt@rabbit.co.th** and/or Slack. `data@rabbit.co.th` alone is not sufficient.

## Multi-agent discipline (Claude Code AND Codex on this repo)
- **One agent at a time in a given working tree.** Never run both against the same checkout simultaneously.
- Each agent works on its own branch; merge via PR with the usual evidence (dry-run + validation proof).
- First action of every session: `git status && git log --oneline -10`, read today's `docs/sessions/`, and reconcile with `20_SAP_PROGRESS`.
- Rules live here only. If you're asked to "add a rule to CLAUDE.md/AGENTS.md", add it to this file instead.

## Reporting rule
After each work item: append `30_SAP_CHANGELOG.md` (newest first, never edit old entries), update `20_SAP_PROGRESS.md`, and report a table of built / verified-against-real-data / still-assumed.

Multi-agent: see docs/AGENT_TEAMING.md — one working tree per agent, ownership by domain, cross-domain requests via docs/HANDOFF_QUEUE.md
