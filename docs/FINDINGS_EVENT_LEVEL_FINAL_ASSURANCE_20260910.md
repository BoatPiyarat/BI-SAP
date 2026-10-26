# Event-level final assurance contract for legacy V2 SAP flows

Date: 2026-09-10  
Scope: repository-only design evidence; no BigQuery query and no production change were performed.

## Outcome

The final assurance layer must be built at **successful-charge event grain**, not from the existing period-grain reconciliation alone. Every qualified `carepay_charges.id` must end in exactly one terminal outcome, while every releasable event must bind to one or more explicit SAP obligations without counting the source amount more than once.

No current single object satisfies that contract:

- `stg_payment_events` keeps one row per `charge_id`, but its `item_rank = 1` intentionally suppresses sibling item fan-out (`sql/ddl/013_stg_payment_events.sql`, CTEs `base`, `qualified`).
- `expected_state` and `recon_all_charges` collapse successful charges at `(OrderItem, Period)` and therefore cannot prove same-period additional payments (`sql/ddl/016_expected_state.sql`, `payment_events`; `sql/ddl/005_recon_all_charges.sql`).
- `interface_daily_status` is period-grain and remains a draft operational view (`sql/ddl/030_interface_daily_status.sql`).
- Unit 2 and the later-payment split already provide the strongest reusable primitives: event/schedule population separation, exact SAP document matching, event identity, payload hash, holds, and count/amount conservation (`sql/ddl/051_v3_unit2_shadow_classifier.sql`; `sql/ddl/088_v3_rcl_later_newpayment_split.sql`).

## 1. Required grains

Maintain three related ledgers. They must not be flattened into one ambiguous row set.

| Ledger | Canonical key | Purpose |
|---|---|---|
| Charge header | `charge_id` | One physical successful charge and its amount; the amount is summed exactly once here. |
| Charge allocation / SAP obligation | `(charge_id, OrderItem, Period, obligation_role)` | The SAP identity or identities created by the charge. One charge may legitimately produce more than one item obligation. |
| Schedule / lifecycle obligation | `(OrderItem, Period, lifecycle_operation, source_state_id)` | Pending spine rows and cancel/change rows that may exist without a new successful charge. |

For every READY charge allocation, persist immutable identity `(pipeline_run_id, OrderItem, Period, charge_id, InvoiceNo, payload_hash)`. This follows the operator event view and later-payment gate (`sql/ddl/083_v3_current_newpayment_events.sql`, final SELECT; `sql/ddl/088_v3_rcl_later_newpayment_split.sql`, event identity and summary sections).

The invariant is:

1. every qualified successful `charge_id` has exactly one terminal charge-header outcome;
2. every READY charge has one or more uniquely identified SAP obligations;
3. every non-READY charge has one durable exclusion, quarantine, rejection, or known-scenario record;
4. event counts and source amounts in satang reconcile exactly across terminal outcomes;
5. RCL release additionally proves one complete validated `1..TotalPeriods` item spine.

## 2. Source qualification and identity

A candidate starts only from `carepay_charges.status = 'SUCCESSFUL'`. Resolve, in order:

1. a unique raw `charge_id`;
2. one transaction by `transaction_id`;
3. one current order through `orders.payment = 'transactions/' || transaction_id`;
4. a purchased lead where that legacy rule applies;
5. one or more nonblank order-item human IDs.

Existing source-failure codes `NO_ORDER`, `NO_ORDER_ITEM`, `EMPTY_ORDER_ITEM_HUMAN_ID`, and `LEAD_NOT_PURCHASED` should be retained as durable exclusions (`sql/ddl/013_stg_payment_events.sql`, `qualification_reason`). Duplicate raw charge IDs or ambiguous transaction/order links are `QUARANTINE_SOURCE_IDENTITY`, not silently deduplicated.

`charge_id` and InvoiceNo are different identities. The implemented InvoiceNo UDF returns the raw `third_party_id`; existing Paid/Cancelled rows must mirror SAP InvoiceNo verbatim (`sql/ddl/015_fn_invoice_no.sql`; `docs/design/SAP_INTERFACE_PRE_EXPORT_GATE.md`, “Invoice identity”). Although staging currently coalesces a missing `third_party_id` to `OrderItem`, the newer first-create gate explicitly holds blank raw invoices and stage/event drift (`sql/ddl/013_stg_payment_events.sql`, `source`; `sql/ddl/087_v3_rcl_first_create_hold_gate.sql`, validation flags). Final assurance therefore fails closed:

