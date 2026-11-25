# FINDINGS: SAP import errors, legacy batch of 2026-11-25 01:30 ICT (files dated _20261124)

* Source: SAP result emails from `rcare_sap_b1@rabbitcare.com` (Gmail), import `.txt` logs and
  error `.xlsx` files, read 2026-11-25 ~16:00 ICT.
* Status: read-only analysis, no fixes made. Class B (findings).
* Customer PII is not copied here.

## Summary per file
| # | file | LogID | status | rejected rows | main reasons |
|---|---|---|---|---|---|
| 01 | RCB_MOTOR_PROCESS_1_CREATE | 23759 | success with error | 10 | PolicyNo > 50 (7); InsurerCode not in DB (3) |
| 02 | RCB_MOTOR_PROCESS_2_CANCEL_NEW | 23760 | success | 0 | – |
| 03 | RCB_MOTOR_PROCESS_3_CHANGE | 23761 | success with error | ~80 | `PolicyStatus: is duplicated` (~70, already in SAP); PolicyNo > 50 (7, same orders as 01); InsurerCode (L79977888, L81209745) |
| 04 | RCB_MOTOR_PROCESS_4_CREDITSHELL | 23762 | success with error (0 JE) | 86 (10 orders) | ActualReceived empty on 62 Pending rows; L81175178 mixes RCL/RCB channels and has a raw `BANK_TRANSFER/SERVICE_PROVIDER_UNSPECIFIED` channel; Health rows in the Motor file |
| 05 | RCL_MOTOR_PROCESS_1_CREATE | 23763 | success with error | 14 | duplicated (3); L80312858 InsurerCode not in DB (11 rows) |
| 06 | RCL_MOTOR_PROCESS_2_NEWPAYMENT | 23764 | success with error | 4 | L80339419 `Sequence of Period invalid` |
| 07 | RCL_MOTOR_PROCESS_3_CANCEL | 23765 | **error** (whole file) | 112 | already Cancelled in SAP (67 rows / 10 orders); `Cannot change InvoiceNo when status Paid` (40 rows / 4 orders); cancel does not reach TotalPeriods (5 orders) |
| 08 | RCL_MOTOR_PROCESS_4_CREDITSHELL | 23766 | **error** (whole file) | 19 (10 orders) | ActualReceived empty; PaymentChannel raw `RCB` not in DB; already-in-SAP duplicates |
| NM01 | RCB_NONMOTOR_PROCESS_1_CREATE | 23767 | success | 0 | – |
| NM02 | RCB_NONMOTOR_PROCESS_2_CANCEL | – | success | 0 | – |
| NM03 | RCL_NONMOTOR_PROCESS_1_CREATE | 23768 | success with error | 19 (2 orders) | L80787073 and L79850962 mix RCL/RCB channels; one period has no PaymentMethod/Channel/Date |
| NM04 | RCL_NONMOTOR_PROCESS_2_NEWPAYMENT | 23769 | success | 0 | – |

Manual file: `INSURANCE_RCB_02_MANUAL_CANCEL_L81095660_20261125` → LogID 23778, `success`.

## Order lists
### PolicyNo > 50 (01 and 03)
L78964002, L79035853, L79080734, L79106158, L79260030, L79402747, L81132503.
* This violates the confirmed rule (AGENT_RULES): PolicyNo > 50 = BLOCK before export.
* The legacy views still send these rows every night.

### InsurerCode not found (vendor and customer code missing in SAP)
L78989298, L80964850, L81209745 (01); L79977888 (03); L80312858 (05).
* SAP master data issue. FA/Aware must add the insurer vendor/customer codes.

### 07 RCL cancel
| group | orders |
|---|---|
| already Cancelled in SAP, re-sent | L78189504, L78359599, L78933150, L79034344, L79083983, L79175333, L79301190, L79411333, L81110863, L81165331 |
| InvoiceNo differs from the Paid InvoiceNo in SAP | L79536764, L79603084, L79865548, L79996868 |
| cancel does not cover the whole period spine | L77833033, L79890647, L80511750, L80513404, L80518454 |

* L78189504 and L78359599 have been waiting for Aware since 2 Nov (Teams).

### 04 RCB_MOTOR creditshell (`RCB_Motor_process_4_creditshell`, RCL installment credit shell)
L80996581, L81175178, L81218217, L81222771, L81230459, L81236516, L81237986, L81238659, L81239131, L81239914.

### 08 RCL_MOTOR creditshell
L81233748, L81234148, L81234360, L81236219, L81236553, L81236556, L81239024, L81241094, L81241160, L81241418.
* Rows carry raw CareOS `RCB` as PaymentChannel, so the channel is not mapped.

## Likely causes (INFERRED, not yet verified against view SQL)
1. **Idempotency gaps.** 03, 07 and 08 re-send items SAP already holds. SAP rejects them, which
   is noise, but whole-file errors (07, 08) also hide any genuinely new rows.
2. **Pending installment rows with empty ActualReceived** (04 and 08). SAP requires a value.
   Compare the Unit 5 rule: Pending may only leave PaymentDate empty.
3. **Unmapped raw CareOS enums** in credit-shell views: `RCB`, `BANK_TRANSFER/SERVICE_PROVIDER_UNSPECIFIED`.
4. **RCB/RCL mixing inside one order** (04 L81175178; NM03 L80787073, L79850962). This violates the
   2026-08-17 fail-closed rule.
5. **PolicyNo > 50 not blocked** pre-export.

## Next steps (not done; each fix is a production view change and needs Boat approval)
* FA/Aware:
  * add insurer codes for the 5 orders above;
  * decide the InvoiceNo mismatch for the 4 RCL cancel orders.
* BI:
  * add PolicyNo > 50 exclusion and the already-in-SAP filters to the 03, 07 and 08 views;
  * map or fail-close raw channels in the credit-shell views.
