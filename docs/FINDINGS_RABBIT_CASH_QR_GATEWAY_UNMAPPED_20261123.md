# FINDINGS — Motor QFlow One-Time QR moved from OPN to the Rabbit gateway: new provider `RABBIT_CASH` is unmapped in production views

Date: 2026-11-23 (query session ~18:45–19:30 UTC). Author: Claude Code (read-only investigation).
Review class: **A** (production-object conclusion + accounting impact). Status: **STOPPED: needs input**
under the AGENT_RULES rule "money/accounting impact: write FINDINGS + INPUTS_NEEDED and stop".

## Trigger
Tech team notice to Boat (2026-11-23): starting 09:00 that day, One-Time QR PromptPay for **Motor QFlow**
switched from OPN (Omise) to the "Rabbit Card Gateway". Other channels are unchanged. Accounting has
issued a new accounting code, which is said to be in an MS Teams chat.

## Evidence (all read-only, BigQuery `pacific-plating-282708`)

### E1. The new gateway arrives as `service_provider = 'RABBIT_CASH'`
`careos.careos_charges`, QR_CODE, providers outside OMISE/RCB/RABBIT_LENDING, since 2026-10-01:

| provider | successful | total | first charge | first success |
|---|---|---|---|---|
| RABBIT_CASH | 4 | 49 | 2026-10-29 (test, PENDING) | 2026-11-23 11:04 |

* The first 2026-11-23 RABBIT_CASH charge has a raw `create_time` of **09:01**, which matches the
  09:00 cutover (in `careos_charges` the raw `create_time` reads as ICT wall-clock).
* `third_party_id` is a 20-hex id rather than `chrg_…`, and `meta_data` is empty, so these charges are
  **not** OPN/Omise charges.
* Mapping "Rabbit Card Gateway" to `RABBIT_CASH` is **INFERRED** from the timing and the id format. Tech
  has not confirmed it.
* OMISE QR (~10/day) and RCB QR (~140/day; still `chrg_` ids) keep flowing after 09:00 on 2026-11-23,
  so the switch covers only part of QR traffic. That matches the scope "Motor QFlow one-time only".

### E2. RABBIT_CASH successful/pending charges in `careos.carepay_charges` (source of the views)
`carepay_charges.create_time` is UTC.

| status | create_time (UTC) | THB | OrderID | item / type | in SAP_LIVE_FULL? |
|---|---|---|---|---|---|
| PENDING | 2026-10-29 04:06 | 645.21 | (no order via `orders.payment`) | | |
| SUCCESSFUL | 2026-11-23 04:04 | 645.21 | L81230409 | L81230409-M1 / COMPULSORY | **no** |
| SUCCESSFUL | 2026-11-23 09:03 | 639.18 | (no order via `orders.payment`) | | |
| SUCCESSFUL | 2026-11-23 10:27 | 4,899.53 | L79086876 | L79086876-V1 / TYPE_3_PLUS | **no** |
| SUCCESSFUL | 2026-11-23 10:30 | 5,800.00 | (no order via `orders.payment`) | | |

* BigQuery job `FJyZ2-PYCb2QAbj2R_YXlDhzyNkH`.
* The three unlinked charges probably belong to change orders or secondary transactions. That is
  **UNVERIFIED**; resolve them before any count goes to a stakeholder.
* None of these charges has reached SAP yet.

### E3. Live view behaviour for `PaymentMethod='QR_CODE'` + `PaymentChannel='RABBIT_CASH'`
Live definitions were read from `INFORMATION_SCHEMA.VIEWS` on 2026-11-23. The repo copies are baseline only.

