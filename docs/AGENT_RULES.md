# AGENT_RULES.md — single source of rules for ALL coding agents
Canonical. `CLAUDE.md` and `AGENTS.md` are pointers to this file. Never duplicate rules into them.
Last updated: 2026-07-29

Project: CareOS ⟷ SAP Business One integration | Owner: Boat (BI Manager, RabbitCare)
GCP project `pacific-plating-282708` | region `asia-southeast1` | auth: data@rabbit.co.th

## Read before any task (in this order)
1. `docs/knowledge/00_AI_BOOTSTRAP.md` — file map & update rules
2. `docs/knowledge/10_SAP_CONTEXT.md` — business rules. **Read the ADDENDUM sections at the end first; they override anything above them.**
3. `docs/knowledge/20_SAP_PROGRESS.md` — current state, in-flight work, pending decisions
4. `docs/AS_BUILT_V3.md` — what actually exists in `sap_integration_v3` (check this BEFORE building anything, to avoid rebuilding what's there)
5. `docs/INPUTS_NEEDED.md` — open questions owned by humans; do not re-derive these
6. Task-specific docs in `docs/design/` and `docs/tasks/`

## Hard rules (non-negotiable)
- **BigQuery Standard SQL only.** Deliver full runnable files; repo diffs are fine, "here's a snippet" is not.
- **DDL only in `sap_integration_v3`.** Never CREATE/ALTER/DROP in `sap_integration_v2`, `SAP`, or `careos`.
- **Never write to `gs://interface-file/**`.** That is production; SAP pulls it every 15 minutes. Shadow prefixes only.
- **DEPLOY GATE:** replacing anything existing consumers read (views, tables, procedures — even inside v3) requires: dry-run evidence + a one-paragraph change summary + explicit human "deploy OK" in that session. Building/testing *new* objects needs no approval.
- **SAP truth = `sap_integration_v2.SAP_LIVE_FULL`** (use `stg_sap_state` / `sap_mirror_state` when you need one row per (OrderItem, Period)). `raw_sap_live` and `gs://sap-bucket-csv` **never existed** — if any doc says otherwise, that doc is stale; report it.
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
- **READ-ONLY self-service:** freely run read-only lookups (`bq show/ls/head`, `INFORMATION_SCHEMA`, `gcloud describe/list`, `gsutil ls`). Never ask the human for something these commands can answer. Approval is for writes only.
- Before flagging an open question, check `20_SAP_PROGRESS` §DECISIONS PENDING and `INPUTS_NEEDED.md`. Reference known items; don't re-derive them.
- Maintain `docs/INPUTS_NEEDED.md` as the one living checklist of human-only inputs. Update it; don't regenerate a fresh request list each session.
- When a decision is made mid-session, edit the affected design doc **in the same session**. Docs are truth; conversation is not.
- Check `ls sql/ddl/` before naming a new file — numbers must not collide.
- Every query change goes through branch → PR → validation evidence (zero-row diff or documented delta) before merge.
- The nightly anchor is the 20:30 ICT `sap-extract-schedule`; downstream work should chain from it rather than wait on independent clocks. Operational steps and incident handling live in `docs/design/SAP_RUNBOOK_v3.md`.
- One task at a time; report before moving on. Don't chain into a second substantial build without a checkpoint.

## Verification discipline (this project has been burned by all of these)
- Row counts staying the same is **not** proof of correctness — compare distributions (e.g. `delta_type` before/after).
- `COUNT(DISTINCT x)` silently drops NULLs. Check NULL counts separately.
- Never trust a number you haven't sampled at row level. Anything unverified must be labelled UNVERIFIED.
- If a metric looks impossible (too big, too round, 100%), assume your own query is wrong before assuming the data is.
- For a new incident, record symptom → hypotheses tested → root cause → fix → lessons. When SAP import errors return, parse the import log before theorizing.
- Money or accounting impact discovered → write it to `docs/FINDINGS_*` + `INPUTS_NEEDED.md` and **stop**. Do not fix, do not notify anyone outside the team.

## Confirmed decisions (do not re-litigate; change only on Boat's instruction)
- ProcessingFee: RCL `/103.3` confirmed. Onetime `/107` **unconfirmed — keep as-is and flag**.
- `CREDIT_CARD_INSTALLMENT` = ONETIME flow (bank pays in full), TotalPeriods=1, channel `RCB-EDC-<bank>` (KBANK confirmed; other banks pending Finance).
- Year scope: ≤2024 untouched | 2025 = cancel only, and only for orders already present in SAP | 2026+ normal. Date basis = `GREATEST(OrderDate, PolicyDate)`.
- Test customers: exact match `LOWER(TRIM(FirstName|LastName)) = 'test'` only. Phone `0999999999` = corroborating signal, **report-only** for now.
- PolicyNo > 50 chars = BLOCK (never truncate) + report in the morning email.
- Date fields: exactly 8 chars and parseable; empty allowed **only** for PaymentDate on pending rows.
- Validation failure policy: item-level quarantine (rest continues) — provisional, pending Boat's final word.

## Current state (2026-07-29)
- V3 produces **no** interface file yet. All files SAP receives still come from the legacy `sap_view.*` path.
- **Phase B/C are ON HOLD** pending investigation of `SAP_LIVE` bloat (151K → 6.9M rows in 3 days; suspected loader OOM crash-loop + plain INSERT on retry). This may be the root cause of the 496-docs-per-period and 89% NULL BatchRunDate anomalies, and it means every baseline number is suspect until cleaned.
- `sap-extract-schedule` may still be failing (401). If extract isn't scheduled, Boat presses EXECUTE manually; a missed-extract alert covers forgotten nights.
- Alert delivery: must reach **piyaratt@rabbit.co.th** and/or Slack. `data@rabbit.co.th` alone is not sufficient.

## Multi-agent discipline (Claude Code AND Codex on this repo)
- **One agent at a time in a given working tree.** Never run both against the same checkout simultaneously.
- Each agent works on its own branch; merge via PR with the usual evidence (dry-run + validation proof).
- First action of every session: `git status && git log --oneline -5` and reconcile with `20_SAP_PROGRESS`. If the working tree is dirty from another agent, report and stop.
- Rules live here only. If you're asked to "add a rule to CLAUDE.md/AGENTS.md", add it to this file instead.

## Reporting rule
After each work item: append `30_SAP_CHANGELOG.md` (newest first, never edit old entries), update `20_SAP_PROGRESS.md`, and report a table of built / verified-against-real-data / still-assumed.
