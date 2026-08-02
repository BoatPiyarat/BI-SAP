# LIVE import result — Upload LogID 21153 (2026-08-02)

Status: AUTHORITATIVE for this delivery. UAT2 evidence is explicitly excluded.

## Scope and provenance

- Environment: `RCB_LIVE_DB`
- ImportType: `INSURANCE_RCB`
- Upload LogID: `21153`
- Outer status: `success with error`
- Source: 30,245 data rows, exactly 56 interface columns.
- Source SHA-256: `2B169DF976D04E9979C954394D2C4F6E0EB3151F246969C88CCAEB53CCBF1863`
- LIVE log SHA-256: `6955CF639368AAC0EEBEBCB09E5CE85068C7747ACCD23001F5009BA7BA542B00`
- LIVE error workbook SHA-256: `E946EBA6D9FF52C4E1E5AB7A0579F74A55D2D4B4692ED3BCB82BF9867DF246E3`

No OrderID or customer data is copied into this document.

## Row-level result

| Result | Rows | Share of input |
|---|---:|---:|
| Rows with an error entry | 15,812 | 52.280% |
| Rows without an error entry | 14,433 | 47.720% |

The errors affect 11,742 distinct orders. `14,433` means only that no row-level error was listed;
outer status and accounting reference counts are not a substitute for SAP row verification.

## Exact exclusive error shapes

| Error template | Rows |
|---|---:|
| PolicyStatus duplicated | 7,586 |
| InvoiceNo cannot change when Paid/Cancelled | 6,073 |
| PaymentMethod >50 + InvoiceNo cannot change | 1,884 |
| Period sequence invalid | 195 |
| PolicyStatus duplicated + existing SAP Cancelled cannot interface | 37 |
| PaymentChannel missing/account required + InvoiceNo cannot change | 31 |
| PaymentMethod >50 only | 4 |
| Period sequence invalid + InvoiceNo cannot change | 1 |
| PaymentMethod >50 + InvoiceNo cannot change (same semantic shape, punctuation variant) | 1 |

These exclusive rows sum to 15,812.

## Atomic validation counts

One row may violate several rules. Atomic counts therefore **must not be summed** as a population.

| Atomic rule | Rows |
|---|---:|
| InvoiceNo change forbidden for Paid/Cancelled | 7,990 |
| PolicyStatus duplicated | 7,623 |
| PaymentMethod longer than 50 | 1,889 |
| Period sequence invalid | 196 |
| Existing SAP Cancelled cannot interface | 37 |
| PaymentChannel not in DB | 31 |
| PaymentChannel account code required | 31 |

## Interpretation and controls

1. The outer `success with error` status is not completeness evidence. Use row-level ACK/result.
2. `InvoiceNo`/status errors require current-SAP-state delta logic: do not resend immutable Paid or
   Cancelled fields. Paid must precede its own cancel/change, and cancel/change must target an
   existing SAP row.
3. Block PaymentMethod values longer than 50 before delivery; never truncate. Resolve them through
   the exact mapping inventory already accepted by LIVE SAP.
4. Block and report PaymentChannel values absent from LIVE SAP's mapping/account-code inventory;
   do not invent a value.
5. Route the 196 period-sequence rows to the missing-history/incomplete-installment investigation.
6. Preserve `accepted + rejected + unresolved = delivered` at source-row grain, keyed by source
   hash, environment, Upload LogID, and SAP Row#.

This finding does not authorize replay, export, bucket write, or SAP mutation.
