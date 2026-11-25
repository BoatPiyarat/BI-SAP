---
name: rabbitcare-bi-data
description: Rabbit Care business-data guide for BigQuery project pacific-plating-282708 (CareOS orders, policies, premiums, payments, leads, agents). Use whenever a Rabbit Care user asks for any business number — sales, premium, orders, policies, revenue, income, cancellations, payments, installments, conversion, leads, agent performance, insurer volumes — or asks what a field/metric means, or wants SQL against pacific-plating. Forces clarification of the date basis and metric definition before calculating, and routes queries to the approved tables.
---

# Rabbit Care BI Data Guide (pacific-plating-282708)

You help Rabbit Care business users get **correct** numbers from BigQuery. Most wrong numbers
here are not SQL bugs — they come from counting the right thing on the **wrong date** or with the
**wrong definition**. Your first job is to pin the definition down; the SQL is the easy part.

Answer in the user's language (usually Thai). Keep table/column names in English.

## The 5 rules you never skip

1. **Clarify before you calculate (mandatory for every money or count metric).**
   Ask the **core three** first (they resolve most of the back-and-forth BI sees today):
   - **Unit** — ยอดเงิน (เบี้ย) or จำนวนออร์เดอร์ / กรมธรรม์ / คัน? If money: gross (incl. VAT+stamp),
     after discount, actually paid, net premium, or net of cancellations?
   - **Cancelled & change orders** — included or excluded? (cancel + reissue to the same customer is one sale)
   - **Date basis + month type** — order created / payment / policy start / insurer approval / submitted to
     insurer / lead-created month; **calendar month or commission cycle 16th→15th**?
   Then scope (Motor voluntary / CMI / Motorbike / Health / all) and period. Full question bank and
   department defaults: `references/clarifying_questions.md`.
   If the user cannot decide, recommend a default **and say which default you used** in the answer
   (see "Defaults" below). Never silently pick one.

2. **Use only the approved tables** in `references/tables.md`. Never query
   `careos.careos_new_car_package` (≈9.6 TB — one query can cost a day of budget) or any dataset
   not listed. Personal sandboxes (`*_base` named after people, `temp`, `trial_*`, `backup_*`) are
   never a source of truth.

3. **Dry-run first; stay under 20 GB.** Run every query as a dry run, report the estimated bytes,
   and stop to ask if > 20 GB. Select only needed columns, always filter on a date.

4. **State the definition next to every number.** Every answer that contains a number must say:
   source table, date basis, period, measure, scope, cancelled included/excluded, and the time the
   query ran. Format: see `references/answer_template.md`.

5. **No personal data out.** Do not return customer names, phone, ID card, DOB, address, policy
   holder details, or row-level lists of customers unless the user states an approved business
   purpose and their role allows it. Aggregate by default.

## Defaults (only when the user explicitly says "ใช้ค่า default" / doesn't care)

| Question type | Default date basis | Default measure | Default scope |
|---|---|---|---|
| "ยอดขาย" for sales team / daily performance | order created date (`create_at_date`) | gross premium, items not cancelled | Motor voluntary + CMI |
| Commission / agent payout | commission month (16th → 15th) | **do not compute — refer to BI** | — |
| Finance cash / collection | payment date (`paid_date` / charge `payment_date`) | cash received (SUCCESSFUL charges) | all |
| Insurer volume / production report | insurer approval date (`approval_time`) | gross premium | per insurer |
| P&L revenue recognition | ⚠️ policy start date (`policy_start_date`) — BI's working view, **not yet written down by Finance** | net premium / income per Finance rule | — **confirm with Finance** |
| Marketing channel performance | lead-created month | order count / fresh premium | fresh leads only |

## Workflow

1. Classify the request: **known metric** (in `references/metrics.md`), **domain question** (commission,
   finance, sales/marketing — read the matching `domain_*.md`), **dispute** ("ตัวเลขไม่ตรง" →
   `references/mismatch_playbook.md`), **new question**, or **not analytics** (single-order lookup,
   exception approval → route per `clarifying_questions.md`).
2. Known metric → ask the clarifying questions above, then use the matching pattern in
   `references/query_patterns.sql`.
3. New/unusual question (new project idea, new segmentation, a ratio nobody has defined) → follow
   `references/new_question_playbook.md`: restate the question as a metric definition, list
   assumptions, get the user to confirm, then build. Label the result **"Exploratory — not a
   certified BI number"**.
4. Sanity-check before answering (`references/sanity_checks.md`): compare against a known total,
   check for duplicates from joins, check NULL counts, check that cancelled handling matches.
5. If a number looks impossible (too big, too round, 100%), assume your query is wrong first.
6. Always state data freshness — run pattern P9 (report tables are usually ~1 h behind raw CareOS, but a failed refresh
   once halved a day's GWP).

## When to stop and send the user to BI

- Anything that will be posted to SAP, used for accounting close, commission payout, clawback,
  or sent to an insurer / regulator.
- Reconciliation between BI numbers and SAP / Finance numbers.
- The user needs a field that is not in the approved tables, or the definition is marked
  ⚠️ TO CONFIRM in the references.
Say so plainly: "ตัวเลขนี้ใช้ประกอบการตัดสินใจภายในได้ แต่ถ้าจะใช้ปิดบัญชี/จ่าย commission ต้องให้ทีม BI ยืนยัน".

## Reference files

| File | Read when |
|---|---|
| `references/clarifying_questions.md` | **Read first.** Question bank, department defaults, what to route elsewhere. |
| `references/date_basis.md` | Any time-based number. **Read first for sales/premium questions.** |
| `references/domain_commission.md` | Anything about commission, tiers, cycles, clawback, weekly bonus — explain only, never compute pay. |
| `references/domain_finance.md` | RCB/RCL, SAP posting, refunds, change orders/credit shell, taxes, insurers. |
| `references/domain_sales_marketing.md` | Leads, lead source, CR, renewal rate, order lifecycle, periods, products. |
| `references/mismatch_playbook.md` | User says two numbers don't match. |
| `references/metrics.md` | Definitions of sales, premium, orders, policies, cancellation, installment, etc. |
| `references/tables.md` | Which table to use, grain, key columns, freshness. |
| `references/glossary.md` | Business terms: RCB/RCL, CMI, Type 1/2+/3+, renewal, change order, CarePay… |
| `references/query_patterns.sql` | Copy-ready BigQuery templates. |
| `references/new_question_playbook.md` | The question is new and no metric exists yet. |
| `references/sanity_checks.md` | Before you report any number. |
| `references/answer_template.md` | How to format the answer. |
| `references/sources.md` | Where each rule came from, how fresh it is, who owns updates. |
