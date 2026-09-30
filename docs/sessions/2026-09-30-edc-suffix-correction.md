# EDC suffix correction


## 2026-09-30 EDC bank-suffix correction

The previous raw-method reclassification was incorrect for existing EDC. Corrective package restores original payment families and changes only identified EDC bank suffixes, with RCB-EDC when bank unknown. Original non-EDC branches, CreditShell priority and manual-cancel mappings are restored. Fifteen view candidate comparisons (09:56–09:58 UTC) show zero nonmapping deltas and zero original EDC rows lost; non-EDC preservation checks (10:02 UTC) show zero unexpected non-EDC rows. All ordered schemas match. Four routine DDL dry-runs pass; three bodies need correction and the EDC hold procedure is already correct. Fresh 10:03:54 UTC production preflight:19 objects,18 changes,0 drift. Production correction pending final independent review.

FA workbook supersedes previous file: existing EDC only,784 exact-charge candidates retain SAP PaymentMethod,83474 unresolved records have no proposed bank. Source snapshot2026-09-29 11:42:03UTC, not September month close. No interface export or historical SAP write. Evidence: docs/evidence/edc_suffix_correction_20260930.


## Correction deployed and verified — 2026-09-30 17:06 ICT

Source commit8a8bfdc; independent Class-A PASS WITH NOTES. Metadata deployment at10:05:51–10:06:05UTC changed15 views and3 procedures; EDC hold procedure verified unchanged. All19 definitions re-read and all15 ordered schemas preserved. Live Motor change query at10:06:52UTC returned666 rows, all EDC EDC: RCB-EDC502, BAY86, KTB38, KBANK30, SCB5, UOB4, BBL1. Next fresh query of these production views uses this corrected rule; existing files and already-posted SAP records are not changed. Full procedure execution / next scheduled export not observed.

Corrected workbook SAP_EDC_Bank_Suffix_FA_Review_20260930.xlsx rendered and actual XLSX cells checked:784 exact-charge candidates,0 method changes,0 non-EDC proposals,all Pending;83474 unresolved investigation rows. Sources SAP_LIVE_FULL/CareOS snapshot2026-09-29 11:42:03UTC. Do not use earlier SAP_Payment_Mapping_FA_Review_20260929.xlsx. No interface file generated.

| Built | Verified against real data | Still unverified |
|---|---|---|
| EDC-only suffix correction,15 views/3 changed procedures |15 original/candidate multisets and schema comparisons;19 production postreads; live Motor change distribution |Procedure body execution and next scheduled SAP import |
| Corrected FA workbook |Actual XLSX preserves784 methods; source-match semantics independently reviewed |FA decisions and SAP historical corrections |
