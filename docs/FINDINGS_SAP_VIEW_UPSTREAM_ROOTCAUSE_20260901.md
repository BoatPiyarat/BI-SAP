# SAP view upstream root-cause audit — 2026-09-01

Status: SOURCE-ONLY; no deploy, GCS, Scheduler, SAP import, or production mutation.

## 2026-09-07 superseding RCL CreditShell payload addendum

The earlier RCL CreditShell row-conservation result did not test item-master completeness or exact
full-row duplicates. A new red-capable audit found 4,152 item-less Period-1 rows, 912 Health rows
with NULL InsuranceType, 758 paid rows with blank raw third-party InvoiceNo, flattened historical
PaymentDates, and 6,579 exact duplicate groups. The full proposal at the same path now additionally
requires a real active item, normalizes Health/TA labels, maps PaymentDate and InvoiceNo from the
period's successful charge (using the established rank/item fallback when needed), and removes
only exact rows before preserving repeated-period payments.

Final shadow `bqjob_r4b4081c856081a43_000001a07a020140_1` is GREEN at 43,041 rows / 12,248 items;
all reported master, finance, invoice, date, pending identity, period-spine, and exact-duplicate
violations are zero. The 6,943 remaining duplicate-period keys are distinct payment rows and have
zero repeated positive ExpectedReceived. The prior proposal hash and 59,970-row shadow are
historical and superseded by SHA-256
`51636A118D47ED6B68D430AD0678D7A43580B2AADE775D71F89AA9CFE2B422DD`.

## Progress

- ✅ Dependency map for the legacy `sap_view` payload views
- ✅ Confirmed NonMotor status root cause in `sap_data_engineer.RCL_HEALTH`
- ✅ Full live-derived source proposal prepared and dry-run
- ✅ Shadow validation for `RCL_NonMotor_process_1_create` and the health branch of
  `RCL_NonMotor_process_2_newpayment`
- ✅ Full live-derived root-fix proposal and shadow validation for
  `sap_integration_v2.RCL 04_new order credit shell`
- ✅ Full source-only root-fix proposal and shadow validation for
  `sap_view.RCB_Motor_process_2_cancel_new`
- ✅ Snapshot audit and full source-only routing fix for
  `sap_integration_v2.04_new order credit shell`
- ✅ Full source-only routing/cancellation fix for
  `sap_view.RCL_Motor_process_2_newpayment`
- ✅ `sap_view.RCB_Motor_process_create` and fully-paid upstream audited GREEN; no change
- ⚠️ Three historical pending/payment-field rows remain in the `SAP_LIVE_FULL` branch; a source
  fix cannot rewrite rows already present in SAP

## Confirmed root cause: `RCL_HEALTH` status precedence

`RCL_HEALTH` sourced `TransactionStatus` from `follow_ups.status`, while ActualReceived,
PaymentMethod, and PaymentChannel came from a matched successful RABBIT_LENDING charge. A stale
`FOLLOWUP_STATUS_PENDING` therefore mislabeled a successfully charged period as pending while
retaining its legitimate payment fields.

The correct legacy rule is surgical: successful charge truth wins; only a period without a
successful charge falls back to its follow-up status.

```sql
CASE
  WHEN charges.status = 'SUCCESSFUL' THEN 'SUCCESSFUL'
  ELSE follow_ups.status
END AS TransactionStatus
```

Do not deploy the previously proposed downstream workaround that blanked PaymentMethod and
PaymentChannel whenever the derived payload status was pending. The captured cases were paid in
raw charge truth; blanking their payment identity would conceal the wrong status rather than fix
it.

## Evidence

All timestamps below are UTC values returned by the queries; add seven hours for ICT.

| Evidence | Result |
|---|---|
| Captured-case replay, job `bqjob_r6c83e2f606784c92_000001a05d682000_1`, 2026-09-01 14:38:20 UTC | 3/3 payload-pending cases had one matching SUCCESSFUL RABBIT_LENDING charge and a pending follow-up; 0/3 lacked a successful charge |
| Newpayment origin split, job `bqjob_r3ae5a5b54d8ea3dd_000001a05d6910fb_1`, 2026-09-01 14:39:23 UTC | 84 pending/payment-field cases originated in `RCL_HEALTH`; 3 originated in historical `SAP_LIVE_FULL` rows |
| Health-branch raw-charge audit, job `bqjob_r2f3de51cb27dbb9c_000001a05d6a2049_1`, 2026-09-01 14:40:32 UTC | 84/84 violation keys had a matching successful charge; 0 had only pending/failed charges; 0 had no charge |
| Full proposal dry-run | 1,825,899,939 bytes (~1.701 GiB), below the mandatory 20 GiB ceiling |
| Combined shadow, job `bqjob_r7c99745ea9ded918_000001a05d76b1b8_1`, 2026-09-01 14:54:16 UTC | `RCL_HEALTH` 38,568→38,568 rows; pending-with-payment-fields 3→0; paid 18,545→18,548 |
| Downstream shadow from the same job | Process 1 create 245→245 rows and 0 violations; Process 2 health branch 503 rows and 0 violations; SAP-history branch 504 rows with 3 historical violations retained |

