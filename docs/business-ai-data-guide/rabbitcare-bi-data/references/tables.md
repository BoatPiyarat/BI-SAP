# Approved tables (pacific-plating-282708, region asia-southeast1)

Use the **report layer first**. Go to raw CareOS only when the report layer lacks the field.
Sizes/rows from `INFORMATION_SCHEMA.TABLE_STORAGE`, 2026-11-25. Raw `careos.*` loads by incremental MERGE about every hour;
`report_*` tables were ~1 h behind when checked (2026-11-25 17:30 ICT) — always run P9 before quoting today.

## Tier 1 — report layer (preferred)

| Table | Grain | Rows | Use for |
|---|---|---|---|
| `analytics_reports.report_order_items` | ~1 row per order item (policy) — ⚠️ 48 rows duplicate an `item_id` (all-time, 2026-11-25): use `COUNT(DISTINCT item_id)` | ~830k | Premium, policies, product mix, insurer, agent, channel, car details. **Default for sales questions.** |
| `analytics_reports.report_orders` | 1 row per order (`short_id`) | ~811k | Order counts, order-level dates (approved/paid/printed/shipped), voluntary vs mandatory premium, installment info, renewal. |
| `analytics_reports.report_leads` | 1 row per lead | ~8.4M | Lead volume, source, conversion funnels. |
| `analytics_reports.report_renew_orders` / `report_renew_leads` | renewal order / lead | ~32k / ~47k | Renewal analysis. |
| `analytics_reports.report_rejection` | rejection event | ~5.6M | Lead rejection reasons. |
| `analytics_reports.report_orders_nonmotor`, `report_leads_nonmotor`, `non_motor_report_order_for_accounting` | non-motor order / lead | small | Health & other non-motor. |
| `analytics_reports.report_agent_daily_performance` | agent × day | ~24M | Agent activity/performance. Filter by date! |
| `analytics_reports.report_marketing_daily`, `report_marketing_kpi`, `report_cr_marketing` | channel × day | small | Marketing spend/leads/CR. |

## Tier 2 — dimensions

| Table | Use |
|---|---|
| `analytics_dimensional_modelling.dim_days` | Calendar. |
| `analytics_dimensional_modelling.dim_commission_months` | Commission month (`start_date` = 16th, `end_date` = 15th). |
| `analytics_dimensional_modelling.dim_work_weeks`, `dim_biweeks` | Work-week / bi-week periods for targets. |
| `analytics_dimensional_modelling.dim_marketing_channels`, `dim_lead_sources_list` | Channel / lead-source mapping. |
| `careos.careos_insurance_companies` | Insurer master (`id`, `name_th`, `shortname_en`). |

## Tier 3 — raw CareOS (only when needed; ask BI if unsure)

| Table | Grain | Key notes |
|---|---|---|
| `careos.careos_orders` | order | `human_id` = order number. Do **not** use its `is_cancelled` for item cancellation. |
| `careos.careos_order_items` | order item | `order_id` → `careos_orders.id`; `policy_start_date`, `approval_time`, `submit_date`, `cancel_time`, `motor_item_type`, `product`, premiums. |
| `careos.carepay_transactions` | payment transaction per order | `order` → order id; `amount` in **satang**; `installments`. |
| `careos.carepay_charges` | one charge (payment attempt / installment) | `transaction_id`; `amount` in **satang**; `status` (SUCCESSFUL/PENDING/FAILED); `payment_date`; `installment_number`; `service_provider` (`RABBIT_LENDING` = RCL). |
| `careos.careos_accounting` | accounting / refund status per item | remittance, refund and cancellation workflow fields. |
| `careos.cancelled_change_orders` | change-order link | `old_human_id` → `current_human_id`. Use to count a cancel + replacement once. |
| `analytics_views.report_daily_cr` | lead-created day | Existing CR definition (view — reads report tables). |

Raw rules: filter `delete_time IS NULL`; CareOS order/item timestamps are already Bangkok time but CarePay timestamps are true UTC (see date_basis.md); satang ÷ 100; JSON fields (`data`,
`annotations`) need BI help.

## Never use

- `careos.careos_new_car_package` (~9.6 TB), `careos.careos_car_insurance_packages_join_car_submodels`,
  `careos.careos_generic_prod_*` — price-catalog tables, huge, not sales data.
- `SAP`, `sap_view`, `sap_data_engineer`, `sap_integration_v2`, `sap_integration_v3` — accounting
  interface pipeline. Numbers here follow SAP posting rules, not business definitions.
- `motor_commission.*` — commission payout engine (governed).
- `nana*`, `ibroker*`, `*_2021_*` — legacy systems before CareOS (pre-Dec-2022 data).
- Personal / scratch datasets: `nutthapoj_base`, `pimwis_base`, `pongsakornm_base`,
  `suphakorn_analytics`, `tsr_arwut`, `temp`, `develop_*`, `staging_*`, `_script*`, and any table
  named `trial_*` or `backup_*`.
- `analytics_reports.report_orders_by_agent_by_day` (~69 GB) — use `report_order_items` instead.

## Traps

- `analytics_views.nonmotor_income` = customer income-bracket survey answers, **not** company income.
- `report_*` tables are built by dbt (raw → `analytics_base` → `analytics_interim` → `analytics_dimensional_modelling` →
  `analytics_reports`); if a run fails the table goes stale (one failure halved a day's GWP). Check
  `MAX(created_at_timestamp)` in `report_orders` before quoting "today" / "yesterday".
- Marketing KPI tables count leads by the dbt `lead_source` mapping; online/offline uses the `is_online_lead` flag.

## Other useful facts (BI onboarding deck, Nov 2026)

- `report_orders` / `report_leads` are partitioned by `created_at_date` — always filter on it.
- Do-not-call list `auto_report.report_exclude_phone_dont_call_pdpa_blacklist` must be applied to **every** contact list.
- `auto_report.motor_order_gwp` (1 row per order) keeps the **first** order of a change-order chain as active — same count
  as pattern P8 but a different row kept; don't mix the two.
- Legacy systems: `nana*` (stopped Jan 2025), `ibroker_adb` (ADB broker, to Feb 2025), `ibroker_rb_nonmotor` (to Aug 2026).
  Nana-era GWP = gross × 0.9308; the iCollection ledger (`ibrokerrb_2021_08_16`) must never be added to GWP. Cross-era
  history → BI only.
- Data requests go to data@ / Jira (SLA: acknowledge 15 min, freshness issue 30 min, new development 3 days–2 weeks).

## Data history

CareOS data starts **2022-12-19**. Earlier sales lived in legacy systems (Nana/iBroker); combining
eras needs BI.
