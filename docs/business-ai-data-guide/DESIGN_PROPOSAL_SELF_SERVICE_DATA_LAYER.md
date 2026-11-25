# Proposal: Governed Self-Service Data for Business AI Users

Owner: BI (Boat) · Status: DRAFT for K.Paul review · Date: 2026-11-25
Scope: BigQuery project `pacific-plating-282708`

## 1. Problem

Business users who design new projects want to ask their own AI assistant for numbers. Their
questions are new each time, so BI cannot pre-build every metric. Today an AI pointed at the
project would face:

- **~95 datasets**, most undocumented, including personal sandboxes, legacy systems (Nana /
  iBroker), SAP interface pipelines and backups that look like real data.
- **Ambiguous definitions.** "Sales" can be counted on order-created, payment, policy-start or
  insurer-approval date. For October 2026 those four bases differ by about ฿18M (≈10%) on the same
  data (see `rabbitcare-bi-data/references/date_basis.md`; this is a method illustration, not a
  certified figure). In 2026 YTD, 35.8% of orders have a policy-start month that differs from the
  order month.
- **Cost risk.** One catalog table (`careos.careos_new_car_package`) is ~9.6 TB; an unguided query
  could scan it.
- **PII exposure.** Report tables carry customer names, DOB and addresses.

## 2. Recommendation (three layers, delivered in order)

| Layer | What | Solves | Effort (estimate) |
|---|---|---|---|
| **1. Skill (now)** | `rabbitcare-bi-data` Claude skill: date-basis clarification, metric definitions, approved tables, query templates, playbook for new questions. | Wrong definitions, wrong tables | Delivered as v1 (this repo) |
| **2. Governed access dataset (next)** | New dataset `bi_self_service` with **authorized views** over the report layer: PII columns removed, one view per grain (`v_order_items`, `v_orders`, `v_leads`, `v_payments`), all four date bases pre-computed in Bangkok time, a `metric_catalog` table. Business users get `roles/bigquery.dataViewer` on this dataset **only**, plus a per-user custom quota. | PII, cost, table sprawl | ~1–2 weeks BI (estimate, not yet scoped) |
| **3. Semantic layer / warehouse (target)** | Conformed star schema: `fact_policy_item`, `fact_payment_charge`, `fact_lead`, shared `dim_date` with role-playing date keys (created / paid / policy-start / approved), `dim_insurer`, `dim_agent`, `dim_product`. Certified metrics defined once (dbt metrics or Looker/LookML) and reused by dashboards, SAP recon and AI. | New questions answerable by combining certified building blocks | Quarter-scale; aligns with the existing BI-restructure / single-source-of-truth pillar |

### Why not a pre-computed metric for every question?

Because the questions are unpredictable. The design goal is **certified building blocks + clear
definitions**, not certified answers. A new question then becomes "combine these blocks, choose a
date basis" — which an AI can do safely — instead of "find the right columns among 95 datasets".

### Why a skill rather than a user preference?

| | Skill | Preference |
|---|---|---|
| Shared once, same for all users | ✅ (org-provisioned) | ❌ each user pastes their own copy |
| Can hold reference files & SQL | ✅ loaded only when needed | ❌ short text, always in context |
| Versioned in Git, updated centrally | ✅ | ❌ drifts per user |
| Triggers only on data questions | ✅ | ❌ affects every conversation |

Recommendation: distribute as an org skill; optionally give users a one-line preference such as
"For Rabbit Care data questions, always use the rabbitcare-bi-data skill."

## 3. Guardrails (apply from day one)

1. Business users get **no** access to `careos`, `SAP*`, `sap_*`, `motor_commission` or sandboxes
   once Layer 2 exists; until then, rely on the skill's rules plus BigQuery per-user quotas.
2. Every AI answer states its definition (date basis, measure, scope, source, time).
3. Numbers for accounting close, commission, insurer reconciliation or regulators remain BI-certified only.
4. Exploratory results are labelled "not a certified BI number".
5. New definitions discovered by users are sent back to BI and added to the skill (monthly review).

## 4. Open decisions (owner)

| # | Decision | Owner |
|---|---|---|
| D1 | Confirm P&L revenue basis = policy start date, and which premium/income measure | Finance (K.Bell) |
| D2 | Confirm insurer production basis = approval date for all insurers | BI + Operations |
| D3 | Commission month assignment date (created vs paid vs approved) | Sales ops / commission owner |
| D4 | Whether report-table `*_date` columns are Bangkok dates | BI |
| D5 | Who may access row-level customer data via AI | Data governance / DPO |
| D6 | Pilot user group and BigQuery quota per user | K.Paul |
| D7 | Confirm time-zone conventions (CareOS order timestamps = Bangkok wall-clock; CarePay = UTC) and fix in Layer 2 views | BI + IT |

## 5. Next steps

1. Pilot the v1 skill with 2–3 business users for two weeks; log every question that needed BI help.
2. Use that log to scope Layer 2 views (only the grains people actually needed).
3. Close D1–D6 and update the skill's ⚠️ TO CONFIRM items.