Counts are point-in-time because all objects are dynamic views. The captured-case replay is kept
as the stable reproduction evidence for the transient follow-up/charge disagreement.

## Source artifact

`sql/production/RCL_HEALTH_status_precedence_fix_20260901.sql`

- Captured live definition last modified: 2026-08-29 02:21:39 UTC
- Captured live query SHA-256: `0f41e474e2ffeadbe3b8c11087af7763cd732823ffde6604227ec8658f358606`
- Proposal file SHA-256: `5ccde3f6329a966017a2a550e4e78c68dbee5529a0b2b8f5ab25fa66ec79f03c`
- Exact normalized comparison: every live query byte is preserved except the one status expression
  and its explanatory root-fix comment

The file is a full runnable SELECT, not `CREATE OR REPLACE VIEW`. Repository policy currently
forbids replacement of `sap_data_engineer.RCL_HEALTH`; deployment requires a newer scoped Boat
legacy exception, Class-A PASS on the exact artifact, and separate explicit deploy approval.

## Confirmed root fix: `RCL 04_new order credit shell`

The live upstream joined every matching row from `carepay_transaction_snapshots`. Multiple
snapshots for one transaction could therefore fan out the order, and an incomplete snapshot could
shape the period result. The legacy-compatible fix selects the latest snapshot per transaction by
`update_time DESC, id DESC`, requires `number_of_installment >= 1`, and retains every legitimate
same-period payment row.

For duplicate business payments in the same `OrderItem`/`Period`, the first deterministic row keeps
`ExpectedReceived`; subsequent rows keep their ActualReceived/payment identity but set
`ExpectedReceived = 0`. Paid rows rank first, followed by PaymentDate, InvoiceNo, and a stable row
fingerprint. This prevents expected premium from being counted twice without deduplicating real
additional payments.

### CreditShell evidence

| Evidence | Result |
|---|---|
| Full proposal dry-run | 9,183,487,742 bytes (~8.553 GiB), below the mandatory 20 GiB ceiling |
| Combined shadow, job `bqjob_r5cf88def06688941_000001a05ff163dd_1`, 2026-09-02 02:27:31 UTC | Upstream parity: 59,970→59,970 rows, 12,191→12,191 items; invalid period rows 0→0 |
| Exact downstream legacy-wrapper replay from the same job | 70→70 rows, 8→8 items; duplicate-period keys preserved at 4; repeated-Expected keys 0; pending payment-field violations 0; incomplete distinct spines 0 |

Source artifact: `sql/production/RCL_04_new_order_credit_shell_rootfix_20260901.sql`

- Captured live definition last modified: 2026-08-23 14:47:19 UTC
- Captured live query SHA-256: `1266758867acc03c48c11fa2486b680eddf32bda7b4e0dd4fbcd0de66a032dba`
- Proposal file SHA-256: `c8935ffb1f897a3cf21fc57e71f0633107a6af9d1810d983c1bcff31d7eed40a`
- Full runnable SELECT only; no DDL and no production replacement

## Confirmed root fix: RCB `04_new order credit shell`

The suspected snapshot fan-out did not reproduce: 9,228 eligible transactions / 12,677 eligible
items had zero transactions or items with multiple snapshots and zero installment-version
conflicts. The current `sap_view.RCB_Motor_process_4_creditshell` output was also clean at one row,
one item, exact Period/TotalPeriods 1/1, and zero duplicate or pending-payment-field violations.

The real upstream defect was RCB/RCL routing. The upstream accepted every successful non-lending
charge and copied `charges.installment_number` to Period while hardcoding TotalPeriods=1. Eight
rows therefore appeared as period 2+ / TotalPeriods 1. Raw trace proved every one belonged to a
`RABBIT_CARE_INSTALLMENT` transaction with a six-installment snapshot. The surgical legacy fix is
to exclude that payment option from this RCB upstream; no snapshot change is proposed.

### RCB CreditShell evidence