- nonblank raw `third_party_id` -> canonical expected InvoiceNo;
- blank raw `third_party_id` -> `QUARANTINE_SOURCE_IDENTITY`;
- a legacy fallback or prefixed variant is admissible only from an immutable reviewed lineage record with demonstrated uniqueness, never by heuristic prefix stripping.

## 3. Deterministic route and item allocation

Routing must use source business facts plus an approved effective-dated mapping registry. It must not infer ownership from an output prefix or folder (`sql/ddl/052_v3_unit3_closed_mapping_registries.sql`; `docs/design/SAP_INTERFACE_PRE_EXPORT_GATE.md`, “Routing and ownership”).

Apply this precedence:

| Predicate | Owner / flow | Product scope | Period shape |
|---|---|---|---|
| compulsory Motor item **and** successful `RABBIT_LENDING` charge | RCL / CMI | Motor | `1/1` |
| `payment_option = RABBIT_CARE_INSTALLMENT`, non-compulsory | RCL / installment | Motor or NonMotor from approved product mapping | complete `1..N` |
| `payment_option = CREDIT_CARD_INSTALLMENT` | RCB / EDC onetime | Motor or NonMotor | `1/1` |
| `payment_option = FULL_PAYMENT` | RCB / onetime | Motor or NonMotor | `1/1` |
| unknown, null, conflicting, or unmapped facts | quarantine | unresolved | no release |

The first rule is a narrow MS-06 exception: the repository evidence found a compulsory item with a successful `RABBIT_LENDING` charge and `FULL_PAYMENT`. It must be treated as lender-funded CMI, but this does **not** make every `FULL_PAYMENT` transaction RCL (`docs/FINDINGS_MS06_RCL_MOTOR_COMPULSORY_FULL_PAYMENT_20260909.md`, “Root cause” and “Required legacy fix”). This exception still requires production rule approval and live revalidation before implementation.

Product scope is fail-closed:

- exact `products/car-insurance` -> Motor;
- NonMotor only through an approved product/category mapping;
- missing, ambiguous, or unapproved product -> `QUARANTINE_ROUTE_MAPPING`.

Item allocation rules:

- Ordinary RCL: map the charge period to the uniquely resolved non-compulsory schedule item. More than one same-role candidate without a durable allocation key is quarantined.
- CMI companion: map the qualifying lender charge to the compulsory item at `1/1` using role `CMI_COMPANION`. If that charge also supports another item obligation, retain both allocations but count its amount once at charge-header grain.
- RCB onetime/EDC: emit `1/1` obligations for the uniquely determined active item allocation(s). Ambiguous bundled-item splits are quarantined; they are not resolved merely by `item_rank`.
- Change order: map payment to the current replacement item and retain the predecessor as `RefOrder`. Cancellation of the predecessor is a separate lifecycle obligation.
- Cancel: do not invent a charge. Mirror the exact SAP item/period/invoice state in the lifecycle ledger.

Credit Shell remains a separate change-chain operation. Its router must validate ONETIME `1/1` versus complete RCL spine and hold missing or ambiguous shapes (`sql/ddl/081_v3_creditshell_flow_router.sql`).

## 4. Period, spine, and same-period payments

- ONETIME, EDC, and CMI use `Period = 1`, `TotalPeriods = 1`.
- Ordinary RCL uses raw `charges.installment_number`, which must exist within the current complete schedule `1..N`.
- `N` is derived from the complete current schedule using installment details, latest snapshot count, and transaction installments, with conflicts held (`sql/ddl/012_stg_schedule.sql`, `latest_snapshots`, `order_period`, and schedule generation).
- Multiple distinct successful charges in the same period remain separate event rows. Rank deterministically by effective payment/create/update time and then `charge_id`.
- The first scheduled receipt carries the scheduled `ExpectedReceived`; a later genuine payment in that period carries positive Actual and `ExpectedReceived = 0` (`docs/knowledge/10_SAP_CONTEXT.md`, “Repeated payment in the same period”).

