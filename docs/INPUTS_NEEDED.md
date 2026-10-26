## OPEN 2026-09-30 — residual charge recovery exceptions

The 2026 reconciliation and approved delivery are recorded in `FINDINGS_CHARGE_RECOVERY_20260930.md`. No further approval was required for the delivered 177 rows. Remaining items need source policy/lead repairs, verified invoice mapping, change-order/CMI decisions, or the specified further diagnosis. Neither prepared V2/sap_view SELECT proposal is deployed: backlog regression passes 4 of 5 target items, while contract normalization has dry-run-only evidence. Population regression and scoped deploy authorization remain required before deployment. No V3 work was requested.

# INPUTS NEEDED — things only Boat / Aware / Attila / Finance can answer

## OPEN 2026-09-25 — RCL same-period recovery scope, diagnosis complete

Mo's two examples have THB 667.25 in distinct successful additional charges absent from the
current dashboard and SAP mirror: L80570054 THB 22.04; L79109956 THB 645.21.
See [finding](FINDINGS_RCL_SAME_PERIOD_ADDITIONAL_PAYMENT_20260925.md) for source timestamps,
charge identities and causal probe. This is source/mirror coverage evidence, not a quantified
GL loss or a SAP-side JE verification. No production fix or backfill was performed.
Any recovery must first prepare and review corrections to both upstream charge retention and
downstream event-level eligibility, preserve existing invoices and M1 allocation, and establish
the full affected population. Production deployment/recovery authorization is not inferred from
the investigation request. No decision is being requested before a concrete reviewed artifact exists.

## OPEN 2026-09-08 — MS-01 source charge exceeds current replacement policy total

Before deploying the proposed reuse of `sap_view.RCB_NonMotor_process_2_cancel`, confirm the
intended ActualReceived for `L80799909-1`. CareOS contains one successful EDC/KRUNGSRI charge of
`3600.00`, while the current replacement item's TotalAmount and ExpectedReceived are `2160.00`.
The source-only candidate deliberately preserves ActualReceived `3600.00`; it does not silently cap
or reallocate the difference. PaymentChannel is correctly mapped as `RCB-EDC-BAY`.

## OPEN 2026-09-08 — human investigation: Change-cancel item has NULL cancel_time

`L77754975-1` is Health, exists in SAP at Period/TotalPeriods 1/1, and has
`is_cancelled=true` plus accounting status `CANCELLATION_STATUS_CHANGE_ORDER_COMPLETED`, but its
CareOS item `cancel_time` is NULL. Boat directed that current universal cancellation eligibility
remain based only on item `is_cancelled/cancel_time` and that this NULL-time case wait for human
investigation rather than being automatically interfaced.

Required answer: confirm the genuine cancellation effective date and whether CareOS should repair
`cancel_time`. Do not add a SQL fallback from underwriting/accounting status while this is open.

## OPEN 2026-08-27 — Boat: approve the six Unit 2 magnitude thresholds and provenance

The reviewed bootstrap procedure `sp_bootstrap_v3_unit2_magnitude` is deployed, and baseline run
`V3NIGHTLY-2026-08-25T22:21:31-manual` has verified archive, summary, conservation, and zero-
conflict evidence. No bootstrap CALL has occurred because no active magnitude configuration exists.

Provide these exact values; none may be inferred from observed population changes:

1. `records_absolute` (INT64, at least 0);
2. `records_percentage` (NUMERIC from 0 through 1);
3. `orders_absolute` (INT64, at least 0);
4. `orders_percentage` (NUMERIC from 0 through 1);
5. `amount_satang_absolute` (INT64, at least 0);
6. `amount_percentage` (NUMERIC from 0 through 1);
7. approval provenance: `approval_reference`, `approved_by`, `approved_at`, plus effective start
   and optional end.

This is the direct blocker for a fresh normal Scenario 1 and Scenario 3 build and for any common
V3 Scheduler cutover. General production-run approval does not supply these numbers. Until they
are explicitly approved, keep both flows at zero release-ready rows and keep the V3 Scheduler
PAUSED.

## OPEN 2026-08-25 — AR 1134-01 vs 1135-01 misposting confirmed for 142 EDC/KBANK onetime orders

Full detail: `docs/FINDINGS_AR_1134_VS_1135_MISPOSTING_20260825.md`. Pui reported 224 OrderIDs
booked to `1134-01` "AR Installment - Motor" that she believes belong on `1135-01` "AR Credit Card
and Payment Gateway". Verified directly against live `OJDT`/`JDT1` on `RCB_LIVE_DB`: 142 of the 224
were found in the GL, and **all 142 (100%)** have their primary AR debit on `1134-01`, totaling
฿1,601,582.47 (JE `RefDate` 2026-08-01 to 2026-08-21). All 142 share the same shape:
`PaymentMethod = EDC EDC`, `PaymentChannel = RCB-EDC-KBANK`, `TotalPeriods = 1` (onetime
credit-card settlement per this project's own confirmed `CREDIT_CARD_INSTALLMENT` definition).
Needs Boat/Finance to (1) confirm this is a defect and not an intentional mapping, (2) if a defect,
confirm the `D14` `MISPOSTING` classification applies here (it was defined for a different,
unrelated incident) before any correction is designed, and (3) decide who root-causes the
account-selection logic — not yet identified. 82 of the 224 reported OrderIDs were not found under
either account and are a separate, un-investigated follow-up.

**Update same day, same session (Boat present, asked directly):** ruled out wrong
PaymentMethod/PaymentChannel from the interface file — those fields are correct and consistent in
both good and bad cases. Narrowed instead to: (a) Pui's 224-order list is a curated known-bad list,
not proof of a systemic 100% failure — an independent 40-order sample of the same payment pattern
split ~50/50; (b) Compulsory (`-M`) items are **never** affected (93/93 correct in a 300-order
sample); the defect is entirely confined to Voluntary (`-V`) items, which split ~2:1 wrong:correct;
(c) not a per-batch/per-day toggle — the same JE batch contains both correct and incorrect `-V`
lines. The actual per-line discriminator inside SAP's posting logic is still unidentified; further
isolation needs either a stratified sample by insurer/product or direct access to the SAP-side
posting program (Aware-owned, out of reach here). Full detail and the crosstab table are in the
FINDINGS doc.

**Update same session — BigQuery source confirmed:** the 143.93/163.94-style residual is produced
by `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_fully_paid` (live definition,
not the repo baseline). For a Voluntary item sharing one combined EDC/KBANK charge with a
Compulsory sibling, `ExpectedReceived` is built from the item's own premium/fee/discount stack,
while `ActualReceived` subtracts the Compulsory sibling's **gross** premium (not its VAT/stamp-duty
-inclusive total) from the combined charge — a basis mismatch that never reconciles exactly.
Verified against `L80512627-M1`/`-V1`: Compulsory `GrossPremium` 1,900.00 vs `TotalPremium`
2,041.56 (short by 141.56); Voluntary residual comes out to 163.94.

**CORRECTION, same session:** the "gross vs total" claim above was checked further and is wrong —
retracted in the FINDINGS doc. `compu_detail.gross_premium` correctly reads the full VAT/duty-
inclusive figure (verified against `careos.careos_order_items` directly: `gross_premium =
net_premium + vat_amount + stamp_duty` exactly), and the view's own `M1` output confirms
`ExpectedReceived = ActualReceived = 2,041.56` (not 1,900.00). The real source of the 163.94 gap:
`careos.carepay_charges.amount` for this order's transaction (status `SUCCESSFUL`) is verifiably
฿16,912.62 — ฿163.94 less than the theoretical combined total from `careos_order_items` pricing
after the recorded discount, and no discount/fee field explains the difference. This is a genuine
discrepancy between quoted order price and actual amount charged, not a formula bug in the
BigQuery view. Cause not yet identified (price-change timing vs. charge-time snapshot is the
leading candidate). **ROOT CAUSE CONFIRMED, same session:** checked `careos_orders.invoice_price`,
`carepay_transactions.amount`, `carepay_charges.amount`, and
`carepay_transaction_snapshot_price_summaries.net_premium_amount` together for `L80512627` — all
four agree on 16,912.62 as the true total (one snapshot only, `is_current=true`, ruled out a
stale-snapshot join issue). The price summary also carries `wht_amount = 163.94`, an **exact**
match to the gap. **The bug: the view's `ExpectedReceived` formula for a Voluntary/`charge_rank=1`
item subtracts `Discount_master` but never subtracts `WHT`/`WHT_master`, even though it computes
`WHT_master` from `wht_amount` elsewhere in the same query.** `ActualReceived` correctly reflects
the WHT-reduced real charge; `ExpectedReceived` doesn't account for WHT, so the two never
reconcile whenever `wht_amount ≠ 0`. This is a concrete, one-line-fix candidate in
`pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_fully_paid` (add `- WHT_master`,
or equivalent, to the `ExpectedReceived` CASE branch). Not yet proven: whether fixing this view
alone stops the SAP misposting — the SAP-side code path that reads the Expected/Actual equality
and picks the account is still unconfirmed (vendor-owned, Aware, unreachable from here). No fix
applied — read-only per this project's hard rules; needs Boat/Aware sign-off before any change.

**REFRAMED, same session — Boat flagged an existing Aware agreement:** `WHT=0` in the interface is
intentional per a prior agreement — SAP is supposed to hold the resulting gap (WHT + rounding +
discount) in a separate "ส่วนต่าง" (variance) account for manual adjustment, not misroute the whole
receivable. Checked against live JE data: the amounts actually landing in `1134-01` are **full
receivables** (฿14,470.68 / ฿27,900.00 / ฿31,200.00 per order; ฿1,601,582.47 total across 142
orders), three to four orders of magnitude bigger than the WHT-sized gap (~฿163.94 for one
example). **This does not look like "small gap parked in a variance account" — the entire AR
amount is going to the wrong account.** Open question for Boat/Aware: does the agreed design mean
only the small residual should go to a suspense account while the bulk stays on `1135-01`? If so,
current behavior violates that agreement — but whether the fault is SAP's JE logic or a missing
signal from our interface is still undetermined and needs Aware's input on the agreed mechanics.

**HISTORY, same session — this is chronic since 2025-07, not new:** pulled the full JE history
(427,162 rows, `RefDate` 2023-04-30 to 2026-08-25) for Voluntary-item debit lines on `1134-01` vs
`1135-01`, by month. Two distinct eras: (1) 2023-07 to 2024-03, an early-system anomaly (67% wrong
at first, declining to ~3%) that resolved on its own by April 2024 — not investigated, likely
unrelated; (2) **2024-04 to 2025-06, a genuinely clean 15-month stretch at ~0% wrong** (only two
one-off spikes: 2024-09 and 2025-04, each surrounded by clean months); then **2025-07 through
2026-08 (now), every single month wrong at 7.6–13.9%, with no clean month since** — 14 consecutive
months. This is the real onset to root-cause: something changed around June/July 2025. No
deploy/change log has been checked yet for that window — that is the natural next step.

**⚠️ METHODOLOGY CORRECTION, same session — company-customer rate figures were overstated:**
full-JE inspection while preparing Aware examples showed "does this order have a `1134-01` line"
conflates three different things: (A) true full misposting — 2-line JE, `1134-01` debit = full
receivable, no `1135-01` line at all (this is what the original 142-order/฿1,601,582.47 EDC/KBANK
finding actually is, re-verified, still stands); (B) a WHT-sized residual debit to BOTH `1134-01`
and the dedicated `2142-10` "บัญชีส่วนขาด WHT" account, alongside a full and correct `1135-01`
line — not the same defect, much smaller, arguably duplicate-posting rather than wrong-account;
(C) self-offsetting entries netting to zero, not a defect. Re-classified company customers with a
proper net-balance method: **true misposting (A) is rare among company customers, single digits to
~20/month — not the 60–67% previously reported.** The earlier company-rate, exact-onset-date, and
August-dollar-spike figures summed raw `1134-01` debits without netting credits or checking for a
paired `1135-01` line, so they overstate the problem and should not be cited until redone with this
corrected method. **Do not send anything to Aware using the company-customer 60–67% figures or
those specific examples** — use the original EDC/KBANK individual-customer finding (type A,
cleanly verified) instead. Not yet done: redo the monthly/onset/dollar analysis correctly;
characterize the large "Other/unclassified" bucket from the reclassification.

