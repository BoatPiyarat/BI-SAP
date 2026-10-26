# Findings — August 2026 Health payments exported as BAY

Date: 2026-09-07 (ICT)  
Scope: read-only root-cause investigation; no view replacement, deploy, SAP correction, or re-interface.

## Conclusion

The reported defect is on the **legacy NonMotor V2 interface path**. The payment was not incorrectly
typed in the raw CareOS charge: the affected charges were successful `QR_CODE` payments through
`RABBIT_LENDING`, and the associated order items were `products/health-insurance`. The defect was
the precedence of the legacy payment-channel mapping: the generic RCL/BAY mapping was applied
without first preserving the Health product classification.

The active source chain is:

`careos.carepay_charges` + `careos.careos_order_items`
→ `sap_data_engineer.RCL_HEALTH`
→ `sap_view.RCL_NonMotor_process_2_newpayment`
→ legacy Gen-1 `rcb-nonmotor-order-payment-sap-bucket-1`
→ SAP / `sap_integration_v2.SAP_LIVE_FULL` mirror.

This is not the Motor path. Although `sap_dashboard_carepay_installment` contains a similar
Health-before-BAY mapping today, it is not the upstream selected by the NonMotor new-payment view.
That view explicitly selects `sap_data_engineer.RCL_HEALTH`.

## Exact reported-list replay

The supplied list contained 149 distinct `(OrderID, Period)` pairs. Read-only job
`bqjob_r1ae3230f61059071_000001a07a0fef76_1` found all 149 in `SAP_LIVE_FULL`:

| Classification | Pairs |
|---|---:|
| SAP row has incorrect `RCL-Omise QR Prompt Pay-BAY` | 145 |
| Current `RCL_HEALTH` returns correct `RCL-Omise QR Prompt Pay-Health` | 144 |
| Not the BAY defect | 4 |
| Missing from SAP | 0 |

The four non-BAY pairs are separate scenarios:

| Order / period | SAP payment channel | Current classification |
|---|---|---|
| `L79143469 / 9` | `RCL-Direct Debit` | `RCL-Direct Debit-Health` |
| `L80552297 / 1` | `RCL-Credit Shell` | not emitted by current `RCL_HEALTH` |
| `L80637895 / 1` | `RCL-Credit Shell` | not emitted by current `RCL_HEALTH` |
| `L80682561 / 1` | `RCL-Credit Shell` | not emitted by current `RCL_HEALTH` |

`L79502560 / 8` is one of the 145 confirmed historical BAY rows but is not emitted by the current
`RCL_HEALTH` result. The raw-charge trace still classified its historical payment as successful
Health + QR + `RABBIT_LENDING`; therefore it belongs to the historical defect population, but it
is not a current-output validation case.

## Broader production evidence

Read-only job `bqjob_rb9c404df6c79c2b_000001a07a07081d_1` found 232 Health/BAY SAP rows for
August 2026 payment dates. All 232 had SAP update dates from 2026-08-27 through 2026-09-01; 225
now resolve to Health in current `RCL_HEALTH`, while zero resolve from the installment dashboard.

An all-history extension, job `bqjob_r1a01f7da5ca4b715_000001a07a5e6a3c_1`, found 585 distinct
Health/BAY Order/Period pairs in `SAP_LIVE_FULL`. The reported list overlaps 145 of those pairs,
leaving 440 additional pairs across 431 orders:

| Payment month | Additional pairs outside Mo's list |
|---|---:|
| 2026-01 | 4 |
| 2026-07 | 349 |
| 2026-08 | 87 |
| **Total** | **440** |

For the August incident specifically, the complete population is therefore 232 pairs: 145 from
the reported list plus 87 additional pairs. The last affected PaymentDate is 2026-08-31, the last
BatchRunDate is 2026-08-31, and the last SAP mirror UpdateDate is 2026-09-01. No matching
Health/BAY PaymentDate later than 2026-08-31 was found.

Raw trace job `bqjob_r4a8125f7687a6083_000001a07a0c21f1_1` matched all 232 rows to the exact charge:
232/232 were `SUCCESSFUL`, `QR_CODE`, `RABBIT_LENDING`, and 232/232 order items were
`products/health-insurance`. This proves that product-aware mapping, not the gateway value alone,
must decide the SAP channel.

## Why the 06-Aug statement did not protect late-August imports

The 2026-08-06 repository finding explicitly recorded that its fix was drafted in the repo only,
not live-verified and not deployed. Job history shows a Health-aware replacement of
`sap_dashboard_carepay_installment` on 2026-08-25 15:33 ICT, but that object is not the legacy
NonMotor new-payment source. Replacement events for the relevant `RCL_HEALTH` object occurred on
2026-09-01 around 21:30 ICT, and the live definition now has the correct Health-specific branch.

Therefore the late-August rows are consistent with the relevant production source remaining
unprotected after the 06-Aug repo-only edit. This also explains why rows with posting/payment dates
24–25 Aug were imported with a 27-Aug batch date and the wrong BAY label.

## Current state and disposition

The live `RCL_HEALTH` definition now evaluates the Health-specific case before passthrough:

```sql
WHEN PaymentMethod = 'QR_CODE'
 AND PaymentChannel = 'RABBIT_LENDING'
 AND InsuranceGroup = 'products/health-insurance'
THEN 'RCL-Omise QR Prompt Pay-Health'
```

The current source is therefore correct for future matching Health QR rows. No new legacy SQL fix
is proposed in this investigation. The 145 wrong values already stored in SAP are historical and
will not self-correct merely because the view is now correct; correcting or re-interfacing them is
a separate operation and was intentionally not performed.

## Reproducible read-only queries

- `sql/adhoc/20260907_verify_reported_149_health_bay_pairs.sql`
- `sql/adhoc/20260907_repro_health_bay_august_sap.sql`
- `sql/adhoc/20260907_trace_health_bay_raw_charge.sql`
- `sql/adhoc/20260907_trace_health_channel_view_deploy_history.sql`