Correction/retry and genuine additional payment remain structurally indistinguishable without durable intent. A second same-period charge must therefore be held until a trusted source marker or reviewed exception identifies its intent (`docs/V3_BUSINESS_SCENARIO_MATRIX.md`, repeated-payment scenarios). The rejected NonMotor MS-06 hypothesis is evidence that repeated period alone must not be labelled missing (`docs/FINDINGS_MS06_RCL_NONMOTOR_SAME_PERIOD_ADDITIONAL_PAYMENT_20260909.md`, “Conclusion”).

An RCL event is not released by itself. It expands into one complete item spine: the target period/invoice is Paid and non-target periods remain contextual Pending rows (`sql/ddl/058_v3_unit5_newpayment_shadow.sql`, payload-spine construction and assertions). Payload statuses are exactly `Paid` or `Pending`; Pending rows have blank InvoiceNo, PaymentDate, PaymentMethod, and PaymentChannel while retaining valid scheduled expected values (`docs/design/SAP_INTERFACE_PRE_EXPORT_GATE.md`, “RCL schedule contract”).

## 5. Evidence hierarchy

Evidence is evaluated in this order:

1. **SAP document truth:** exact `(OrderItem, Period, InvoiceNo)` in `SAP_LIVE_FULL` / `sap_mirror_doc`, including status. Do not use the period-collapsed `sap_mirror_state` as event proof (`sql/ddl/051_v3_unit2_shadow_classifier.sql`, event classifier).
2. **SAP rejection:** exact import-result/rejection record linked by immutable file/run and row identity.
3. **Delivered interface:** immutable payload hash plus exporter run, file/archive manifest, and pickup evidence.
4. **Current interface candidate:** exact row in a freshly captured live legacy view definition. Dynamic view presence is not proof that a file was delivered.
5. **Expected source event:** qualified, routed, validated event with no later evidence.

The current AS-BUILT inventory does not prove that all delivery/import-result runtime evidence is deployed. Until verified, report `IN_INTERFACE_CANDIDATE`, not `IN_INTERFACE_WAITING_SAP` (`docs/AS_BUILT_V3.md`, deployment/runtime status; `docs/SAP_SCHEDULER_INVENTORY.md`).

## 6. Daily assurance statuses

Use one mutually exclusive `assurance_status`, assigned in this precedence. Keep `scenario_code` as a separate cross-cutting field so a known scenario never hides its actual disposition.

| Precedence | Status | Definition |
|---:|---|---|
| 1 | `QUARANTINE_SOURCE_IDENTITY` | Missing/duplicate/ambiguous charge, transaction, order, item, raw invoice identity, or item allocation. |
| 2 | `QUARANTINE_ROUTE_MAPPING` | Product, RCB/RCL owner, payment mapping, or effective-date mapping is missing/ambiguous/unapproved. |
| 3 | `QUARANTINE_PAYLOAD_VALIDATION` | Required field, numeric, date, status, period, full-spine, or payload-hash validation failed. |
| 4 | `EXCLUDED_BUSINESS_RULE` | Exact documented exclusion with rule code and evidence. |
| 5 | `IN_SAP_EXACT` | Exact item/period/invoice exists with expected Paid state. A later cancel is recorded separately as lifecycle state. |
| 6 | `SAP_TERMINAL_CANCELLED` | Exact identity is terminally cancelled; it is not a payment omission. |
| 7 | `SAP_STATUS_CONFLICT` | Exact identity exists but status/amount/route facts conflict. |
| 8 | `SAP_REJECTED` | Exact immutable import rejection is present. |
| 9 | `IN_INTERFACE_WAITING_SAP` | Exact immutable delivered payload exists and SAP acknowledgement is not yet visible. |
| 10 | `IN_INTERFACE_CANDIDATE` | Present in the current live generator, but delivery/pickup evidence is unavailable. |
| 11 | `NEW_EVENT_GRACE` | Event is younger than one proven complete operational cycle. |
| 12 | `KNOWN_SCENARIO` | Exact registered MS predicate is unresolved and no stronger evidence above applies. Also populate `scenario_code`. |
| 13 | `CONFIRMED_MISSING` | All missing-proof conditions below pass. |
| 14 | `UNCLASSIFIED_BLOCK` | Fail-closed residual; never treat as READY or missing automatically. |

