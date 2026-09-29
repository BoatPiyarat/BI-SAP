# EDC bank mapping proposal and impact — 29 September 2026

Status: investigated; proposal only, no mapping deployed and no interface file generated.

User clarification: EDC-KBANK in existing output does not establish that the source payment belongs to KBank. EDC includes multiple banks. Map from the successful charge and reuse established bank codes where supported.

## Evidence and scope

Fresh definitions at 2026-09-29 10:27:01 UTC: 96 views and 81 routines across sap_view, sap_data_engineer, sap_integration_v2 and sap_integration_v3. Data snapshots: charge profile 10:27:21 UTC; current Motor change matching 10:29:09 UTC. Evidence files accompany this report under evidence/edc_bank_mapping_20260929. Static dependency extraction covers fully qualified backtick references, not all dynamic SQL, external applications or other datasets.

## Proposed EDC channels

For these six providers, existing live CASE expressions pair the following channel with PaymentMethod = EDC EDC. The SAP_LIVE_FULL mirror also contains Paid records with all six pairs. Historical occurrence is evidence of usage, not confirmation of current SAP account configuration or approval for every flow.

| Source service_provider | Bank code | Proposed PaymentChannel | Successful EDC charges in profile | Existing transfer reference |
|---|---|---|---:|---|
| KRUNGSRI | BAY | RCB-EDC-BAY | 9,708 | RCB-Transfer-BAY: live CASE |
| KRUNGTHAI | KTB | RCB-EDC-KTB | 2,764 | RCB-Transfer-KTB: live CASE |
| KASIKORN | KBANK | RCB-EDC-KBANK | 2,147 | RCB-Transfer-KBANK: live CASE |
| UOB | UOB | RCB-EDC-UOB | 361 | No matching transfer evidence established |
| BANGKOK_BANK | BBL | RCB-EDC-BBL | 339 | RCB-Transfer-BBL: mirror history, absent from inspected transfer CASE |
| SCB | SCB | RCB-EDC-SCB | 75 | RCB-Transfer-SCB: live CASE |
| TMB | Unresolved | HOLD pending approved SAP code | 5 | Do not assume TMB/TTB alias |
| SERVICE_PROVIDER_UNSPECIFIED | Unknown | HOLD missing bank | 1 | Do not default to KBANK or Transfer-other |

Profile scope: all CarePay products, SUCCESSFUL EDC charges with payment_date >= 2026-01-01 and < 2026-10-01, observed September 29; total 15,400. September is still open. These are source-profile counts, not affected export rows or SAP postings. One KRUNGSRI charge has RABBIT_CARE_INSTALLMENT: route separately for flow validation, not automatically ONETIME. Other EDC charges are FULL_PAYMENT or CREDIT_CARD_INSTALLMENT.

Reusable live mapping references: sap_data_engineer.sap_dashboard_carepay_fully_paid, sap_data_engineer.RCB_HEALTH, sap_view.RCB_NonMotor_process_2_cancel, sap_integration_v3.vw_onetime_payload_source. Reuse the explicit six EDC pairs, not their generic ELSE Transfer/Transfer-other fallbacks. NonMotor has method=EDC for any EDC source while channel can fall back to Transfer-other; this is a paired-field inconsistency for unknown banks.

Other established channel families in those CASE expressions:

| Source | Existing PaymentMethod | Existing PaymentChannel |
|---|---|---|
| BANK_TRANSFER + KASIKORN/KRUNGSRI/KRUNGTHAI/SCB | TRF Transfer | RCB-Transfer-KBANK/BAY/KTB/SCB respectively |
| ONLINECARD + OMISE or RCB | OMC Omise Credit Card | RCB-Omise Credit Card-BAY |
| QR_CODE + OMISE or RCB | OME Omise QR Prompt Pay | RCB-Omise QR Prompt Pay-BAY |
| CASH + SERVICE_PROVIDER_UNSPECIFIED | TRF Transfer | RCB-Transfer-อื่นๆ |
| DIRECT_PAYMENT + SERVICE_PROVIDER_UNSPECIFIED | DPM จ่ายตรงกับบริษัทประกัน | RCB-DIRECT PAYMENT |
| Explicit credit-shell classification | RCB-CreditShell | RCB-CreditShell |
| Explicit RCL-CMI classification | RCL-CMI-channel | RCL-CMI-channel |

