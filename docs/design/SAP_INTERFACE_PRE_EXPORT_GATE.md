# SAP interface pre-export gate

Status: canonical contract, source enforcement pending Class-A review and live verification
Owner decision: Boat, 2026-08-17

## Purpose

Every CareOS-to-SAP interface file must pass one fail-closed gate immediately before `EXPORT DATA`
or any equivalent file write. Passing an upstream transformation or a previous run is not enough.
The gate evaluates the exact rows and exact positional schema that will be written.

The gate has one small interface:

- exact candidate relation or immutable candidate snapshot;
- declared business flow (`RCL`, `RCB`, `RCL_CMI`, or approved EDC variant);
- declared operation (`CREATE`, `NEWPAYMENT`, `CANCEL`, `CHANGE`, `CREDITSHELL`, or reviewed manual
  operation);
- intended BU folder and filename.

It returns PASS plus evidence, or raises before any file write. There is no warning-only result.

For the Mo RCL recovery interface, validation is applied at complete `OrderItem` spine grain.
An invalid item is quarantined in full with its reasons; other items may continue only when the
file-level gates (including one declared flow and exact physical schema) also pass. Confirmed by
Boat on 2026-08-17.

## Universal checks — every file

1. Candidate grain is unique at the operation's canonical key; new-payment/installment files are
   unique at `(OrderItem, Period)`. Duplicate keys block the whole file.
2. Every row resolves to exactly one canonical flow. Declared flow, source flow, PaymentMethod,
   PaymentChannel, BU folder, and operation must agree. RCL and RCB may never mix in one order_item
   or one candidate file. Unknown or NULL flow blocks.
3. The physical column names, types, and ordinal positions equal the reviewed SAP contract. Never
   use `SELECT *` as the export contract and never reorder via `SELECT * EXCEPT(...), expr AS ...`.
4. Required fields contain neither SQL NULL nor literal `"NULL"`; required identifiers and codes
   are non-blank after trim. Pending `PaymentDate` is the only confirmed empty-string exception.
5. Date strings are exactly `DDMMYYYY` and parseable. `PaymentDate=''` is allowed only when status
   is `Pending`. Period-lock and approved month-transition rules apply before export.
6. Status values belong to the operation's reviewed vocabulary. A new-payment RCL spine permits
   exactly `Paid` or `Pending`; unknown spelling/case blocks rather than being normalized silently.
7. `InvoiceNo` is immutable for any row ever Paid or Cancelled in SAP; mirror it verbatim. New
   values may be produced only by the reviewed `fn_invoice_no` path. Paid rows require non-blank
   InvoiceNo and PaymentDate.
8. Numeric values are finite, at the SAP contract scale, and reconcile to the canonical source.
   CarePay satang values are divided by 100 and rounded to two decimals. Confirmed RCL
   ProcessingFee uses `/103.3`; unconfirmed Onetime `/107` remains unchanged and blocks any new
   interpretation.
9. `PolicyNo` longer than 50 characters blocks; never truncate. Required insurer/payment/channel
   master values must be confirmed. Test-customer, old-year, cancellation, and other exclusions
   are written to `sap_excluded_records` with `rule_code`, never silently dropped.
10. Every SUCCESSFUL charge is represented in SAP, in this candidate, or in
    `sap_validation_error`/`sap_excluded_records`. Candidate/input/output reconciliation must prove
    zero silent drops.
11. The exact SQL is dry-run under the repository cost wrapper; bytes, timestamp, source objects,
    row count, distinct key count, validation count, and candidate hash are retained as evidence.
12. The destination is a shadow prefix unless Boat explicitly says `deploy OK` in the current
    session. Production filenames/folders must match the reviewed routing contract and must never
    be used to infer business flow.
13. Before delivery, reconcile the exact candidate against prior user-reported and SAP-import
    errors applicable to the same flow/operation. A previously observed error family without a
    preventive assertion or reviewed disposition blocks the file.

## RCL installment checks

- For each accepted OrderItem with `TotalPeriods=N`, rows are exactly the integer set `1..N`.
- Assert one TotalPeriods value, `MIN(Period)=1`, `MAX(Period)=N`, `COUNT(*)=N`, and
  `COUNT(DISTINCT Period)=N`.
- Include old Paid periods, the newly Paid period, and every unpaid Pending tail period. Exporting
  only the changed period is prohibited.
- Every period has non-NULL status exactly `Paid` or `Pending`; no period or required value is NULL.
- Reconcile total candidate rows to `SUM(TotalPeriods)` across accepted OrderItems.
- RCL compulsory/CMI is a separate one-period flow and must not be folded into ordinary RCL.

## RCB / Onetime / EDC checks

- Onetime and `CREDIT_CARD_INSTALLMENT` use exactly one SAP period (`1/1`).
- `CREDIT_CARD_INSTALLMENT` is an Onetime/RCB flow because the bank pays in full; it must not enter
  an RCL installment spine.
- Only confirmed EDC channel mappings may pass. Currently KBANK is confirmed; an unconfirmed bank
  blocks instead of receiving a guessed `RCB-EDC-*` value.

## Cancel, change, and credit-shell checks

- Cancellation uses only item-level `is_cancelled IS TRUE OR cancel_time IS NOT NULL`; never fan a
  cancelled sibling across active items.
- Cancel/change requires the reviewed SAP Paid/Pending predecessor proof and the complete operation
  period contract. Already-Cancelled rows do not re-interface.
- Change-order and credit-shell candidates require reviewed old/new item mapping. Unknown Method-2
  replacement naming blocks; never invent `-M2`, `-M1R2`, or another suffix.
- Amount-only reconciliation is insufficient for a correction: required SAP document/JE evidence
  and the approved correction method remain separate gates.

## Unresolved-rule policy

An unresolved human decision is not a default. If it is relevant to a candidate, the candidate is
blocked and named in validation evidence. Current examples include non-KBANK EDC channel mappings,
Aware's multi-document picking decision, change-order supersession behavior, Method-2 replacement
naming, and numeric validation-regression thresholds.

## Required enforcement seam

The legacy workflow currently exports eight `sap_view.*` relations directly; V3 has separate
validation routines. Source implementation must add one pre-export call for every loop item and
every manual/shadow export. The call must validate an immutable candidate snapshot, then the export
must read that same snapshot so validation and output cannot diverge (TOCTOU). A workflow retry must
rerun the gate; it may not retry only the file write.

Deployment is prohibited until current live legacy view definitions and the 56-column physical
contract are captured, the gate SQL is dry-run, every flow/operation adapter has positive and
negative fixtures, Class-A review passes, and Boat approves the exact deployment.
