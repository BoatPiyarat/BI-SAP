# Universal V2 cancel scenario gaps — 2026-09-07

Status: SOURCE-ONLY CURRENT-SCOPE FIX VALIDATED. No query replacement, deployment, SAP mutation,
or interface execution.

Target view: `pacific-plating-282708.sap_view.RCB_Motor_process_2_cancel_new`

Requested target behavior: one item-level cancel interface covering RCB/RCL, Motor/NonMotor,
ordinary Cancel/Change order, and partial/full item cancellation.

## Approved decision and validated fix

The six listed old-OrderDate items are examples of one general rule, not a hardcoded allow-list.
The approved proposal now accepts every item whose `cancel_time >= 2026-01-01`, regardless of the
original OrderDate year. Eligibility remains based only on `is_cancelled/cancel_time`; the two
underwriting-rejected-only items are deliberately ignored, and `L77754975-1` remains parked for
human investigation because its `cancel_time` is NULL.

Test data is excluded after the SAP and installment payload branches are combined. This final
payload guard is necessary because nine items had non-Test names in SAP history but `FirstName =
Test` in the supplemented installment rows.

Full proposal:
`sql/production/RCB_Motor_process_2_cancel_new_current_cancel_scope_fix_20260907.sql`

Final shadow job `bqjob_rcfea64538e1671_000001a07c7fe6ef_1` is GREEN:

- 292 expected current-scope cancellation items = 292 candidate items / 1,352 rows;
- missing expected items 0; unexpected items 0;
- Test rows 0; parked/ignored rows 0;
- incomplete/conflicting period spines 0; exact duplicate hashes 0;
- all six known old-OrderDate examples are present; `L74079056-V1` is complete at Periods 1–6.

Proposal SHA-256:
`D6BB6B3675974295BDE113E464A62A8CBD0662647DE1A2825A7265BA17CB7EE4`

The current universal view covers 302 of 311 current-scope SAP-present cancellation candidates.
Nine items are missing from this view and from both remaining actual cancel views
(`RCB_NonMotor_process_2_cancel` and `RCL_Motor_process_3_cancel`).

| Status | Items |
|---|---:|
| Covered by `RCB_Motor_process_2_cancel_new` | 302 |
| Current-scope missing from universal view | 9 |
| Of the 9, covered by another cancel view | 0 |
| Historical pre-2026 backlog, parked separately | 1,010 |

RCB/RCL classification is derived from SAP payment routing: an item with any
`PaymentChannel` beginning `RCL` is RCL; otherwise it is RCB. `CompanyDB` is not used as the
financing-route classifier.

## Current missing scenarios

### 1. RCB NonMotor Change — `is_cancelled=true`, but `cancel_time` is NULL

One item is excluded because the live target first accepts `is_cancelled=true OR cancel_time IS
NOT NULL`, then applies `DATE(cancel_time) >= '2026-01-01'`, which drops the NULL timestamp.

- `L77754975-1` — Order `L77754975`, Health, 1/1
- Accounting status: `CANCELLATION_STATUS_CHANGE_ORDER_COMPLETED`
- Required output status: `Cancelled (Change order / Rejected)`

### 2. RCB Motor ordinary Cancel — current cancellation, historical OrderDate filter

Five items have 2026 cancellation timestamps but are excluded by
`OrderDate NOT LIKE '%2023%' / '%2024%'`.

- `L74079056-V1` — 6 periods, SAP currently contains 5 distinct periods
- `L77083183-M1` — 1/1
- `L77083183-V1` — 1/1
- `L77121047-M1` — 1/1
- `L77121047-V1` — 1/1

### 3. RCB NonMotor ordinary Cancel — current cancellation, historical OrderDate filter

One Health item is cancelled in 2026 but excluded by the same OrderDate filter.

- `L77675780-1` — 1/1; item is also underwriting-rejected

### 4. RCB NonMotor ordinary Cancel — underwriting rejected without item cancel flag/time

The legacy NonMotor cancel view treats underwriting rejection as a cancellation trigger, but the
universal target checks only `is_cancelled/cancel_time`.

- `L77796694-1` — Health, 1/1
- `L77832970-1` — Health, 1/1

No current RCL Motor or RCL NonMotor missing scenario was found. No current refund-only or
accounting-cancellation-only gap remained among SAP-present, not-yet-cancelled items.

## Current scenarios already covered

| Route | Product | Event | Item scope | Items |
|---|---|---|---|---:|
| RCB | Motor | Cancel | Full/single | 50 |
| RCB | Motor | Cancel | Partial item | 6 |
| RCB | Motor | Change | Full/single | 80 |
| RCB | Motor | Change | Partial item | 1 |
| RCB | NonMotor | Cancel | Full/single | 13 |
| RCB | NonMotor | Change | Full/single | 2 |
| RCL | Motor | Cancel | Full/single | 34 |
| RCL | Motor | Cancel | Partial item | 6 |
| RCL | Motor | Change | Full/single | 52 |
| RCL | Motor | Change | Partial item | 1 |
| RCL | NonMotor | Cancel | Full/single | 52 |
| RCL | NonMotor | Change | Full/single | 5 |

## Historical backlog parked separately

The target's `cancel_time >= 2026-01-01` gate leaves 1,010 older SAP-present uncancelled items:

| Route/product/event | Full/single | Partial | Total |
|---|---:|---:|---:|
| RCB Motor Cancel | 252 | 36 | 288 |
| RCB Motor Change | 157 | 8 | 165 |
| RCB NonMotor Cancel | 1 | 0 | 1 |
| RCL Motor Cancel | 329 | 206 | 535 |
| RCL Motor Change | 18 | 3 | 21 |
| **Total** | **757** | **253** | **1,010** |

This backlog should not be mixed into the nine current gaps unless historical re-interface is
explicitly approved.

## How the remaining views can contribute

- `RCB_NonMotor_process_2_cancel`: reuse its cancellation signals—refund, underwriting rejected,
  and accounting cancellation status—in the universal item's eligibility CTE. Do not UNION its
  final output blindly because it uses a separate upstream payload and V3 state gate.
- `RCL_Motor_process_3_cancel`: provides no unique current item beyond the universal view. Its RCL
  channel predicate is useful as validation, not as an additional current source.
- `RCB_Motor_process_3_change`: despite its name, this is a paid create/catch-up view for items not
  yet in SAP. It cannot cancel SAP-present items. Reuse only the `cancelled_change_orders`
  relationship concept for choosing `Cancelled (Change order / Rejected)`.

## Final disposition

1. ✅ Remove original OrderDate-year filtering; use `cancel_time >= 2026-01-01` for every current
   cancellation.
2. ✅ Exclude Test payload rows across both SAP and installment sources.
3. ⏸ Do not accept `is_cancelled=true` with NULL `cancel_time`; human investigation pending.
4. ⏸ Do not add underwriting/refund/accounting-only eligibility signals.
5. ✅ Keep SAP history authoritative and retain item-level already-cancelled idempotency.
6. ⏸ Keep the 1,010 historical items behind a separate explicit backfill decision.

## Evidence

- Repro query: `sql/adhoc/20260907_audit_universal_cancel_scenario_coverage.sql`
- Final job: `bqjob_r4c3da204f86457c5_000001a07c6a76ea_1`
- Dry-run: 9,866,821,996 bytes (~9.189 GiB), below the 20 GiB cap
- Point-in-time result: 1,321 total candidates; 302 covered; 9 current missing; 1,010 historical
  missing; zero of the missing items covered by another cancel view
