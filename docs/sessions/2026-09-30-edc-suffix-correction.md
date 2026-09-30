# EDC suffix correction


## 2026-09-30 EDC bank-suffix correction

The previous raw-method reclassification was incorrect for existing EDC. Corrective package restores original payment families and changes only identified EDC bank suffixes, with RCB-EDC when bank unknown. Original non-EDC branches, CreditShell priority and manual-cancel mappings are restored. Fifteen view candidate comparisons (09:56–09:58 UTC) show zero nonmapping deltas and zero original EDC rows lost; non-EDC preservation checks (10:02 UTC) show zero unexpected non-EDC rows. All ordered schemas match. Four routine DDL dry-runs pass; three bodies need correction and the EDC hold procedure is already correct. Fresh 10:03:54 UTC production preflight:19 objects,18 changes,0 drift. Production correction pending final independent review.

FA workbook supersedes previous file: existing EDC only,784 exact-charge candidates retain SAP PaymentMethod,83474 unresolved records have no proposed bank. Source snapshot2026-09-29 11:42:03UTC, not September month close. No interface export or historical SAP write. Evidence: docs/evidence/edc_suffix_correction_20260930.
