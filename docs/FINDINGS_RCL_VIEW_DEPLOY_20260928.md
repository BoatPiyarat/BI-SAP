# RCL production views — deployed 2026-09-28

**DEPLOYED and live postcheck PASS.** User explicitly authorized direct view changes and confirmed
both principal fields of additional receipts equal the new charge amount. V3 remains held.

## Views changed

| Production view | Change |
|---|---|
| `sap_data_engineer.sap_dashboard_carepay_installment` | For raw-rank-identified additional receipts only, PrincipleThisPeriod and PrincipleEIRThisPeriod now equal ActualReceived. ExpectedReceived remains0; ActualReceived remains the new charge. Ordinary/CMI rows and interest fields unchanged. |
| `sap_integration_v2.RCL 05_newpayment` | Receipt-aware additional payment eligibility despite existing Paid period; immutable invoice/item/period terminal checks prevent replay. Explicit error for unsent nonzero receipts missing source lineage. |
| `sap_integration_v2.RCL 05_paid by period` | A recent outstanding receipt in any installment may reopen the item even if its latest period is Paid; ordinary fallback invoice supported; deterministic latest-charge ranking. |
| `sap_view.RCL_Motor_process_2_newpayment` | Removes unrelated order-created-in-2026 cutoff. Keeps receipt-recency, product and cancellation guards; parses payment dates and resolves ties deterministically. |

Project: `pacific-plating-282708`. Dependency-order DDL jobs all DONE:
- `rcl_release_deploy_dashboard_20260928_001` — sap_data_engineer.sap_dashboard_carepay_installment; read-back 2026-09-28T03:06:37.439316+00:00
- `rcl_release_deploy_newpayment_20260928_001` — sap_integration_v2.RCL 05_newpayment; read-back 2026-09-28T03:08:51.040161+00:00
- `rcl_release_deploy_gate_20260928_001` — sap_integration_v2.RCL 05_paid by period; read-back 2026-09-28T03:09:13.857093+00:00
- `rcl_release_deploy_wrapper_20260928_001` — sap_view.RCL_Motor_process_2_newpayment; read-back 2026-09-28T03:09:37.223671+00:00

## Verification

Fresh metadata matched reviewed originals. All four definitions and positional schemas match the
intended release after deployment: 56/56/13/56 columns. BigQuery removes leading SQL comments;
read-back comparison normalizes only those leading comments and whitespace. The first deployment
checker stopped after newpayment on this textual difference; inspected diff showed no executable
SQL difference, and deployment continued. No failed DDL job or rollback occurred.

Fresh preflight `rcl_release_preflight_20260928_001`, checked 2026-09-28 03:02:14 UTC:
- zero additional principal mismatches;
- zero removed ordinary first-receipt or nonprincipal dashboard payloads;
- zero original wrapper payload removals, duplicate event keys or incomplete schedules;
- baseline2,474 → candidate4,036 rows on that snapshot.

Live postcheck `rcl_release_postcheck_20260928_001`, checked 2026-09-28 03:11:23 UTC:
- 4032 rows / 523 items; zero duplicate event keys and zero incomplete schedules;
- all10 targeted invoices pass ExpectedReceived=0 and both principal fields=ActualReceived;
- this includes all8 previously flagged period2–4 exceptions and both reported extra receipts;
- L80570054:22.04 THB; L79109956:645.21 THB, present in live Motor newpayment output.

The preflight and postcheck use different current-data snapshots; their counts are not an asserted
same-snapshot equality. Before/after payload preservation was checked within the preflight population.

`python scripts/verify_rcl_release_20260928.py` verifies saved DDL job completion, exact definitions,
schemas, principal targets and live output checks. Static review: docs/reviews/2026-09-28-rcl-principal-independent.md.
Evidence and rollback: docs/evidence/rcl_downstream_deploy_20260928/.

## Scope and operating notes

No manual SAP import, export file, production GCS write, scheduler change or V3 mutation occurred.
This confirms live view output, not completed SAP import/posting. Existing Motor schedule remains
01:30 Asia/Bangkok. Invoice values already held by SAP are not rewritten by this correction.

Rollback uses the four captured *_rollback.sql files in reverse dependency order, only if needed.
Definitions are also preserved verbatim in *_before.json. Broad lineage diagnostics and unresolved
NonMotor/change-order/backlog scenarios remain separate from this four-view release.

All queries used bq_safe_query and its hard20-GiB cap. Preflight processed18,486,348,625bytes; postcheck
processed10,730,304,368bytes. Script dry-run estimates of0 reflect temporary-table scripting, not zero
query cost. DDL jobs and exact executed SQL are preserved in the evidence files.
