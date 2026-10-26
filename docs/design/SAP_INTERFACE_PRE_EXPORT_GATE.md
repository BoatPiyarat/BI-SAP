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
   PaymentChannel, period shape, motor item type, and operation must agree. The Motor transport
   template (`RCB_MOTOR` folder / `INSURANCE_RCB` filename prefix) may carry RCL and is not itself
   a flow classifier. RCL and RCB may never mix in one order_item or one candidate file. Unknown
   or NULL flow blocks.
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

- Motor RCL payload identification requires `PaymentChannel` starting with `RCL` and either
  `TotalPeriods > 1`, or `motor_item_type = 'MOTOR_TYPE_COMPULSORY'` with `TotalPeriods = 1`.
- The production Motor transport template remains folder `RCB_MOTOR` with filename prefix
  `INSURANCE_RCB`; this does not reclassify the payload as RCB.
- For each accepted OrderItem with `TotalPeriods=N`, rows are exactly the integer set `1..N`.
- Assert one TotalPeriods value, `MIN(Period)=1`, `MAX(Period)=N`, `COUNT(*)=N`, and
  `COUNT(DISTINCT Period)=N`.
- Include old Paid periods, the newly Paid period, and every unpaid Pending tail period. Exporting
  only the changed period is prohibited.
- Every period has non-NULL status exactly `Paid` or `Pending`; no period or required value is NULL.
- Reconcile total candidate rows to `SUM(TotalPeriods)` across accepted OrderItems.
- RCL compulsory/CMI is a separate one-period flow and must not be folded into ordinary RCL.
- An order_item whose declared period count is known (`stg_schedule.total_periods > 1`) but whose
  `carepay_transaction_snapshot_installment_details` has zero rows for the current (latest) snapshot
  is a CareOS-side data gap, not an ordinary in-progress schedule; it must be explicitly held as
  `HOLD_EMPTY_INSTALLMENT_DETAILS` (not folded into the generic incomplete-spine hold) and never
  silently resolved by a `Period=NULL` fallback row. See
  `sql/ddl/082_v3_rcl_empty_installment_detail_hold.sql` and
  `docs/FINDINGS_EMPTY_INSTALLMENT_DETAILS_20260825.md`.

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


## 2026-10-19 — user confirmation: blank PolicyNo is allowed

Boat explicitly confirmed in the four-item SAP recovery session that the policy number may be blank. This supersedes earlier required/nonblank PolicyNo wording. Preserve blank PolicyNo without inventing a value; normalize missing source PolicyNo to an empty interface field when preparing a payload. Nonblank PolicyNo still follows the existing length and source-integrity checks.

L81020554-V1 no longer requires source PolicyNo repair and MISSING_POLICY_NUMBER has been removed from its local assessment. The remaining one-period Credit Shell amount discrepancy and alternate-path NULL money still block release. L80999097-V1 financial hold and L81026484-M1/V1 missing-predecessor holds are unchanged. Historical notes asking for the policy number are superseded by this entry. No interface/upload performed; existing validator code has not yet been changed or revalidated.


## 2026-10-19 — L80999097-V1 Credit Shell allocation confirmed

User instructed: allocate Credit Shell equal to Expected (5456.00), and split the remaining 352.00 as Credit Shell in the next period with ExpectedReceived=0. Total carried credit remains 5808.00; do not discard the remainder or interpret it as a refund. This resolves the amount-disposition question for L80999097-V1 only.

The captured source is FULL_PAYMENT and the live candidate is Period=1/TotalPeriods=1. Pending clarification: does next period explicitly authorize Period=2 and TotalPeriods=2, or refer to an additional receipt row within Period=1? Do not silently increase TotalPeriods or reinterpret the destination. Existing split InvoiceNo, conservation, exact-payload and independent-review gates remain. No payload/upload generated. L81020554-V1 is not covered by this item-specific amount instruction.


## 2026-10-19 — L81026484-M1/V1 Paid-before-Cancelled recovery authorized

User explicitly instructed that cancelled items absent from SAP be imported as Paid first, then Cancelled. Apply to the requested L81026484-M1 and L81026484-V1. This overrides their prior missing-predecessor lifecycle hold and permits reconstruction from verified successful-payment evidence despite current CareOS cancellation. It does not authorize invented payments, duplicate sibling allocations, customer refunds, or blind resend. Validate/review exact Paid payload, confirm direct SAP Paid acknowledgement, then derive and validate/review Cancelled from the accepted immutable Paid documents before cancellation upload. Preserve receipt identity and prove change-order provenance from L81023226. No repeat lifecycle approval is needed.


