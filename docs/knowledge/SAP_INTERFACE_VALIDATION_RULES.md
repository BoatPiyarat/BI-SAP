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
8. `InsuredID` is customer identity. NULL/empty source becomes `-` and is never blank in the file.
9. `InsurerCode` is distinct from `InsuredID`. Motor codes are digits; NonMotor codes are `N`
   followed by digits. Boat's item 11 named InsurerID but described InsurerCode format.
10. PolicyNo longer than 50 characters is blocked as `POLICYNO_TOO_LONG`; never truncate.
11. Contract column 35 is `TransactionStatus`; SAP stores the same semantic value as
    `U_PolicyStatus`. They are cross-system aliases, not two CSV columns.

## Status-dependent fields and amounts

12. Paid requires non-empty `InvoiceNo`, `ExpectedReceived`, `ActualReceived`, `PaymentDate`,
    `PaymentMethod`, and `PaymentChannel`, with status `Paid`.
13. Pending requires empty `InvoiceNo`, `ActualReceived`, `PaymentDate`, `PaymentMethod`, and
    `PaymentChannel`, with status `Pending`. `ExpectedReceived` remains populated as the scheduled
    amount. This corrects the literal wording of item 16, which conflicts with accepted SAP
    installment evidence.
14. One `(OrderItem,Period)` may contain multiple payment rows. Rank 1 carries scheduled
    ExpectedReceived; later rows use ExpectedReceived=0. Sum ExpectedReceived equals the period
    expectation. Compare summed ActualReceived at order grain: absolute variance below THB 10 is
    tolerated; material variance, double-sized/negative values, and zero-net cross-item
    mispostings remain separate investigation signals.

## Accounting periods and cancellation

15. PaymentDate uses the paid date while open. After month close, backlog imported into the next
    open month uses that month's first day (`payment_date_clamped=TRUE`); preserve raw PaymentDate.
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

## Additional confirmed controls

- E1: OrderDate <=2024 is `YEAR_OUT_OF_SCOPE`; 2025 is cancel-only when already in SAP; >=2026
  processes normally. Processing date basis stays `GREATEST(OrderDate,PolicyDate)`.
- E2: exact trimmed lower FirstName/LastName in `('test','test div')`; never substring matching.
- E3: unknown InsurerCode is excluded against successful SAP history (non-empty code, positive
  DocEntry in `SAP_LIVE_FULL`) and listed in the morning report.
- Correction/additional-payment rows need a durable marker because their shapes may match. Wrong
  or negative ExpectedReceived requires Cancel + Paid replacement.
- Winner selection uses UpdateDate, UpdateTime, DocEntry recency while Cancelled remains terminal
  and Paid never regresses to Pending.
- Column name+ordinal is a hard guard. Data-type drift should be WARN, not a positional substitute.

## Implementation status

- Source present: positional guard; five-date format; PolicyNo length; InsuredID default; E1-E3;
  period lock/clamp; schedule spine; and Order/OrderItem/PURCHASED-lead joins in 013.
- Partial: `SCHEDULE_GAP` now also checks the exact set `1..N` and flow/TotalPeriods invariants.
- Pending Phase-B 56-column model: status-field completeness, insurer-code shape, repeated-row
  amount checks, cancel preflight, and credit-shell linkage. Do not claim these are deployed.