| object | PaymentMethod result | PaymentChannel result | effect |
|---|---|---|---|
| `sap_data_engineer.RCB_MOTOR` | ELSE `'TRF Transfer'` | ELSE `'RCB-Transfer-อื่นๆ'` | **silent misposting as bank transfer** |
| `sap_data_engineer.sap_dashboard_carepay_fully_paid` | ELSE `'TRF Transfer'` | ELSE `'RCB-Transfer-อื่นๆ'` | same |
| `sap_data_engineer.sap_fixing_rcb` | ELSE `'TRF Transfer'` | ELSE `'RCB-Transfer-อื่นๆ'` | same |
| `sap_data_engineer.RCB_HEALTH` | ELSE `'TRF Transfer'` | ELSE `'RCB-Transfer-อื่นๆ'` | same, if health ever uses it |
| `sap_view.RCB_NonMotor_process_2_cancel` | ELSE `'TRF Transfer'` | ELSE `'RCB-Transfer-อื่นๆ'` | same (cancel path) |
| `sap_data_engineer.sap_dashboard_carepay_cancelled` | no ELSE → **NULL** | no ELSE → **NULL** | NULL required value |
| `sap_integration_v3.fn_rcb_payment_mapping` (used by `sap_view.RCB_Motor_process_3_change`) | `'OME Omise QR Prompt Pay'` | `'RCB-Omise QR Prompt Pay'` (no `-BAY`) | wrong/unknown SAP channel (labelled as Omise) |
| `sap_integration_v3.vw_onetime_payload_source` | ELSE `'TRF Transfer'` | ELSE `'RCB-Transfer-อื่นๆ'` | same as RCB_MOTOR (V3, not delivering) |
| RCL views (`RCL_MOTOR`, `RCL_HEALTH`, `sap_dashboard_carepay_installment`, `sap_fixing_rcl`, `sap_fix_rcl_2025`) | ELSE raw `'QR_CODE'` | ELSE raw `'RABBIT_CASH'` | raw CareOS enum, so SAP rejects it or it lands in an unknown channel; only relevant if RCL ever uses it |
| `sap_integration_v3.payment_mapping` seed (DDL 057) | no RABBIT_CASH row | | V3 fails closed (correct) |

No view drops RABBIT_CASH by filter: the only provider filters are `!= 'ICOLLECTION'` and
`<> 'RABBIT_LENDING'`. Rows are therefore **exported with wrong codes**, not lost.

## Impact
* From 2026-11-23 09:00, every successful Motor QFlow one-time QR payment will reach SAP as
  `TRF Transfer / RCB-Transfer-อื่นๆ` on the next legacy RCB export.
* That posts the receipt to the wrong GL/bank account, and the error is invisible because the
  value is a valid SAP code.
* Exposure so far is 2 linked motor orders, ฿5,544.74, plus 3 unlinked charges (฿7,084.39). These
  figures are **PROVISIONAL** and come from `carepay_charges` at query time.

## What is needed (see INPUTS_NEEDED)
1. The new SAP **PaymentMethod** and **PaymentChannel** strings from Accounting. They were not
   found by Teams search (index searched 2026-11-01..23, terms: Rabbit Card Gateway, QFlow,
   PromptPay, Rabbit Cash, account/accounting code, OPN) or by Outlook search.
2. Tech confirmation that `RABBIT_CASH` is the Rabbit Card Gateway provider value, and whether
   any other value will appear.
3. Boat's decision on the interim: hold RABBIT_CASH rows out of the RCB exports until the codes
   exist (route them to `sap_excluded_records`), or let them export with the wrong codes and correct later.

## Fix outline (not built; prepare only after item 1)
* Add a `WHEN PaymentMethod='QR_CODE' AND PaymentChannel='RABBIT_CASH'` branch, placed ahead of the
  ELSE, in each RCB view above.
* Add the same case to `fn_rcb_payment_mapping` and a RABBIT_CASH row to the v3 `payment_mapping`.
* Keep column order (`SELECT * REPLACE`).
* Legacy-object DDL needs a new explicit Boat exception: the current AGENT_RULES exception covers
  only `sap_dashboard_carepay_installment`.
* Dry-run, Class-A review, Boat deploy OK, then Codex executes.
