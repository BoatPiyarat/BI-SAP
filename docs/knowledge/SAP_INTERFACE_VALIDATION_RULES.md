# SAP interface validation rules

Canonical source-only specification consolidated with Boat on 2026-08-01. It does not claim that
every check is deployed. `EXCLUDED != DELETED`: exclusions, validation failures, and real backlog
remain separately auditable.

## Population and routing

1. The goal is to move successful CareOS payment transactions that resolve to an order number into SAP.
2. `carepay_charges.status='SUCCESSFUL'` is necessary but not sufficient. The charge must resolve
   through its transaction to `careos_orders`, a `careos_order_items` row with non-empty `human_id`,
   and a lead with `status='LEAD_STATUS_PURCHASED'`. Orphans/non-purchased leads are source-data
   exceptions, not interface-qualified payments.
3. RCB is one-time/full payment and has `TotalPeriods=1`.
4. RCL normally has `TotalPeriods>1`. The confirmed exception is compulsory motor (CMI) paid with
   VMI in one bundled charge: `RCL_CMI`, `TotalPeriods=1`. Identify CMI only with
   `motor_item_type='MOTOR_TYPE_COMPULSORY'`.
5. RCL contains exactly periods `1..TotalPeriods`, with no gaps/extras. Thus TotalPeriods=6 means
   six schedule rows; period 1 may be Paid while the rest remain Pending.

## Positional and format contract

6. Every CSV has exactly the canonical 56 columns in `sap_column_contract`, in identical ordinal
   order. SAP reads by position; moving one column corrupts all following values.
7. `OrderDate`, `PolicyDate`, `PaymentDate`, `ExpectedDate`, and `BatchRunDate` are empty only where
   status permits, or exactly eight parseable `DDMMYYYY` characters. `BatRunDate` is a typo;
   `BatchRunDate` is the contract field.
8. `InsuredID` is the insured person's Thai national identification number or passport number.
   NULL/empty source becomes `-` and is never blank in the file.
9. `InsurerCode` is the code used to map the insurance-company name. It is distinct from
   `InsuredID`. Motor codes are digits; NonMotor codes are `N` followed by digits. Boat's item 11
   named InsurerID but described InsurerCode format; Boat clarified the two definitions on
   2026-08-01.
10. PolicyNo longer than 50 characters is blocked as `POLICYNO_TOO_LONG`; never truncate.
11. Contract column 35 is `TransactionStatus`; SAP stores the same semantic value as
    `U_PolicyStatus`. They are cross-system aliases, not two CSV columns.

## Status-dependent fields and amounts

12. Paid requires non-empty `InvoiceNo`, `ExpectedReceived`, `ActualReceived`, `PaymentDate`,
    `PaymentMethod`, and `PaymentChannel`, with status `Paid`.
13. Pending requires `TransactionStatus='Pending'` and empty `InvoiceNo`, `PaymentDate`,
    `PaymentMethod`, and `PaymentChannel`, because those fields arise from a completed payment.
    `ExpectedReceived` and `ActualReceived` are not part of this rule's mandatory-empty set.
    In the normal installment schedule, ExpectedReceived remains available as the scheduled
    amount. This wording is Boat's corrected item 16 and supersedes the earlier interpretation.
    Pending has no successful payment transaction and therefore does not enter the closed
    PaymentMethod/PaymentChannel event-mapping registry.
14. One `(OrderItem,Period)` may contain multiple payment rows. Rank 1 carries scheduled
    ExpectedReceived; later rows use ExpectedReceived=0. Sum ExpectedReceived equals the period
    expectation. Compare summed ActualReceived at order grain: absolute variance below THB 10 is
    tolerated; material variance, double-sized/negative values, and zero-net cross-item
    mispostings remain separate investigation signals.

## Accounting periods and cancellation

15. PaymentDate uses the paid date while open. After month close, backlog imported into the next
    open month uses that month's first day (`payment_date_clamped=TRUE`). CareOS remains the source
    of the original raw date; the durable V3 audit marker is `payment_date_clamped` rather than a
    duplicated stored raw-date column.