This vocabulary normalizes the existing Unit 2 outcomes (`ACKNOWLEDGED`, `PENDING_ACK`, holds, rejection, exclusion) and the operating-model term `ACKNOWLEDGED_IN_SAP` (`sql/ddl/051_v3_unit2_shadow_classifier.sql`, outcome CASE; `docs/design/MONTHLY_DELTA_OPERATING_MODEL_V3.md`, outcome definitions).

`CONFIRMED_MISSING` is allowed only when all are true:

- source identity, item allocation, route, period, invoice, and payload are uniquely valid;
- no exact SAP document, rejection, hold, exclusion, current candidate, or delivered payload exists;
- at least one complete applicable generator -> export -> pickup/import -> post-import SAP extract/mirror cycle finished after the event;
- every evidence source is fresh and the current live view definition/version was captured;
- grace has expired;
- it is not Test, outside the agreed date scope, terminally cancelled, intentionally excluded, or already assigned an exact known-scenario disposition.

Calendar age or `D+2` alone is never sufficient.

## 7. Required daily report columns

| Group | Required fields |
|---|---|
| Run/evidence | `assurance_run_id`, `as_of_ts`, source/mirror/interface freshness, generator definition timestamp/hash, exporter/importer job IDs, completed-cycle flag |
| Raw charge | `charge_id`, raw `third_party_id`, `transaction_id`, amount satang and THB, raw status, installment number, payment/create/update timestamps, raw method/provider, payment option |
| Business link | `OrderID`, `OrderItem`, `obligation_role`, source cardinalities, product, item type, lead state, item `is_cancelled`, `cancel_time`, change old/current IDs, exact Test/date-scope flags |
| Route | RCB/RCL owner, Motor/NonMotor scope, flow (`ONETIME`, `RCL`, `RCL_CMI`, `EDC`, `CREDITSHELL`), operation, expected legacy view, route rule ID, mapping ID/evidence/effective window |
| Period/spine | `Period`, `TotalPeriods`, same-period charge rank/count, detail/follow-up counts, spine-valid flag, expected and actual allocated values |
| Invoice | canonical InvoiceNo, invoice rule/version, legacy variant, blank/collision/cardinality flags |
| Interface/delivery | view name, candidate count, payload hash, file/archive/manifest ID, export/pickup timestamps |
| SAP | exact match count, DocEntry, InvoiceNo, status, PaymentDate, PaymentMethod, PaymentChannel, amount, BatchRunDate/update timestamp |
| Validation | exclusion/hold/rejection code, evidence reference, result timestamp |
| Classification | `assurance_status`, reason code, `scenario_code`, first seen, age/cycle count, owner, next action, `live_verified`, assumptions/gaps |

Publish both charge-header conservation and allocation/spine conservation. Never sum charge amount across allocation rows. Existing classifier summaries demonstrate the required count/amount shape (`sql/ddl/051_v3_unit2_shadow_classifier.sql`, conservation assertions; `sql/ddl/088_v3_rcl_later_newpayment_split.sql`, scenario summary).

## 8. False-positive controls

- Match SAP at exact document identity, not only OrderItem/Period or a selected “winner”. Multiple SAP documents remain an explicit ambiguity (`docs/INPUTS_NEEDED.md`, SAP multi-document decision Q3a).
- Do not treat presence in a dynamic legacy view or archive folder as delivery.
- Require one completed operational cycle and green freshness; do not infer missing from elapsed days alone.
- Preserve distinct same-period charges; deduplicate only exact raw charge identity.
- Keep charge amount conservation separate from multi-item allocation and RCL spine row counts.
- Apply item-only cancellation: `is_cancelled OR cancel_time IS NOT NULL`; underwriting/order status must not fan cancellation to siblings (`docs/knowledge/10_SAP_CONTEXT.md`, cancellation semantics).
- Resolve change direction explicitly: current item receives the payment; predecessor becomes `RefOrder`/cancel obligation.
- Apply the exact approved Test rule and expose it; never hide historic/date-scope exclusions in the WHERE clause.
- Pending rows cannot acknowledge a successful charge because they intentionally carry blank payment identity.
- Require approved non-overlapping effective-dated payment mappings; unknown mappings hold (`sql/ddl/052_v3_unit3_closed_mapping_registries.sql`).
- Validate a whole RCL item spine as one release unit; one invalid sibling period holds the spine (`sql/ddl/088_v3_rcl_later_newpayment_split.sql`, whole-item hold gate).

