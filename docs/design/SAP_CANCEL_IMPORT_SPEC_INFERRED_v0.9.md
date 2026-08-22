# SAP Import Validation Spec — CANCEL (Installment) — INFERRED v0.9
Status: DRAFT FOR VENDOR CONFIRMATION | Prepared by: BI (RabbitCare) | 2026-07-23
Evidence base: import logs 20884, 20888, 20908*, 20912 (22–23 Jul 2026)
(*log ids by filename timestamps)

Purpose: We reverse-engineered the validation rules of the RCB/RCL cancel import
from observed error responses. Please CONFIRM or CORRECT each rule below.
Reviewing this list should take ~15 minutes — no need to write documentation
from scratch.

---

## Inferred rules — please mark ✔ correct / ✘ wrong (+ correction)

**R1. Full-schedule requirement**
A cancel set for an installment order must cover ALL periods 1..TotalPeriods.
Evidence: `Period: Status Cancelled must be end to TotalPeriod(6)` (log 20888 Row#30)
[ ] confirm

**R2. One row per period**
Each period may appear exactly once in the cancel set. Duplicate periods →
`Period: Sequence of Period invalid`.
Evidence: log 20912 (file contained multiple docs per period → every row flagged)
[ ] confirm

**R3. InvoiceNo must match the stored value of the current document**
For rows whose stored status is Paid or Cancelled, the InvoiceNo in the file
must equal the stored InvoiceNo exactly, else
`InvoiceNo: Cannot change InvoiceNo when status Paid,Cancelled`.
[ ] confirm
**Q3a: When a period has MULTIPLE documents in SAP (e.g. an original Pending
schedule doc + a later Paid payment doc), which document's InvoiceNo must the
cancel row reference?** ← คำถามสำคัญสุด

**Q3a (added 2026-07-27, same question, a harder sub-case)**: some multi-document periods have
**no `BatchRunDate` at all** on any of their candidate documents — confirmed live, e.g. the 45-row
`SaleOrder` junk-label case and 442 of the 496 `Invoice` junk-label rows
(`docs/FINDINGS_SAP_MIRROR_20260726.md` §13) have `BatchRunDate = NULL`, and this isn't only a
junk-label phenomenon — any real multi-doc period could in principle have the same gap. When
**none** of the candidate documents have a date to order by at all, the current picking rule's
last tiebreak (`BatchRunDate DESC`, then `DocEntry DESC`) falls through to `DocEntry` alone. **What
should indicate which document is current when there is no date signal whatsoever?** (Options to
put to Aware: DocEntry as a proxy for creation order — already the de facto fallback; some other
SAP-side sequence/timestamp field not currently extracted; or treat undated multi-doc periods as
inherently unresolvable and route them to a human queue instead of auto-picking.)

**R4. Status precondition on other periods**
Cancelling requires every other period of the same order in DB to be in
status Paid or Pending:
`PolicyStatus: Cancelled order other period in DB must be Status Paid,Pending before`.
[ ] confirm
**Q4a: Which statuses block? (e.g. Overdue? partially-cancelled?)**

**R5. First-period precondition**
`PolicyStatus: Cancelled order first period in DB must be Status Paid before`
→ period 1 must be Paid before any cancel.
[ ] confirm

**R6. Already-cancelled orders reject re-interface**
`PolicyStatus: In DB Status Cancelled not allow to interface`.
[ ] confirm

**R7. Row grouping / atomicity**
Rows of the same OrderId are validated as one set (errors reference
`Ref.Row[N]`); one failing row rejects the entire order set, and the "anchor"
row N is reported.
[ ] confirm
**Q7a: Does row ORDER inside the file matter (must periods be ascending)?**

**CONFIRMED 2026-08-22 (Boat relaying Aware):** order rows by `Period` ascending within each
cancelled item (`1, 2, ... TotalPeriods`), and keep the complete spine for each `OrderItem`
contiguous before the next item begins.

**R8. InvoiceNo uniqueness within file**
`InvoiceNo: is duplicated` — the same InvoiceNo (including empty?) may not
appear on more than one row of the same import scope.
[ ] confirm
**Q8a: scope = per order, per file, or per DB?**
**Q8b: are EMPTY InvoiceNo values exempt for Pending periods?**

**CONFIRMED 2026-08-22 (Boat relaying Aware):** for a Pending SAP period, preserve the existing
SAP `InvoiceNo` verbatim. If the existing SAP value is blank, leave it blank. Do not generate or
substitute an InvoiceNo for the Pending period. Multiple Pending rows may each have blank
`InvoiceNo`; blank is the correct Pending representation and is exempt from nonblank uniqueness.

**R9. Balance check on cancel**
`FullPayment: Not balance transaction` also applies to cancel rows —
TotalAmount must equal component sum.
[ ] confirm

---

## Open questions beyond error evidence

**Q10.** Correct way to cancel an order where customer payments continued
after CareOS cancellation (periods Paid in SAP after cancel date): cancel all
periods as-is, or must a refund/credit memo flow precede?

**Q11.** For a cancel row on a Pending (unpaid) period: required values for
ActualReceived / PaymentDate / InvoiceNo (empty vs mirror)?

**CONFIRMED 2026-08-22 (Boat relaying Aware):** preserve the existing SAP `PaymentDate`
verbatim for a Pending period; if SAP has a blank value, leave it blank. Together with the Q8b
answer above, Pending `InvoiceNo` is also preserved verbatim, including blank. Preserve Pending
`ActualReceived` exactly when non-NULL; convert SQL NULL to numeric `0` because the interface must
not contain NULL. Preserve Pending `ExpectedReceived` exactly when non-NULL; convert SQL NULL to
numeric `0`.

Pending `ExpectedDate` must not be blank. Preserve the existing SAP value when present; otherwise
use the preserved `PaymentDate`; if that is also blank, use the cancellation file's `BatchRunDate`.
Pending `PaymentMethod` and `PaymentChannel` must be blank, regardless of the stored SAP values.
Pending `PendingPayment` preserves the existing SAP value exactly and may remain SQL NULL.

**CONFIRMED 2026-08-22 (Boat relaying Aware) — CareOS payment precondition:** before cancellation,
reconcile every SAP Pending period against CareOS. If CareOS shows that period was actually paid,
complete the Paid transaction in SAP before cancelling it. A stale SAP Pending status must never
be carried directly into the cancel file merely because the SAP mirror says Pending.

The sequence is mandatory and asynchronous: send a separate Paid/new-payment file first, wait for
SAP import completion, refresh the SAP mirror, and prove the period is now `Paid`; only then may a
later cancellation file include it. Never combine Paid and Cancelled transitions in one file or
send the cancellation before SAP confirmation.

**Implementation decision 2026-08-22:** for a plain cancellation, every row in the required full
period spine emits `TransactionStatus = 'Cancelled'`, including rows whose predecessor was
Pending. Paid/Pending describes the required predecessor state; it is not the outgoing status.
Change-order rows are excluded from this flow and retain their separate reviewed status.

**Q12.** Is there an idempotency key — if the same cancel file is imported
twice, what happens?

---

## Why this matters
Nightly cancel batches currently fail for ~100 orders/night against these
undocumented rules. Confirming this one page eliminates the trial-and-error
cycle on both sides (fewer bad files hitting your import too).