**✅ 100% CONFIDENCE ACHIEVED for August 2026 company customers, card/gateway channels (Boat's
goal), same session:** corrected scope to `RCB-EDC-*`/`RCB-Omise*` only (Transfer/Credit-Shell
never touch `1135-01` by design — excluding them was itself a needed fix). True misposting: **3
orders out of 207** (฿19,410.97 total) — not 60–67%. **100% clean discriminator**: all 3 have
`@INSURANCE.U_ActualReceived ≤ 0` (0.00 / −55.15 / −350.14); **0 of the 204 correctly-posted
orders** have `ActualReceived ≤ 0` — exact, not probabilistic. Traced and ruled out: (1)
`careos.carepay_charges` raw data is clean for all 3 (single `SUCCESSFUL` charge, correct positive
amount each); (2) SAP JE logic is reacting consistently/correctly to bad input, not misbehaving on
its own; (3) the `compu_detail`/Compulsory-sibling-subtraction mechanism does not apply — reproduced
that CTE directly and confirmed zero matches for all 3 `order_id`s. **Root cause is 100% confirmed
to sit inside `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_fully_paid`'s
`onetime_master` construction — not CareOS source tables, not SAP.** One line item remains open:
the exact join/branch inside `onetime_master` producing `ActualReceived = charge_amount −
TotalAmount` for these 3 (candidates: multi-row fan-out from a join, or the `change`/superseded-
order CTE) — not yet pinned to a specific line, but not blocking any decision Boat/Aware need to
make now.

**✅ AWARE CONFIRMED THE SAP RULE, same session (Sarawut/Boyd, Kanjana/June via Nong/Mo):**
`ExpectedReceived=0` → SAP posts the entire `ActualReceived` to `1134-01` (`Dr` payment-channel /
`Cr` `1134-01`) — confirmed real, designed SAP behavior, not a SAP-side bug; SAP is reacting
correctly to bad input. The view forces `ExpectedReceived=0` **by design** whenever `charge_rank
<> 1` (`sap_dashboard_carepay_fully_paid`, `onetime_master`, ~line 263), where `charge_rank` is
`ROW_NUMBER() OVER (PARTITION BY transaction_id ORDER BY create_time)` on `SUCCESSFUL` charges —
so any transaction with 2+ successful charges (retries, corrections, cancel-then-resubmit reusing
the same `transaction_id`) forces its later charge(s) to `ExpectedReceived=0` even when that later
charge is the genuine final one. **This is the leading, most actionable fix target.**

**Caveat surfaced while verifying against the original list**: `[dbo].[@INSURANCE]` is a live,
mutable, current-state table with no exposed version/audit history — checking `L78667850-V1`
against Aware's rule showed the *opposite* shape (`ExpectedReceived` nonzero, `ActualReceived=0`)
from what the JE structure implies, most likely because the order was re-interfaced after the JE
posted (same pattern as Boyd's `L77286597` example) and the current snapshot no longer matches
what was live at posting time. A broader August check found only 103/902 (11.4%) currently-flagged
orders show `ExpectedReceived=0` — **do not use current `@INSURANCE` values alone to validate what
triggered a historical JE**; that needs an audit/history table this session hasn't located.

**Fix-plan drafted in the FINDINGS doc** (not executed — Claude Code does not deploy per this
project's SINGLE DEPLOYER rule): investigate and correct the `charge_rank<>1→0` branch first
(likely needs to key off which charge is operative per OrderItem, not raw chronological order);
separately investigate the August 3-order `ActualReceived = charge_amount − TotalAmount` mechanism
(a second, distinct defect in the same view — candidates: the `change`/superseded-order CTE, or a
join fan-out). Any deploy needs Codex + the project's DEPLOY GATE (dry-run + summary + explicit
Boat approval), and Aware should weigh in on whether SAP's `ExpectedReceived=0` fallback behavior
itself should also change.

**⚠️ CORRECTION, same session (Boat):** `charge_rank<>1 → ExpectedReceived=0` is **by design**,
not a bug — retracting it as a fix target above. Likely intentional: multiple `SUCCESSFUL` charges
on one transaction is itself an exception, and routing it to `1134-01` may be the designed flag for
manual accounting review (consistent with the earlier Aware-agreement variance concept). Reframes
part of the original 142-order population as possibly correctly-flagged exceptions needing a
reconciliation-process check, not a code fix — not yet sized how much of the population this
explains. **The August 3-order investigation (`ActualReceived = charge_amount − TotalAmount`) is
unaffected and still valid**: all 3 have exactly one `SUCCESSFUL` charge (`charge_rank=1`
necessarily) and a correct, positive `ExpectedReceived` — the by-design branch cannot explain them;
their `ActualReceived` failure is a separate, still-open, likely-genuine defect, and the
investigation plan for it stands unchanged. Next step before any fix: classify the full 142-order
population by which mechanism explains each order (by-design `charge_rank<>1` vs. the unexplained
`ActualReceived` defect vs. unclassified) — not yet done.

**⚠️ MAJOR CORRECTION, 2026-08-26 — the 3 August orders don't come from `_fully_paid` at all.**
Checked `careos.carepay_transaction_snapshots.number_of_installment` for all 3: **6, 10, 10 — not
1.** Queried `sap_dashboard_carepay_fully_paid` directly: **zero rows** for these `OrderItem`s
today. Queried `sap_dashboard_carepay_installment` instead: **all 3 are there**, with
`ExpectedReceived = NULL`, `ActualReceived = 0.0`, and `Period`/`PaymentChannel`/`PaymentMethod`
all `NULL` — broken/incomplete rows in a different view than the one investigated. **The order's
onetime-vs-installment classification changed in CareOS at some point after the JE posted
(2026-08-06/11/13)** — same "state drifted after posting" pattern as the `L78667850-V1` caveat
already noted, now confirmed independently. **Conclusion for these 3: this is CareOS-side data
instability (plan classification changing post-facto), not a formula bug in
`sap_dashboard_carepay_fully_paid` (which no longer even sees these orders) and not evidence of a
stable-input SAP behavior change.** The earlier `charge_amount − TotalAmount` numeric match was
very likely an artifact of reading `@INSURANCE`'s stale state, not a live view bug — **retracting
that as an active fix target.** Plausible (not confirmed) these 3 are also explained by Aware's
`ExpectedReceived=0` rule, but the historical value can no longer be verified since both candidate
source views have moved on. If this thread is worth pursuing further, it's now a different
question: why did these orders' plan classification change, and does
`sap_dashboard_carepay_installment` have its own defect (`NULL` `ExpectedReceived`/
`PaymentChannel`/`Period`) — not started.

**✅ CONSOLIDATED, 2026-08-26 (no new queries — synthesis of this session's results + project
history):** found `docs/FINDINGS_EMPTY_INSTALLMENT_DETAILS_20260825.md` (a different, prior
investigation, same project) already documents that `number_of_installment` drifting `>1` for
genuinely-onetime (`EDC`/`CREDIT_CARD_INSTALLMENT`, confirmed-onetime per `stg_schedule`) orders is
a known, quantified, "expected and mostly benign" artifact (20,793 such items found there) — this
is what explains the 3 August orders' confusing `NULL`-filled row in `sap_dashboard_carepay_installment`;
it's known downstream noise, not new corruption, and not what actually produced their JE.
**Narrowed final answer**: the original 142-order population is best explained by SAP correctly
executing its confirmed, by-design `ExpectedReceived=0` exception-flag (Aware) on orders whose
transaction had `charge_rank>1` (also by-design, per Boat) — **this looks like a reconciliation/
process gap (are `1134-01` balances from this flag being cleared?), not a code defect**, unlike the
separate, confirmed WHT-formula bug found earlier. Genuinely still open, needs Boat/Finance (not
derivable from data): is `1134-01` being monitored/cleared for this mechanism today? Also open,
deliberately not measured this pass: what fraction of the 142 orders had `charge_rank>1` — one new
query, not run per Boat's "no new runs" instruction this round.

**⚠️⚠️ VERIFIED WRONG, 2026-08-26 — retracting the `ExpectedReceived=0` explanation.** Boat asked
to check real data. Result: only **6/148 (4%)** of the original 224-order list's V-items currently
show `ExpectedReceived=0` in `@INSURANCE`; **142/148 (96%) have nonzero `ExpectedReceived`.** The
`charge_rank<>1` mechanism does not explain this population. **Real pattern**: `ActualReceived=0`
exactly for **116/148 (78%)** (another 16 negative, 16 small-positive) while `ExpectedReceived`
correctly equals `TotalAmount`. **Confirmed same mechanism as the 3 August orders, at scale**: a
12-order sample of the `ActualReceived=0` group all show `careos.carepay_transaction_snapshots.
number_of_installment = 6 or 10` — the exact drift artifact `docs/FINDINGS_EMPTY_INSTALLMENT_
DETAILS_20260825.md` already quantified (20,793 ONETIME-flow items system-wide) as excluding
orders from the legacy `sap_dashboard_carepay_fully_paid` view and falling through to the broken
`sap_dashboard_carepay_installment` path. **Corrected answer**: the bulk of the 224-order
population is genuine onetime EDC payments whose CareOS installment-count field drifted away from
1 (known, pre-existing artifact) — not new corruption, not the `ExpectedReceived=0`/`charge_rank`
mechanism. Still open: the exact live process producing `@INSURANCE`'s row for these (neither
`_fully_paid` nor `_installment` matches it exactly); whether Aware has a separate confirmed rule
for "`ActualReceived=0` with positive `ExpectedReceived`" (not yet asked — only two other scenarios
confirmed so far); and this project's own `AGENT_RULES.md` positional-column-mapping risk is a
concrete, checkable next hypothesis, not yet verified.

**FINAL STATUS, 2026-08-26 — pushed to the practical limit, one link not closed.** Checked every
live production interface view: `RCB_Motor_process_create` reads only `_fully_paid`, which returns
**zero rows** for these orders (ruled out). `RCL_Motor_process_1_create`'s **live** definition (not
the drifted repo baseline) filters to `payment_option='RABBIT_CARE_INSTALLMENT'`; all 12 sampled
orders are `CREDIT_CARD_INSTALLMENT` (ruled out). Searched all 12 live `sap_view` objects — none
reference `carepay_installment`. **No standard, documented production path explains how these
orders got into `SAP_LIVE_FULL`.** Each order has exactly one `SAP_LIVE_FULL` row (append-only —
one interfacing event), `OrderDate` in early August 2026, interfaced within days — genuinely new,
not old orders that drifted years later. **High confidence** the `number_of_installment` drift is
the right diagnosis of what's different about this population (12/12 sampled show it, matches a
separately-documented, pre-existing project artifact) — **not confirmed**: the exact live
process/script that turns that into `ActualReceived=0` in `@INSURANCE`. Candidates: an undocumented
manual/ad-hoc backfill script (this project is confirmed to deploy those — see
`RCL_Motor_process_1_create`'s own live "quick fix" history), an Apps Script/scheduled job not
captured in any `sql/` file read this session, or the drift happening *after* a legitimately-
computed `ActualReceived=0` (coincidental correlation, not ruled out). **Recommended next step**:
ask Codex or whoever owns the nightly scheduler which job actually produced the Aug 1–21 interface
batch — that job's logs would show the real source and close this session's last gap.

**✅ MYSTERY SOLVED, 2026-08-26 — Boat confirms he ran the missing manual backfill himself**
(force-converting `number_of_installment`-drifted `EDC`/`CREDIT_CARD_INSTALLMENT` orders back to
onetime). Closes the "which process interfaced these" gap. **Full population pulled directly**:
`PaymentMethod='EDC EDC'`, `ActualReceived=0`, `ExpectedReceived=TotalAmount`, `BatchRunDate`
Jul–Aug 2026 → **141 unique OrderItems, ฿1,640,393.50** (2 in July, 139 in August) — matches the
original 142-order/฿1,601,582.47 finding closely, same population confirmed from a different angle.
Full list sent to Boat as `tmp_full_list_jul_aug_backfill_pattern.csv`. **Reframed fix target**:
Boat's own backfill script needs to write the real charged amount (confirmed clean in
`careos.carepay_charges` throughout this investigation) as `ActualReceived`, instead of whatever
currently produces `0` — that `0` is what triggers SAP's confirmed `Expected≠Actual→1134-01` rule.
Draft message to Aware rewritten (`docs/DRAFT_MESSAGE_TO_AWARE_20260825.md`) asking: (1) confirm
whether fixing `ActualReceived` to the real charged amount alone is sufficient to post to `1135-01`
correctly; (2) any other field SAP's account-selection depends on; (3) how to correct the 141
already-misposted records. Not yet sent — Boat's to review/approve.

