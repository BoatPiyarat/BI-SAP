# Finding — RCB onetime change-order M1 labelled as RCL Credit Shell

Status: OPEN; source-only diagnosis; Class A review required before any live change.

This is a new finding. It is not INCIDENT-002a, INCIDENT-002b, the 224 unknown-cause orders,
or the onetime M1/V1 allocation finding.

## Known-answer case

FA reported `L80482368-M1`. The plate was checked directly in CareOS on 2026-08-03; the Slack
transcription was not used. The value is intentionally not copied into this repository because
vehicle identifiers are PII.

CareOS truth establishes an RCB one-time order: `FULL_PAYMENT`, transaction installments 1,
current snapshot `number_of_installment=1`, and `is_fully_paid=TRUE`. V3 `stg_schedule` routes
both M1 and V1 as `ONETIME`, one period.

The current live installment and RCL-create views contain neither target row. SAP contains M1
with valid `DocEntry=2386647`, `CompanyDB=RCB`, period 1/1, but both payment fields say
`RCL-Credit Shell`. Thus “recorded on RCL” means the payment mapping/account label, not the SAP
company database.

## Governance pull and live/repo diff

Live definitions were pulled read-only at `2026-08-03T12:04:11.971Z`.

| Object | Live vs repo | Exact material difference |
|---|---|---|
| `sap_data_engineer.sap_dashboard_carepay_installment` | drift | The normalized query body from `WITH` onward matches the repo body. Live adds an outer `SELECT * REPLACE`: RULE-01 clamps PaymentDate to at least 2026-07-01 and RULE-02 derives BatchRunDate with a 2026-07-31 floor. Both still filter snapshots with `number_of_installment > 1`. |
| `sap_view.RCL_Motor_process_1_create` | full-definition drift | Repo is a short dashboard wrapper with six hard-coded order exclusions and string year filters. Live is an inlined emergency backfill: successful charge, `RABBIT_CARE_INSTALLMENT`, charge update date from 2026-04-01, not cancelled, three insurer exclusions, absent from SAP, and absent from change orders. It retains `number_of_installment > 1`. |

Normalized full-definition hashes: installment live `85e70a7...bab30f`, repo
`0e4ccf...67c85`; RCL create live `d7ffe445...98253`, repo `bb3b33a...298bed`.

The direct trace refutes `number_of_installment > 1` as this order’s cause.

## Root cause

Three historical jobs on 2026-07-20 explicitly included the target order:

- `job_tfcQXwP1P4pT4cFGi5ZqkhxHkN-4` at 22:50:25Z;
- `job_JlzKA6yTr573w4Tq_hWuzzmuMvwq` at 22:51:50Z;
- `job_wTmnGHtB4eT2T1xSKcdBjy_OjIK1` at 23:39:09Z.

All route solely on `is_carried_over_from_old_order` and assign both payment fields to
`RCL-Credit Shell`; they do not first route the new order by `payment_option`. SAP shows the
target the next day with exactly that label. The defect is flow-blind credit-shell mapping:
being a change order was treated as proof of RCL even when the new order was FULL_PAYMENT.

The repo analogue has the same unsafe shape in
`sql/production/RCL_04_new_order_credit_shell_all.sql`: its M1 branches force
`RCL-Credit Shell`, and the query does not carry `transactions.payment_option` as a router key.

## Population and posted-state gate

Reproducible query: `sql/adhoc/20260803_l80482368_rcb_creditshell_misroute.sql`.

Evidence job `codex_l80482368_exactpop_20260803_121114`, query timestamp
`2026-08-03T12:11:14.139Z`; dry-run `2026-08-03T12:11:12.405Z`; dry-run and processed
7,463,914,284 bytes; billed 7,464,812,544; ceiling 21,474,836,480.

| Gate | Orders | Order items |
|---|---:|---:|
| source FULL_PAYMENT + 1/1 snapshot + change order | 12,463 | 17,077 |
| source population present in SAP with valid DocEntry | 12,395 | 16,988 |
| exact wrong RCL Credit Shell label | **9** | **9** |
| exact wrong label and M1 | **9** | **9** |

