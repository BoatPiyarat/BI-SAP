# Legacy SAP interface export path — factual inventory

Evidence timestamp: deployed-function logs from `2026-07-30T18:30:05Z` through
`2026-07-30T18:39:04Z`, function metadata read 2026-07-31, and live BigQuery
`INFORMATION_SCHEMA.COLUMNS` read 2026-07-31. No object was changed.

## Actual producers and source views

The live scheduled path is Pub/Sub → two Gen-1 Cloud Functions with entry point
`extract_and_store` → `gs://interface-file/{RCB_MOTOR,RCB_NONMOTOR}/`. The deployed 30-Jul logs
show each SQL filename and the corresponding successful GCS write:

| Function/folder | Step | `sap_view` source |
|---|---:|---|
| Motor / `RCB_MOTOR` | 01 | `RCB_Motor_process_create` |
| | 02 | `RCB_Motor_process_2_cancel_new` |
| | 03 | `RCB_Motor_process_3_change` |
| | 04 | `RCB_Motor_process_4_creditshell` |
| | 05 | `RCL_Motor_process_1_create` |
| | 06 | `RCL_Motor_process_2_newpayment` |
| | 07 | `RCL_Motor_process_3_cancel` |
| | 08 | `RCL_Motor_process_4_creditshell` |
| NonMotor / `RCB_NONMOTOR` | 01 | `RCB_NonMotor_process_1_create` |
| | 02 | `RCB_NonMotor_process_2_cancel` |
| | 03 | `RCL_NonMotor_process_1_create` |
| | 04 | `RCL_NonMotor_process_2_newpayment` |

This supersedes older documentation that described only six Motor steps: deployed version 436
ran all eight. All 12 files logged successful writes on 30-Jul. Both invocations subsequently
reported failure while sending SMTP notification; that final function status does not negate the
preceding GCS-write success.

No recent ADB producer execution was present in the inspected 24–31 Jul logs, so this report does
not claim an additional current `sap_view` consumer for ADB.

## Positional CSV contract

All 12 watched views have the same 56 column names and ordinal positions. The representative live
contract is:

```text
01 CompanyDB                 15 PolicyType               29 ProcessingFee
02 OrderID                   16 Endorse                 30 ProcessingFeeVat
03 OrderItem                 17 PolicyDate              31 ShippingFee
04 InvoiceNo                 18 PolicyNo                32 ShippingFeeVat
05 OrderDate                 19 EndorsementNo           33 TotalAmount
06 InsuredID                 20 ChassisNo               34 Discount
07 Title                     21 LicensePlate            35 TransactionStatus
08 FirstName                 22 GrossPremium            36 SubmissionStatus
09 LastName                  23 StampDuty               37 ApprovalStatus
10 InsurerCode               24 VAT                     38 PaymentStatus
11 InsuranceGroup            25 TotalPremium            39 ExpectedReceived
12 InsuranceType             26 WHT                     40 ActualReceived
13 InsuranceProduct          27 TotalEIR                41 InterestThisPeriod
14 ProductType               28 TotalSBT                42 PrincipleThisPeriod
43 InterestEIRThisPeriod     48 PendingPayment          53 RefundAmountBeforeFee
44 PrincipleEIRThisPeriod    49 PaymentMethod           54 RefundAmountAfterFee
45 PaymentDate               50 PaymentChannel          55 BillingAddress
46 Period                    51 ExpectedDate             56 BatchRunDate
47 TotalPeriods              52 RefOrder
```

The currently deployed `expected_state` has 12 columns in this order:
`order_item, order_id, period, total_periods, flow, payment_option, expected_status,
expected_invoice_no, expected_payment_date, charge_id, charge_amount, computed_at`.
Reviewed source 037 will add `payment_date_clamped` and `old_year_rescued`.

Therefore `expected_state` is not an interface-contract-shaped table:

- only seven fields have direct name/meaning counterparts: OrderID, OrderItem, InvoiceNo,
  TransactionStatus, PaymentDate, Period, and TotalPeriods;
- `charge_amount` may supply ActualReceived only after explicit transformation; it is not the
  56-column contract by itself;
- the remaining identity, customer, insurance, premium, accounting, payment-channel, refund,
  address, and BatchRunDate fields are absent;
- `flow`, `payment_option`, `charge_id`, `computed_at`, `payment_date_clamped`, and
  `old_year_rescued` are internal/audit fields not present in the SAP CSV;
- even counterpart fields are in different ordinal positions. A direct `SELECT *` from
  `expected_state` cannot satisfy the positional SAP contract.

## ImportType and the (ก)/(ค)/(ง) populations

The only ImportType value confirmed by actual SAP success evidence is `INSURANCE_RCB`. The process
labels `CREATE`, `CANCEL_NEW`, `CHANGE`, `CREDITSHELL`, `NEWPAYMENT`, and `CANCEL` occur in file
names/steps; the evidence does not show them as separate SAP `ImportType` values.

The live producer creates 12 process files per complete daily cycle: eight Motor and four
NonMotor. Of those, six are create/payment-relevant templates: four CREATE files (RCB/RCL ×
Motor/NonMotor) and two RCL NEWPAYMENT files (Motor/NonMotor).

Groups (ก), (ค), and (ง) are analytical populations, not existing ImportType or filename values.
The current `expected_state` does not contain enough product/insurance columns to assign each row
to one of the six templates, and group (ค) itself contains both never-in-SAP and pending-in-SAP
rows. Consequently the exact number of occupied output files for those groups is **not established
by the current files**; claiming “three files” or another exact number would be a design inference.
No routing design is proposed in this finding.