**✅ EXACT LINE FOUND, same session:** Boat's manual backfill script is the **live** definition of
`sap_view.RCL_Motor_process_1_create` (repo baseline file is stale, doesn't match — confirmed via
`INFORMATION_SCHEMA.VIEWS`; its own header: *"QUICK FIX 2026-07-16: Manual backfill RCL creates..."*).
Root cause pinned to one `CASE` expression: `ActualReceived` for `charge_rank=1` computes
`charges.amount - add_ons`, but `charges` is `LEFT JOIN`ed on `charges.installment_number =
transaction_snapshot_installment_details.period` — for our population (`installment_details` empty,
the pre-existing CareOS artifact), `period` is `NULL`, so the join never matches, `charges.amount`
and `charge_rank` both come back `NULL`, and the `ELSE COALESCE(charges.amount,
installment_details.payment_amount)` fallback is also `NULL` (both inputs `NULL`) — resolving to
`0` on SAP import. **100%-confirmed, code-level root cause.** Full detail and proposed fix (a
second `charges` join keyed on `transaction_id` alone, as a fallback when `installment_details.id
IS NULL`, mirroring V3's already-correct `vw_onetime_payload_source` pattern) in the FINDINGS doc.
Not deployed — this is Boat's own script outside normal `sap_view` governance, so Boat should
decide the deploy path; recommended to dry-run the fix as a plain `SELECT` against the 141-order
population before replacing the live view.

**COMPANY-CUSTOMER SPLIT, same session — sharp step-change confirmed at 2025-07:** found
`careos_orders.data.policyHolder.isCompany`; `[dbo].[@INSURANCE].U_Title` blank is a clean 20/20
verified proxy for it. Company customers: 0% wrong in 2025-05/06 → **51.3% in 2025-07** → steady
**60–67%** every month since. Individuals: 0–1% → 12.4% in 2025-07 → steady **5–10%** since. Same
month, both cohorts, no reversion — one systemic change, not a gradual drift or volume effect.
Company rate runs 6–9× individual, consistent with the WHT mechanism (Thai WHT applies to juristic
payers more often than individuals) combined with the missing-`WHT` bug in `ExpectedReceived`.
Still needed: the actual deploy/change log for late June–early July 2025 (Aware's side, or
whoever last touched `sap_dashboard_carepay_fully_paid` / CareOS WHT computation) — not checked
this session.

**MAJOR COMPLICATION, same session — needs Boat/Finance's read before continuing:** pulling 5
correct + 5 wrong company-customer records per month (all payment channels, not just EDC/KBANK)
surfaced a dedicated `2142-10` "บัญชีส่วนขาด WHT" variance account already in active use — likely
the account from the Aware agreement. In these broader-channel examples, the amount hitting
`1134-01` is small and WHT-sized (not the full receivable), mirrored by an identical debit to
`2142-10`, while the bulk of the money flows through `2121-02` "Account Payable Trade" (an AP
account) + a bank/contra line — a JE shape this session cannot confidently interpret. One example
(`L77603344-V1`) shows the bulk correctly on `1135-01` *and* a small duplicate-looking entry on
`1134-01` alongside `2142-10` — suggesting the real defect may be narrower than first thought (a
redundant WHT-sized leak into `1134-01`, not full-receivable misrouting). This does not obviously
reconcile with the original EDC/KBANK-scoped finding (full receivable, no `1135-01` line at all,
e.g. `L78667850-V1` ฿14,470.68) — open question whether there are two different mechanisms by
payment channel, or whether the LineMemo-based join was conflating AR-side and AP-side JEs sharing
an OrderItem in their memo. **Stopped here rather than speculate further; needs Boat/Finance to
explain what `2121-02`/`9001-17`/`2142-10` represent in this business's JE design.**

**EXACT DATE + WHY AUGUST, same session:** onset pinned to **2025-07-01** — a single-day spike of
413 wrong V-item entries (vs. 0–3/day background before), reading as a bulk event, settling to a
persistent 3–23/day elevated baseline for the 13 months since (steady ฿500K–1.1M/month wrong,
all V-items). **August 2026 (partial month, data through ~08-21/25) already shows ฿3.99M wrong —
4–8× the steady monthly baseline and comparable to the original 2025-07 onset spike** — the
likely reason this became visible enough to notice and report now, after 13 months of a smaller,
easy-to-miss chronic rate. Not yet done: why August 2026 itself spiked (day-level breakdown not
pulled for August).

**DEFINITIVE, same session — it's the JE/posting behavior that changed, not the interface:** held
input constant (`PaymentChannel` + whether `Expected == Actual`) and compared before vs. after
2025-07 across the full 11,160-row company-customer population. **Before 2025-07: every channel,
every match-type (including `GAP`/mismatched cases, which already existed then) posted to
`1135-01` with zero exceptions.** After 2025-07: the *same* channel-and-match-shape input starts
splitting — Transfer channels ~100% wrong, EDC/Omise `GAP` cases ~50/50, Credit Shell `GAP` ~98%
wrong, while `EXACT` cases on EDC channels stay 0% wrong. Since a nonzero Expected/Actual gap
already existed and posted fine before 2025-07, and the same input shape now splits inconsistently
after, **the interface/input did not change — whatever decides the account at posting time did**,
right at that boundary. Still needed: the specific deploy/config/code change at that date — not
queried this session (no access to deploy history from here).

## URGENT OPEN 2026-08-24 09:28 ICT — Boat ordered V2 production + all schedules stopped tonight, V3 cutover; V3 delivery has never been enabled

Boat's instruction, verbatim, given directly to Codex outside this file: **"Please stop the V2
production and all schedule, I found a lot of continuing productions errors. We will push V3 up
and running tonight."** Relayed to Claude Code with the ask to document it and help Codex
plan/review/recheck the result.

**Readiness check performed before any action was taken (read-only, no BigQuery mutation, no
gcloud mutation):**

V3 has never produced a real 56-column interface file for SAP.
- `docs/AS_BUILT_V3.md` (2026-08-05, live-cross-checked, not memory): *"the unattended V3
  workflow still writes no production interface file: `delivery_enabled: false` remains live and
  there is no recurring workflow trigger."*
- `docs/design/V3_DELIVERY_CONTROL_PLANE.md` is headed **SUPERSEDED — DO NOT RUN** and lists 6
  sequential, still-open gates before `delivery_enabled` may even be flipped to `true` (deploy
  contract DDLs, complete Apps Script rehearsal, a separately-scoped GCS-write approval, flip the
  flag for one bounded execution, verify generation/CRC/SHA/SAP pickup, *then* a separate atomic
  cutover review). None is marked complete.
- Of the 12 case-type interface producers under `sql/sap_view/*.sql`, the last live drift check
  (`RQ-20260801-0040`, PASSed) found 9 match their reviewed baseline, 2 drift
  (`RCL_Motor_process_1_create`, `RCL_NonMotor_process_2_newpayment`), and 1 has no baseline at
  all (`RCL_Motor_process_2_newpayment`); a separate production copy of
  `RCB_NonMotor_process_1_create` also drifts. No later evidence these were fixed or re-reviewed.
- The column-contract guard (`sql/ddl/028_column_contract_guard.sql`) exists but is not called
  from anywhere in the nightly chain — it would not catch a bad export tonight.
- No V2→V3 cutover runbook exists anywhere in the repo. Cutover is explicitly framed in the
  delivery-control-plane doc as its own future, separately-reviewed step — never drafted.
- The most recent activation work (yesterday, `RQ-20260823-2304`, PASSed) only turned on **inert**
  post-import infrastructure (Cloud Run revisions, a paused test-cadence scheduler); zero GCS
  writes, zero SAP actions, `delivery_enabled` still false as of that review.

**What this means literally**: if V2 production and its schedules are stopped tonight with nothing
else changed, the business stops sending SAP any interface file at all — not a controlled
migration to a working replacement, a full outage of invoice/commission delivery, until V3's
6 delivery gates are closed and at least the 3 drifted/missing-baseline case-type views are fixed
and re-reviewed.

**Decision needed from Boat before Codex executes "stop V2" as literally worded:**
1. Is the intent to stop ALL V2 schedules tonight regardless of the SAP-delivery gap above
   (accepting a documented delivery outage until V3 closes its gates), or to stop only the
   specific V2 objects/schedules causing "continuing production errors" (which ones?) while
   V3 is finished in parallel?
2. If a full stop-tonight is still wanted despite the gap: what is the accepted downtime window,
   and does Finance/Aware need advance notice that no SAP interface file will post until V3 is
   live?
3. "Push V3 up and running tonight" — does this mean close all 6 delivery-control-plane gates and
   flip `delivery_enabled: true` for full production tonight (large scope, multiple still-open
   Class-A reviews, not achievable safely in one night per the control-plane doc's own sequencing),
   or something narrower (e.g., just the CreditShell routing fixed today)?

No V2 schedule has been stopped and no V3 delivery flag has been changed by Claude Code in
response to this instruction — this entry exists so Codex has the same evidence before acting, and
so this decision is recorded rather than inferred. See `docs/tasks/TASK_V2_STOP_V3_CUTOVER_20260824.md`
for the readiness checklist and options laid out for Codex.


## RESOLVED 2026-08-23 20:43 ICT — RCB one-time change-order mislabelled RCL: both decisions made

Boat decided both open questions below directly in chat:
1. **Deploy the fix: YES** — approval-in-principle, still stands. **Update 20:46 ICT: the specific
   artifact this was granted for (`f25af4f`, patching the v2 legacy view) was BLOCKED by Codex's
   review, not deployed** — see `docs/reviews/2026-08-23-f25af4f-codex.md` and the finding file's
   "Review outcome: BLOCKED" section. Root blocker: `sap_integration_v2` is not a permitted DDL
   target at all (v3-only per `AGENT_RULES.md`) — this needs a v3-canonical redesign, not a
   re-review of the same file. Boat's "yes" still applies once a compliant fix exists; no new
   decision is needed from Boat, this is implementation rework.
2. **The 7,557 already-posted items: do nothing.** No backfill/correction of historical
   `RCL-Credit Shell`-labelled SAP rows. This finding's scope ends at stopping future mislabelling.
   Unaffected by the BLOCK above — still stands as-is.

## OPEN 2026-08-23 — RCB one-time change-order mislabelled RCL: fix prepared, scale is 7,557 items, two decisions needed (SUPERSEDED — see RESOLVED entry above)

Mo reported `L80569331-M1` (relayed via Boat) as the same defect class as
`docs/FINDINGS_RCB_ONETIME_CHANGE_ORDER_MISROUTED_RCL_20260803.md`'s known-answer case
(`L80482368`). Independently verified live and traced to the actual live-executing object (not the
repo file first suspected — see the finding file for the drift-detection detail):
`sap_integration_v2.\`RCL 04_new order credit shell new tunning\``, which routes purely on
"is this charge shared with the predecessor order" with no `payment_option` check at all.

**A source-only fix is prepared** (`sql/production/RCL_04_new_order_credit_shell_new_tunning.sql`,
not deployed): routes carried-over FULL_PAYMENT/CREDIT_CARD_INSTALLMENT orders to
`RCB-CreditShell` instead of `RCL-Credit Shell`, matching the label the reviewed V3 canonical
router already uses. Full-population regression run live: row/item counts unchanged, zero blank
PaymentMethod regression, and **exactly one transformation type** across the entire diff
(`RCL-Credit Shell` → `RCB-CreditShell`, nothing else touched) — see the finding file's
"Full-population regression result" section.

**The scale is far bigger than the original "9"-item population from 2026-08-03: 7,557 distinct
order items** are currently live-mislabelled through this one view. Two decisions needed:

1. **Deploy the fix?** (Class-A review still pending, then Codex deploys via
   `CREATE OR REPLACE VIEW` under the standard gate.) This only stops *future* mislabelling — it
   changes nothing about rows already posted to SAP.
2. **Do the 7,557 already-posted items need a separate correction/backfill?** SAP's stored
   `InvoiceNo`/Paid rows are immutable per `AGENT_RULES.md`; correcting an already-posted wrong
   `PaymentMethod`/`PaymentChannel` label is a distinct, larger decision (correction method, GL/
   accounting impact, whether Finance needs to reconcile a mislabelled-channel history) that this
   finding does not propose and has not scoped. This needs its own explicit decision before any
   correction work starts, per the D10–D14 confirmed-decision framework already governing other
   SAP corrections.

Also flagging a possible connection (not confirmed) to the "urgent_for refund to cust" tab —
described in the entry below as FULL_PAYMENT orders "sync to omise RCL > refund to RCB" for
May–June, structurally the same failure shape. Given the scale just found here, this connection is
worth checking with real urgency, not just noting.

## OPEN 2026-08-21 — urgent refund: approvals needed after exact population/live classification

Boat supplied the `RCL_missing order` workbook and decided that CareOS item status is definitive;
completion means SAP Paid then Cancelled. The `urgent_for refund to cust` tab is sheetId
`493163004` (the supplied gid opens `SAP_LIVE`) and currently has 15 populated rows resolving to
18 CareOS items. Live Phase 1 is recorded in
`docs/tasks/TASK_URGENT_REFUND_PAID_CANCEL_20260821.md`: 2 complete, 6 plain-cancel candidates,
and 10 held.

Human/vendor inputs still required before the six candidates can become a production file:

1. Aware: confirm the remaining applicable cancel-import rules still marked inferred in
   `SAP_CANCEL_IMPORT_SPEC_INFERRED_v0.9.md`, especially required Pending-period values. Pending
   `InvoiceNo` and `PaymentDate` are now resolved: preserve each existing SAP value verbatim,
   including blank. Pending `ActualReceived` is also resolved: preserve non-NULL SAP values and
   convert SQL NULL to numeric `0`. Apply the same rule to Pending `ExpectedReceived`.
   Pending `ExpectedDate` is resolved: existing value, else `PaymentDate`, else `BatchRunDate`;
   never blank.
   Pending `PaymentMethod`/`PaymentChannel` are blank-only; `PendingPayment` preserves SAP exactly
   and may be NULL. New required gate: reconcile every SAP Pending period to CareOS payment truth;
   any CareOS-paid/SAP-pending period must be completed as Paid in SAP before cancellation.
2. Boat: after an immutable payload and Class-A PASS exist, give explicit scoped `deploy OK` in
   the execution session. The priority instruction and completion definition do not by themselves
   waive the production-write gate.
3. Boat/Aware: separately decide the valid item-level Paid allocation/predecessor path for the six
   held items whose successful charge is only provable at shared order grain. Do not infer M1/V1
   allocation from that charge.

The two items whose CareOS item flags are not cancelled remain ineligible under Boat's definitive
rule. The incomplete-spine and change-order cases require their own reviewed routing, not an
exception to plain cancellation.

## OPEN 2026-08-17 — Boat/Mo: sheet link + scope for the 1-15 Aug RCL pending-interface report

Mo Pawinee reported to Boat (chat, 2026-08-17, not yet independently verified — see
`docs/HANDOFF_QUEUE.md` 2026-08-17 10:09 ICT entry for the investigation request to Codex):
2,301 orders (her count, unverified) where the customer's Omise payment landed 1–15 Aug 2026 but
the order hasn't reached SAP, excluding new orders created via a changed order; plus a separate
"urgent_for refund to cust" tab.

1. **RESOLVED — sheet link and exact "1-15 Aug" population**: Boat provided the link —
   https://docs.google.com/spreadsheets/d/1BVnd49n_kxVQhqHIou70n_GbpRV-hlbXXQjscS5-upA
   (title "RCL_missing order", owner `pawineet@rabbit.co.th`, last modified 2026-08-17T03:05:30Z).
   Downloaded as `.xlsx` and parsed the sheet XML directly (the Drive text-export tool flattens all
   8 tabs together with no gid/name boundary, so this went past that limitation from my last
   entry). Confirmed with certainty: sheet "1-15 Aug" = internal `sheetId=6`, `state="visible"`,
   `_xlnm._FilterDatabase` range `$A$4:$W$2305` = **2301 total data rows, which literally is Mo's
   2,301 figure** — a real row count, not a fabricated number. 2295 of those rows have the sheet's
   own status column marked `"not on SAP"`; 6 are a different, non-standard shape (order IDs
   already suffixed `-M1`, no Period column, mostly annotated `"paid + cc"` — a distinct edge case
   needing separate triage, not folded into the systematic population); 1 of the 2295
   (`L80416399`, period 1) carries a note suggesting it may already be resolved despite its status
   cell. Full detail and the extracted `(order_item, period)` list are in
   `sql/adhoc/20260817_verify_mo_1-15aug_missing_from_sap.sql`, handed to Codex
   (`docs/HANDOFF_QUEUE.md` 2026-08-17 10:45 ICT) to classify against live `sap_integration_v3`
   before anything is prepared for interface-file generation. This closes the "sheet link" input —
   the only remaining human decision on this item is Boat reviewing Codex's live classification
   numbers once Phase 1 comes back, and the "urgent_for refund to cust" tab is a *different*
   problem than originally assumed (see below), also needing a decision.
   **Also found**: "urgent_for refund to cust" is a small (10-row) separately-structured tab, rows
   flagged `metadata_FULL_PAYMENT`, annotated "MAY-June, FULL PAYMENT but sync to omise RCL >
   refund to RCB" — these are orders that paid in full but got routed/synced to the wrong channel
   and now need a refund back to RCB. **This is a refund-routing problem, not a SAP-import gap** —
   confirm with Mo/Finance whether this needs its own tracked finding (money-impact, likely small
   population but real customer-facing refunds) separate from the "1-15 Aug" interface-file work.
2. **Cancel-import scope (Boat)**: Mo asked to "import Cancel for CareOS-cancelled orders per
   Mandatory/Voluntary as it should be." The canonical cancellation rule already exists (D1,
   revised 2026-07-29: `careos.careos_order_items.is_cancelled IS TRUE OR cancel_time IS NOT
   NULL`, never `careos_orders.is_cancelled`, never fanned to active siblings) — confirm whether
   Mo's ask is just "apply the existing D1 rule to this population" or something new about
   Mandatory-vs-Voluntary handling specifically that D1 doesn't already cover.
3. **Changed-order import scope (Boat)**: Mo asked to import Changed Order rows because Omise's
   view doesn't surface them. Confirm whether this is the same defect class as
   `FINDINGS_VMI_MISSING_EXPORT_PIPELINE_20260807.md` /
   `FINDINGS_MOTOR_MISROUTING_AND_MISSING_INTERFACE_20260805.md` (both already open, both about
   real payments not reaching SAP) or a genuinely separate gap — needs Codex's live-data check
   first, but the business-rule question of how a changed order's SAP row should differ from a
   normal one is a human answer, not something derivable from data alone.
4. **`RCL_pending cancel` tab scope (Boat/Mo)**: identify the exact workbook/tab snapshot,
   canonical row grain, and whether it is a subset of the Cancel-import population above or a
   distinct operational queue. Confirm the intended SAP operation and predecessor requirements
   before writing a task file. Do not infer this population from the tab name and do not build an
   interface file until the scoped task and pre-export gates are reviewed.

These import asks are production mutations and are **not authorized** by this entry — they need the
usual dry-run + Class-A review + Boat's explicit deploy OK once scoped, per `AGENT_RULES.md`.

## OPEN 2026-08-14 — Boat/IT admin: single `run.invoker` grant + reconcile workaround-doc contradiction

Raised by senior data-engineer design review (`docs/HANDOFF_QUEUE.md` 2026-08-14 14:22 ICT entry).
The entire post-import stack (DDL 070–075, dispatcher, watchdog, promoter) is Class-A PASSed and
deployed inert. The live activation checker's only remaining readiness blocker is the dispatcher
`run.invoker` binding on `sap-post-import-dispatcher`, and neither `data@rabbit.co.th` nor
`piyaratt@rabbit.co.th` holds `run.services.setIamPolicy` to grant it (confirmed via live
`testIamPermissions`, see the "SUPERSEDED — dedicated-IAM post-import runtime activation" entry
below). This is now the single highest-leverage open item: one administrator action activates a
week+ of already-reviewed work.

**Ask 1 (administrator with `run.services.setIamPolicy`):** grant `roles/run.invoker` on
`sap-post-import-dispatcher` to the runtime caller identity per
`docs/design/POST_IMPORT_ADMIN_COMPLETION.md`.

**Ask 2 (Boat/design owner):** `docs/design/DEFAULT_COMPUTE_SA_AUTOMATION_WORKAROUND.md` states the
workaround "no longer require[s] ... a Cloud Run service-level `run.invoker` binding," but the live
checker still reports it as blocking (unreconciled since the 2026-08-10 permission-narrowing note
below). Confirm which is correct — either correct the design doc, or identify the as-yet-unbuilt
call path that actually avoids the binding — before further work is built on top of the ambiguity.

## RESOLVED 2026-08-17 — `bq` CLI reauth blocking the mandatory dry-run gate (Claude Code's machine)

Raised 2026-08-14 by the senior data-engineer review. `scripts/bq_safe_query.sh` had failed with
`ReauthUnattendedError` on Claude Code's machine every session since 2026-08-10 (see
`docs/HANDOFF_QUEUE.md` entries 2026-08-10 19:18, 2026-08-11 10:15, 2026-08-11 18:45, and the
1-15-Aug Phase 1 attempt at 2026-08-17T15:30 ICT) — the interactive reauth step couldn't complete
in a non-interactive session. Boat reauthenticated the credential 2026-08-17. This should now
unblock every source unit that was dry-run-pending purely because of this:
`sql/ddl/075_v3_period_cutoff_calendar.sql`, `sql/ddl/067_v3_daily_completeness_snapshot.sql`,
`sql/adhoc/20260811_verify_period_cutoff_calendar.sql`,
`sql/adhoc/20260817_verify_mo_1-15aug_missing_from_sap.sql`, and
`sql/adhoc/20260817_verify_puii_edc_missing_from_sap.sql`. **Codex should retry Phase 1 of both
open interface tasks (`docs/tasks/TASK_1_15AUG_MISSING_INTERFACE_20260817.md`,
`docs/tasks/TASK_EDC_MISSING_INTERFACE_20260817.md`) and the three older dry-run-pending files
before assuming any of them are still blocked** — this entry is not itself proof the retry
succeeded, only that the credential should no longer be the reason it fails.