16. During an explicitly open July period, older rows may use BatchRunDate no later than
    31 July 2026. BatchRunDate is `last_day(open_period)` from `sap_period_lock`, not silently
    `CURRENT_DATE()`. Exactly one active period is required or processing fails closed.
17. A SAP document already Cancelled is terminal. Missing Paid data discovered afterward is
    reported by OrderItem for human handling, not mutated.
18. Cancel only an item already present in SAP. Reproduce the current SAP structure for all
    periods `1..TotalPeriods`, one winner per period with its current InvoiceNo; change only status
    to Cancelled or Cancelled(Change order).
19. Historical `SAP_LIVE_FULL` may lack part of an installment spine. Require full-period
    preflight for cancel/newpayment; do not invent missing SAP documents. Import-result email
    details remain rejection evidence.

## Credit shell

20. Credit shell links an old order cancelled as change-order to its paid replacement. The
    replacement PaymentDate is the old cancellation BatchRunDate and ActualReceived is the carried
    amount. The channel semantic is CreditShell with RCB/RCL flow prefix. Live sources contain
    `CreditShell`, `Credit Shell`, and `Credit-Shell`; enforce a reviewed mapping, not a new literal.

## Monthly delta and operational controls (Boat 2026-08-02)

21. A Paid document must be accepted by SAP before its own Cancelled or
    `Cancelled (Change order / Rejected)` document is eligible. Sequence is a hard gate, not an
    export-order preference.
22. Cancel/change is invalid when SAP has neither a Paid nor Pending document for the same
    `(OrderItem, Period)`. Mirror the winning SAP document and preserve its immutable InvoiceNo;
    never manufacture a cancel spine from CareOS alone.
23. For raw transactions on or after 2026-08-01, every NonMotor row is held from bucket delivery
    until its InsuranceGroup mapping has an explicit approved state. Unknown or merely non-empty
    InsuranceGroup is not approval. Holds are reported separately and never silently dropped.
24. The July-only release scope ends after July closing. Normal nightly processing is a delta from
    the last acknowledged SAP mirror through the current processing time; it is not permanently
    restricted to 2026-07-01..2026-07-31.
25. Before a month's configured closing timestamp, a transaction belongs to its own accounting
    month. BatchRunDate must be inside that same month and no later than both the run date and that
    month's last calendar day. A July row therefore cannot have BatchRunDate after 2026-07-31; an
    August row must use a date in 2026-08-01..2026-08-31 until August closes.
26. At closing, the system must atomically close the current period and open the next. Any backlog
    whose raw PaymentDate is earlier than the newly open month is clamped to the new month's first
    day; transactions originating in the new month retain their real PaymentDate. BatchRunDate is
    the real run date capped to the open month's last day.
27. Every nightly interface ends with `sap-extract-job`, loader completion, SAP mirror refresh,
    and reconciliation. Delivery status alone is not evidence of SAP state.
28. PaymentMethod and PaymentChannel are closed mappings. Values must come from a reviewed V2
    success mapping or distinct values demonstrably accepted in SAP history. Unknown values and
    mojibake are held; never truncate, invent, or silently substitute a literal.
29. Every filtered, held, rejected, and excluded row appears in the daily human-action report with
    a reason code and auditable key. `EXCLUDED != DELETED` remains binding.
30. Daily completeness reconciles all CareOS-qualified transactions from rule 1 into mutually
    exclusive outcomes: acknowledged in SAP, pending acknowledgement, ready to send, held,
    excluded, or rejected. The counts must conserve exactly and the result is emailed every day.

## SAP master vocabulary and NonMotor mapping (Boat 2026-08-02)

- `InsuranceGroup` is SAP `nvarchar(50)` and accepts: `Motor`, `Corporate`, `Motorbike`, `Health`,
  `Personal Accident`, `Life`, `Inter`, `Miscellaneous`, `TA`.
