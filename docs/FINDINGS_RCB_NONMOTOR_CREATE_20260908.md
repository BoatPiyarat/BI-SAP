# RCB NonMotor create — live V2 legacy review

Status: **UPSTREAM ROOT CAUSE FOUND; FULL SOURCE-ONLY FIX VALIDATED GREEN**

Scope:

- `pacific-plating-282708.sap_view.RCB_NonMotor_process_1_create`
- `pacific-plating-282708.sap_data_engineer.RCB_HEALTH`
- `pacific-plating-282708.sap_data_engineer.RCB_TRAVEL`

No DDL, deployment, SAP mutation, or interface execution occurred.

## Root cause

The live `sap_view.RCB_NonMotor_process_1_create` wrapper is already correct for its role: its old
2025-only condition has been removed and it anti-joins `sap_integration_v3.stg_sap_state` by
OrderItem. The live wrapper itself therefore needs no SQL change.

The real gap is upstream in `sap_data_engineer.RCB_HEALTH`. It applies both of these filters:

1. removes `transactions.payment_option = 'CREDIT_CARD_INSTALLMENT'`; and
2. retains only snapshots where `number_of_installment = 1`.

That contradicts the confirmed SAP rule: `CREDIT_CARD_INSTALLMENT` is an ONETIME RCB flow because
the bank settles the full amount to Rabbit Care. The customer's 3/6/10-month bank term must not
route the row as an RCL installment.

## Live evidence

Charge-driven job `bqjob_r5c12aa2d91593540_000001a07cc7c4fe_1` found 23 active 2026 Health items
with successful non-RABBIT_LENDING charges that were absent from SAP and from the target view due
to `CREDIT_CARD_INSTALLMENT` being absent from `RCB_HEALTH`.

All-view proof job `bqjob_r1f3bbf20a8822d84_000001a07ccb7d5f_1` confirmed all 23 items are:

- fully paid;
- transaction status SUCCESSFUL;
- backed by at least one SUCCESSFUL charge;
- without follow-ups;
- absent from `SAP_LIVE_FULL`; and
- absent from all 12 legacy `sap_view` interface views.

Their snapshots contain 3, 6, or 10 installments; none has a one-installment snapshot. Both
upstream gates therefore need adjustment together.

## Validated legacy fix

Full source-only query:
`sql/production/RCB_HEALTH_credit_card_installment_rootfix_20260907.sql`

SHA-256: `D1E8BB9763B6A5B6484ACC3729A0DA3A7AEE4CA046F3269B4B9A6BF361BCEEEC`

The fix preserves normal one-time behavior and changes only the ONETIME eligibility seam:

- retain transaction snapshots until the final gate;
- do not discard `CREDIT_CARD_INSTALLMENT` in the transactions CTE; and
- accept `(number_of_installment = 1) OR (payment_option = 'CREDIT_CARD_INSTALLMENT')`.

Final shadow job `bqjob_r622445d20c2c7dad_000001a07cd6cd4b_1` ran from
2026-09-08 00:07:27 to 00:07:56 ICT and processed 5,135,382,541 bytes. Result: **GREEN**.

- Candidate output: 40 rows / 40 items, versus 17 rows / 17 items live.
- All 23 missing items are present exactly once.
- Missing scoped items: 0.
- Removed upstream rows: 0.
- Invalid Period/TotalPeriods: 0; all candidate rows are 1/1.
- Non-paid status, non-RCB channel, blank InvoiceNo, blank InsurerCode: 0.
- NULL Expected/Actual, invalid Order/Policy/Payment dates: 0.
- Test rows, canonically cancelled rows, duplicate keys, exact duplicates: 0.

The fixed upstream contains 1,040 additional distinct historical/current rows, but the unchanged
SAP anti-join limits the actual next interface delta to the 23 currently missing items.

## Other findings — no change in this work item

- `RCB_TRAVEL` currently has 29 rows across 27 old orders (2024–2025). Root-cause job
  `bqjob_r92c4a3f4f31e223_000001a07cc2005b_1` found all 29 transactions PENDING with zero charge
  rows and zero successful charges. `TransactionStatus IS NULL` correctly keeps them out of the
  create interface. There is no current 2026 successful Travel case to justify a legacy fix.
- Three active 2026 Health change-order items with successful RCB charges are excluded by the
  upstream credit-shell gate: `L80720286-1`, `L80797823-1`, and `L80799909-1`. They are parked as a
  separate NonMotor change/credit-shell scenario; this create fix intentionally does not absorb
  them.

## Progress

- ✅ Live wrapper definition and upstream definitions inspected
- ✅ Wrapper year/existence logic confirmed
- ✅ Current output payload audit GREEN
- ✅ Charge-driven missing scenario reproduced
- ✅ All-view coverage gap confirmed for 23 items
- ✅ Full upstream legacy query prepared
- ✅ Shadow validation GREEN
- ⏸ Three NonMotor change/credit-shell items — separate scenario
- ⏳ Production deployment — not requested

