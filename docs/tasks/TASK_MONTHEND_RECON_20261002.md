# SAP month-end reconciliation — 2026-10-02

User requested local review files, reusable SQL, and outstanding summaries. No upload is authorized by this task.

## Latest user decision

The final instruction supersedes September settings: BatchRunDate is CURRENT_DATE in Asia/Bangkok;
every non-empty interface PaymentDate must be within CURRENT_MONTH. Before-month unposted receipts
are clamped to day 1 under the existing rollover rule. Original source dates remain audit evidence.
Do not rewrite SAP Paid predecessor dates: hold the complete spine if immutable historical dates
conflict with the current-month instruction.

Paid scope is SUCCESSFUL charge payment_date in 2026 Bangkok. Cancel scope is item cancel_time
in 2026 Bangkok only. Unknown dates are separate, never inferred from update/create timestamps.
Pending scope includes current SAP Pending items of any year plus 2026 source order/payment schedules.

## Local result

Completed at 2026-10-02T18:05:53.874062+07:00. Output: `C:/Users/Developer/OneDrive - Rabbit Internet/Documents/03 Project - Partner/02 SAP/2026 Q3 closing/reconcile_20261002`.
Paid outstanding candidates: 789 obligations / 767 items.
Cancellation outstanding/review population: 619 items.
Local review interfaces: 2 files / 6 items / 32 rows.
These counts do not establish SAP posting or JE acceptance. See READ_ME_RECONCILIATION.txt and
summary.json for source query times, scope and non-additive exceptions.

The immutable draft gate uses full source period spines, exact SAP receipts, prior-interface
exclusion, per-view schema/type evidence, current-month dates, source policy/address repairs,
and final accepted-payload plus exact SAP allocation conservation. Invalid whole items remain
in interface_validation.csv. Unknown/multi-document cancellation remains held.

Independent static review: /root/review_reconcile PASS for payment preparation/export after
corrections; evidence/output verification is recorded alongside files. No production writes,
view deployment, GCS upload, scheduler mutation, or SAP mutation occurred.

Repository startup git pull --ff-only failed because existing branches diverge. Existing dirty
work was preserved. This operational handoff is local; no unrelated merge/rebase or publication.
