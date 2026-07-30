# Finding — onetime M1/V1 allocation generator

Status: OPEN, internal only, quantification under class-A review.

> ⚠️ **POSTED-STATE GATE:** BI-output populations and error XLSX rows do not prove SAP posting.
> Any count or amount in this finding remains non-citable until each correction candidate passes
> the `POSTED_WRONG` gate: SAP mirror + successful status + JE reference from a successful import
> log. Route `REJECTED_NEVER_POSTED` to generator fix + normal send, not correction.

## Known-answer case

`L78496990` is not a credit-shell order. It is produced by
`sap_data_engineer.sap_dashboard_carepay_fully_paid`, where one combined successful payment is
allocated incorrectly across M1/V1. Evidence in commit `9e6b44d`:

- the order is absent from all checked credit-shell views and `cancelled_change_orders`;
- the onetime view emits both M1 and V1;
- SAP evidence showed M1/V1 sharing the payment identity/amount shape instead of a correct split.

This is a second generator of the same `AMOUNT_VARIANCE` / `MISPOSTING` defect classes associated
with the 263-transaction incident family. It is separate from the credit-shell multi-charge join
and requires its own fix.

## Reporting constraint

FA-facing incident totals must combine:

1. credit-shell generator population; and
2. onetime `sap_dashboard_carepay_fully_paid` generator population,

with overlap removed at order grain. Commit `3c10215` contains a first quantification but reports a
range because raw identical-charge rows are not yet proven to be duplicate logs versus real
payments. It is under class-A review (`b7d4f81`). Do not quote a combined point estimate to FA
until that ambiguity is resolved and the review passes.

## Prevention

Option A for the credit-shell v2 view does not fix this onetime generator because the join shapes
are different. Claude Code must design and validate a separate onetime correction path. No SQL or
live object is changed by this finding.
