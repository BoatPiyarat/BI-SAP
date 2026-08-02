# SAP import result retained for later process tuning — Upload LogID 21153

Status: evidence retained; Boat is maintaining the manual July-closing cover. No automatic retry,
archive status rewrite, or production resend is authorized from this finding.

File: `RCB_MOTOR_INSURANCE_RCB_01_V3_JULY_PAYMENT_20260731_V3JULY-20260802-000806-12ccb84a_000000000000.csv`.
SAP reported `success with error` for `INSURANCE_RCB` in `RCB_LIVE_DB`.

- Submitted rows: 30,245.
- Error workbook rows: 15,843 across 11,742 orders (52.38% of submitted rows).
- Text log rows: 15,812; it undercounts workbook errors by 31. Workbook is the row-error source of
  truth for this run.
- Dominant workbook errors: PolicyStatus duplicated 7,623; immutable InvoiceNo 8,021;
  PaymentMethod over 50 characters 1,889; invalid period sequence 196; PaymentChannel not found 31.
  These are error instances, not mutually exclusive buckets: 17,760 instances occur across 15,843
  rejected rows because one row may carry more than one error.
- The 14,402 rows absent from the workbook are only candidate successes until a post-import SAP
  extract/mirror proves them. Outer status and journal references are not row-level proof.
- Confirmed source defect: the July exporter used export-archive membership but did not classify
  against current SAP state before delivery.
- Confirmed encoding/mapping defect already present in BigQuery payload: 1,889 PaymentMethod values
  are mojibake (70 characters / 143 bytes) and 31 PaymentChannel values are a mojibake form of the
  Thai `RCB-Transfer-other` mapping. Do not quote raw affected records in repo/docs.

Encoding root-cause owner: **Data Engineering / V3 payload-source owner (Codex implementation,
Boat approval)**. Rule 28's hold contains the symptom; it does not close the upstream double-encoding
defect. Trace source Unicode through the V2-derived payload view before any future delivery.

Raw `.xlsx` and `.txt` evidence remains outside the repository. Revisit after July close to ingest
row outcomes, prove accepted rows from SAP, and tune the reusable delta process.