## 2026-10-19 — superseding FULL_PAYMENT decision for L80999097-V1

User explicitly specified FULL_PAYMENT uses Period=1 and ActualReceived=5808.00. Keep TotalPeriods=1 and existing ExpectedReceived=5456.00. This supersedes the earlier 5456.00 + 352.00 split and removes the next-period clarification and amount-disposition hold for this item. Do not cap ActualReceived, create Period=2, or invent a refund. The difference is explicitly accepted for this item's one-period payload; source, mapping, prior-delivery, exact validation and independent review remain required. This is not a confirmed rule for unrelated RCL installment cases.


## 2026-10-19 — remaining recovery scope explicitly approved

User confirmed L81020554-V1 FULL_PAYMENT keeps ActualReceived15035.00, ExpectedReceived13546.67, Period1/TotalPeriods1, no split. Blank PolicyNo remains allowed. User also explicitly approved inclusion of L81023226-M1/V1 change-cancellation before Paid then Cancelled for L81026484-M1/V1. No further routine scope approval required. Each phase must pass exact validation/independent review and direct SAP acknowledgement before the next. Preserve original invoice/payment fields on cancellations; no customer refund is initiated.


## 2026-10-20 06:15 ICT — corrected phase-1 delivery; ACK pending

Original targeted log23028 rejected L80999097-V1 (PaymentChannel mapping). Nightly logs23031/23032/23036 likewise rejected target rows; file-level success-with-error was not target ACK. Evidence: C:/dev/sap-request-20261019-four-items/latest_receipt_analysis.json and raw MIME receipts.

Root cause: historical stored PaymentChannel Code is not current importer U_MappingCode proof. Current dbo.[@PAYMENTCHANNEL] mapping is RCB-Credit Shell (Code Credit Shell; account9001-17); Credit Shell and RCB-CreditShell are invalid outgoing channel mappings. Pre-export now requires exactly one current exact U_MappingCode and a nonblank trimmed account. Method validated separately in dbo.[@PAYMENTMETHOD]. No masters or legacy schedules changed.

Explicit user decisions preserved: FULL_PAYMENT 1/1 Actual5808.00 Expected5456.00 and Actual15035.00 Expected13546.67, no split; blank policy allowed; old L81023226-M1/V1 change-cancel authorized before L81026484 Paid then Cancelled.

Direct SAP at23:12:31Z: target4 absent, old L81023226 pair still Paid; predecessor cancelled documents for other replacements unchanged. Exact content/delivery independent review PASS (/root/payload_review); local prior inventory reconciles known rejected original; current periods open; independent exporter disabled; no concurrent legacy activity after source snapshot. Source successor check finds only L81023226 -> L81026484, no successor of target orders.

Create-only upload and byte readback verified:
- INSURANCE_RCB_03_CHANGE_RECOVERY_20261020_A.csv: two Paid, SHA cf91e0265f60900992ef2395a95749e65110fe801e93d94c7ed884ff88c784aa, generation1792451677053830 at23:14:37Z.
- INSURANCE_RCB_02_CANCEL_CHANGE_RECOVERY_20261020_L81023226.csv: two predecessor change-cancellations, SHA cc2ae88f105f036dacae99e47b1b738ab7b33d4e6f80b0c6e8766bd22decb2bc, generation1792451689234199 at23:14:49Z.

Status is UPLOADED_PENDING_ACK, not completed. Durable ledgers phase1_delivery_0.json/phase1_delivery_1.json prohibit replay. Await item-level SAP ACK before dependent L81026484 phases. Never rerun batch after partial/unknown delivery. No source mutation, customer refund, JE certification, legacy deployment, or external messages sent.


## 2026-10-20T15:25:22.296093 — L78870324-V1 explicit full-actual approval
User explicitly authorized Paid ActualReceived8945.22, ExpectedReceived8300.01 retained, Period1/TotalPeriods1. Preserve the645.21 excess in the same approved receipt; do not invent sibling/refund/split. Source ONLINECARD/OMISE maps to OMC Omise Credit Card / RCB-Omise Credit Card-BAY, account1135-01 verified live. Scope now includes this additional Paid import; previous status-only limitation is superseded. Exact candidate awaits independent delivery review. Evidence C:/dev/sap-request-20261019-four-items/l78870324_authority.json and phase4_candidate.json.