Some references also support QR_CODE + RABBIT_LENDING; NonMotor differs. Do not broaden this context without flow-specific validation. Legacy mirror labels (EDC installment-month variants, VEDC, bare EDC and anomalous values) are not additional recommended new-output codes.

## Mapping method

1. Retain raw payment_method, service_provider, charge_id, transaction_id and payment_option through the source CTE. Choose the successful charge for the event and item, not an arbitrary order-level or latest charge. Reject ambiguous matches; preserve item allocation when a charge covers multiple items.
2. Classify operation/flow first: new payment, change-create, cancellation/reversal, credit-shell, RCL. Preserve explicit credit-shell/CMI rules. CREDIT_CARD_INSTALLMENT is a bank installment option, not sufficient reason to construct an RCL repayment schedule.
3. Use the existing sap_integration_v3.payment_mapping_registry as the shared source for paired method/channel values, with raw method/provider plus flow, product scope, payment source type, credit-shell flag, effective dates and approval state. Require exactly one applicable APPROVED, nonretired row. Check overlapping entries before joining so mapping cannot multiply rows. Define which event date controls effective-date matching before implementation; do not silently reinterpret old charges using today's approval.
4. Keep provider-to-bank-code normalization separate from payment-method family. Reuse KBANK/BAY/KTB/BBL/SCB/UOB codes; do not derive every channel by concatenation because QR/ONLINECARD settlement channels have explicit rules. service_provider identifies the source provider; it does not prove card issuing-bank identity. Never derive bank from card numbers or from the existing hardcoded output.
5. Unknown/NULL provider, TMB, unsupported pair, unapproved scope, multiple registry matches or unmatched charge => visible mapping hold with reason and source identity. Retain raw NULLs in evidence; do not turn them into KBANK. Existing acceptance of NULL fields in the earlier installment task is not approval to invent a payment bank.
6. For already posted SAP rows, cancellation/reversal and historical identity must use stored SAP values where required. Preserve Paid InvoiceNo verbatim. Correcting historical accounting is a separate reconciled action; changing an outbound view will not repair existing SAP documents.

## Current defects and approval gaps

The live sap_view.RCB_Motor_process_3_change hardcodes EDC EDC / RCB-EDC-KBANK; its EDC/payment-option predicates are commented out. Mapping-only replacement must not silently restore restrictive predicates and drop legitimate payments. Separately prove create/change ownership and avoid exporting the same event twice.

Current exact transaction + InvoiceNo = third_party_id matching finds 34 non-EDC output-to-charge links: QR_CODE/RCB 16 links (11 charges), QR_CODE/OMISE 9 (6 charges), ONLINECARD/RCB 9 (7 charges). Another 17 links have no exact successful-charge match. These are joined diagnostic counts, not a certified deduplicated export population or posted SAP count. There are no matched EDC links in this snapshot. Unmatched links need charge lineage investigation; do not assign bank using an order-level fallback. Older audit figures of 88 links/87 items refer to September 26 and must not be described as current.

The registry contains five APPROVED EDC mappings: BAY, KBANK, UOB, BBL, KTB. They are scoped to ONETIME / MOTOR / CREDIT_CARD_INSTALLMENT / non-credit-shell, effective from 2026-08-01. SCB appears in live CASE and mirror history but not in the returned EDC registry entries. These approvals do not establish FULL_PAYMENT or NonMotor approval. The live sp_build_v3_edc_onetime_holds still hardcodes KASIKORN and RCB-EDC-KBANK and retains scenario-release holds. Align registry and hold procedure; do not remove unrelated scenario gates merely because a bank mapping exists.

## Upstream and downstream impact

