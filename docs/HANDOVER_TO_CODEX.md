# HANDOVER TO CODEX — 2026-07-29
Prepared by: design-review session (Claude chat) for Boat | Incoming executor: **Codex**
Previous executor: Claude Code (sessions 2026-07-24 → 07-29)

---

## 0. ⚠️ MERGE RULES — read before copying anything

This package contains **only genuinely new files**. The live repo is **newer than this package** in
several places (Claude Code corrected design docs in Phase 0, updated PROGRESS/CHANGELOG repeatedly,
and created `sql/ddl/013–025`, `FINDINGS_SAP_MIRROR_20260726.md`, `AS_BUILT_V3.md`,
`INPUTS_NEEDED.md`, `AWAY_20260726_30.md`, `RETURN_TRIAGE_*.md`).

**ADD these (they do not exist yet, or are pointers that intentionally replace old content):**
| File | Action |
|---|---|
| `docs/AGENT_RULES.md` | ADD — new canonical rules file |
| `AGENTS.md` | REPLACE with the 3-line pointer in this package |
| `CLAUDE.md` | REPLACE with the 3-line pointer in this package |
| `docs/knowledge/KNOWLEDGE_ADDENDUM_20260729_v2.md` | ADD |
| `docs/tasks/TASK_V3_GAP_CLOSURE_v2.md` | ADD if missing; if present, keep the repo copy |

**Before replacing `AGENTS.md`/`CLAUDE.md`:** move any rule that exists in them but NOT in
`AGENT_RULES.md` into `AGENT_RULES.md` first. Losing a rule is worse than a duplicate.

**DELETE / rename (wrong date or superseded):**
- any `*_20260730*` file → the correct date is **2026-07-29** (verify with `date` first)
- `KNOWLEDGE_ADDENDUM_*_v1` (superseded by v2)
- `docs/tasks/TASK_V3_GAP_CLOSURE.md` (v1 — built on the false `raw_sap_live` premise)
- `METHOD_CLEAN_SAP_LIVE_FULL.md` if present (same false premise; superseded by TASK_CLEAN_SAP_MIRROR)
- Any CHANGELOG entry dated 2026-07-30 → correct to 2026-07-29

**DO NOT overwrite** (repo version is authoritative): `docs/knowledge/00/10/20/30/90_*.md`,
everything in `docs/design/`, `sql/**`, `docs/FINDINGS_*`, `docs/AS_BUILT_V3.md`, `docs/INPUTS_NEEDED.md`.

---

## 1. Where to start
1. `docs/AGENT_RULES.md` ← **all rules live here. Read fully before touching anything.**
2. `docs/knowledge/10_SAP_CONTEXT.md` — read the ADDENDUM sections at the end FIRST (they override
   everything above them)
3. `docs/knowledge/20_SAP_PROGRESS.md` — current state
4. `docs/AS_BUILT_V3.md` — what already exists in `sap_integration_v3`
   (**check this before building anything — a previous session nearly rebuilt two existing tables**)
5. `docs/INPUTS_NEEDED.md` — questions owned by humans; don't re-derive them

## 2. Self-test before doing real work
Answer these from the repo. If you get any wrong, your context load failed — say so instead of guessing.
1. What is the SAP truth table, and what is `raw_sap_live`?
   → `sap_integration_v2.SAP_LIVE_FULL`; `raw_sap_live` **never existed** (nor did `gs://sap-bucket-csv`).
2. Can Phase B start now, and why?
   → **No — ON HOLD** pending the `SAP_LIVE` bloat investigation.
3. What must happen before changing a view that feeds an interface file?
   → Deploy gate (explicit human "deploy OK") + dry-run + verify column ORDER via
   `INFORMATION_SCHEMA.COLUMNS` (SAP import is positional).
4. A successful charge cannot be interfaced. What are the only two legal destinations for it?
   → `sap_validation_error` or `sap_excluded_records` — never a silent drop.

## 3. Where the project stands (2026-07-29)
- **V3 produces no interface file.** Every file SAP receives still comes from legacy `sap_view.*`.
  V3 = staging + `expected_state` (~12 cols, not 56) + validation + `delta_export` + mirror layers + alerts.
- **Phase A (safety net) largely done:** column-contract guard, `interface_daily_status`,
  `sap_import_result`, 4 alerts (missed-extract fired for real twice — mechanism proven),
  07:00 digest, dead-man's switch.
