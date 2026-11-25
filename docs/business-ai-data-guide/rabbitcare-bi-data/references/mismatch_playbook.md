# "ตัวเลขไม่ตรง" playbook

Ranked by how often each cause appeared in BI's Teams/email disputes (Nov 2025 – Nov 2026).

| # | Cause | Typical symptom | How to check |
|---|---|---|---|
| 1 | **Premium definition** | Dashboard (premium − recorded discount) vs commission (invoice actually paid) vs SV metric (net of cancellations) | Recompute both with the same measure; list orders where they differ |
| 2 | **Cancelled / change orders** | Cancel + reissue counted twice; RR differs by whether change-order cancels count | Use `careos.cancelled_change_orders`; state cancel handling |
| 3 | **Date basis** | Same month, different totals (created vs paid vs policy start vs submitted vs lead-created month) | Run pattern P2 to show all bases side by side |
| 4 | **Cycle vs calendar month** | "Nov" = M11 (16 Oct–15 Nov) for sales, calendar Nov for finance | Ask; show both if unsure |
| 5 | **Freshness** | Today's number far too low (a failed nightly refresh once showed 2.53M GWP vs ~5.9M real) | Check `MAX(created_at_timestamp)` in `report_orders` vs now; raw `careos_orders` for today |
| 6 | **Team attribution** | Agent under the wrong SV, moved mid-cycle, team name with trailing space | Team as of cycle snapshot vs today |
| 7 | **Grain** | Orders vs items vs policies vs cars | State the grain; `COUNT(DISTINCT …)` |
| 8 | **External platform** | Ads Manager vs sheet spend (missing ad account, FX), insurer premium vs CareOS (endorsements) | Name both sources; differences in definitions are expected |
| 9 | **Product misclassification** | CMI-only order recorded as voluntary | Use `motor_item_type`, report count of suspicious rows |
| 10 | **SAP year scope / posting date** | 2024–2025 SAP totals ≠ BI; payment posted in next month after close | Explain by design (domain_finance.md) |

## How to answer a dispute (BI's pattern)

1. Ask for the user's number, its source (dashboard page / file) and, if possible, an export.
2. Reproduce **their** definition first, then the official one.
3. Return an **order-level reconciliation**: orders in A not in B, B not in A, and per-order amount
   differences — each labelled with the cause from the table above.
4. If the gap is commission-related, point to the /commission portal request form.
