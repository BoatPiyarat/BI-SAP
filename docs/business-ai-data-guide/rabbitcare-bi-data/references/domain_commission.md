# Domain: commission & incentive — how "sales" is counted for pay

🚫 **Never compute anyone's payout or tier.** Payout is produced by BI's commission engine and
confirmed on the /commission portal. Use this file to **explain** why a commission number differs
from a sales number, and to route questions. Rate tables live in the signed scheme memos (not here).

Status as of 2026-11-25. Rules change often — if a user cites a newer announcement, it wins; tell
them to confirm with BI.

## Why commission "ยอดขาย" ≠ dashboard "ยอดขาย"

| | Dashboard / report sales | Commission sales (Motor) | Commission sales (NonMotor) |
|---|---|---|---|
| Amount | gross premium (or after discount) | **varies by team** (engine, M07 2026): Fresh tier on **net** premium; Database = rate × **net** (was invoiced before M07); Academy threshold on **gross**; weekly bonus uses invoice price after discount | **net premium after discount** ("เบี้ยหลังส่วนลด") |
| Which date puts it in the period | order created (usually) | **order created** 16th→15th (`DATE(create_time)`) **+ paid + QC-passed + submitted to insurer (แจ้งงาน) by ~16th**; not submitted → carries to the cycle it is submitted ("ยกยอด"). **Confirmed by BI Manager 2026-11-26** (supersedes the memo's "payment date" wording) | **paid** 16th→15th **and QC approved by the 18th** |
| Cancelled | depends on filter | item not cancelled; later cancellation = clawback next cycle | same; clawback rules below |
| Duplicates | none | **1 car (chassis) × 1 seller × 1 cycle counts once**, per Vol / CMI | **1 customer in the same coverage period counts once** |
| Installment | annual premium | first successful installment date | counted only when a payment is recorded; counts as annual premium |

Source: Motor scheme memo eff. 16 Mar 2026 (M03, CEO-approved) and "TSR Motor Commission Policy 2026" decks (Drive);
engine notes (Drive: Motor Commission PROJECT_KNOWLEDGE, M10 MASTER README, Nov 2026); BI emails 9–23 Nov 2026; live view
`motor_commission.paid_orders_for_weekly_bonus` (2026-11-25).

## Cycle & cut-offs

- Cycle **Mxx = 16th of previous month → 15th**, named by the month it ends (M11 2026 = 16 Oct–15 Nov 2026).
- Motor cut-off: sales window ends the 15th (engine comment: 18:00); submission checked to ~16th;
  **clawback cut-off 15th 10:00**, moved earlier when the 15th is a weekend (M11: Sat 14 Nov 10:00).
- NonMotor: QC cut-off **18th**.
- Review window ≈ 20th, final run ≈ 23rd, payroll files to HR ≈ 24th. After that, corrections go to next month.
- **Advance renewal**: paid + QC'd but cover starts **> 60 days** ahead (insurer won't accept
  submission yet) → may count in the paid cycle. Within 60 days and not submitted → next cycle.
- Voucher (VC) deductions: cycle of the **form-entry date** (rule 21 Nov 2026).

## Clawback (หักคืน)

- **Motor**: policy cancelled within **6 months** of effective date → clawed back by **OIC short-rate**,
  offset in the next cycle. (Observed engine data: clawback applied when OIC refund rate > ~30% — unverified.)
- **NonMotor**: by time to cancellation **0–3 m 70% · 4–6 m 45% · 7–9 m 20% · 10–12 m 5%**, pro-rata by cover days.
- **Repeat order / change order (ออเดอร์ซ้ำ), effective 20 Nov 2026 (NonMotor)**: new order counts in full,
  old order clawed back **100% plus any tier uplift** it caused — "ลูกค้า 1 คน ในช่วงคุ้มครองเดียวกัน นับยอดให้ 1 ครั้งเสมอ".
  Exceptions (days-based clawback only): plain cancel with no resale; or cancelled for non-payment and
  new cover starts after old cover ended. Platform-wide (Motor) adoption awaits COO approval.
- Closed-cycle tiers are **not** recalculated.

## Weekly bonus

- Weeks Mon–Sun inside the cycle; top 3 per SV team (Motor) / per branch (NonMotor DB) above a weekly threshold.
- **From M12 (16 Nov 2026)**: a sale paid in week N counts in week N if QC + submission complete by end of
  week N+1; ranks then lock ("อันดับชั่วคราว" → "อันดับยืนยันแล้ว"). Advance renewals count in the week the
  **order was created**.
- Paid weekly bonus is **never clawed back**. Exceptions (อนุโลม) count for commission only, not weekly.

Weekly thresholds (policy eff. 1 Apr 2026): Motor Fresh ฿100,000, Motor Database ฿40,000 per week; prizes
2,000/1,000/500 (Fresh) and 1,000/500/300 (Database). Base = paid premium of orders created and QC-passed.

## Other pay components (explain only)

- **Probation** = first 119 days; Fresh/Renew get the higher of the per-policy special rate or the tier.
- **On-Time Bonus** abolished for all TSRs from 1 Apr 2026; BackOffice still has a flat OTB (engine rule).
- **Licence incentive** ฿1,000/month with a valid broker licence registered under Rabbit Care Broker.
- **Refer incentive** ฿100 per referral pair (Refer-Renew form), paid to the referrer; new order must be lead type
  NEW, QC-passed, not cancelled, not CMI-only.
- **Exclusion flags** in the Motor engine (meaning to confirm with BI): Type 3 premium < ฿600, short-term, special programs.
- Pay conditions: employed on pay date, no disciplinary investigation, confirmed premium only; clawback allowed
  after payout for cancellation/refund or falsified data.

## CI (installment collection) commission

- Qualifying window = customer pays **8–10 days after the installment due date** (confirmed by BI Manager 2026-11-26;
  changed from the earlier 4–9-day window because the cancellation timeline process changed), with a follow-up call after
  the due date and before payment. Cycle uses due dates of the previous 16th→15th window.

## Supervisor metrics

SV commission = % of team's **paid premium net of cancellations** in the cycle (policy 2026: Fresh 0.30%, Renew 0.12%,
Database 1.00%; Inbound SV = 0.5 × lowest TSR commission in team; Academy SV fixed per TSR transferred); team = assignment at
the cycle snapshot (transfers/resignations handled per cycle).

## Open / unstable (say so if asked)

- New-hire Fresh scheme (hires from 16 Sep 2026) pending COO approval; M11 paid on old method.
- Self/family purchases counting toward tier — no rule yet (decision due ~27 Nov 2026).
- Unapproved proposals (e.g. Jun-2026 Health / Renewal Health / Top-Up tier drafts) are **not** a source — the commission
  engine documentation in OneDrive is the reference (BI Manager decision 2026-11-26).
- "Database tier" means different tables in Motor (4–8% of paid premium) vs NonMotor (3–15% of net premium).

## Where the data is

`motor_commission` dataset is the engine (governed; do not self-serve). For "why is my number X",
direct users to the /commission portal (synced daily ~03:00) or BI.