**Ask (whoever has working `bq` auth on that machine, e.g. Codex per the 2026-08-10 note):**
re-authenticate the legacy `bq` credential store once so the dry-run backlog can clear in a single
pass instead of being re-disclosed session after session.

## RESOLVED 2026-08-14 — Boat: recipient(s) for the new daily recon MTD email report

Boat asked (2026-08-14) for a daily 06:00 ICT email with the SAP↔CareOS month-to-date
reconciliation summary. Boat confirmed recipients same session: primary `piyaratt@rabbit.co.th`,
fallback `data@rabbit.co.th`. Codex should set Script Properties `RECON_MTD_RECIPIENT=piyaratt@rabbit.co.th`
and `RECON_MTD_FALLBACK_RECIPIENT=data@rabbit.co.th` per `workflows/DAILY_RECON_MTD_REPORT_DEPLOYMENT.md`
and proceed with review/rehearsal/deploy — no further input needed on this item.

## OPEN 2026-08-11 — Mo/Finance: duplicate QR installment correction decisions + untracked root cause

`docs/FINDINGS_DUPLICATE_QR_INSTALLMENT_20260804.md` (2026-08-04, read-only investigation,
**not yet Class-A reviewed** — review requested separately, see `RQ-20260811-2001-duplicate-qr-installment-finding`
in `docs/REVIEW_QUEUE.md`) answered Mo Pawinee's request about `L78611713`/`L78803976` and found a
genuine CareOS-payment-layer double QR-code collection, not a SAP pipeline bug. This ask was never
added here before, despite the finding's own caveats flagging it — recording it now:

1. **Per-order correction decision (Mo/Finance)**: for each of the 100 identified order items
   (44 in July 2026, ฿403,977; ฿1,078,326 total June–July), decide whether the duplicated charge
   is reassigned to a future installment period or refunded. The finding deliberately makes no
   recommendation and applies no correction — per this project's "money-impact finding →
   document and stop" rule.
2. **Confirm the 31-row ฿645/651 sub-pattern (Finance/product)**: 31 of the 100 rows have one leg
   at exactly ฿645 or ฿651 — flagged as possibly a legitimate fee (not the same defect) rather than
   folded into the "likely real duplicate" 69-row set. Needs an explicit answer before any bulk
   correction touches those 31.
3. **Root cause of the double QR collection itself (engineering, un-started)**: whether it's a
   double-tap on the payment page, a webhook firing twice, or a retry-after-timeout bug was
   explicitly not investigated by the finding — a separate task from the population/quantification
   work already done.
4. **Historical scope (Boat, if wanted)**: the finding's query window was deliberately narrowed to
   June 1 – July 30 2026 to match Mo's reported orders; an earlier unscoped run surfaced matching
   cases back to 2024, materially larger — quantifying the full historical population is a separate
   exercise, not yet requested.

This is a CareOS/payment-collection-layer item, outside this repo's SAP-integration build — recorded
here only because the investigation used this project's tooling/access and shares its money-impact
disclosure rule.

## OPEN 2026-08-11 — Finance: `sap_period_cutoff_calendar` correction/registry policy

**2026-08-24 confirmation makes this correction path immediately required.** Mo Pawinee
Tantheeraphonchai relayed at 13:51 ICT: “Boat Piyarat Toomsap แจ้งวัน closing period
1-Sep-26 (16.00) ค่ะ”. This explicitly changes the August-period cutoff from the previously
recorded `2026-09-01 14:00:00 Asia/Bangkok` to `2026-09-01 16:00:00 Asia/Bangkok`. The durable
human-input source is the Google Sheet `SAP V3 — FA Period Cutoff Confirmation`:
https://docs.google.com/spreadsheets/d/1K_LLlIfPgJWnKRJfJ1e4ZMkdf8M7_u2addZGbdwHo_Q/edit . The
14:00 row is retained as `SUPERSEDED`; the 16:00 row is `APPROVED`. Do not silently UPDATE live
period state or re-register the insert-only calendar row. A reviewed correction artifact is
required before changing V3 production state.

`sql/ddl/075_v3_period_cutoff_calendar.sql` (monthly cutoff automation source, PASS-pending
Class-A review) deliberately builds no UPDATE/correction path for a wrong cutoff row —
`sp_register_period_cutoff` is insert-only and rejects re-registration for an already-registered
`period_start`. This matches the governing finding's own gate
(`docs/FINDINGS_MONTHLY_CUTOFF_AUTOMATION_GAP_20260805.md`, "Gates before implementation" #1):
*"Confirm the registry/correction policy with Finance; do not assume cutoffs always occur on the
first day or at a fixed hour."* That confirmation has never been requested as its own tracked
item — recording it here now (flagged in Codex's review `docs/reviews/2026-08-11-a82409d-codex.md`
as still outstanding).

**Ask**: if a registered cutoff is later found wrong (wrong date/hour, wrong approver), what is the
correction mechanism — a superseding row with an explicit link back to the original, a formal
correction artifact reviewed like any other production change, something else? Do not assume a
fixed first-of-month/fixed-hour pattern; the design must accept whatever cutoff timing Finance
actually uses. Until this is answered, the calendar can only ever be appended to, never corrected,
and `sp_register_period_cutoff` will keep hard-rejecting any second attempt at the same
`period_start` — which is the deliberately conservative default, not a bug.

## OPEN 2026-08-07 — `rcb-motor-order-payment-sap-bucket-1` unreliable, real customer payments not reaching SAP

Root cause of missing VMI for `L78794968`, `L78583606`, `L78786429` traced to this Cloud Function
(the real RCL/RCB Motor interface file producer), not to any BigQuery view — see
`docs/FINDINGS_VMI_MISSING_EXPORT_PIPELINE_20260807.md`. Two confirmed failure modes in the last
week alone: an uncaught `smtplib.SMTPAuthenticationError` crash on 2026-07-31 (bad Gmail
app-password in its post-run notification step) and a hard 540s timeout on 2026-08-06, both after
all 8 CSV exports had already been written. This was already flagged as an open, unresolved defect
in `docs/SAP_SCHEDULER_INVENTORY.md` row 7 on 2026-07-26 — it is still not fixed 12 days later.
This repo does not hold this function's Python source (only its `sql/sap_view/*.sql` query
files), so a source fix cannot be prepared here without first pulling that source.

**Needs Boat/IT with `cloudfunctions.functions.update`/source access**: (1) fix or rotate the
Gmail credential and make the notification step non-fatal to the export, (2) resolve the
recurring timeout for real (parallelize the 8 sequential queries / split the batch / more
CPU-memory), not another ceiling bump. Until fixed, expect continued sporadic silent drops of
paid installment periods from the daily Motor interface, recoverable only via manual/month-end
backfill. Full action plan: `docs/tasks/TASK_FIX_RCL_MOTOR_EXPORT_RELIABILITY_20260807.md`.
Note: pulling the actual function source confirmed the CSV writes complete before both observed
failures, so this is not yet proven to be the sole cause for these 3 orders — the plan's step D
covers checking the SAP-side import log to close that gap.

## CLOSED 2026-08-06 — unavailable Cloud Run IAM administrators

Boat confirmed that `data@rabbit.co.th` and `piyaratt@rabbit.co.th` are not administrators and do
not have `run.services.setIamPolicy`. Do not retry that option under either account.

Binding workaround: reuse
`919786098205-compute@developer.gserviceaccount.com`, the project's default Compute service
account, for the unattended V3 runtime/caller identities and rely only on its pre-existing
permissions. No new IAM grant is authorized. A denied permission must fail closed and be recorded;
it must not be worked around with a public Cloud Run principal. See
`docs/design/DEFAULT_COMPUTE_SA_AUTOMATION_WORKAROUND.md`.

Created 2026-07-27 per `TASK_V3_GAP_CLOSURE_v2.md` (A0, A5, Housekeeping — "keep this current").
Nothing here blocks build work that doesn't depend on the specific answer; each item notes what
IS being done in the meantime.

## SUPERSEDED — dedicated-IAM post-import runtime activation

The 2026-08-06 default-SA decision above closes this administrator path. The historical inputs
below are retained for provenance and must not be pursued under the available user accounts.

**Historical Boat decision required:** explicitly approve or reject table-level
`roles/bigquery.dataEditor` for both dedicated runtime identities on only
`sap_integration_v3.v3_post_import_refresh_outbox`:

- `sap-post-import-dispatch@pacific-plating-282708.iam.gserviceaccount.com`
- `sap-post-import-watchdog@pacific-plating-282708.iam.gserviceaccount.com`

This exact-table grant is operationally sufficient but permits direct table DML outside the
reviewed procedures. Approval of a PASS review or of the overall project does not by itself record
informed acceptance of that residual permission. The alternative authorized-routine design needs
the routines in a different dataset from the protected table and therefore needs a separate
exception to the current `sap_integration_v3`-only DDL rule.

**Administrator action required after Boat's decision:** use an account with `iam.roles.create`,
project IAM administration, and Cloud Run/Pub/Sub service-policy authority to run the already
reviewed [post-import administrator completion](design/POST_IMPORT_ADMIN_COMPLETION.md).
It creates the two narrow custom Workflows roles, binds the dedicated identities, creates the
authenticated push subscription, and creates then pauses the watchdog scheduler. Do not resume
the scheduler or populate the Gmail publisher topic during this step.

The live activation checker currently passes safety and reports exactly three readiness blockers:
dispatcher `run.invoker`, authenticated push subscription, and watchdog scheduler. The current
`data@rabbit.co.th` account cannot complete the administrator-owned policy changes.

**2026-08-10 permission narrowing (Claude Code, read-only `testIamPermissions` evidence, no
mutation):** only one of the three blockers actually requires an administrator. Live, authoritative
permission tests against the real resources found `data@rabbit.co.th` already holds
`pubsub.subscriptions.create` + `iam.serviceAccounts.actAs` on the default Compute SA (sufficient
to create the authenticated push subscription), `cloudscheduler.jobs.create`/`.update` (also holds
`roles/cloudscheduler.admin` outright — sufficient for the watchdog scheduler), and
`run.services.update` (sufficient to redeploy the dispatcher/watchdog services under the new
identity). The account does **not** hold `run.services.setIamPolicy` on `sap-post-import-dispatcher`
(confirmed via the Cloud Run `testIamPermissions` API directly on that resource) or
`resourcemanager.projects.setIamPolicy`/`iam.roles.create` at the project level (confirmed via
Resource Manager `testIamPermissions`, empty result) — so it cannot self-grant this either. The
`run.invoker` binding on the dispatcher Cloud Run service remains the one genuinely
administrator-gated action; the push subscription and watchdog scheduler creation do not need to
wait for that administrator action and can proceed under the current account once reviewed.
**Note:** `docs/design/DEFAULT_COMPUTE_SA_AUTOMATION_WORKAROUND.md` states the workaround "no
longer require[s] ... a Cloud Run service-level `run.invoker` binding" — that appears to be a
design intent not yet matched by the live checker, which still reports `run.invoker` as an active
blocker. Needs reconciliation: either the design doc's claim needs correcting, or an as-yet-unbuilt
call path avoids the binding. Do not treat the push-subscription/scheduler pieces as blocked on
that reconciliation; they are independently unblocked per the permissions above.

## Boat / Google Apps Script owner — Unit 6 project identity and authorization

**Needed to finish daily automation:** provide or create the Apps Script project that will own
`workflows/sap_result_ingestion.gs`, and confirm the account that can complete its interactive
OAuth consent. The repository has no `.clasp.json`/Script ID and this computer has no authenticated
`clasp` installation, so Codex cannot safely identify or update the intended project.