| Evidence | Result |
|---|---|
| Downstream audit, job `bqjob_r40fafa4dd358b02d_000001a0610416ba_1` | 1 row / 1 item; exact duplicates, duplicate invoice-period keys, non-1/1 rows, NULL periods, and pending-field violations all 0 |
| Snapshot-seam audit, job `bqjob_r4ec8f92920516e08_000001a0610631e6_1` | 9,228 eligible transactions / 12,677 items; multi-snapshot transactions/items 0/0; installment conflicts 0 |
| Upstream output audit, job `bqjob_r6fda4ac013796d59_000001a06107bb53_1` | 14,813 rows / 12,443 items; 8 invalid non-1/1 rows; duplicate invoice-period keys 0 |
| Raw invalid-row trace, job `bqjob_r2009b9d782e299df_000001a06109cb33_1` | All invalid rows were `RABBIT_CARE_INSTALLMENT` with six-installment snapshots; all affected items already existed in SAP |
| Current payload control, job `bqjob_r261430c2f6443537_000001a0610b5e91_1` | The one exportable row is `FULL_PAYMENT`, snapshot 1, payload 1/1 |
| Full proposal dry-run | 11,549,245,062 bytes (~10.756 GiB), below the mandatory 20 GiB ceiling |
| Combined shadow, job `bqjob_r42a4d694bb4b9de3_000001a0610e1993_1`, 2026-09-02 07:38:29–07:38:50 UTC | Upstream 14,813→14,673 rows and 12,443→12,311 items; invalid non-1/1 rows 8→0; downstream conserved at 1 row / 1 item with new/missing items 0/0 |
| Removed-item coverage, job `bqjob_r5445ee0e7f297aa5_000001a0610fcaf7_1`, 2026-09-02 07:40:20–07:40:41 UTC | 132 removed RCL items; all 132 already in SAP, 86 also present in RCL CreditShell upstream, uncovered current items 0 |

Source artifact: `sql/production/RCB_04_new_order_credit_shell_routing_fix_20260902.sql`

- Captured live definition last modified: 2026-08-07 03:04:57 UTC
- Captured live query SHA-256: `fabe59ea688029899d69a1b90ecbdb280f4a7f1ae1634f9945303ac05ed29a3d`
- Proposal file SHA-256: `40534b810b1007b521bb7170b0601797d035e12e51c8945a6512d104369a6d08`
- Exact normalized comparison: live body preserved except one routing predicate and explanatory comment
- Full runnable SELECT only; downstream wrapper requires no change; no DDL or deployment

## Confirmed root fix: `RCB_Motor_process_2_cancel_new`

The six failing cancel items had two different causes. Four SAP histories contained only period 1
despite `TotalPeriods` 3, 6, or 10; the existing
`sap_data_engineer.sap_dashboard_carepay_installment` upstream still held their complete schedules.
Two other items contained the complete period set but mixed historical `TotalPeriods` 1 and 3.

The legacy-compatible proposal keeps `SAP_LIVE_FULL` authoritative for every period already in
SAP, supplements only SAP-missing periods from an existing complete installment schedule, and
canonicalizes `TotalPeriods` to the maximum SAP-proven schedule value per item. The fallback is
fail-closed: SAP history itself must contain `TotalPeriods > 1`, so seven RCB one-time controls whose
current installment upstream showed 6/10 periods remained exactly period 1 / TotalPeriods 1.
Legitimate duplicate-period payment rows remain; only exact full-row duplicates are removed.

### Cancel evidence

| Evidence | Result |
|---|---|
| Red-capable spine audit, job `bqjob_r374d78e658a61e25_000001a06023cc12_1` | Reproduced exactly 6 failures: four missing-last-period items and two TotalPeriods-conflict items |
| Six-item raw SAP trace, job `bqjob_r5470ac1e96fbde29_000001a060254bbb_1` | Four items truly had only period 1 in `SAP_LIVE_FULL`; two had historical TotalPeriods 1/3 mixtures |
| Installment-upstream trace, job `bqjob_r57a1c87e0823340e_000001a06027b740_1` | Existing upstream supplied exact complete schedules for all four missing-spine items |
| Over-broad negative-control shadow, job `bqjob_r640cee4ed56b2534_000001a0602dd6b4_1` | Rejected 445→525 result because it would also expand seven SAP-proven one-time items |
| Final proposal dry-run | 9,617,175,351 bytes (~8.957 GiB), below the mandatory 20 GiB ceiling |
| Final shadow, job `bqjob_r1be272cffb0d05ea_000001a06036fa8f_1`, 2026-09-02 03:43:31–03:51:47 UTC | Rows 445→470; items 123→123; incomplete spines 6→0; new/missing items 0/0; duplicate-period keys 5→5; exact full-row duplicates 0; all seven one-time controls stayed `{1}/1` |

Source artifact: `sql/production/RCB_Motor_process_2_cancel_new_rootfix_20260902.sql`

- Captured live definition last modified: 2026-07-24 18:53:33 UTC
- Captured live query SHA-256: `147b293e15f6b2f808c14dcd10d6e3b9b68249fd6d2c827e461e23adbcf448e4`
- Proposal file SHA-256: `51eb8c8176921b6700d17792ff9c018e8637592c5281c374973b7f5a218be2fc`
- Full runnable SELECT only; no DDL and no production replacement

