# Legacy SAP interface export path — factual inventory

Evidence timestamp: deployed-function logs from `2026-07-30T18:30:05Z` through
`2026-07-30T18:39:04Z`, function metadata read 2026-07-31, and live BigQuery
`INFORMATION_SCHEMA.COLUMNS` read 2026-07-31. No object was changed.

## P0 finding: 028 omits data types and 22/56 positions have live type drift

`028_column_contract_guard.sql` intentionally checks column names and ordinal positions but not
data types; its documented rationale was that type checks would create more false positives than
useful signal. A 2026-07-31 live `INFORMATION_SCHEMA.COLUMNS` comparison of the four CREATE and two
RCL NEWPAYMENT views now proves real type drift at 22 of the 56 contract positions. All 22 are
money or quantity fields:

`GrossPremium`, `StampDuty`, `VAT`, `TotalPremium`, `WHT`, `TotalEIR`, `TotalSBT`,
`ProcessingFee`, `ProcessingFeeVat`, `ShippingFee`, `ShippingFeeVat`, `TotalAmount`, `Discount`,
`ExpectedReceived`, `ActualReceived`, `InterestThisPeriod`, `PrincipleThisPeriod`,
`InterestEIRThisPeriod`, `PrincipleEIRThisPeriod`, `PendingPayment`, `RefundAmountBeforeFee`, and
`RefundAmountAfterFee`.

Positions 22–34 and 39–40 drift between `STRING` and `FLOAT64`; positions 41–44 and 48 drift
between `INT64` and `FLOAT64`; positions 53–54 appear as `STRING`, `INT64`, and `FLOAT64` across
the six views. The current guard therefore passes a positional contract while leaving a real CSV
serialization risk undetected: quoting, decimal places, and scientific notation may differ by
view. This is a risk, not proof that a successfully imported file used any particular rendering;
the physical files and deployed serialization code are unavailable (ground-truth limits below).

After the 2026-08-03 close, add data-type comparison to the contract guard as **WARN**, not FAIL,
until each accepted coercion has an explicit contract. No guard or production object was changed
as part of this finding.

## G1/G2 ground-truth limits

An all-version recursive read of `gs://interface-file/` on 2026-07-31 found only three prefixes:
`ADB_MOTOR`, `RCB_MOTOR`, and `RCB_NONMOTOR`. Each contains only a zero-name folder placeholder;
no retained CSV or object version exists. Consequently the latest successful CREATE file cannot
be inspected for header presence, physical 56-versus-57 column count, quoting, decimal places, or
scientific notation. A fourth BU folder is **not evidenced** by the live bucket and must not be
invented.

The deployed writers are Gen-1 Python 3.12 Cloud Functions
`rcb-motor-order-payment-sap-bucket-1` version 436 and
`rcb-nonmotor-order-payment-sap-bucket-1` version 400, both with entry point
`extract_and_store`. Their metadata exposes only expired one-time `sourceUploadUrl` locations;
read-back returned HTTP 403, with no source archive/repository location. Repository search found
no deployed `main.py`, and a targeted 30-Jul log search found no explicit `to_csv`, `csv.writer`,
`extract_table`, `EXPORT DATA`, or `pandas` marker. The deployed serialization method is therefore
**unknown**. Parity between the legacy writer and BigQuery `EXPORT DATA` is not established and
remains a blocker for manual export logic.

## P0 D1/D2 membership diagnostic

Job `p0_d1_d2_view_membership_20260731_160300`, query timestamp
`2026-07-31 16:06:59 UTC`, compared the locked G1 populations at `(order_item, period)` grain with
the four CREATE and two RCL NEWPAYMENT views. Dry-run/processed bytes were 8,645,545,976; billed
bytes were 8,646,557,696 under the 21,474,836,480-byte ceiling.

| Population | Total records/orders | In relevant view | Not in relevant view |
|---|---:|---:|---:|
| (ก) | 2,404 / 1,787 | 1,502 / 1,090 | 902 / 697 (THB 4,051,711.04) |
| (ง) | 2,996 / 2,983 | 2,670 / 2,658 | 326 / 325 (THB 640,290.79) |

(ก) membership by view: RCB Motor 1,470 records; RCB NonMotor 14; RCL NonMotor 18; RCL Motor 0.
(ง) membership by view: RCL Motor 2,663 records and RCL NonMotor 296. These per-view counts overlap;
their unique union is 2,670, so they must not be added.

Conclusion is mixed, not a single-side diagnosis. The 902 (ก) and 326 (ง) records absent from all
relevant views are filtered on the BI/view side. For the 1,502 (ก) and 2,670 (ง) records present in
the current views, present-day membership does not prove they were rows in the 30-Jul CSV. The live
bucket retains only folder placeholders, even with version listing, so D3 row-level file evidence
is unavailable. Those rows cannot yet be classified as SAP pickup/rejection versus timing/view
drift.

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

The six CREATE/NEWPAYMENT views explicitly requested for RULE-10 each returned `column_count=56`
and `keys_columns=0`. Thus `keys` is not a projected view column. Because no successfully imported
CSV is retained, its absence from the physical SAP-consumed header remains unverified rather than
inferred from metadata.

The relevant production bucket folders confirmed by deployed logs and GCS listing are
`RCB_MOTOR` and `RCB_NONMOTOR`.

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

## RULE-10 and BatchRunDate

Boat locked the July close delivery as manual CSV sourced from V3, without modifying legacy views
or cutting V3 into the nightly path. Export SQL remains prohibited until the physical-file contract
gate clears. Legacy views derive `BatchRunDate` from the execution date with
`FORMAT_DATE('%d%m%Y', CURRENT_DATE())`; RULE-02 deliberately requires
`FORMAT_DATE('%d%m%Y', LAST_DAY(open_period_start))`, which is `31072026` for this close. That is an
intentional accounting-period deviation, not a legacy-parity bug.