- `InsuranceType` is SAP `nvarchar(50)`. Motor values are `1`, `2`, `3`, `2+`, `3+`, `พรบ.`;
  NonMotor values are `Health`, `Life`, `PA`, `Cancer`, `ชดเชยรายได้`, `Saving`, `Marine`, `Travel`.
- `InsuranceProduct` is SAP `nvarchar(100)` and carries the product name. `PolicyType` is one
  character: `N` (new) or `R` (renew).
- Only NonMotor derives InsuranceGroup from scheduled query
  `6914e2e2-0000-2f6b-afc8-c82add6cb068`. Live metadata read at 2026-08-02 20:27 ICT showed its
  `product_category` outputs `Cancer`, `Home`, `Health`, `Life`, or `ERROR`. Only exact master
  matches (`Health`, `Life`) are currently releasable. Hold `Cancer`, `Home`, and `ERROR` until an
  explicit mapping is approved; never infer that they mean `Miscellaneous`.

## Import-error validation backlog (phase after daily cutover)

These LIVE importer message families are canonical regression cases. Existing equivalent checks
remain binding; missing checks are source backlog and must not be described as deployed.

| SAP message family | Required preventive rule |
| --- | --- |
| date field invalid DDMMYYYY | exactly eight parseable DDMMYYYY characters |
| ExpectedDate required | non-empty ExpectedDate where the contract requires it |
| CompanyCode must be RCB | CompanyDB/CompanyCode output exactly `RCB` |
| FullPayment/InstallmentCancelled/InstallmentRCL not balance | quarantine failed amount/spine conservation |
| InsuredId required | output `-` for missing source identity |
| InvoiceNo less than 30 characters | block length greater than 30; never truncate |
| OrderItem less than 30 characters | block length greater than 30 |
| PaymentChannel inconsistent/not found/required/account code | closed mapping plus same-order flow consistency |
| PaymentDate posting period locked | derive effective date from the single OPEN period |
| PaymentMethod required | Paid rows require an approved closed mapping |
| Period sequence invalid | exact schedule spine `1..TotalPeriods` |
| PolicyNo less than 50 characters | block length greater than 50; never truncate |
| Cancel first period must be Paid before | Paid ACK before cancel/change release |
| PolicyStatus not found/required | reviewed status literals and status-dependent completeness |
| TotalEIRAmt not allowed in RCB | RCB TotalEIR validation and balanced calculation |

## Additional confirmed controls

- E1: OrderDate <=2024 is `YEAR_OUT_OF_SCOPE`; 2025 is cancel-only when already in SAP; >=2026
  processes normally. Processing date basis stays `GREATEST(OrderDate,PolicyDate)`.
- E2: exact trimmed lower FirstName/LastName in `('test','test div')`; never substring matching.
- E3: unknown InsurerCode is excluded against successful SAP history (non-empty code, positive
  DocEntry in `SAP_LIVE_FULL`) and listed in the morning report.
- Correction/additional-payment rows need a durable marker because their shapes may match. Wrong
  or negative ExpectedReceived requires Cancel + Paid replacement.
- At `(OrderItem,Period)` grain, winner selection uses UpdateDate, UpdateTime, then DocEntry while
  Cancelled remains terminal and Paid never regresses to Pending. Per-DocEntry mirror dedup uses
  the reviewed content-hash tiebreak after recency.
- Column name+ordinal is a hard guard. Data-type drift should be WARN, not a positional substitute.

## Implementation status

- Source present: positional guard; five-date format; PolicyNo length; InsuredID default; E1-E3;
  period lock/clamp; schedule spine; and Order/OrderItem/PURCHASED-lead joins in 013.
- Partial: `SCHEDULE_GAP` now also checks the exact set `1..N` and flow/TotalPeriods invariants.
- Pending Phase-B 56-column model: status-field completeness, insurer-code shape, repeated-row
  amount checks, cancel preflight, and credit-shell linkage. Do not claim these are deployed.
