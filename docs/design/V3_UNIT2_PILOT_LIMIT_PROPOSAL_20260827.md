# V3 Unit 2 pilot magnitude-limit proposal

Status: **SOURCE-ONLY RISK PROPOSAL — NOT APPROVED, NOT REGISTERED**

Date: 2026-08-27

## Proposed conservative pilot limits

| Field | Proposed value | Operational meaning |
|---|---:|---|
| `records_absolute` | 25 | ignore percentage-only noise of at most 25 records per cell |
| `records_percentage` | 0.05 | require more than 5% as well as more than 25 records |
| `orders_absolute` | 10 | ignore percentage-only noise of at most 10 orders per cell |
| `orders_percentage` | 0.05 | require more than 5% as well as more than 10 orders |
| `amount_satang_absolute` | 500,000 | ignore percentage-only noise of at most THB 5,000 per cell |
| `amount_percentage` | 0.05 | require more than 5% as well as more than THB 5,000 |

DDL 063 uses `absolute breach AND percentage breach` independently for records, orders, and
amount. These values are a conservative operational risk policy, not a fit to observed data and
not a recommendation to make a particular run pass. Use them only after explicit approval of all
six values and provenance.

## Replay against the already-completed August 25 to August 27 comparison

Authoritative stored-result source:
`pacific-plating-282708:asia-southeast1.bqjob_r653b2df0f1d8c18a_000001a040f3cd28_1`

- job state: `DONE`;
- created / started / ended epoch milliseconds:
  `1787796115207` / `1787796115234` / `1787796124282`;
- processed / billed bytes: `644127533` / `693108736`;
- result retrieval: `bq head --job` on 2026-08-27 at 21:13 ICT; no query rerun;
- compared baseline: `V3NIGHTLY-2026-08-25T22:21:31-manual`;
- compared current: `V3NIGHTLY-2026-08-27T00:17:51-manual-fresh-sap`.

A deterministic local replay of DDL 063's exact `>` and `AND` predicates produces:

- 39 total comparison cells;
- 15 breached cells;
- 11 record breaches;
- 15 order breaches;
- 6 amount breaches.

The breached population includes the normal `READY_CREATE_OR_PAYMENT` cells:

| Grain / flow / status | Record change | Order change | Amount change | Reasons |
|---|---:|---:|---:|---|
| PAYMENT_EVENT / ONETIME / Paid | -382 (-46.25%) | -383 (-46.37%) | -497,720,770 satang (-49.36%) | records, orders, amount |
| PAYMENT_EVENT / RCL / Paid | +491 (+88.47%) | +493 (+89.31%) | +82,718,771 satang (+77.23%) | records, orders, amount |
| SCHEDULE / ONETIME / Paid | -547 (-46.12%) | -421 (-47.41%) | n/a | records, orders |
| SCHEDULE / ONETIME / Pending | -155 (-49.21%) | -149 (-53.99%) | n/a | records, orders |
| SCHEDULE / RCL / Paid | +499 (+91.90%) | +498 (+91.71%) | n/a | records, orders |
| SCHEDULE / RCL / Pending | -1,065 (-62.06%) | -192 (-71.64%) | n/a | records, orders |

Unknown-classification, validation-hold, cancel/change, and RCL-CMI cells account for the other
nine breached cells. Therefore the proposed pilot limits correctly refuse to make the existing
August 27 comparison green.

## Force-pass boundary is not recommended

Because any breached cell stops Unit 3, clearing every stored breach while retaining 5% percentage
limits would require absolute limits of at least:

- 1,065 records;
- 498 orders;
- 497,720,770 satang (THB 4,977,207.70).

Alternatively, retaining the small absolute floors would require percentage limits near the
largest observed changes (about 92% for records/orders and 77% for amount). Either choice would
normalize the very movements the gate is intended to stop. Do not adopt these force-pass
boundaries merely to obtain a green production run.

## Decision required

Recommended: approve the conservative six-value pilot, allow the first post-bootstrap evaluation
to hold, review the 15 cells against business expectations, and then make a separate evidence-
based decision. This does not deliver a normal scenario tonight, but it preserves the fail-closed
contract.

If Boat instead accepts materially wider first-run risk to pursue a release tonight, Boat must
approve all six exact replacement values explicitly. General production-run approval is not enough.
No configuration, baseline distribution, Workflow execution, Scheduler, export, GCS object, or SAP
state was changed by this proposal or replay.
