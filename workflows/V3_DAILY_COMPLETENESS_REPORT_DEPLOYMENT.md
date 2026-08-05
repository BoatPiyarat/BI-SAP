# V3 daily completeness report — source-only deployment contract

The source does not authorize deployment, a trigger, a mailbox change, or a BigQuery mutation.

Run the offline contract before packaging or deployment:

```powershell
node workflows/test_v3_daily_completeness_report.js
Get-Content -Raw -Encoding UTF8 workflows/v3_daily_completeness_report.gs | node --check -
```

The test uses no Apps Script ID, OAuth, Gmail, BigQuery, network, or mail call. It covers metric
report construction, recipient exclusion from the body, success ordering, primary→fallback
ordering, dual-channel failure, and multi-run batch isolation.

Before deployment, Boat must approve and prove a primary recipient and an independent fallback
recipient; they must be different, and `data@rabbit.co.th` alone is insufficient. Set Script
Properties `PROJECT_ID`, `COMPLETENESS_RECIPIENT`, and `COMPLETENESS_FALLBACK_RECIPIENT` (with
optional `BQ_DATASET=sap_integration_v3`). Use the existing Apps Script BigQuery, external-request,
and send-mail scopes. Install a trigger for `dispatchPendingV3DailyCompletenessReports` only after
review PASS and a scoped production approval.

Acceptance rehearsal must prove a pending snapshot sends a sanitized metric-only report then moves
from `PENDING` to `DELIVERED`; a forced primary-mail failure changes it to `ALERT_FAILED` before
the independent fallback is attempted; and an unavailable fallback raises an error rather than
silently claiming delivery.