## 9. Known scenarios and legacy-flow coverage

All legacy V2 operations feed the same assurance ledgers rather than separate completeness definitions:

| Operation family | Required assurance treatment |
|---|---|
| RCB create/payment, Motor and NonMotor | Successful charge event plus ONETIME/EDC item allocation; exact `1/1` SAP identity. |
| RCL create/new payment, Motor and NonMotor | Successful event plus complete item spine; later same-period payments remain separate events. |
| RCL CMI companion | Lender-charge allocation to compulsory `1/1`, including the narrow MS-06 source shape. |
| Cancel, Motor and NonMotor | Separate item lifecycle obligation using canonical item cancel flags and exact SAP document state. |
| Change order | Current replacement payment/create plus predecessor cancel obligation with explicit chain direction. |
| Credit Shell | Separate routed change-chain operation with ONETIME/RCL shape validation. |

The current legacy view name for each operation must come from a versioned live registry because repository SQL files are captures and some views are intentionally being repurposed. Prior MS-01–MS-06 evidence must be encoded as exact `scenario_code` predicates, not lists of example orders (`docs/FINDINGS_MISSING_INTERFACE_SCENARIOS_20260908.md`; `docs/knowledge/20_SAP_PROGRESS.md`). Human-held scenarios remain held, including missing cancellation time/intent and unresolved amount or correction-vs-additional decisions (`docs/INPUTS_NEEDED.md`, current human decision gates).

## 10. Assumptions and live verification required

This contract assumes:

- `carepay_charges.id` is globally unique and immutable;
- raw `third_party_id` is the intended InvoiceNo for new successful events;
- charge amount is an order/payment event fact and must not be duplicated across item allocations;
- a complete operational cycle can be identified from immutable exporter, pickup/import, and post-import SAP extract metadata.

Before implementation, live verification is required for:

1. current definitions and modification timestamps of all `sap_view`, `sap_integration_v2`, and `sap_data_engineer` dependencies;
2. currently scheduled/exported legacy views, filenames, pickup acknowledgements, and import-result retention;
3. active approved payment-method/channel mappings, including non-KBANK entries and Health versus Motor channel split;
4. MS-06 compulsory `FULL_PAYMENT` + `RABBIT_LENDING` route approval and its full population;
5. bundled-order allocation semantics where one charge supports V1 and M1;
6. correction/retry/refund versus genuine same-period additional-payment intent;
7. multi-document SAP resolution and immutable legacy invoice variants;
8. current status of MS-01 and MS-03 human-held cases.

Repository captures and dated findings are evidence of observed or designed behavior only; they are not proof of current production behavior. No live-data result or future-run guarantee is asserted here, in accordance with `docs/AGENT_RULES.md`.

## 11. Live execution result — 2026-09-10

The contract was implemented as a cost-safe two-stage assurance pack. A single query over all 12
legacy views exceeded the repository's 20 GiB billing ceiling, so the executable form performs one
SAP-first event scan and then verifies only SAP-absent candidates in their owning live route.

Baseline job `bqjob_r7c6046823feb0ffb_000001a08adedb07_1` checked 266,613 distinct successful
charges and 309,114 allocation obligations. Route jobs found three obligations absent from SAP and
their live owner: two MS-05 compulsory M1 rows whose exact 1/1 payload exists in the installment
dashboard, and known MS-06 whose upstream dashboard row is absent. One RCB bundled-order case was
held for allocation ambiguity, and one apparent miss was proven present in CreditShell.

The complete operational result, exact transaction IDs, evidence jobs, and daily checklist are in
`docs/DAILY_EVENT_ASSURANCE_20260910.md`. None of the three absent rows is promoted to
`CONFIRMED_MISSING` because immutable delivery/pickup/import-cycle evidence is still unavailable.
