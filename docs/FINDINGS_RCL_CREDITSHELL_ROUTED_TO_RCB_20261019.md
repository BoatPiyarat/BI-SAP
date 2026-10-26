# FINDINGS — 10 RCL CreditShell orders booked at RAB but not at RCL (2026-10-19)

Status: READ-ONLY INVESTIGATION. No view replaced, no file sent, no SAP write.
Reported by: accounting (Mo, via Boat). The 10 orders below are from batch 14 Oct and are Paid in SAP RAB with
`RCL-Credit Shell`, but have no RCL accounting:
L81019162 L81021191 L81025264 L81025633 L81025701 L81025704 L81025975 L81027931 L81027939 L81028493.

## Root cause (verified in SAP)

The 15 Oct 02:30 SAP import of batch `20261014` stopped partway through. `RCB_LIVE_DB.[@TMPUPLOADLOG]`:

| Code | File | UploadedDate | U_InterfaceProcess |
|---|---|---|---|
| 22964–22968 | Motor 01–05 (RCB create, cancel_new, change, creditshell; RCL create) | 02:43–03:04 | 9 / 1 (complete) |
| **22969** | **06 RCL_MOTOR_PROCESS_2_NEWPAYMENT_20261014** | **NULL** | **8 (stopped)** |
| 22970–22974 | 07 RCL cancel, **08 RCL creditshell**, NonMotor 01–03 | NULL | 0 (never processed) |

Every other night in 13–16 Oct processed all 11 files to stage 9.

During that window, `RCB_LIVE_DB.[@INSURANCE]` created exactly **88 rows / 10 items at 03:08** on 15 Oct. These are the
10 reported orders (InvoiceNo `2_chrg_*`, Period 1 Paid `RCL-Credit Shell`, full spine), and they match the
88 rows in BigQuery `SAP_LIVE_FULL`. No other rows were created between 03:04 and 04:00. The rows carry no
file reference, so attributing them to import 22969 is an inference from timing.

The import created the RAB side: one JE per order, TransType 30, Dr `9001-13 Contra Account - AR
RCL_Motor` / Cr `2121-02 AP Trade`, LineMemo `<item>_<insurer>_#1`. It never reached the RCL side:
`RCL_LIVE_DB.[@INSURANCE]` has 0 rows and RCL `OJDT/JDT1` has 0 JEs for all 10. By comparison, the
same night's completed files were replicated to `RCL_LIVE_DB` (1,175 rows at 02:5x; 28 NonMotor CreditShell
rows at 02:48 from step 04).

The rows are now in the SAP mirror, so the next nights' views drop them (`NOT EXISTS SAP_LIVE_FULL`).
They were never re-sent, which is why the gap persisted.

## Population check (JE level)

`scripts/adhoc_rcl_creditshell_je_check_20261019.py` checks OJDT/JDT1 in all 6 company DBs. It ran against
the 205 RCL installment CreditShell items whose first SAP batch was 15 Sep–16 Oct
(`docs/evidence/rcl_creditshell_routed_to_rcb_20261019/je_status_205_items.csv`):

| RCL JE | RAB JE | Items | CreditShell paid THB |
|---|---|---:|---:|
| yes | yes | 189 | 383,168.97 |
| yes | no | 6 | 15,520.56 |
| **no** | yes | **10** | **19,608.14** |

The only items without an RCL JE are the 10 reported orders, all from batch 14 Oct. The other 3 items from that batch
(NonMotor `-1`, created 02:48 by completed step 04) have RCL JEs. Control check: 8 random RCL CreditShell
orders from 1–13 Sep each have 2–5 RCL JEs, so the search method does find RCL entries.
The 6 "RCL yes / RAB no" items have not been investigated.

## Correction of the earlier draft (same day)

An earlier version of this file blamed the 2026-09-14 console overwrite of
`sap_view.RCB_Motor_process_4_creditshell` (it now reads `RCL 04_new order credit shell`; Cloud Audit
Log, piyaratt@, 11:02 UTC). The JE check **disproves that as the cause of the RCL gap**. SAP routes RCL rows
into `RCL_LIVE_DB` by content even when they arrive in the RCB 04 file, and 189 of 205 post-swap items have
RCL JEs. The overwrite is still a real defect on the RCB side. The correct 31 Aug body
(`04_new order credit shell`) would emit 185 RCB one-time CreditShell new orders (FULL_PAYMENT 180 /
CREDIT_CARD_INSTALLMENT 5, about ฿2.06M) that are not in SAP. 4_creditshell is the step that creates the new
order (3_change cancels the old one), so those orders have had no create path since 14 Sep. Evidence:
`audit_rcb.json`, `rcb_view_2026-08-31.sql`, `rcb_view_2026-09-14.sql`.

## Proposed remediation (needs a decision)

1. The 10 orders: ask SAP/IT to resume or reprocess upload 22969 for the RCL side, or post the RCL entries
   another way they approve. Sending a new file risks duplicate RAB rows and JEs, because the rows already exist in
   `RCB_LIVE_DB`.
2. Ask SAP/IT why 22969 stopped at stage 8 and why 22970–22974 were never processed. Check whether any
   other rows from files 06–08 or NonMotor 01–03 of batch 20261014 were lost, rather than re-emitted the next night.
3. Add a daily check: alert when any `[@TMPUPLOADLOG]` row has `U_UploadedDate IS NULL` or
   `U_InterfaceProcess` < 9 after the run window.
4. Separately: restore `RCB_Motor_process_4_creditshell` to the RCB source with the refund guard and a
   `RABBIT_CARE_INSTALLMENT` exclusion, and recover the 185 RCB new orders.
