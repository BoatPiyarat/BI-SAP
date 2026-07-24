# AGENTS.md — SAP Interface Pipeline (RabbitCare BI)

You are working on the CareOS ⟷ SAP Business One integration pipeline.
Owner: Boat (BI Manager). GCP project: `pacific-plating-282708`. Region: `asia-southeast1`.

## Read first (in this order, before any task)
1. `docs/knowledge/00_AI_BOOTSTRAP.md` — file map & update rules
2. `docs/knowledge/10_SAP_CONTEXT.md` — business rules (**อ่าน ADDENDUM 2026-07-23 ท้ายไฟล์ก่อน — override กติกาเก่า**)
3. `docs/knowledge/20_SAP_PROGRESS.md` — current state, in-flight work, pending decisions
4. `docs/design/SAP_INTERFACE_REDESIGN_V3.md` + `SAP_PIPELINE_E2E_DESIGN_v3.md` — target architecture
5. Task-specific: `SAP_DATA_PREP_DESIGN_v3.md` (queries), `SAP_RUNBOOK_v3.md` (ops), `SAP_DASHBOARD_DESIGN_v1.md`

## Hard rules (non-negotiable)
- **SQL dialect: BigQuery Standard SQL only.** Deliver full runnable files, never diffs-as-answer (repo diffs are fine).
- **SAP truth = `sap_integration_v2.SAP_LIVE_FULL` ONLY.** (Corrected 2026-07-24: `raw_sap_live`/Phase 6 B2 extract was never actually deployed in this project — it only existed as a plan in the design docs. `SAP_LIVE_FULL` is the real, current source; it already dedups by DocEntry but NOT by (OrderItem, Period) — use `sap_integration_v3.stg_sap_state` for anything that needs one row per (OrderItem, Period).) Never derive status/InvoiceNo from `SAP_LIVE`, `SAP_LIVE_2024/2025/2026` directly (those are the raw per-year shards `SAP_LIVE_FULL` unions together).
- **Never bypass validation before export.** Anything written to `gs://interface-file/` must pass the validation stage. No exceptions, including "urgent".
- **InvoiceNo is immutable in SAP.** Rows already Paid/Cancelled: mirror stored values exactly. Never invent or reformat invoice numbers; the '2_' prefix vs raw-id conflict is unresolved — ask before choosing.
- **Do not touch vendor-owned components:** WireGuard tunnel config, SAP hourly pull, `gs://interface-file` pull cadence, SAP-side import program (Aware owns these).
- **Secrets:** never print/echo/commit credentials. SAP DB creds live in Secret Manager (`sap-db-username`, `sap-db-password`). Note: passwords may contain `&`/`\` — always use `read -s` / files, never inline in shell.
- **NULL-safe filters always:** e.g. `(motor_item_type != 'MOTOR_TYPE_COMPULSORY' OR motor_item_type IS NULL)`.
- **Charge-driven principle:** population is driven by successful charges. Every SUCCESSFUL charge must end up in SAP or in `sap_validation_error` — silent drops are the #1 historical bug class.
- Dates in interface files: `DDMMYYYY` strings. Money: ROUND(...,2), amounts from CarePay are satang (÷100).
- Every query change: branch → PR → validation evidence (0-row-diff or documented delta) before merge.
- Destructive ops (DROP/DELETE/overwrite prod tables, `gcloud ... delete`, scheduler changes): propose first, wait for approval.

## Environment & commands
- BigQuery: `bq query --use_legacy_sql=false '...'`
- Cloud Run job (extract): `gcloud run jobs execute sap-extract-job --region=asia-southeast1 --wait`
- Nightly anchor: extract 20:30 ICT (`sap-extract-schedule`). Everything downstream should chain, not wait on clocks (see E2E design).
- Manual step-by-step ops & incident playbook: `docs/design/SAP_RUNBOOK_v3.md`

## Current priorities (see 20_SAP_PROGRESS for detail)
P0 mostly done (2026-07-24): `stg_sap_state` built and verified in BigQuery; NULL-safe filter (A2)
fixed live in the two confirmed-production views. Remaining: decide on 6 other views with the same
A2 pattern (not confirmed live), finish secret rotation.
Blocked on decisions listed in PROGRESS §DECISIONS PENDING — do not implement past a pending decision; ask.

## Discipline
- After any session with conclusions: update `20_SAP_PROGRESS.md` (overwrite) and append to `30_SAP_CHANGELOG.md` (newest on top, never edit old entries).
- New incident → follow template in `SAP_INCIDENT_LOG.md` style: symptom → hypotheses tested → root cause → fix → lessons.
- When SAP import errors return, parse the log before theorizing; one confirmed error message beats three hypotheses.
