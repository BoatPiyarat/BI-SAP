# SAP import error finding — Upload LogID 22049

Checked: 2026-09-14 ICT  
File: `RCB_MOTOR_INSURANCE_RCB_02_RCB_MOTOR_PROCESS_2_CANCEL_NEW_20260913.csv`  
Source log: `import_20260914-023912981.txt`  
Mode: read-only diagnosis; no view replacement, re-import, or SAP mutation

## Result

The import failed with 77 row-error lines across 11 orders. Error counts overlap because one row
can contain more than one validation message and an anchor-row failure is propagated to the full
OrderID through `Ref.Row[...]`.

| Error signature | Lines | Orders | Finding |
|---|---:|---:|---|
| Other period not Paid/Pending before cancel | 67 | 8 | Two distinct root causes: period absent from SAP, or SAP is stale Pending while CareOS is already paid |
| Cannot change InvoiceNo | 38 | 4 | The anchor period is SAP Pending/blank InvoiceNo but CareOS has a successful charge/nonblank InvoiceNo |
| ProductType must be Insurance/Add-On | 9 | 3 | The cancel view emits blank ProductType because it normalizes only literal `NULL`, not blank strings |
| TotalEIR does not equal period sum | 6 | 1 | `L74079056-V1`: TotalEIR 152.59/152.60 versus period InterestEIR sum 157.64 |
| First period must previously be Paid | 1 | 1 | `L74079056-V1` Period 1 was supplemented but does not exist in SAP |
| Cancel transaction not balanced | 1 | 1 | `L74079056-V1` supplemented Period 1 has Expected 1,082.36 and Actual 0; the set is short one installment |
| Cancelled-Date outside permissible range | 1 batch | — | SAP journal DueDate/posting-period validation; the log does not identify an OrderID |

## Root-cause groups

### A. SAP Pending is already paid in CareOS — Paid must be imported first

| OrderItem | Anchor period | SAP state | CareOS successful InvoiceNo |
|---|---:|---|---|
| `L79180940-1` | 5 | Pending / blank InvoiceNo | `chrg_6893rhye87rtfiklprg` |
| `L79308561-1` | 7 | Pending / blank InvoiceNo | `chrg_688n6s9yycv6lbm1piq` |
| `L79510340-1` | 6 | Pending / blank InvoiceNo | `chrg_688rnq2ja4esoecvvo3` |
| `L79949677-1` | 4 | Pending / blank InvoiceNo | `chrg_68820l4ihfi3opg0wkp` |

The confirmed cancel contract requires an asynchronous sequence: send Paid/new-payment, wait for
successful SAP import, refresh the SAP mirror and prove Paid, then send Cancelled. The current
cancel view does not perform this CareOS-versus-SAP paid reconciliation.

### B. Full spine was synthesized, but missing periods cannot be cancelled directly

| OrderItem | SAP-backed periods | Supplemented periods not in SAP |
|---|---|---|
| `L77833033-V1` | 1 | 2–6 |
| `L80511750-V1` | 1 | 2–10 |
| `L80513404-V1` | 1 | 2–10 |
| `L80518454-V1` | 1 | 2–3 |

The importer requires a complete 1..TotalPeriods cancel set, but each period must already exist in
SAP in Paid/Pending state. Therefore the current `missing_installment_rows` branch is unsafe for a
one-step cancel: the missing periods need a separate successful create/pending import and SAP
refresh before the later cancel file. Until that sequence exists, hold the entire OrderItem rather
than emitting a partly SAP-backed cancel set.

### C. Historical payload defects

- `L74079056-V1`: SAP contains Periods 2–6 only; synthesized Period 1 violates the Paid-first
  precondition and creates the balance/EIR failure. Hold for targeted historical data repair.
- `L74079056`, `L77083183`, `L77121047`: blank ProductType. The legacy CASE handles only the text
  `NULL`; it must also normalize SQL NULL/blank values to an allowed ProductType.

### D. SAP posting-period gate

`InstallmentRCLCancelled-Date deviates from permissible range [JDT1.DueDate][line: 3]` is a
batch-level SAP journal validation. The payload BatchRunDate was `14092026`, but the log contains
no OrderID for this error. SAP/Aware must confirm that the RCB posting period and due-date range are
open; changing an order row cannot be justified from this log alone.

## Disposition

- Do not retry the same file unchanged.
- Send the four missing Paid events first; wait for SAP success and mirror refresh before cancel.
- Do not directly cancel dashboard-only periods. Create/import the missing pending spine first or
  hold the item pending an approved two-stage legacy process.
- Hold `L74079056-V1` for EIR/balance and missing-first-period repair.
- ProductType blank normalization is a direct legacy-query defect and can be fixed independently.
- Ask SAP/Aware to verify the 14-Sep-2026 posting period for the batch-level DueDate error.

## Evidence

- RED log parser: 77 row-error lines / 11 orders.
- View/SAP trace job `bqjob_r1dda2d1c6130fc52_000001a09fa981df_1`.
- CareOS successful-charge trace job `bqjob_r4b89cca715d9018c_000001a09faf74e0_1`.
- Validated mirror-state check: all four anchors are unambiguous SAP Pending rows with blank
  InvoiceNo, confirming the mismatch is CareOS Paid versus SAP Pending rather than mirror dedup.

## 2026-09-15 full legacy query prepared

Prepared `sql/production/RCB_Motor_process_2_cancel_new_import_contract_fix_20260915.sql` as a
SELECT-only replacement proposal. It removes the unsafe dashboard-period supplementation and
adds item-level gates for complete SAP spine, Paid Period 1, Paid/Pending predecessor statuses,
CareOS-paid/SAP-pending conflicts, and EIR consistency. It also uses deterministic one-document
selection and normalizes blank ProductType.

Population regression found 681 eligible cancelled items before the new gates: 669 ready and 12
held. Counts by reason overlap: five incomplete-spine items, seven stale SAP-Pending/CareOS-Paid
items, two without a Paid first period, and one EIR mismatch. For LogID 22049, 13 OrderItems were
evaluated: four ready rows (`L77083183-M1/V1`, `L77121047-M1/V1`) and nine held items. Runtime
execution returned the expected 56-column payload. No deployment or re-import was performed.

Validation job: `bqjob_r463f02b8f49c1d46_000001a0a3a258cd_1`.  
Candidate runtime job: `bqjob_r7bdfffa049cff65f_000001a0a3a48efe_1`.