| Area | Evidence / affected objects | Required treatment |
|---|---|---|
| Source lineage | carepay_charges, transactions, snapshots, snapshot price summaries; orders/items/leads; cancelled_change_orders | Retain charge-level method/provider; prove uniqueness, charge allocation and source-to-item lineage; no CareOS mutation needed |
| Motor change | sap_view.RCB_Motor_process_3_change | Primary hardcoded defect; map both fields; prove event ownership against Motor create and credit-shell |
| Motor create / validation | sap_dashboard_carepay_fully_paid -> RCB_Motor_process_create and sp_run_validation | Existing six-bank reference; centralization affects consumers and unknown-bank fallbacks |
| NonMotor create | RCB_HEALTH -> RCB_NonMotor_process_1_create | Reuse bank codes; preserve product/flow approvals and allocations |
| NonMotor change-create | RCB_NonMotor_process_2_cancel | Name is misleading; existing explicit six-bank CASE needs paired fallback review |
| V3 payload builders | vw_onetime_payload_source -> vw_v3_edc_onetime_payload_source, sp_build_v3_onetime_create_shadow, sp_build_v3_newpayment_shadow, sp_build_july_export_shadow | Shared changes propagate beyond EDC; compare non-EDC output and rebuild affected immutable payload manifests before future export |
| V3 mapping gates | payment_mapping_registry; sp_build_v3_unit3_mapping_holds; sp_build_v3_edc_onetime_holds; sp_build_mo_rcl_prod02_interface | Audit scope/date match, duplicate mappings, KBANK-only conditions and generic fallbacks; no automatic scenario activation |
| Legacy consumers | Additional V2 mapping views, RCB_MOTOR, sap_dashboard_carepay_cancelled, sap_fixing_rcb and backups in dependency_inventory.json | Distinguish active consumers from archives before changing; avoid bulk edits of historical definitions |
| Export automation | Repo workflows/sap_interface_pipeline.yaml names Motor change as step03 and NonMotor change as step02; same-day scheduler evidence has Motor/NonMotor legacy jobs ENABLED at 01:30 Asia/Bangkok and V3 orchestrator PAUSED | View edits can change subsequent exports. Current deployed exporter source and dynamic reads are not fully verified in this analysis; do not assume workflow comments prove active topology |
| SAP import/accounting | PaymentMethod/PaymentChannel select SAP interpretation and may affect bank/clearing allocation | Verify exact channel/account master with Aware/Finance; historical mirror usage is not proof of correct GL. No vendor component changes proposed |
| Cancellation / credit-shell / reconciliation | SAP_LIVE_FULL, sap_mirror_state and plain-cancel payload paths | Preserve posted identities and reversal semantics; separately identify earlier misclassified imports rather than rewriting history |
| Reporting / operations | Validation, mapping holds, reconciliation and bank aggregates | Report bank counts and held unknowns; explain redistribution from KBANK to other banks; don't mistake relabeling for new money |

No stored view/routine downstream reference to Motor change was found in the four-dataset static scan. This does NOT mean it has no consumers: exporters access it externally. Dependencies outside these datasets, dynamic queries, BI consumers and vendor SAP configuration remain unverified. All identified effects above are assessed; exhaustive external lineage is not claimed.

## Implementation and validation sequence

Prepare one reviewed mapping contract and approved scoped registry additions, then patch Motor change's paired mapping from a fresh live definition. Align V3 KBANK-only checks and explicit unknown handling in separately scoped changes; common registry adoption should not require immediate bulk migration of every legacy view. Keep route eligibility changes separate and demonstrate no duplicate ownership.

Before deployment: freeze a diagnostic population, prove one charge mapping per event, compare full before/after rows, require equal amounts/dates/InvoiceNo/periods except explicitly reviewed holds or ownership changes, preserve all 56 interface columns and positions, test all six banks plus TMB/NULL/unapproved/duplicate cases and QR/ONLINECARD regressions, verify CCI period semantics and posted cancellation behavior, and reconcile candidates = ready + visible holds. September 2026 remains open. After a future approved import, reconcile acceptance and bank/channel against SAP mirror; export success alone is insufficient.

This deliverable does not authorize deployment, historical SAP correction, scheduler changes or interface generation.
