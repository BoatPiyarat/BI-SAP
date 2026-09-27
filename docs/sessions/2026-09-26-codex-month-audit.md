# Current-month completeness audit

User requested September CareOS paid and cancellation coverage in SAP, reusable current-month SQL and grouped reasons. Dedicated branch audit/careos-month-completeness-20260926.

Read-only raw CareOS and SAP_LIVE_FULL reconciliation. Corrected false positives using independent static review: provider/route-specific fallback ranks, compulsory later-charge links, latest source status selection, historical cancellation conflicts. Exact final query succeeds with three conservation/grain assertions. Source boundaries checked (zero orphan September cancels and zero successful charges without any paid date).

Live upstream and cancellation membership queried separately, using cached populations to avoid repeated scans. Paid 10 extra receipts blocked by live paid-period gate; cancellation 8 missing invoice rows in 7 items, including L80517642-1. 134 cancellation rows already in output need import logs. No production object or SAP/interface write.

Detailed results/limits: docs/FINDINGS_CAREOS_MONTH_COMPLETENESS_20260926.md. Independent review PASS WITH NOTES; formal Claude review requested after artifact commit. Diagnostic failures and superseded results are retained and clearly labeled; final source is bound to the successful execution.
