# Domain: sales, leads, marketing, renewal, operations

## Order lifecycle (what "counted" means)

created → paid → **QC approved** → **submitted to insurer (แจ้งงาน)** → insurer accepted / policy uploaded → shipped.
Motor sales count for commission at submission; Health at QC approval. Status values in
`report_order_items.status`: created, insurer accepted, shipped, cancelled.

## Leads

- **`lead_source`** is normalised by BI's dbt model (`base_nana_leads`): CareOS source name + lead type →
  e.g. Change - Online, Renewal, Database - renew expired (Renew / ADB-RENEWAL / Roojai-Renewal), Priceza,
  Other - offline - Retainer, Other - online, Other - offline (fallback), TRUE (dtac/trueapp), OpenAI,
  Friendgetfriend, Google, Facebook, SEO, LINE, Tiktok…
- **Fresh** lead = anything not mapped to Renewal / Retainer / Database.
- **Online vs offline** = CareOS flag `is_online_lead`, **not** the `lead_source` label (some "Other - online"
  sources are flagged offline). Say which one you used.
- Known issue since 9 Oct 2026: Priceza retainer leads may be counted as Fresh in `total_fresh_lead_non_dup`.
- Lead re-pooling (คละลีด / mass assign of in-progress leads > 2 weeks old) is **not** new leads; it can reset
  assignment dates.
- Lead assignment rules (company practice): new hires receive leads from 13:00 on onboarding day (from 9 Nov 2026);
  Health Fresh/SEM leads go only to agents with sales (from 10 Aug 2026).
- HSBC / Vietnam (RCV) programme has its own lead/qualified/approved definitions — never mix with Thai insurance.

## Conversion rate (CR)

- Existing BI definition — `analytics_views.report_daily_cr`: **online leads by lead-created date**; an order
  counts if it carries the lead's `short_id`, is **not cancelled (order level)**, and was created within
  **4 calendar months** of the lead. CR = orders ÷ leads per lead-created date.
- Commission/SV CR30 / CR60: base = distinct leads whose **lead-created and latest-assignment dates** fall in the
  cycle window; numerator = those converted to paid + QC-passed policies in the window.
- CareOS "Conversion Performance" is **one day behind** (paid status imported daily).
- Reference: Motor company CR ≈ **6.6–8.4%** (Aug–Sep 2026, BI) — basis (lead vs order date) unconfirmed.
- Cost per conversion = total spend ÷ total conversions (weighted), never an average of ratios.
- Leads count toward the product named on the lead; moving a Health lead to a Motor seller lowers Health CR.

## Renewal rate (RR)

- **Motor**: from the monthly Renewal sheet/dashboard, cohort = **expiry month**, snapshotted at the cycle cut-off.
  Two columns: "Renewal Rate" (excludes status *create*) and "Renewal Rate (inc. Create)" (includes it).
  Changes after the snapshot are not disputable.
- **Health (Renewal Health)**: PURCHASED leads ÷ leads assigned in the previous month's tab (method pending owner confirmation).
- Targets seen (Aug 2025, may be stale): Renewal team 68% / 70% / 72% for month 1 / 2 / 3+.
- Advance renewal: insurers accept submission only within ~60 days before start.
- For retention questions, use a **first-purchase-year cohort**.
- Some renewal orders are created in bulk manually (e.g. certain insurers) — not from normal lead flow.

## Periods

- Sales/commission month **Mxx = 16th → 15th**; weeks Mon–Sun inside it.
- Marketing dashboards attribute orders to the **lead-created month**.
- Calendar month is used by Finance and most exec reporting — always ask.

## Products

- Motor voluntary Type 1 / 2+ / 3 / 3+; CMI (พ.ร.บ.) via `motor_item_type`; Motorbike (`oicCode LIKE 'TYPE_6%'`,
  excluded from Motor commission). Short-term policies and extended CMI cannot be identified from CareOS fields.
- Health from 2024-10; NonMotor categories Cancer / Home / Health / Life.
- Referral (FGF / Friendgetfriend): voucher 500 THB when premium < 25,000 (Nov 2026).

## Ops SLA buckets (refund dashboard)

Operation SLA 1–7 days; FA SLA 8–14 days; Company SLA 16–30 days (event → refund sent to bank). Start/stop events ⚠️ to confirm.

## Not found yet (answer "BI has no written definition")

Contact rate, valid lead, duplicate-lead key, ticket size / AOV, per-team targets, talk-time → lead quota table.
