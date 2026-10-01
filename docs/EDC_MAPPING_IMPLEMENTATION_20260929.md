# Multi-bank payment mapping implementation — 29 September 2026

User approval covers all legacy views and related upstream/downstream queries. Fallback decision: retain raw payment-method family for unmapped methods; append recognized source bank if available, otherwise omit bank suffix. EDC/TMB => EDC EDC / RCB-EDC-TMB; EDC/NULL => EDC EDC / RCB-EDC; CHEQUE/NULL => CHEQUE / RCB-CHEQUE. ALL is reserved for paired ALL/ALL CMI only. Missing payment method remains unresolved.

## Scope

15 views listed in sql/production/edc_mapping_20260929/manifest.json, including two legacy archive-named views explicitly included in the user's all-query scope. Shared fn_rcb_payment_mapping replaces duplicated CASEs. Existing CreditShell and cancellation manual-marker exceptions are preserved. NULL provider exclusion predicates now allow a real source charge with unknown bank. Fully-paid dashboard additionally requires charges_id to prevent unmatched LEFT JOIN rows from becoming payments.

Four V3 routines align ONETIME non-credit-shell fallback and EDC gates: sp_build_v3_unit3_mapping_holds, sp_build_v3_onetime_create_shadow, sp_build_v3_newpayment_shadow, sp_build_v3_edc_onetime_holds. Existing approved effective registry entries retain precedence in builders; retired entries are excluded. Duplicate applicable registry rows remain blocked. Missing mappings can use the shared fallback. Unrelated scenario, identity, schedule, insurance, amount, date, release and export gates remain in force. The legacy summary field kbank_structurally_ready_count is retained for schema compatibility but now counts all structurally eligible EDC banks.

The RCL-only recovery builder is deliberately unchanged: its approved RCL mappings must not fall back to RCB channels. RCL/credit-shell-specific producers and SAP-mirrored cancellation paths remain unchanged; these are separate flow mappings, not obsolete EDC/KBank constants. Motor/NonMotor create consumers inherit corrected upstream mappings and do not filter by bank. No interface generation, scheduler changes or historical SAP mutation.

## Validation

20 mapping fixtures and 10 gate fixtures pass, including six bank mappings, TMB, NULL/unspecified bank, raw CHEQUE fallback, reserved ALL mismatch, NULL scope fields and duplicate mapping holds. Full before/after comparisons check the multiset of every field except PaymentMethod/PaymentChannel. Final evidence and schema comparison are recorded alongside this document after completion.

Procedure DDL dry-runs pass. These plus extracted gate fixtures and source review do not execute full procedure branches or constitute end-to-end export validation. No mutating production procedure CALL is used for testing.

## Historical workbook

SAP_Payment_Mapping_FA_Review_20260929.xlsx is a local FA/Aware handoff, not an SAP interface file. Source snapshot 2026-09-29 11:42:03 UTC from SAP_LIVE_FULL and raw CarePay charges/transactions/orders/items, all available history. 9,585 unique-source mapping differences (784 involving EDC) are pending human review. 83,748 legacy EDC records lack an exact charge match; 89 additional RCL-source-flow conflicts are separated, total83,837 investigation records. Total93,422 records. Current rules compared with history do not prove historical account misposting; historical settlement context must be reviewed.

Preserved CompanyDB, DocEntry, OrderID, OrderItem, InvoiceNo, current SAP method/channel, source charge evidence and proposed values. Decision, Owner and FA/Aware notes are editable. No row is preapproved or batch-executed. Match is exact order+item+nonblank invoice=third_party_id; no guessing of missing or generated invoice identities. Source charge amount may span multiple SAP items and must not be summed across rows. Source RCL conflicts have no proposed RCB correction. Full record extracts stay local; repository contains SQL, aggregates, validation and hashes only.

## Deployment and rollback

Full live definitions were captured before edits; rollback files accompany every existing object. New helper created first for isolated candidate compilation. Existing view/routine replacements require final independent review and fresh drift check. Deploy in producer-first order, then procedures. Preserve 56-column names, types and ordinal positions. Verify fresh definitions and downstream schemas after replacement. September2026 remains open.


## 2026-09-30 preflight continuation

Authentication restored by user. Before production mutation, API metadata exposed CLI cache encoding differences in two views. Preserved live nonmapping title strings/comments and exact rollback definitions. Fresh API baseline now used for drift checks. Targeted live-before/rebased-after comparison reports zero nonmapping multiset differences (2026-09-30 07:37:12 UTC). Procedure bodies match the reviewed baseline.


## DEPLOYED 2026-09-30

All15 existing views and4 procedure definitions replaced and immediately verified via fresh BigQuery API reads. Every view schema preserved; exact reviewed definitions verified. Shared helper is live. Deployment timestamps/etags: docs/evidence/edc_mapping_fix_20260929/production_deployment.json. Updates use etag-protected metadata API calls, not query jobs. Independent final review and encoding-delta review PASS. No procedure CALL, export, scheduler change or historical SAP update. Workbook remains the September29 source snapshot.