Once available, deploy the reviewed source/manifest, set `PROJECT_ID`, `LOG_BUCKET`,
`ALERT_RECIPIENT=piyaratt@rabbit.co.th`, and optional `BQ_DATASET`, then install separate 15-minute
`pollSapResultMailbox` and `checkSapResultIngestionHeartbeat` triggers. Keep
`POST_IMPORT_REFRESH_TOPIC` blank until the dispatcher IAM, authenticated push subscription, and
synthetic rehearsal pass. The first authorization must be completed by the mailbox owner because
the script uses Gmail, BigQuery, Cloud Storage, Pub/Sub, and send-mail scopes.

**Separate completeness-report inputs:** approve one primary recipient that reaches Boat and one
distinct independent fallback recipient, plus the trigger cadence for
`dispatchPendingV3DailyCompletenessReports`. DDL 067 and the reviewed dispatcher remain source
only, and the nightly workflow does not call the snapshot procedure. A project staged with only
`sap_result_ingestion.gs` does not contain the completeness dispatcher; see
`FINDINGS_DAILY_COMPLETENESS_RUNTIME_GAP_20260805.md`.

## RESOLVED 2026-08-04 — LogID 21183 filename provenance and mirror reconciliation

The approved 2026-08-04 post-import extract/load/mirror/reconciliation completed. Boat confirmed
that SAP LogID `21183`'s `RCB_MOTOR_INSURANCE_RCB_06_V3_DAILY_NEWPAYMENT_20260803_`
`V3DAILY-20260803-113257-55042e7c_000000000000.csv` name is the SAP-interface rename of the
DELIVERED archive-ledger file `INSURANCE_RCB_06_V3_DAILY_NEWPAYMENT_20260803_`
`V3DAILY-20260803-113257-55042e7c`. The TXT log has no row count. The ledger has 558 distinct
identities, all of which match refreshed SAP mirror rows with `TransactionStatus='Paid'`; zero are
missing. The separate 584-row `RCB_MOTOR...072831-38902dd9` entry belongs to the earlier REJECTED
LogID 21178 run.

The remaining implementation gap is only the Unit 6 attachment-ingestion runtime for persisted
row-level attachment detail and automatic acknowledgement. Preserve the original archive name and
its SAP-interface rename as paired provenance; do not overwrite either identity.

## NonMotor InsuranceGroup master — Live SAP confirmation 2026-08-04

Boat confirmed the live SAP master with identical Code/Name/Mapping Code values and these Business
Unit codes: Cancer `BU-0010`, Corporate `BU-0006`, Health `BU-0003`, Home `BU-0012`, Inter
`BU-0004`, Life `BU-0005`, Miscellaneous `BU-0012`, Motor `BU-0001`, Motorbike `BU-0007`,
Personal Accident `BU-0008`, and TA `BU-0017`. Therefore the exact scheduled-query outputs
`Cancer -> Cancer` and `Home -> Home` are confirmed master mappings, alongside the already-known
`Health -> Health` and `Life -> Life`. `ERROR` is not a SAP InsuranceGroup value and remains held
and reported; do not silently map it to Miscellaneous.

## P0 — Aware disposition for July InsurerCode exclusions

Job `p0_insurer_risk_20260731_152353` at `2026-07-31 15:23:55 UTC` found 300 July-PaymentDate
records / 294 orders / THB 2,260,768.08 excluded as `INSURER_NOT_IN_MASTER`. Aware must confirm the
disposition for normalized codes `30`, `46`, `48`, `49`: add to SAP master, map to an existing
code, or intentionally hold. Do not silently restore/delete records; see
`docs/FINDINGS_INSURER_EXCLUSION_RISK_20260731.md`.

**Fresh check 2026-08-05 21:16 ICT:** the exact documented E3 rule found zero positive-DocEntry
`SAP_LIVE_FULL` rows and zero `sap_insurer_master` rows for every one of `30`, `46`, `48`, and
`49` (job `bqjob_r2f4166e07184b869_0000019fd2488a6e_1`; see
`docs/FINDINGS_INSURER_CODES_30_46_48_49_20260805.md`). They cannot be confirmed as accepted codes
from the current canonical source, so the hold remains. If “passed code” refers to a different SAP
object or a mapping to other values, provide that exact source/mapping.

## RESOLVED 2026-07-31 — RULE-09 narrow OLD_YEAR_NO_TOUCH exception

Boat kept `GREATEST(OrderDate, PolicyDate)` as the year-rule basis and approved one narrow
exception: `OLD_YEAR_NO_TOUCH` does not remove a row whose raw PaymentDate falls inside the open
calendar month. For July the exact window is `[2026-07-01, 2026-08-01)`; `lock_datetime` does not
extend it. No other exclusion rule inherits this exception.

## SOURCE READY 2026-08-04 — enrich excluded-record audit

Source DDL 032/037 now retains `amount` (successful charge amount in satang; nullable where no
charge exists) and processing `date_basis` on every `sap_excluded_records` row, sourced from the
existing `_rules` temp table. Exclusion predicates and `expected_state` output are unchanged.
Both complete files passed dry-run-only validation at 0 bytes. Deployment still requires Class-A
review and separate approval.
DDL 032 alone cannot add these columns to the existing table. The actual schema migration occurs
only when the reviewed DDL 037 procedure is deployed and later CALLed with separate mutation
approval; verify the columns and exclusion distributions as specified in runbook §7.

## RESOLVED 2026-07-31 — scheduler 401; run.invoker downgraded to P3 hygiene

The scheduler used an OIDC ID token against the Cloud Run Admin API, which requires OAuth. It was
changed to OAuth using the default compute service account and returned HTTP 200 at
`2026-07-31T14:16:30Z`; IAM was never the blocker. The former blocking Attila request below is
superseded. A future `run.invoker` grant for `sap-bucket-csv@` is P3 least-privilege hygiene only.

## Boat — extract timing before 2026-08-03 reconciliation

**Decision needed:** approve one manual extract immediately before reconciliation (recommended),
or add a permanent morning schedule. The current 20:30 ICT extract trails the ~01:30 ICT interface
import by about 19 hours. Until Boat decides, do not manually trigger the job.

## RESOLVED 2026-07-30 — GitHub remote URL

Repository remote is `https://github.com/BoatPiyarat/BI-SAP.git`. `origin` was configured and
`p0/stg-sap-state` pushed successfully on 2026-07-30. Do not request the URL again.

## RESOLVED 2026-07-30 — materiality buffer and grain

D12/D13 resolves the former tolerance input: ±฿10 **per order**, after order aggregation.
`MISPOSTING` has no buffer. Do not ask whether the threshold is per row/period/document again.

## RESOLVED 2026-08-05 — monthly accounting cutoff calendar

Boat approved the following ICT cutoffs for the reviewed monthly transition:

- July: `2026-08-03 15:00:00 Asia/Bangkok`
- August: `2026-09-01 16:00:00 Asia/Bangkok` — corrected 2026-08-24 13:51 ICT by Mo Pawinee
  Tantheeraphonchai relaying Boat Piyarat Toomsap; supersedes the earlier 14:00 approval. Durable
  confirmation: https://docs.google.com/spreadsheets/d/1K_LLlIfPgJWnKRJfJ1e4ZMkdf8M7_u2addZGbdwHo_Q/edit

Use these exact instants for the corresponding `sap_period_state` close transition; do not infer
other months. Finance remains owner of future monthly calendar entries.

## RESOLVED 2026-07-29 — Aware actual-received correction method

Aware and Sarawut/Boyd confirmed two supported methods. Adjustment lines use the original Period,
`ExpectedReceived=0`, and `ActualReceived=delta`; Cancel + new Paid is mandatory when
`ExpectedReceived` is incorrect or negative. Test evidence: adjustment `L79899055` /
`L79965977`; Cancel + Paid `L79899088` / `L79965966`. This closes the former validation-library
question “cancel+re-import vs manual SAP correction — รอคำตอบ Aware”; do not ask it again.

---

## SUPERSEDED 2026-07-31 — Attila IAM request was not blocking freshness

**Ask**: grant `roles/run.invoker` to `sap-bucket-csv@pacific-plating-282708.iam.gserviceaccount.com`
on the Cloud Run job `sap-extract-job`, so `sap-extract-schedule` (Cloud Scheduler, 20:30 ICT
nightly) can invoke it again — currently failing `401 UNAUTHENTICATED` every night (confirmed via
audit logs: this binding most likely never successfully applied in the first place, not a
regression — see `docs/knowledge/30_SAP_CHANGELOG.md` 2026-07-24 cont'd 6).

**Exact command** (already drafted, see `docs/knowledge/_draft_message_attila.md`):
```bash
gcloud run jobs add-iam-policy-binding sap-extract-job \
  --region=asia-southeast1 --project=pacific-plating-282708 \
  --member="serviceAccount:sap-bucket-csv@pacific-plating-282708.iam.gserviceaccount.com" \
  --role="roles/run.invoker"
```
**Current status**: scheduler automation works through OAuth with the default compute SA. Retain
this command only as a P3 least-privilege option for switching back to `sap-bucket-csv@`; it is not
a recovery action and manual compensation must stop.

---

## Aware (SAP vendor) — Q3a, the picking-rule question

**Ask**: when a period has MULTIPLE documents in SAP (see `sap_mirror_state.docs_considered > 1`,
328k+ keys), which document's `InvoiceNo`/status is authoritative? Draft already sent for review:
`docs/design/SAP_CANCEL_IMPORT_SPEC_INFERRED_v0.9.md`.

**In the meantime**: `sap_mirror_state`'s picking rule (Cancelled > Paid > Pending, non-empty
InvoiceNo wins ties, latest BatchRunDate wins remaining ties, highest DocEntry as final
deterministic tiebreak — added 2026-07-27) is live and tags every affected row
`PROVISIONAL_PENDING_AWARE_Q3A` so downstream consumers know which answers are still opinion, not
fact. Change only that one `ORDER BY` block when Aware answers.

## Aware (SAP vendor) — change-order supersession, separate from Q3a

**Ask**: when an old CareOS order is superseded through `careos.cancelled_change_orders`, must the
old order receive an explicit SAP `Cancelled` document, or does the replacement order supersede it
without a separate cancel import?

This is deliberately separate from Q3a: Q3a chooses the authoritative document when SAP already
has multiple documents; this question decides whether a superseded old order must receive a new
cancel document at all. Per D2, do not send this population until all three change-order preflight
checks are documented and passed and FA approves the batch.

Evidence population: **⚠️ PROVISIONAL — UNDER VERIFICATION: 9,625 order_items**, sourced from
`careos.cancelled_change_orders`, `careos.careos_orders`, `careos.carepay_transactions`,
`sap_integration_v3.stg_order_dim`, and the SAP mirror logic. Exact query timestamp was not captured;
evidence was recorded in session commit `19d9452` at 2026-07-29 17:58:53 ICT. Do not cite as a
production batch count until a provenance-complete rerun.

## Aware (SAP vendor) — Q4, Method-2 replacement naming

**Ask**: what exact SAP-facing OrderItem prefix/template must be used for a replacement generation
created by Method 2? Does the SAP C# code currently apply or recognize an existing prefix,
especially the `C#` convention observed around Credit Shell?

**Why this is open**: `-M2` cannot mean “revision 2”; `careos.careos_order_items` already has
**⚠️ PROVISIONAL 1,019 real `-M2` rows**, source query recorded in commit `73e94e0`, exact query
timestamp not retained. `-M1R2` is only a rejected-as-hardcode proposal, not a decision.

**In the meantime**: D10 requires a configuration parameter for the naming template/prefix.
Do not hardcode or deploy any replacement naming until Aware answers. Per D14, this question is a
blocker only for B2 (`ExpectedReceived` wrong); it is **not** a blocker for Class 1 or Class 2,
which use Method 1.