- **Phase B (56-column rebuild) and Phase C (shadow export): not started, ON HOLD.**
- **Open bug, highest priority:** `SAP_LIVE` grew 151K → 6.9M rows in 3 days (suspected loader
  OOM crash-loop + plain INSERT on retry). Hypothesis to test: this is the root cause of
  (a) 496 documents on one (OrderItem, Period), (b) 89% NULL `BatchRunDate`,
  (c) the original "many records missing" complaint — both loss and duplication from one cause.
  **Every baseline number (373k/340k MISSING, 9.55% multi-doc, delta distribution) is suspect until this
  is settled.** The loader (`sap-order-payment-initial-phase`) is not owned by BI — confirm ownership
  before proposing changes.
- `sap-extract-schedule` may still be failing (401 / IAM). Boat presses EXECUTE manually when needed;
  the missed-extract alert covers forgotten nights. Fixing IAM is worth doing now that Boat is back.
- Alert delivery still lands on `data@rabbit.co.th` — must also reach `piyaratt@rabbit.co.th` and/or Slack.

## 4. Task queue (in order — do not skip ahead)
1. **Date correction + rules consolidation** (§0 of this file). Run `date` first.
2. **`SAP_LIVE` bloat investigation — read-only.** Live row count/freshness; distinct DocEntry vs total;
   are duplicate rows byte-identical (re-insert) or genuinely different documents; do NULL-`BatchRunDate`
   rows cluster around loader crash times; **is any DocEntry present in the extract output but missing
   from `SAP_LIVE`** (real loss). Then: which baseline numbers must be recomputed. Propose a
   preservation + prevention plan (retain append-only audit history → fix future loader
   INSERT→idempotent write by DocEntry → OOM sizing). **Do not clean/dedup/rebuild historical
   `SAP_LIVE` before the incident is closed; do not execute changes.**
3. **Small fixes:** alert routing (+`piyaratt@`, Slack); `PAID_AFTER_CANCEL` alert only on new/changed
   cases (currently re-fires the same 7 rows daily → alert fatigue); freshness guard (if `SAP_LIVE`
   older than 26h, mark the chain `DEGRADED`, don't let recon results drive decisions, ⚠️ in digest).
4. **Apply the permanent knowledge rules** in `KNOWLEDGE_ADDENDUM_20260729_v2.md` (E1–E3, F1–F3),
   with `sap_excluded_records`, config-table parameters (not hardcoded), morning-report lines, and a
   refreshed backlog number (the old 373,044 must not be quoted again).
5. **Then** Phase B/C per `docs/tasks/TASK_V3_GAP_CLOSURE_v2.md` — only after item 2 is settled.
6. **Definition of Done for V3** (all must pass): 5 consecutive unattended nights; morning report
   delivered and useful; missing backlog inside the approved window = 0 or explained per row;
   v3 import error rate ≤ legacy over 5 nights; golden test passes on 3 fixtures; every alert verified
   to reach Boat's phone; runbook/AS_BUILT/PROGRESS match what is deployed.

## 5. Blocked on humans (do not attempt; keep `INPUTS_NEEDED.md` current)
| Item | Owner |
|---|---|
| 3 accepted interface files → `docs/fixtures/` (golden test) | Boat |
| Onetime `ProcessingFee` divisor (107?) | Boat / Finance |
| Validation-failure policy: item quarantine vs run-atomic (final) | Boat |
| EDC channel matrix for non-KBANK banks | Finance |
| Q3a — which document's InvoiceNo when a period has many, incl. all-NULL `BatchRunDate` | Aware — **hold sending; may be asking about our own garbage until the bloat is understood** |
| `run.invoker` IAM binding on `sap-extract-job` | Attila (or Boat if he has `run.admin`) |
| `sap_integrety_2025_RCL` duplicate-SUM issue | **CLOSED:** dormant/obsolete, no real consumer in 90 days; no notification; housekeeping/archive candidate |
| 7 genuine `PAID_AFTER_CANCEL` cases | FA — confirm intent before any cancel is sent |

## 6. Hard "do not" list
- Do not write to `gs://interface-file/**` (production; SAP pulls every 15 min).
- Do not DDL outside `sap_integration_v3`.
- Do not replace an object existing consumers read without an explicit "deploy OK" in that session.
- Do not enable/disable any schedule that someone may have paused deliberately.
- Do not notify anyone outside the team about money/accounting findings — write them up and stop.
- Do not run two agents against the same working tree at once; start every session with
  `git status && git log --oneline -5` and reconcile with `20_SAP_PROGRESS`.
- Do not declare anything "done" that hasn't been verified against real data. Label it UNVERIFIED.
