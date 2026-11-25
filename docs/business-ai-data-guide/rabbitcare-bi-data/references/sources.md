# Where this knowledge came from (v1, 2026-11-25)

| Source | What was taken | Window |
|---|---|---|
| BigQuery `pacific-plating-282708` (metadata + profiling queries, read-only) | Tables, grains, value distributions, verified formulas, live view SQL (`motor_commission.*`, `analytics_views.report_daily_cr`, `SAP.*`) | snapshot 2026-11-25 |
| BI-SAP Git repo (`docs/knowledge/*`, validation rules, change-order design) | RCB/RCL, cancellation, change order, credit shell, SAP posting rules, test customers | as of commit date |
| Microsoft Teams (BI, FA, sales, marketing, ops chats) | Business rules, decisions, clarifying questions BI asks, disputes | Nov 2025 – Nov 2026 |
| Company email (BI mailbox; commission, finance, insurer, HR threads) | Commission memos & announcements, finance/insurer processes | Nov 2025 – Nov 2026 |

Not used: Google Drive (repository rule: backup only, not a knowledge source).

Rules of use:
- Newer, explicit decisions win. When a user cites an announcement newer than 2026-11-25, prefer it and
  tell them to confirm with BI.
- Items marked ⚠️ are evidence-based or pending an owner's confirmation — never present them as policy.
- No customer data and no individual pay figures are stored in this skill.

Owner: BI (Rabbit Care). Review monthly; add every new definition BI agrees with a business owner.
