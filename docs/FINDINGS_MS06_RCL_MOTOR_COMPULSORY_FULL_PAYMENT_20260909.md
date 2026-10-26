# MS-06 — RCL-funded compulsory M1 stored as FULL_PAYMENT has no interface owner

Status: **CONFIRMED MISSING; QUERY NOT YET PREPARED**. Point-in-time evidence:
2026-09-09 04:26 ICT. No DDL, deployment, SAP mutation, or interface execution.

## Scenario

An active Motor compulsory M1 has a real successful `RABBIT_LENDING` charge, but its CarePay
transaction is labelled `FULL_PAYMENT` and its one-installment snapshot has no installment-detail
or follow-up row. It is therefore excluded from both sides of the current legacy split:

- RCB fully-paid logic rejects the Rabbit Lending-funded charge;
- RCL installment logic requires installment detail Period 1;
- the item is consequently absent from `sap_dashboard_carepay_installment`,
  `sap_dashboard_carepay_fully_paid`, all 12 `sap_view` interfaces, and `SAP_LIVE_FULL`.

## Confirmed current population

One item met the active-2026, non-Test, successful-charge, absent-from-SAP, absent-from-all-interface
criteria:

| OrderItem | Product/type | Transaction | Charge | Snapshot |
|---|---|---|---|---|
| `L80161278-M1` | Motor / `MOTOR_TYPE_COMPULSORY` | `FULL_PAYMENT`, `SUCCESSFUL` | ฿645.21, `QR_CODE`, `RABBIT_LENDING`, Period 1, invoice `chrg_67i5i9355dpxs2imp64` | 1 installment, zero detail rows, zero follow-ups |

The item is active (`is_cancelled=false`, `cancel_time=NULL`) and its policy start date is
2026-05-19.

Broad all-view discovery job
`bqjob_r4430153e42e1fb9a_000001a082e6c17a_1` processed 11,867,290,304 bytes and returned this as
the only remaining active successful-charge item outside SAP and all 12 interfaces after the known
scenario classifications. Focused trace job
`bqjob_r1d858435fae61def_000001a082ea57a0_1` processed 11,877,254,200 bytes and confirmed the
source and downstream absence above.

## Root cause and proposed ownership

The root drop is in `sap_data_engineer.sap_dashboard_carepay_installment`:
`compulsary_installment_details` requires
`transaction_snapshot_installment_details.period = 1`. This item has a valid successful lender
charge but no detail row, so the CTE cannot emit it. A dormant legacy
`compulsary_onetime_no_installment_details` pattern exists in the older `RCL_MOTOR` source, but it
must be corrected and validated before reuse; in particular, ActualReceived must come from the
successful charge rather than be assumed from item price.

Preferred sequence, one legacy object at a time:

1. prepare a full source-only `sap_dashboard_carepay_installment` query adding a narrowly scoped
   active compulsory/no-detail/successful-Rabbit-Lending 1/1 branch;
2. validate the full 56-column payload and confirm charge amount against item financial fields;
3. update the prepared `RCL_Motor_process_1_create` wrapper eligibility from payment-option-only
   proof to successful-Rabbit-Lending proof so this valid `FULL_PAYMENT` exception can pass.

Do not solve this by allowing all `FULL_PAYMENT` rows into RCL. The lender charge is the required
route proof. Do not repurpose `RCL_Motor_process_3_cancel` while the root upstream path can own the
scenario.

## Rejected preliminary candidate

RCL NonMotor same-period additional payment was checked first and is **not missing**. Job
`bqjob_r20b759bd286b3740_000001a082e5333d_1` found 30 later distinct source events: 29 exact
invoice events were already in SAP and the remaining event was in the current NonMotor wrapper;
confirmed missing count was zero.

## Evidence

- `sql/adhoc/20260909_verify_MS06_RCL_NonMotor_same_period_additional_payment.sql`
- `sql/adhoc/20260909_trace_MS06_L80161278_M1_route_gap.sql`
- live metadata for `sap_view.RCL_NonMotor_process_2_newpayment` and
  `sap_data_engineer.RCL_HEALTH`, fetched 2026-09-09 04:18 ICT