## Confirmed root fix: `RCL_Motor_process_2_newpayment`

The live Motor wrapper used the shared `RCL 05_paid by period` gate without a Motor product
predicate. That gate contains NonMotor transactions, and the wrapper's final condition excluded
only `MOTOR_TYPE_COMPULSORY`; it therefore emitted 148 Health items / 557 rows into the Motor
interface.

A second mismatch produced partial Motor spines. `RCL 05_paid` excludes an entire item if SAP has
any Cancelled history, while `RCL 05_newpayment` can still emit the item's current schedule and
`RCL 05_paid by period` can still admit it. Six such Motor items appeared incomplete. CareOS proves
all six are cancelled; three more cancelled Motor items happened to have complete spines but also
belong outside new-payment. The scoped legacy fix applies the canonical cancellation gate in the
Motor wrapper and adds explicit product/InsuranceGroup routing. It does not synthesize historical
Paid rows for cancelled items.

### RCL Motor newpayment evidence

| Evidence | Result |
|---|---|
| Live red-capable audit, job `bqjob_r1778cf29a5f06fdd_000001a07c16d1b7_1` | 5,536 rows / 850 items; 154 incomplete/conflicting items; 20 legitimate duplicate-period keys; pending/payment-identity violations 0; exact duplicates 0 |
| Upstream trace, job `bqjob_r411b48ca08826da0_000001a07c1e5166_1` | 148 Health items / 557 rows; all 148 incomplete; six incomplete Motor items caused by Paid SAP rows excluded through the item-level cancelled gate |
| Gate coverage, job `bqjob_r328c691f7cb8ad63_000001a07c222de1_1` | 6,195 gate items; zero active 2026 Motor non-CMI items missing from live output; all six incomplete Motor items canonically cancelled in CareOS |
| Candidate dry-run | 9,723,126,906 bytes (~9.055 GiB), below the mandatory 20 GiB ceiling |
| Candidate shadow, job `bqjob_r4a9ccf3b252d64f0_000001a07c285c41_1` | GREEN: 4,932 rows / 693 items; incomplete spines 0; non-Motor rows 0; pending identity/date violations 0; paid blank invoices 0; RCB leakage 0; exact duplicates 0 |
| Duplicate-period preservation | 17 keys remain; every key has distinct nonblank InvoiceNo and at most one positive ExpectedReceived row |

Source artifact: `sql/production/RCL_Motor_process_2_newpayment_rootfix_20260907.sql`

- Captured live definition last modified: 2026-08-31 22:32:22 ICT
- Captured live query SHA-256: `126D8247922361EE3BC64B14B702AF1D152702DCE7C50912A9A2C5D6CC366A6A`
- Proposal file SHA-256: `91AA12A1EBC3AA9F4EDCAAE46DBD4987A0065CACA51BA05A006D86E4865FFB14`
- Full runnable SELECT only; no DDL and no production replacement

## Remaining upstream dispositions

| Downstream view | Upstream | Disposition |
|---|---|---|
| `RCL_NonMotor_process_1_create` | `RCL_HEALTH` | Fix upstream status precedence; do not apply the wrapper blanking proposal |
| `RCL_NonMotor_process_2_newpayment` | `RCL_HEALTH` + `SAP_LIVE_FULL` | Fix future health rows upstream; treat 3 SAP-history rows as separate remediation |
| `RCL_Motor_process_4_creditshell` | `RCL 04_new order credit shell` | Full source-only root fix validated: latest snapshot, complete period gate, duplicate ExpectedReceived protection; no deploy |
| `RCL_Motor_process_1_create` | `sap_dashboard_carepay_installment` | Current upstream already blanks payment fields when no successful charge; no fix proposed |
| `RCB_Motor_process_4_creditshell` | `04_new order credit shell` | Snapshot audit clean; full upstream routing fix validated to exclude `RABBIT_CARE_INSTALLMENT`; wrapper unchanged; no deploy |
| `RCB_Motor_process_2_cancel_new` | `SAP_LIVE_FULL` + `sap_dashboard_carepay_installment` | Full source-only root fix validated: SAP-authoritative rows, fail-closed missing-period supplement, canonical TotalPeriods; no deploy |
| `RCL_Motor_process_2_newpayment` | `RCL 05_paid` + `RCL 05_newpayment` + `RCL 05_paid by period` | Full source-only wrapper fix validated: Motor-only route plus canonical CareOS cancellation gate; no deploy |
| `RCB_Motor_process_create` | `sap_dashboard_carepay_fully_paid` + `SAP_LIVE_FULL` | Audited GREEN at 582 rows / 576 items; no routing, cancellation, period, duplicate, identity, or coverage defect; no change |