## Aware + FA — GL verification for two Method-1 pilots

**Ask after explicit pilot approval and execution**: verify both the SAP interface amounts and the
underlying GL/journal entries for:

1. Class 1 `AMOUNT_VARIANCE`: `L80046687`.
2. Class 2 `MISPOSTING`: `L79900064`.

D15 makes this pair authoritative. `0a69143`'s `L79871659`/`L80524847` pair is superseded:
the former is too close to the noise floor and has no confirmed CMI sibling; the latter was
rejected and has no JE, so it is only a rejection-detection test case.

Purpose: replace the theoretical question “can the interface fix GL?” with observed evidence.
Method 1 can correct item amounts but does not remove a duplicate document holding full Expected.
If that document generated a duplicate JE, the JE may remain. Do not expand either correction
population based only on balanced interface amounts; require explicit Aware/FA GL confirmation.

## FA — approve change-order cancel batch only after preflight

**Ask**: after Aware answers the supersession question and all three D2 preflight checks pass,
approve or reject sending the change-order cancel batch. No batch may be sent before explicit FA
approval.

Current candidate count is the same **⚠️ PROVISIONAL 9,625 order_items** described immediately
above; source tables and evidence timestamp are inherited from that entry, not a second count.

## Boat / IT — parent cancel flag not set after every child item was cancelled

**Ask**: should `careos.careos_orders.is_cancelled` automatically become TRUE when every
`careos.careos_order_items` child has a non-NULL `cancel_time`?

Latest diagnostic found **⚠️ PROVISIONAL 25 orders / 50 items** with all child items individually
cancelled but the parent order flag not TRUE. This is an IT/data-consistency question, not a reason
to cancel active siblings or change the canonical revised-D1 formula. Sources:
`careos.careos_orders`, `careos.careos_order_items`, `careos.cancelled_change_orders`, and
`sap_integration_v3.sap_mirror_state`; queried 2026-07-29, exact query timestamp not retained,
evidence committed in `fa9b351` at 2026-07-29 18:46:14 ICT. Session evidence says only a small
subset requires SAP action; do not derive a batch from this count.

**Also Aware/SAP DB** (same access gap as Q3a — cannot query `[RCB_LIVE_DB].[dbo].[@INSURANCE]`
directly from this environment):
- Total `@INSURANCE` row count + breakdown by row type — would convert the 373,971
  ceiling-not-estimate "missing DocEntry" number (`docs/FINDINGS_SAP_MIRROR_20260726.md` §10) into
  a real completeness percentage. 2-minute query at source.
- Whether `U_OrderItem = 'Invoice'`/`'SaleOrder'` (541 real, distinct documents that lost their
  true OrderItem to a literal SAP object-type-label string, 2024-03 to 2024-05, confirmed
  non-recurring since — see FINDINGS §12) is a known/recoverable extract defect on SAP's side.
- The 5 (OrderItem, Period) keys with 11-13 duplicate same-amount same-status Pending documents
  clustered in a single ~2.5-week window in 2024-03/04 (FINDINGS §12) — confirmed NOT ongoing and
  NOT real distinct postings (at most 1 row per key ever carried real money), but root cause
  (extract fan-out vs genuine source duplicate rows) unconfirmable without SAP DB access.

---

## Boat — interface_daily_status (A2) alert gap: MISSING/STATUS_CONFLICT can't be alerted on yet

`interface_daily_status` (built 2026-07-27, `030_interface_daily_status.sql`) uses the revised
status vocabulary OK/PENDING_ACK/MISSING/STATUS_CONFLICT/PAID_AFTER_CANCEL/
CANCEL_TIME_MISSING/UNROUTED. `CANCEL_TIME_MISSING` keeps an effective cancellation visible when
`careos.careos_orders.is_cancelled IS TRUE` but `careos.careos_order_items.cancel_time IS NULL`,
so PAID_AFTER_CANCEL timing cannot be evaluated. The current deployed classification predates
revised D1 and needs Claude Code implementation/0A–0B verification.

Literally alerting on "MISSING/STATUS_CONFLICT present" would still fire every day. **⚠️ PROVISIONAL
— UNDER VERIFICATION; DO NOT CITE until Claude Code reports passing 0A/0B and STATUS_CONFLICT
decreases in line with D1 acceptance:** after E1–E3
filtering, the 2026-07-29 14:01:28 ICT snapshot is MISSING 576 and STATUS_CONFLICT 34,758
(Return Triage's 340,051/59,501 snapshot was pre-filter). Only wired an alert for `PAID_AFTER_CANCEL`
(rare, 7 rows today, always actionable) and staleness (no fresh row by late morning). Real
Source DDL 066 now provides an immutable daily history snapshot and increase-based checker for
MISSING/STATUS_CONFLICT. It intentionally contains no threshold seed. Boat must approve the
maximum day-over-day record and order increases for both statuses before the checker can run;
missing or duplicated active configuration fails closed.

Also unverified and worth your review: the exact classification logic for STATUS_CONFLICT and
PAID_AFTER_CANCEL (see the judgment calls documented at the top of `030_interface_daily_status.sql`)
- built from my own best-effort reading of the task spec, not yet confirmed against your intent.
One real bug already caught and fixed during build: the first version of PAID_AFTER_CANCEL didn't
compare payment date against cancel date, so it fired on the normal "paid some periods, cancelled
later" pattern (1,898 false positives) - fixed to compare timing directly (now 7 genuine cases).

## Boat — email alerts go to data@rabbit.co.th, not you directly

### Validation-regression thresholds — source ready, approval needed

DDL 068 replaces the obsolete global `>60` heuristic with per-check day-over-day record and order
increases. Boat must approve the maximum increase for each active validation `check_name` before
the v2 checker can run. No historical count was silently adopted as a threshold. After reviewed
deployment, acceptance still requires one synthetic breach reaching a human recipient and one
healthy run producing no alert.
For a newly introduced `check_name`, the first comparison is against zero: inspect its first
snapshot before threshold approval. The full onboarding sequence is canonical in
`docs/design/SAP_RUNBOOK_v3.md` §5c; no day-zero history may be silently seeded.

**2026-08-05 clarification:** Boat approved the alert threshold/config approach, but no numeric
threshold rows were supplied and the reviewed DDL deliberately contains none. The remaining
executable inputs are:

- DDL 066 effective date plus `max_record_increase` and `max_order_increase` for `MISSING`;
- DDL 066 effective date plus the same two values for `STATUS_CONFLICT`;
- DDL 068 effective date plus those two values for every active `sap_validation_error.check_name`
  after its first real snapshot is inspected.

General approval does not authorize treating the current backlog, fixture numbers, or the obsolete
global `>60` value as any of these rows.

Confirmed 2026-07-27: every BQDTS `enableFailureEmail` alert (dead-man's-switch/missed-extract,
column-contract guard, validation-regression) is owned by `data@rabbit.co.th`
(`ownerInfo.email` on the transfer config) - that's where the failure emails go, not
`piyaratt@rabbit.co.th`. If you don't check that inbox (or it doesn't forward to you), these
alerts won't reach your phone this week. The separate 6am/daily-digest routine (RemoteTrigger
cloud agent) does email you directly, since it uses your own Gmail connector - that one's fine.
Options if this matters: (a) check `data@rabbit.co.th` too while away, (b) set up a forward from
that inbox to yours, (c) tell me and I can look into whether the transfer configs can be
recreated under different ownership (would need to be done under the right identity, not
something I can just reassign).

For the future Gmail attachment-ingestion writer, Boat must approve an Apps Script trigger
interval strictly shorter than its 60-minute lookback and the human channel for an independent
no-successful-poll heartbeat alert. The writer cannot be accepted until a deliberate poll-gap test
reaches that channel; see runbook §5b.

## Boat — 2 new findings from return-triage (2026-07-29), both outside sap_integration_v3

1. **`SAP_LIVE` bloat**: 151,024 → 6,858,653 rows in 3 days (distinct DocEntry only 106,873→122,169).
   Leading hypothesis: the loader (`sap-order-payment-initial-phase`) crash-looped on its 1024 MiB
   memory limit for ~16 min around 2026-07-29 02:43-02:59 UTC and plain `INSERT` retries reinserted
   rows. Daily count comparison at 2026-07-30 09:10:41 UTC found no distinct-DocEntry deficit
   against Boat's supplied SQL row counts, but set-level real loss remains **UNVERIFIED** because
   source DocEntry IDs were not supplied for anti-join. Phase B/C remain ON HOLD. `SAP_LIVE` is an append-only audit trail: no cleanup,
   dedup, truncate, rebuild, or delete is allowed before the incident closes and a reviewed
   preservation/retention decision exists. Read-only investigation must precede loader changes.
   See `docs/RETURN_TRIAGE_20260729.md` §1 and HANDOVER queue item 2.
2. **Legacy Cloud Functions reporting `crash` every night** (07-26/27/28, both Motor and NonMotor):
   root-caused to an expired/revoked Gmail SMTP app-password in the post-export notification email
   step (`mailer.py`), NOT the export itself - confirmed via log ordering that every real GCS file
   write completes before the crash. Cosmetic for data delivery, but the notification email nobody
   is receiving, and Cloud Function status alone looks like nightly failure. See
   `docs/RETURN_TRIAGE_20260729.md` §4.

## CLOSED — `sap_integrety_2025_RCL`: dormant/obsolete housekeeping candidate

90-day consumer check: `sap_integrety_2025_RCL` and `sap_integrety_2025_Q1` have **no real
consumers** in 90 days (only my own investigation queries today) - the bug is real but currently
dormant. Boat confirmed on 2026-07-30 that `sap_integrety_2025_RCL` has no real consumer:
**no notification is required and no owner follow-up remains**. Classify it as dormant/obsolete
and retain only as a housekeeping/archive candidate.

**Separate note:** `audit_010_careos_missing_in_sap_detail` IS actively used by Boat (3 times in 90 days)
and has the same unguarded-SUM code pattern, but Return Triage verified its actual zero-match output
is unaffected because the risky SUM is never used for matched rows. No fix is currently requested
for that view. THB delta for `sap_integrety_2025_RCL` computed by year/BU - see FINDINGS §14; note the sign
flips between years (2024/2025 positive, 2026 negative), consistent with undefined/inconsistent
behavior rather than one-directional overstatement - don't read the raw totals as "money lost."
`reconcile_revenue 202508_booking` (one of the 6 remaining views) wasn't relocated in this pass -
genuinely unverified, not confirmed dormant or active.

## Boat / accounting — standard decisions

