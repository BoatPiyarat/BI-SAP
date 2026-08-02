# UAT2 import result — Upload LogID 17800 (2026-08-02) — IGNORE

Status: **NON-AUTHORITATIVE / DO NOT CITE OR USE FOR DESIGN.** Boat narrowed analysis to LIVE-only
on 2026-08-02. This file is retained solely as an audit record that the evidence was received; all
analytical conclusions and proposed controls below are superseded by
`docs/FINDINGS_LIVE_IMPORT_21153_20260802.md`.

## Scope and provenance

- Environment: `RCB_ISSUE_DB` (email label UAT2)
- ImportType: `INSURANCE_RCB`
- Upload LogID: `17800`
- Source file: `RCB_MOTOR_INSURANCE_RCB_01_V3_JULY_PAYMENT_20260731_V3JULY-20260802-000806-12ccb84a_000000000000.csv`
- Source: 30,245 data rows, exactly 56 columns in the interface contract order.
- Source SHA-256: `2B169DF976D04E9979C954394D2C4F6E0EB3151F246969C88CCAEB53CCBF1863`
- Import log SHA-256: `AE6AE34FD809FFE2D8C5010424687A65D1B0F4A74A9D6C05DBC3B82218DAE753`
- Error workbook SHA-256: `20A2FDEE783D2460D576B4DFD8E14808ECF38DC004FF0F82A7AE55BD033AE443`

The workbook contains 15,790 error rows and 59 columns: the 56 interface columns plus
`InvoiceId`, `SaleOrderId`, and `ErrorLog`. Those three result columns are not part of the upload
contract. SAP `Row#` is the 1-based data-row ordinal with the CSV header excluded; all 15,790
Row#/OrderID checks matched after applying that rule.

## Aggregate result

| Result | Rows | Share of input |
|---|---:|---:|
| Error rows | 15,790 | 52.207% |
| Rows without a row-level error | 14,455 | 47.793% |

`14,455` means only “not present in the exhaustive row-error section”; the 104 success reference
lines are accounting reference groups, not row counts. Do not use 104 as the successful-row count.

| Error class | Rows | Share of errors | Share of input |
|---|---:|---:|---:|
| Period sequence invalid | 13,870 | 87.840% | 45.859% |
| PaymentMethod longer than 50 | 1,889 | 11.963% | 6.246% |
| PaymentChannel absent/account code missing | 31 | 0.196% | 0.102% |

The PaymentMethod failures are one distinct DPM Thai-label value whose exported representation is
70 characters and appears encoding-corrupted. The PaymentChannel failures are one distinct
`RCB-Transfer-<Thai other>` value. Preserve the raw evidence outside the repo; do not copy customer
rows into documentation.

## Same-payload comparison with production

The identical SHA-pinned source was previously processed by `RCB_LIVE_DB`, Upload LogID `21153`.

| Environment | Total error rows | Period sequence | PaymentMethod >50 | PaymentChannel |
|---|---:|---:|---:|---:|
| `RCB_LIVE_DB` | 15,812 | 196 | 1,889 | 31 |
| `RCB_ISSUE_DB` | 15,790 | 13,870 | 1,889 | 31 |

Exactly 2,116 row/order error pairs overlap. The 1,889 PaymentMethod rows, 31 PaymentChannel rows,
and 196 production period-sequence rows are contained in that overlap. Production's remaining
13,696 errors are dominated by already-existing SAP state (`PolicyStatus is duplicated` and
`InvoiceNo cannot change when Paid/Cancelled`); UAT2 instead reports 13,674 additional sequence
errors. This is strong evidence that the period result is environment-state dependent.

## Decision boundary

- **High confidence:** the 1,889 PaymentMethod and 31 PaymentChannel failures are intrinsic file
  validation gaps and must be blocked/fixed before future delivery.
- **High confidence:** UAT2 period-sequence volume cannot be projected onto production or used to
  redesign the export; `RCB_ISSUE_DB` does not share production's prior-period SAP state.
- **Critical:** `success with error` is only an outer status. Row-level result ingestion remains the
  source of truth for completeness.
- Do not replay this July file automatically. Resolve/reconcile at row grain and respect the July
  manual-close boundary.

## Smallest durable controls

1. Add a pre-export `LENGTH(PaymentMethod) <= 50` block and report rejected rows separately.
2. Validate PaymentMethod/PaymentChannel against the exact successful SAP mapping inventory; do
   not truncate or invent replacements.
3. Treat period-sequence validation as target-environment stateful: validate against the same SAP
   environment that will receive the file, including all prior periods.
4. Ingest every result workbook/log by source hash + environment + Upload LogID and conserve
   `accepted + rejected + unresolved = delivered` at row grain.
