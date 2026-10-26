# MS-06 candidate — RCL NonMotor same-period additional payment

Status: **REJECTED AS A MISSING SCENARIO AFTER LIVE VERIFICATION**. Repository evidence below
explains why the risk was tested. Live job `bqjob_r20b759bd286b3740_000001a082e5333d_1` found 30
later distinct source events: 29 exact events were already in SAP and the remaining event was in
the current wrapper. Confirmed missing count was zero. No fix, deployment, SAP mutation, or
interface execution was performed.

## Candidate scenario

An RCL Health/NonMotor installment period is already Paid in SAP, then a later distinct successful
charge is recorded against the same `installment_number`. The later payment is legitimate only
when it has its own charge/invoice identity; its interface row must retain that ActualReceived and
use `ExpectedReceived = 0`.

The strongest next candidate is that `sap_view.RCL_NonMotor_process_2_newpayment` does not emit
this later row because its progress cursor is only `(OrderItem, maximum paid Period)`, not charge or
InvoiceNo identity.

## What repository evidence proves

1. The current business rule explicitly allows repeated periods for additional payments and
   requires the later row to carry zero ExpectedReceived.
2. The live-derived `RCL_HEALTH` proposal captured on 2026-09-01 preserves this shape. It ranks
   successful charges by `(transaction_id, installment_number)` and sets
   `ExpectedReceived = 0` when `charge_rank <> 1`, while ActualReceived continues to use the
   matched charge amount.
3. The repository capture of `RCL_NonMotor_process_2_newpayment` dated 2026-07-25 reduces SAP
   history to `MAX(U_Period)` per item. Its CareOS branch keeps only
   `interface.careos_installment > newpayment.installment_number`; therefore a second charge on an
   already-posted Period N cannot pass. The SAP branch returns the old SAP row and cannot introduce
   the later charge identity.
4. Historical evidence in `FINDINGS_CREDITSHELL_DUPLICATE_20260729.md` proves that multiple
   successful charges on one transaction/installment are a real source shape, including distinct
   later top-ups. Its broad 11,935-transaction count is not an MS-06 population: it was not scoped
   to current RCL NonMotor, and it also includes ambiguous retries or raw duplicates.

This is a structural silent-drop risk at payment-event grain that the MS-05 discovery could not
see: that discovery stopped checking an OrderItem once the item existed in SAP or any interface.

## What is not yet proven

- The 2026-07-25 wrapper capture may have drifted; repository source is not live truth.
- No current RCL NonMotor charge/InvoiceNo has yet been proven absent from SAP and all live
  interface views for this exact mechanism.
- No population count or financial impact is established.
- Multiple successful charges are not automatically legitimate additional payments. Exact raw
  duplicates, retries, refunds, and corrections must be separated before any row is proposed.

## One required live verification

Fetch the current definitions of `sap_view.RCL_NonMotor_process_2_newpayment` and
`sap_data_engineer.RCL_HEALTH`, then reconcile at
`(OrderItem, Period, charge_id, InvoiceNo)` grain:

1. start from active Health/NonMotor `RABBIT_CARE_INSTALLMENT` transactions;
2. require at least two distinct `SUCCESSFUL` `RABBIT_LENDING` charges on one installment;
3. exclude byte-for-byte/raw charge duplicates and separately label retry/refund/correction cases;
4. test whether the later distinct charge InvoiceNo is absent from `SAP_LIVE_FULL` and every
   current interface view; and
5. confirm that `RCL_HEALTH` emits the later row with positive ActualReceived and zero
   ExpectedReceived while the NonMotor newpayment wrapper removes it.

Only a positive result should promote this to **CONFIRMED MISSING** and justify a full legacy
query. The natural root-fix target is the existing `RCL_NonMotor_process_2_newpayment` payment
identity gate; `RCL_Motor_process_3_cancel` should remain reserved because this is neither Motor
nor a cancellation.

## Evidence files

- `sql/sap_view/RCL_NonMotor_process_2_newpayment.sql`
- `sql/production/RCL_HEALTH_status_precedence_fix_20260901.sql`
- `docs/FINDINGS_CREDITSHELL_DUPLICATE_20260729.md`
- `docs/FINDINGS_MISSING_INTERFACE_SCENARIOS_20260908.md`