1. **B2B rows**: currently 0 rows in every source table at every layer — confirm this is expected
   (business line genuinely has no B2B SAP records yet) rather than a silent extract-side filter
   losing them. Low priority (no evidence it's causing any reported problem).
2. **ProcessingFee divisor**: RCL `/103.3` is confirmed. Onetime `/107` remains unconfirmed —
   keep it as-is and flag until Finance confirms; do not re-open the RCL decision.
3. **C2 policy** (PHASE C review item): item-level quarantine vs run-level atomic validation
   failure handling for the shadow/real export layer — needs an explicit choice before PHASE C
   builds the export-blocking logic, not a default silently picked.
4. **EDC channel matrix**: only KBANK confirmed (`RCB-EDC-KBANK`); need the full bank list for
   `CREDIT_CARD_INSTALLMENT` orders on other banks before PHASE B can route them correctly.

---

## Housekeeping notes (not blocking, just tracked)

- `docs/design/SAP_INTERFACE_REDESIGN_V3.md`, `SAP_PIPELINE_E2E_DESIGN_v3.md`,
  `SAP_DATA_PREP_DESIGN_v3.md`, `SAP_DASHBOARD_DESIGN_v1.md`, `SAP_RUNBOOK_v3.md` — all corrected
  2026-07-27 to remove stale `raw_sap_live`/B1 references (see `30_SAP_CHANGELOG.md`).
- `vw_dash_extract_scheduler_health` (the new widget the dashboard design doc now specifies) is
  designed but not yet built — see `docs/AS_BUILT_V3.md`.


## 2026-10-19 — requested four-item SAP recovery held after live verification

Scope: Paid replacements L81020554-V1 (old L80991502) and L80999097-V1 (old L80806589); Cancelled L81026484-M1/V1. VPN and secure Windows SQL profile succeeded. Direct dbo.[@INSURANCE] SELECT at 2026-10-19T04:59:04Z found no documents for the four targets, and confirmed old change-cancel DocEntry 2540828 / 2533076.

Current candidate evidence (not a release PASS): L81020554-V1 Expected 13546.67 vs Actual 15035.00, missing PolicyNo; L80999097-V1 Expected 5456.00 vs Actual 5808.00. Both are one-period Credit Shell replacements. The alternate creditshell view emits NULL expected/actual values. Source mirror confirms cancellation on both L81026484 items, pending refund records and old-order link L81023226, but no target SAP predecessor. Do not invent Paid/Cancel predecessors or infer refund amounts.

Required inputs: source owner to populate verified L81020554 PolicyNo; Finance/source owner to reconcile replacement discount, carried credit and refund disposition for both Paid items; SAP integration/Finance to resolve the missing-predecessor lifecycle for L81026484. Money differences are candidate comparisons, not certified GL loss/refund liabilities. No CSV, upload, deployment, source change or refund initiated.

Evidence and resumable item states: C:/dev/sap-request-20261019-four-items/assessment.json, sap/, source.json, payload.json and job metadata. Source job bqjob_r85d29b2138ded3a_000001a15287f376_1; payload job bqjob_r79e8e981e3f91a9f_000001a1528a1371_1. Payload dry-run 10032822623 bytes; source charges table modified 2026-10-19T04:03:27.378Z. No GL/JE certification.



## 2026-10-19 — user confirmation: blank PolicyNo is allowed

Boat explicitly confirmed in the four-item SAP recovery session that the policy number may be blank. This supersedes earlier required/nonblank PolicyNo wording. Preserve blank PolicyNo without inventing a value; normalize missing source PolicyNo to an empty interface field when preparing a payload. Nonblank PolicyNo still follows the existing length and source-integrity checks.

L81020554-V1 no longer requires source PolicyNo repair and MISSING_POLICY_NUMBER has been removed from its local assessment. The remaining one-period Credit Shell amount discrepancy and alternate-path NULL money still block release. L80999097-V1 financial hold and L81026484-M1/V1 missing-predecessor holds are unchanged. Historical notes asking for the policy number are superseded by this entry. No interface/upload performed; existing validator code has not yet been changed or revalidated.


## 2026-10-19 — L80999097-V1 Credit Shell allocation confirmed

User instructed: allocate Credit Shell equal to Expected (5456.00), and split the remaining 352.00 as Credit Shell in the next period with ExpectedReceived=0. Total carried credit remains 5808.00; do not discard the remainder or interpret it as a refund. This resolves the amount-disposition question for L80999097-V1 only.

The captured source is FULL_PAYMENT and the live candidate is Period=1/TotalPeriods=1. Pending clarification: does next period explicitly authorize Period=2 and TotalPeriods=2, or refer to an additional receipt row within Period=1? Do not silently increase TotalPeriods or reinterpret the destination. Existing split InvoiceNo, conservation, exact-payload and independent-review gates remain. No payload/upload generated. L81020554-V1 is not covered by this item-specific amount instruction.


## 2026-10-19 — L81026484-M1/V1 Paid-before-Cancelled recovery authorized

User explicitly instructed that cancelled items absent from SAP be imported as Paid first, then Cancelled. Apply to the requested L81026484-M1 and L81026484-V1. This overrides their prior missing-predecessor lifecycle hold and permits reconstruction from verified successful-payment evidence despite current CareOS cancellation. It does not authorize invented payments, duplicate sibling allocations, customer refunds, or blind resend. Validate/review exact Paid payload, confirm direct SAP Paid acknowledgement, then derive and validate/review Cancelled from the accepted immutable Paid documents before cancellation upload. Preserve receipt identity and prove change-order provenance from L81023226. No repeat lifecycle approval is needed.


## 2026-10-19 — superseding FULL_PAYMENT decision for L80999097-V1

User explicitly specified FULL_PAYMENT uses Period=1 and ActualReceived=5808.00. Keep TotalPeriods=1 and existing ExpectedReceived=5456.00. This supersedes the earlier 5456.00 + 352.00 split and removes the next-period clarification and amount-disposition hold for this item. Do not cap ActualReceived, create Period=2, or invent a refund. The difference is explicitly accepted for this item's one-period payload; source, mapping, prior-delivery, exact validation and independent review remain required. This is not a confirmed rule for unrelated RCL installment cases.


## 2026-10-19 — remaining recovery scope explicitly approved

User confirmed L81020554-V1 FULL_PAYMENT keeps ActualReceived15035.00, ExpectedReceived13546.67, Period1/TotalPeriods1, no split. Blank PolicyNo remains allowed. User also explicitly approved inclusion of L81023226-M1/V1 change-cancellation before Paid then Cancelled for L81026484-M1/V1. No further routine scope approval required. Each phase must pass exact validation/independent review and direct SAP acknowledgement before the next. Preserve original invoice/payment fields on cancellations; no customer refund is initiated.


## 2026-10-20 06:15 ICT — corrected phase-1 delivery; ACK pending

Original targeted log23028 rejected L80999097-V1 (PaymentChannel mapping). Nightly logs23031/23032/23036 likewise rejected target rows; file-level success-with-error was not target ACK. Evidence: C:/dev/sap-request-20261019-four-items/latest_receipt_analysis.json and raw MIME receipts.

Root cause: historical stored PaymentChannel Code is not current importer U_MappingCode proof. Current dbo.[@PAYMENTCHANNEL] mapping is RCB-Credit Shell (Code Credit Shell; account9001-17); Credit Shell and RCB-CreditShell are invalid outgoing channel mappings. Pre-export now requires exactly one current exact U_MappingCode and a nonblank trimmed account. Method validated separately in dbo.[@PAYMENTMETHOD]. No masters or legacy schedules changed.

Explicit user decisions preserved: FULL_PAYMENT 1/1 Actual5808.00 Expected5456.00 and Actual15035.00 Expected13546.67, no split; blank policy allowed; old L81023226-M1/V1 change-cancel authorized before L81026484 Paid then Cancelled.

Direct SAP at23:12:31Z: target4 absent, old L81023226 pair still Paid; predecessor cancelled documents for other replacements unchanged. Exact content/delivery independent review PASS (/root/payload_review); local prior inventory reconciles known rejected original; current periods open; independent exporter disabled; no concurrent legacy activity after source snapshot. Source successor check finds only L81023226 -> L81026484, no successor of target orders.

Create-only upload and byte readback verified:
- INSURANCE_RCB_03_CHANGE_RECOVERY_20261020_A.csv: two Paid, SHA cf91e0265f60900992ef2395a95749e65110fe801e93d94c7ed884ff88c784aa, generation1792451677053830 at23:14:37Z.
- INSURANCE_RCB_02_CANCEL_CHANGE_RECOVERY_20261020_L81023226.csv: two predecessor change-cancellations, SHA cc2ae88f105f036dacae99e47b1b738ab7b33d4e6f80b0c6e8766bd22decb2bc, generation1792451689234199 at23:14:49Z.

Status is UPLOADED_PENDING_ACK, not completed. Durable ledgers phase1_delivery_0.json/phase1_delivery_1.json prohibit replay. Await item-level SAP ACK before dependent L81026484 phases. Never rerun batch after partial/unknown delivery. No source mutation, customer refund, JE certification, legacy deployment, or external messages sent.


## 2026-10-20T15:25:22.296093 — L78870324-V1 explicit full-actual approval
User explicitly authorized Paid ActualReceived8945.22, ExpectedReceived8300.01 retained, Period1/TotalPeriods1. Preserve the645.21 excess in the same approved receipt; do not invent sibling/refund/split. Source ONLINECARD/OMISE maps to OMC Omise Credit Card / RCB-Omise Credit Card-BAY, account1135-01 verified live. Scope now includes this additional Paid import; previous status-only limitation is superseded. Exact candidate awaits independent delivery review. Evidence C:/dev/sap-request-20261019-four-items/l78870324_authority.json and phase4_candidate.json.


## 2026-10-22 — requested change-order recovery awaiting scoped financial decisions

User requested L81072106 Paid, L81048975 Paid, L81036194 Cancelled(Change order); repeated order IDs were deduplicated. Import authorization covers the requested outcome, but does not resolve the monetary/refund ambiguities below. No production upload, CSV, SAP write, refund, or GL certification performed.

Direct RCB_LIVE_DB.dbo.[@INSURANCE] captured 2026-10-22 17:26:36 ICT: no requested target documents. Original L78977757-M1/V1 remain Paid, DocEntry2544908/2544909, Actual645.21/8500.00; original L79012592-M1/V1 remain Paid, DocEntry2548206/2548207, Actual645.21/20370.00. No original change-cancel documents were found.

CareOS source and change-order links prove L78977757 -> L81036194 -> L81072106 and L79012592 -> L81048975. Item-level source cancellations are true on both original pairs and L81036194-M1/V1. Requested final Paid items are active FULL_PAYMENT. These are separate linked stages, not additional independent successful receipts.

Current sap_view.RCB_Motor_process_3_change candidates (not a validated release): L81072106-M1 Actual/Expected645.21; V1 Actual8500.00 Expected5900.00; L81048975-V1 Actual21015.21 Expected12622.79. Source records pending refunds on L81036194 total9145.21 and on L79012592 total8392.42. Do not subtract a merely pending refund or silently carry the full credit into the replacement. Prior Oct19 full-actual approvals were item-specific. User questions are pending for both chains, including intermediate Paid-before-Cancel recovery of L81036194. Preserve existing accepted original invoice identities; the transfer-based generated replacement IDs still require exact provenance review.

Source freshness metadata: careos_order_items modified2026-10-22T10:01:13.192Z, carepay_charges10:01:55.933Z; carepay_refunds last modified2026-10-21T13:15:04.019Z; cancelled_change_orders last modified2026-10-21T15:35:59.808Z. Pending refund claims are from this mirror, not proof of bank payout. Fresh refund evidence is required at release.

Live payment registry at2026-10-22T10:29:11.786Z confirms Credit Shell method / RCB-Credit Shell outbound channel (account9001-17); October OFPR AbsEntry43 is open. Both create/change positional contracts have56columns. Current alternate creditshell view emits NULL monetary values for L81048975 and must not be exported.

Independent reviewer /root/review_request_holds confirms HOLD all requested target rows pending decisions and exact release gates. No safe independent target subset: M1 is part of the unresolved linked chain/shared refund. Conditional sequencing: original change-cancel ACK -> intermediate/replacement Paid ACK -> L81036194 change-cancel ACK -> final L81072106 Paid ACK. Each step requires exact immutable payload validation, independent review, current prior-delivery check, create-only intent/readback, and item-level SAP ACK.

Evidence C:/dev/sap-request-20261022/assessment.json, sap_baseline.json, chain_facts.json, payload.json, current_payment_masters.json. Source job bqjob_rf63958ea8bacb3f_000001a163252f15_1; chain job bqjob_r64861516efeade37_000001a16326c281_1; payload job bqjob_r23584fa16ee6edd4_000001a163265234_1. SQL/logs/metadata: workspace outputs/sap_request_20261022. Repository pull --ff-only failed due pre-existing divergent branches; no merge/rebase or unrelated modifications made. Review status scan reported zero assigned OPEN reviews; no exact-payload release review exists for this request.
