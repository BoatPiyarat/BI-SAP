# RULE-03 scope for live SAP_LIVE_FULL — design only

Status: proposed; **do not deploy before 2026-08-03** and do not edit the legacy view during July
close.

## Finding

The deployed `sap_integration_v2.SAP_LIVE_FULL` selects one row per DocEntry using
`ORDER BY UpdateDate DESC` without `UpdateTime`. This is the same class of same-day tie defect that
STEP B exposed: legitimate states on the same date cannot be ordered reliably. All legacy SAP
interface views consume this live object, so RULE-03 must cover it, not only v3 DDL 024/025.

## Proposed scope after close

1. Capture the live definition immediately before implementation; never start from repo 007.
2. Preserve existing column names, native types, and positional order. Project `UpdateTime` in the
   same position across all four UNION branches without `* EXCEPT` plus re-add.
3. Rank DocEntry versions by `UpdateDate DESC, UpdateTime DESC`, followed by a reviewed deterministic
   tie-break when both are equal or NULL.
4. Do not claim `DocEntry DESC` resolves the final tie: DocEntry is constant inside
   `PARTITION BY DocEntry`. Candidate tie-breaks require measured evidence and a documented source
   precedence or stable row fingerprint.
5. Measure candidate count, winner changes, InvoiceNo changes, and NULL UpdateDate/UpdateTime before
   replacement. Route unresolved semantic ties to review rather than auto-picking silently.
6. Verify row count, distinct DocEntry count, column order/types, and all six live interface view
   consumers in a shadow object before requesting a deploy gate.

This change is separate from retry idempotency. DISTINCT already contains byte-identical retry
copies; RULE-03 addresses which legitimate same-DocEntry version wins.