## Second confirmed occurrence, 2026-08-23 — root cause still live, not fixed

Mo Pawinee reported `L80569331-M1` (relayed via Boat, chat, "No.3" issue type — matches this
finding's exact description, quoted verbatim: "Change order แบบ FULL_PAYMENT ถูกกำหนดเป็น
RCL-Credit Shell"). Independently verified live, not trusted from the chat report alone:
- `sap_integration_v3.sap_mirror_state`: `DocEntry=2422529`, `CompanyDB=RCB`, `TotalPeriods=1`
  (ONETIME), `TransactionStatus=Paid`, both `PaymentMethod` and `PaymentChannel` =
  `RCL-Credit Shell`. `OrderDate=13082026`.
- `careos.careos_orders` joined to `carepay_transactions`/`carepay_transaction_snapshots`:
  `payment_option=FULL_PAYMENT`, `number_of_installment=1`, `create_time=2026-08-13 17:42:03`,
  and it is a change order (`cancelled_change_orders.current_human_id=L80569331`,
  `old_human_id=L80544283`) — the exact same shape as the known-answer case (`L80482368`) above.
- `sap_integration_v2.SAP_LIVE_FULL` for the same DocEntry: `PaymentDate=01082026` — this is what
  Mo's "SAP posting date = 01.08.26" refers to (the underlying charge date carried onto the
  change-order row), not `OrderDate`/`UpdateDate` (`2026-08-14`).

**This is not a pre-fix legacy artifact.** The change order was created 2026-08-13, ten days after
this finding was filed (2026-08-03) with its correction proposal still source-only and never
deployed ("No deploy, backfill, correction, export, or production mutation was performed"). The
live legacy generator (`sql/production/RCL_04_new_order_credit_shell_all.sql`) still contains the
same unconditional `PaymentMethod IN ('CASH','QR_CODE') => 'RCL-Credit Shell'` branches with no
`payment_option`/flow check, confirmed by re-reading the file 2026-08-23 — consistent with, though
not proof of, the live drifted view's identical defect. **The root cause remains active and will
keep producing new wrong-label cases until the flow-aware routing fix in this finding's "Future
correction proposal" is actually implemented and deployed**, not just designed.

Also worth checking for the same underlying defect family: `docs/INPUTS_NEEDED.md`'s
"urgent_for refund to cust" tab describes FULL_PAYMENT orders that "sync to omise RCL > refund to
RCB" for May–June — structurally the same failure (a FULL_PAYMENT/RCB-flow order ending up
associated with RCL), possibly the same root cause surfacing as a different downstream symptom
(refund-needed instead of wrong-label-already-posted). Not confirmed as the same population —
flagging the connection, not asserting it.

No correction, deploy, or production mutation was performed for this new occurrence either.

Nine is the population of this exact posted cause, not every possible one-time/RCL mechanism.
Correction eligibility remains separate and is not approved by this finding.

## Future-order correction proposal (source only)

Route before assigning a credit-shell label:

1. derive flow from the new order’s payment option;
2. FULL_PAYMENT/CREDIT_CARD_INSTALLMENT => ONETIME, TotalPeriods=1;
3. carried-over ONETIME => `RCB-CreditShell`;
4. only carried-over RABBIT_CARE_INSTALLMENT => `RCL-Credit Shell`;
5. hold and report unknown flow instead of defaulting it to RCL.

Do not patch a drifted live legacy view from its repo baseline. In V3, the implementation points
are the canonical `stg_schedule` router and `sql/ddl/050_v3_onetime_payload_source.sql`; the
target already passes them. Add a pre-delivery regression assertion: no `flow='ONETIME'` row may
have PaymentMethod or PaymentChannel matching `RCL%`.

Any retained legacy/manual generator must replace the unconditional
`is_carried_over_from_old_order => RCL-Credit Shell` branch with those flow-aware branches,
rebased from the exact executed definition.

No deploy, backfill, correction, export, or production mutation was performed.
