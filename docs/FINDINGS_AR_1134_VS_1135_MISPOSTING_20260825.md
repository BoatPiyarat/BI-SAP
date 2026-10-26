# FINDINGS — AR 1134-01 vs 1135-01 misposting (EDC/KBANK onetime credit-card orders), 2026-08-25

**Status: READ-ONLY INVESTIGATION ONLY. Nothing fixed. Not notified outside the team.**
Per this project's hard rule (money/accounting impact → document + stop). Reported by Pui (chat,
2026-08-25) with a list of 224 unique OrderIDs; verified here directly against the live SAP B1
Journal Entry tables. Awaiting Boat's decision.

## Source of the reported list

Pui reported 224 unique OrderIDs (no item suffix) that she believes were interfaced to
`1134-01` "AR Installment - Motor" when they should have landed on `1135-01` "AR Credit Card and
Payment Gateway". Full list preserved in this session's chat log and in
`sql/adhoc/20260825_verify_ar_1134_vs_1135_misposting.sql`.

## Access used (new for this investigation)

- `sap_integration_v2.SAP_LIVE_FULL` (BigQuery) has no GL-account column — cannot confirm postings
  from it, only payment characteristics.
- Confirmed live on `RCB_LIVE_DB` (SQL Server, `172.25.25.3,1433`) via the existing WireGuard
  tunnel `SAP-Piyarat-Toomsap`, using credentials Pui supplied in chat (not recorded in any repo
  file). Read-only `SELECT` only; no INSERT/UPDATE/DELETE issued.
- `OACT` confirms the two account names verbatim: `1134-01` = "AR Installment - Motor" (Postable),
  `1135-01` = "AR Credit Card and Payment Gateway" (Postable).
- `[dbo].[@INSURANCE].U_JETransId` — the column that looks like the intended OrderItem→JE link — is
  **0% populated across all 2,088,654 rows** in the live table (checked, not assumed). It is not a
  usable link and should not be relied on by any future query.
- The real, working link confirmed empirically: `JDT1.LineMemo` embeds the OrderItem verbatim as
  its first token, e.g. `L78667850-V1_THC-28_V-0012_บริษัท ธนชาตประกันภัย จำกัด (มหาชน)_#1`.

## Verified result

Query: `JDT1` joined to `OACT`/`OJDT`, filtered to `Account IN ('1134-01','1135-01')`, matched to
Pui's 224 OrderIDs via `LineMemo LIKE '<OrderId>-%'`.

| Metric | Count |
|---|---:|
| OrderIDs reported by Pui | 224 |
| Reported OrderIDs found in live JDT1 under 1134-01/1135-01 | **142** |
| Of those, with the primary AR **debit** line posted to `1134-01`| **142 (100%)** |
| Of those, that *also* carry a small secondary `1135-01` **credit** line (fee-only, ~฿295–฿1,082) | 20 |
| Reported OrderIDs not found in JDT1 under either account (not yet posted, or a different account/format) | 82 — not investigated further per stop-and-document rule |
| Total THB debited to `1134-01` across the 142 confirmed orders | **฿1,601,582.47** |
| JE `RefDate` range covering these postings | 2026-08-01 to 2026-08-21 |

Every one of the 142 orders that could be traced to a live JE has its **primary AR receivable**
posted to `1134-01` (Installment), not `1135-01` (Credit Card and Payment Gateway) — a 100% hit
rate among traceable orders, not a scattered handful. In 20 cases there is also a small `1135-01`
credit line, but that appears to be a separate processing-fee entry (values like 295.00, 305.00,
320.04, 645.21, 1082.36 recur, all far smaller than the main premium receivable) — it does not
change where the main receivable itself landed.

## Payment-pattern corroboration (from SAP_LIVE_FULL, before DB access existed)

Before direct DB access was arranged, BigQuery `SAP_LIVE_FULL` was checked for the same 224
OrderIDs: 142 matched a SAP order-item row (bare `-V1` suffix), and 136 of those 142 shared an
identical shape — `PaymentMethod = 'EDC EDC'`, `PaymentChannel = 'RCB-EDC-KBANK'`, `TotalPeriods =
1`, `TransactionStatus = 'Paid'`. Per this project's own confirmed decision
(`AGENT_RULES.md` — *"CREDIT_CARD_INSTALLMENT = ONETIME flow (bank pays in full), TotalPeriods=1,
channel RCB-EDC-<bank>"*), this shape is a onetime credit-card settlement, which is exactly the
class of order `1135-01` exists for. The DB-side JE check above confirms this is not just a
plausible inference — it is what actually posted.

## Mechanism (narrowed, not fully root-caused) — added 2026-08-25, same session, per Boat's ask

Boat asked directly whether this traces to PaymentChannel/PaymentMethod being sent wrong from the
interface file. Checked with two further read-only probes against `RCB_LIVE_DB`:

1. **Pui's 224-order list is a curated "known-bad" list, not a random sample** — an independent
   sample of 40 recent EDC EDC/RCB-EDC-KBANK/TotalPeriods=1/Fully-paid orders (not drawn from
   Pui's list) split roughly 50/50 between `1134-01` and `1135-01`. The 100% hit rate in the
   142-order table above is a property of how Pui's list was selected, not evidence that this
   payment channel is *always* misposted. This matters for scoping the fix.
2. **The defect is confined to Voluntary (`-V`) items; Compulsory (`-M`) items are never
   affected.** A 300-order sample (same filter as above), cross-tabbed by item-suffix letter vs.
   posted account:

   | Item type | Posted 1135-01 (correct) | Posted 1134-01 (wrong) |
   |---|---:|---:|
   | `-M` (Compulsory) | 93 | **0** |
   | `-V` (Voluntary) | 91 | **185** |

   `U_PaymentMethod`/`U_PaymentChannel`/`U_TotalPeriods` are identical across every row in this
   table — the fields the interface file carries are internally consistent for both correctly- and
   incorrectly-posted orders. One specific order (`L78562220`) has *both* an `-M1` item that
   correctly posted to `1135-01` and a `-V1` item that incorrectly posted to `1134-01`, same order,
   same payment, same batch — direct evidence the account choice is being made per line/item, not
   per order or per payment method.
3. **Not a per-batch/per-day toggle either.** The same JE batch (`TransId`) contains both correctly-
   and incorrectly-posted `-V` lines side by side (e.g. `TransId 79424`: 7 correct vs 26 wrong;
   `TransId 77568`: 14 correct vs 31 wrong) — ruling out "some daily import run has the bug, others
   don't."
4. No account-code field exists anywhere in `[dbo].[@INSURANCE]` (checked: no column name matches
   `%acc%`/`%gl%`), and `[dbo].[@PAYMENTMETHOD]` (`Code`/`Name`/`U_MappingCode`) carries no GL
   account either — the AR account is not something BI/CareOS transmits explicitly; it is decided
   entirely on the SAP side at posting time.

**Conclusion so far: this does not look like wrong PaymentChannel/PaymentMethod data sent from the
interface file** — those values are consistent and correct in both good and bad cases. The defect
sits in whatever program decides the AR account per JE line inside SAP (posting/import logic,
Aware-owned per `AGENT_RULES.md`), is scoped to Voluntary items only, and has an unidentified
secondary trigger that splits Voluntary items roughly 2:1 wrong vs. correct.

## Discriminator found — `U_ExpectedReceived` vs `U_ActualReceived` (added same session, Boat's ask)

Boat asked to compare the Expected-vs-Actual-received pattern between correctly- and
incorrectly-posted Voluntary items. Pulled `U_ExpectedReceived`/`U_ActualReceived` for 500 `-V`
items (same EDC/KBANK/TotalPeriods=1/Fully-paid filter as above), joined to the JE account each
one actually hit:

| Posted account | n | ExactMatch (Expected = Actual) | Expected ≠ Actual (shortage/overage) |
|---|---:|---:|---:|
| `1135-01` (correct) | 144 | **139 (96.5%)** | 5 |
| `1134-01` (wrong) | 343 | 1 | **342 (99.7%)** |

This is a clean, near-total split. Orders where `U_ActualReceived` reconciles exactly to
`U_ExpectedReceived` post correctly to `1135-01`. Orders with **any** variance between expected and
actual — usually a small shortage (examples: Exp 13686.08 / Act 13542.15, diff 143.93; Exp 15035.00
/ Act 14871.06, diff 163.94, recurring identically across several unrelated orders, suggesting a
consistent fee/rounding-type gap rather than random error) — post to `1134-01` instead, regardless
of the fact that the payment method was still a onetime EDC/KBANK credit-card settlement.

**Working hypothesis:** the SAP-side posting logic appears to treat "exact reconciliation" as the
signal for the Credit Card/Payment Gateway path (`1135-01`) and falls back to the Installment path
(`1134-01`) whenever `ActualReceived` doesn't exactly match `ExpectedReceived` — as if any variance
is being (wrongly) treated as evidence of a partial/installment-style receivable rather than what
it actually is: a fully-settled onetime card payment with a small fee/rounding difference between
expected and actual. This is a hypothesis from data pattern, not confirmed against the posting
program's source — the small shortage amounts (145–165 THB recurring, matching typical processing
fee sizes seen in `U_ProcessingFee`) are consistent with this being a fee-handling quirk rather
than a genuine payment shortfall, but that link (fee ≈ shortage) has not been verified row-by-row
yet.

Not yet checked: whether the shortage amount reconciles to `U_ProcessingFee` (or another fee field)
row-by-row, which would confirm *why* a fee-adjusted receipt trips the wrong branch. Further
isolation still needs either (a) that row-level fee reconciliation check, or (b) reading the
SAP-side posting program's account-selection logic directly — the latter is vendor-owned (Aware)
per this project's hard rules and out of reach from here.

## CORRECTION (added same session, immediately after the section below) — the "gross vs net" claim was wrong

The section below originally claimed `compu_detail.gross_premium` reads the smaller VAT/duty-
*excluded* figure, causing a basis mismatch. **That was wrong — verified and retracted.** Checked
`careos.careos_order_items` directly for `L80512627-M1`/`-V1`: `gross_premium = net_premium +
vat_amount + stamp_duty` exactly (2,041.56 = 1,900.00 + 133.56 + 8.00) — i.e. in this source table
"gross" correctly means the larger, VAT/duty-*inclusive* figure (standard usage), and
`compu_detail.gross_premium` (used in the M-subtraction formula) reads exactly that same column
`order_items.gross_premium`. Also checked the view's own `M1` output directly (not assumed):
`ExpectedReceived = ActualReceived = 2,041.56` for `L80512627-M1` — the full inclusive figure, not
1,900.00. So the M-subtraction in `ActualReceived` for V uses the correct, complete figure; there is
no gross/net basis inconsistency in the formula itself.

*(Separately, worth flagging to whoever owns this view: its **output column aliases** are
confusingly reversed from source-table naming — `order_items.net_premium AS GrossPremium` and
`order_items.gross_premium AS TotalPremium` at lines 117/120 of the live view — so `SAP_LIVE_FULL`'s
`GrossPremium`/`TotalPremium` columns do NOT mean what their names in `careos_order_items` would
suggest. This caused my own confusion above; it is a naming-clarity issue, not something with a
numeric effect on the misposting.)*

**The real source of the 163.94 THB gap, verified against `careos.carepay_charges` directly:**

| | Value |
|---|---:|
| Theoretical combined total (M `gross_premium` 2,041.56 + V `TotalPremium` 15,500.00 − `Discount_master` 465.00) | 17,076.56 |
| Actual card charge (`careos.carepay_charges.amount` for this order's transaction, status `SUCCESSFUL`) | **16,912.62** |
| Gap | **163.94** |
| `transaction_snapshot_price_summaries.discount_amount` (what the view subtracts) | 465.00 |
| `transaction_snapshot_price_summaries.net_discount_amount` | −465.00 (same magnitude, does not explain the gap) |

The customer's card was genuinely, verifiably charged ฿16,912.62 (a real, `SUCCESSFUL` transaction)
— ฿163.94 less than what `careos_order_items`' current price fields (`gross_premium`/`price`) say
the combined order should cost after the recorded discount. No discount/fee field in
`carepay_transaction_snapshot_price_summaries` accounts for the missing ฿163.94. **This is not a
formula bug in the view — it is a genuine discrepancy between the order's priced amount
(`careos_order_items`) and what was actually collected (`careos.carepay_charges`)**, for reasons
not yet identified (candidates: price changed between quote-time and charge-time, a promo/coupon
applied at the gateway that isn't reflected in `discount_amount`, or the transaction snapshot used
for charging was taken before a later price adjustment). This downstream discrepancy is what then
produces `ExpectedReceived ≠ ActualReceived` for the Voluntary leg, which — per the correlation
established earlier — is what appears to trip SAP's posting logic into `1134-01` instead of
`1135-01`.

## ROOT CAUSE CONFIRMED — missing `WHT` term in `ExpectedReceived` (added same session)

Boat asked to check `careos_orders.invoice_price`, `careos_order_items`, `careos.carepay_charges`,
`carepay_transactions`, and `carepay_transaction_snapshot_price_summaries` together against
`L80512627`. Traced all five:

| Source | Field | Value |
|---|---|---:|
| `careos_orders` | `invoice_price` | **16,912.62** |
| `carepay_transactions` | `amount` | 16,912.62 |
| `carepay_charges` | `amount` (status `SUCCESSFUL`) | 16,912.62 |
| `carepay_transaction_snapshot_price_summaries` | `net_premium_amount` | 16,912.62 |
| `carepay_transaction_snapshot_price_summaries` | `discount_amount` (3% agent discount) | 465.00 |
| `carepay_transaction_snapshot_price_summaries` | **`wht_amount`** | **163.94** ← exact match to the gap |

Four independent sources (`invoice_price`, `transactions.amount`, `charges.amount`,
`net_premium_amount`) all agree on 16,912.62 as the true total — confirming this order has exactly
one snapshot (`is_current = true`, `version = 1`, checked — not a stale-snapshot join issue).

**The bug:** the view computes `WHT_master` from `transaction_snapshot_price_summaries.wht_amount`
and exposes it as an output column `WHT` (forced to 0 for Compulsory items, kept for Voluntary), but
**never subtracts it in the `ExpectedReceived` formula**:

```sql
-- live view, ExpectedReceived for a Voluntary item, charge_rank = 1 — WHT is computed elsewhere
-- in the same SELECT but NOT included here:
ROUND((TotalPremium)+TotalEIR+TotalSBT+ProcessingFee_master+ProcessingFeeVat_master
      +ShippingFee_master+ShippingFeeVat_master-Discount_master, 2)
--                                              ^^^^^^^^^^^^^^^^^ only Discount is subtracted; WHT is not
```

For `L80512627-V1`: `TotalPremium(15,500.00) − Discount_master(465.00) = 15,035.00` — this misses
subtracting `WHT (163.94)`, which the actual charge amount (correctly) already reflects. Hence
`ExpectedReceived (15,035.00) − ActualReceived (14,871.06) = 163.94 = wht_amount` exactly. Every
`-V` item with nonzero `wht_amount` will show this same pattern; `-M` items never do because `WHT`
is unconditionally forced to `0` for `MOTOR_TYPE_COMPULSORY` regardless of the true
`transaction_snapshot_price_summaries.wht_amount` (a related but separate simplification for the
Compulsory leg — its `Expected`/`Actual` both equal `gross_premium` by construction either way, so
it never shows a gap even though its own WHT handling is also not fully modeled).

**This is a confirmed, fixable SQL bug in
`pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_fully_paid`: the `ExpectedReceived`
CASE branch for Voluntary/`charge_rank = 1` items is missing a `- WHT_master` (or equivalent) term.**
Once fixed, `ExpectedReceived` should equal `ActualReceived` for these orders, which — per the
correlation established earlier (`Expected = Actual` → `1135-01`; `Expected ≠ Actual` → `1134-01`)
— would very plausibly stop the AR misposting for this class of order. **Not yet proven**: that
fixing this view is sufficient on its own (the SAP-side account-selection logic that reads this
equality has still not been directly inspected — vendor-owned, Aware). This is a strong, concrete,
one-line-fix candidate to hand to Aware/Boat for confirmation before any change is made — per this
project's hard rules, no fix has been applied; this remains read-only investigation.

## Reframing per Boat's Aware agreement (added same session) — is this actually a defect at all?

Boat states there is an existing agreement with Aware: `WHT` may legitimately be sent as `0` in the
interface, and **SAP is expected to hold the resulting gap (WHT + rounding + discount residue) in a
separate "ส่วนต่าง" (variance/suspense) account**, for accounting to adjust manually later. Under
that design, `WHT = 0` in the interface (the condition traced above) is intentional, not a bug —
and the open question becomes whether the *observed SAP posting behavior* matches that agreement,
or whether either SAP's JE logic or our interface is doing something other than what was agreed.

**Checked against the live JE data already gathered: it does not match a "small gap parked
separately" design.** The amounts landing in `1134-01` are not small residuals — they are the
**entire primary AR receivable**:

| OrderItem | Amount posted to `1134-01` |
|---|---:|
| `L78667850-V1` | ฿14,470.68 |
| `L78795358-V1` | ฿27,900.00 |
| `L80512637-V1` | ฿31,200.00 |
| (142 orders, total) | ฿1,601,582.47 |

These are full order-level receivables, three to four orders of magnitude larger than the
~฿100–200 gap that `WHT`/rounding alone would produce (`L80512627`'s own gap was ฿163.94). If the
Aware agreement means *only the small gap* should land in a variance account while the bulk of the
receivable still posts correctly to `1135-01`, **what's actually happening does not match the
agreement** — the entire receivable, not just the residual, is going to `1134-01`. That points to
either (a) SAP's JE logic not implementing the agreed variance-account behavior correctly — routing
the *whole* order to `1134-01` instead of routing *only the gap* to a suspense account while
`1135-01` still takes the bulk, or (b) the interface not sending whatever signal SAP needs to
apply the agreed split correctly. **Which of these it is has not been determined** — it needs
Boat/Aware to confirm the precise mechanics of the agreed variance-account design (does the
interface send a flag/field for it? does SAP compute it from Expected≠Actual as inferred here, or
some other signal?) before concluding whether this is a SAP-side or interface-side gap.

## Historical onset (added same session, Boat's ask) — this is chronic since 2025-07, not new

Boat asked to trace history: what account did this class of JE hit before, and when does this
pattern first appear. Pulled every Voluntary (`-V`) debit line in `JDT1`/`OJDT` for `1134-01` vs
`1135-01`, by month, across the full history in `RCB_LIVE_DB` (`427,162` total rows across both
accounts; overall `RefDate` range 2023-04-30 to 2026-08-25):

| Period | Wrong (`1134-01`) rate | Note |
|---|---:|---|
| 2023-07 to 2023-09 | 67–69% | Earliest records at all (first: **2023-07-31**). Very high, small volume — likely a different, early-system-era cause, not investigated. |
| 2023-10 to 2023-12 | 28.6% → 12.7% | Declining. |
| 2024-01 to 2024-03 | 3.2–3.9% | Converging toward clean. |
| **2024-04 to 2025-06** | **~0%** (two outlier spikes: 2024-09 at 13.1%, 2025-04 at 7.2%; every other month 0.0–0.2%) | **A genuinely clean 15-month stretch.** This is strong evidence the underlying issue was largely absent (or fully compensated) during this window. |
| **2025-07 to 2026-08 (current)** | **7.6–13.9%, every single month, never returning to 0%** | **The chronic regime starts here and has not broken since — 14 consecutive months.** This is the operative onset for the behavior Boat is asking about, not the 2023 date. |

**Reading:** two distinct eras, not one continuous bug. The 2023 era is a separate, unstudied,
early-system anomaly that was resolved by April 2024. The current problem is a *new, persistent*
condition that began around **2025-07** and has run every month since without a single clean month
— unlike 2024-09 and 2025-04, which were isolated one-off spikes surrounded by clean months. This
distinction matters for root-causing: whatever changed in ~June/July 2025 (a deploy, a config
change, an Aware-side update, a CareOS pricing/WHT change) is the more relevant target than
anything from the 2023 launch period. **Not yet done:** identifying what specifically changed
around that date — no deploy/change log has been checked yet for June–July 2025 in this session.

## Company vs individual customer split (added same session, Boat's ask) — sharp step-change confirmed at July 2025

Boat asked to check `isCompany` from CareOS specifically, and whether the interface data pattern
changed vs. the JE behavior changing on stable input. Found the discriminator field:
`careos_orders.data` JSON has `$.policyHolder.isCompany` (and `$.policyHolder.companyName`).
Cross-checked against `[dbo].[@INSURANCE].U_Title`: **every company customer has a blank
`U_Title`** (verified 20/20 blank-title sample = `isCompany: true` with real company names, e.g.
"บริษัท โพสโค (ไทยแลนด์) จํากัด"; 20/20 individual-title sample = `isCompany: false`) — `U_Title`
blank is a clean, reliable proxy for company customer without needing the BigQuery join every time.

**Company customers have a dramatically higher misposting rate than individuals, and it starts on
an exact date, not a gradual drift:**

| Month | Company: wrong/correct | Company rate | Individual: wrong/correct | Individual rate |
|---|---:|---:|---:|---:|
| 2025-05 | 0 / 386 | 0.0% | 0 / 13,522 | 0.0% |
| 2025-06 | 0 / 362 | 0.0% | 83 / 8,144 | 1.0% |
| **2025-07** | **370 / 351** | **51.3%** | 1,126 / 7,947 | 12.4% |
| 2025-08 | 557 / 271 | 67.3% | 615 / 7,504 | 7.6% |
| 2025-09 to 2026-08 | (steady) | **59.7–67.4%** | (steady) | **5.2–10.6%** |

Both cohorts step-change at the exact same month (2025-07), from ~0% to their respective steady
elevated rates, and both stay elevated every month afterward with no reversion — this is a single
systemic change at a shared date, not two independent drifts, and not a gradual volume effect
(company order *volume* stays roughly flat across the period; only the *rate* jumps). Company
customers run ~6–9× the individual rate throughout, consistent with the WHT mechanism confirmed
earlier: Thai withholding tax on premium payments applies to juristic (company) payers in
circumstances it does not for individuals, so company-customer orders are far more likely to carry
nonzero `wht_amount` — which the `ExpectedReceived` formula's missing `-WHT` term (found earlier)
then turns into an `Expected ≠ Actual` mismatch. The smaller-but-real 5–10% individual-customer
rate suggests a second, smaller contributor exists too (rounding, or some individuals do carry
nonzero WHT) — not isolated in this session.

**What this does and doesn't answer**: it pins the onset to a specific month (2025-07) shared by
both cohorts, which is a strong lead for whoever owns deploy/change history (Aware, or whoever
last modified `sap_dashboard_carepay_fully_paid` or the CareOS WHT computation) to check what
changed right at that boundary. **Not yet done in this session**: pulling the actual change/deploy
log for late June–early July 2025 to identify what changed — that is the natural next step but
requires access to deploy history this session hasn't queried.

## MAJOR COMPLICATION (added same session) — a dedicated WHT variance account exists and is in use; the JE structure for broader company-customer samples does not match the earlier model

Boat asked for 5 correct + 5 wrong company-customer records per month, 2025-05 to 2026-08. Pulling
these (across all payment channels, not just EDC/KBANK) surfaced something the earlier,
narrower analysis (scoped to `EDC EDC`/`RCB-EDC-KBANK` only) did not show: **a dedicated account,
`2142-10` "บัญชีส่วนขาด WHT" (WHT shortfall/variance account), already exists and is actively
used** — this is very likely the "ส่วนต่าง" account from Boat's Aware agreement. Full JE detail
for 5 concrete examples (`JDT1` joined to `OJDT`/`OACT`, all lines for the order, not filtered to
1134/1135 this time):

**`L77760142-V1` (2025-12, TransId 56660):**
| Account | Name | Debit | Credit |
|---|---|---:|---:|
| 1112-03 | Bank Saving Account - KBANK | 10,908.07 | |
| **1134-01** | **AR Installment - Motor** | **106.12** | |
| 6021-04 | Discount | 340.65 | |
| **2142-10** | **บัญชีส่วนขาด WHT** | **106.12** | |
| 2121-02 | Account Payable Trade - Non Related Companies | | 11,354.84 |
| 9001-17 | Contra Account - For Refund | | 106.12 |

**`L78399012-V1` (2026-08, TransId 78503)** — same shape: Bank 27,841.91 dr, `1134-01` 279.99 dr,
Discount 869.75 dr, `2142-10` 279.99 dr, `2121-02` 28,991.65 cr, `9001-17` 279.99 cr.

**`L77603344-V1` (2025-10, TransId 52241)** — has BOTH: `1135-01` **44,316.52** dr (the bulk),
`1134-01` 475.94 dr (small), Discount 5,933.08 dr, `2142-10` 475.94 dr, `2121-02` 50,280.37 cr,
Processing Fee Revenue 416.05 cr, `9001-17` 475.94 cr.

**Three things this changes:**
1. In every example, the small amount hitting `1134-01` is **not the full receivable** — it is
   WHT-sized (matches the WHT gap mechanism confirmed earlier) and is mirrored by an identical
   debit to `2142-10`, the dedicated variance account. The bulk of the money moves through
   `2121-02` "Account Payable Trade" and a bank/contra account — **not through `1134-01`/`1135-01`
   as a simple customer-AR choice** the way the original EDC/KBANK-scoped analysis modeled it.
2. `2121-02` is an **Accounts Payable** account ("Trade - Non Related Companies"), not AR — this
   JE shape looks structurally different from a customer premium receipt; it may represent paying
   the insurer/counterparty net of what was collected, with WHT handled as a side entry. This is
   outside what this session can safely interpret without accounting-process context Boat/Finance
   has and this session does not.
3. `L77603344-V1` shows both mechanisms in the same JE: the bulk correctly on `1135-01`, **and**
   a small residual also landing on `1134-01` (paired with `2142-10`). If `2142-10` is the intended
   sole home for the WHT variance, then **`1134-01` picking up an identical-sized duplicate entry
   alongside it may itself be the real, narrower defect** — not "the whole receivable goes to the
   wrong account" (which is what the original EDC/KBANK-scoped list showed), but "a redundant
   WHT-sized entry leaks into `1134-01` when it should only go to `2142-10`."

**This does not cleanly reconcile with the earlier EDC/KBANK-scoped finding** (full receivable,
thousands of baht, landing in `1134-01` with no `1135-01` line at all, e.g. `L78667850-V1`
฿14,470.68). Two possibilities, not yet distinguished: (a) there are genuinely two different defect
mechanisms depending on payment channel (EDC/KBANK vs. Transfer/Omise/etc.), or (b) the earlier
LineMemo-prefix join (`LineMemo LIKE '<OrderItem>-%'`) may have been matching JE lines from a
different transaction type sharing the same OrderItem in its memo (e.g. an AP-side settlement JE),
conflating populations. **This needs Boat/Finance's read on what `2121-02`/`9001-17`/`2142-10` mean
in this business's JE design before drawing further conclusions — flagging and stopping here rather
than guessing further**, per this project's rule to document and stop on money-adjacent findings.

## DEFINITIVE: it's the JE/posting behavior that changed, not the interface input (added same session)

Boat's exact ask: hold the input constant (`PaymentChannel` + whether `ExpectedReceived ==
ActualReceived`) and check whether the SAME input shape maps to a different account before vs.
after the 2025-07 boundary. If the mapping rule is stable and only the input *mix* shifted, the
interface changed. If the same input shape starts mapping to a different account, the posting
behavior itself changed on stable input.

Pulled the full company-customer (blank `U_Title`) population (11,160 rows, 2025-05 to 2026-08),
cross-tabbed by `(period, PaymentChannel, EXACT-or-GAP-match, Account)`:

| Period | Channel × match (representative rows) | `1134-01` | `1135-01` | Wrong rate |
|---|---|---:|---:|---:|
| **before 2025-07** | *every channel, EXACT and GAP alike* | **0** | *(all of them)* | **0.0%, no exceptions** |
| 2025-07 onward | `RCB-Transfer-KBANK/KTB/SCB/BAY`, GAP | 2,444 | 1 | **~100%** |
| 2025-07 onward | `RCB-EDC-*`, EXACT | 0 | 143 | 0.0% (still correct) |
| 2025-07 onward | `RCB-EDC-*`, GAP | 867 | 881 | **~49–50%** |
| 2025-07 onward | `RCB-Omise Credit Card-BAY` / `QR Prompt Pay-BAY`, GAP | 2,179 | 2,195 | **~50%** |
| 2025-07 onward | `RCB-Omise Credit Card-BAY` / `QR Prompt Pay-BAY`, EXACT | 108 | 675 | 12–19% |
| 2025-07 onward | Credit Shell, GAP | 567 | 14 | **97.6%** |

**This is definitive.** Before 2025-07, `GAP` cases (`Expected ≠ Actual`) already existed in this
population and posted to `1135-01` without exception — so a nonzero WHT/rounding gap was never, on
its own, a problem before that date. After 2025-07, the *exact same* channel-and-match-shape input
starts splitting between `1134-01` and `1135-01`, in some channels close to a coin flip, in others
(Transfer channels) essentially 100% wrong. Since the input shape (channel, and whether the amounts
reconcile) is identical on both sides of the boundary and the outcome is not, **the interface/input
did not change — the JE/posting behavior did**, right around 2025-07. This rules out "CareOS
started sending different data" as the cause and points squarely at whatever decides the account at
posting time (SAP-side logic, or a process between the interface and the JE) as the place that
changed.

**Not yet done:** identifying the specific change (deploy, config, code) that landed at that
boundary — this session has not queried any deploy/change history.

## Exact onset date and why August 2026 is when this surfaced (added same session, Boat's ask)

**Exact onset: 2025-07-01.** Day-level counts of V-item debit lines (all customers, not just
company), 2025-06-15 to 2025-07-14:

| Date | `1134-01` (wrong) | `1135-01` (correct) |
|---|---:|---:|
| 2025-06-15 to 2025-06-30 | 0–3/day (background noise) | 28–481/day |
| **2025-07-01** | **413** | 730 |
| 2025-07-02 to 2025-07-14 | 3–23/day (new elevated baseline) | 15–431/day |

A single enormous spike lands exactly on **2025-07-01** — the first calendar day of the month, 413
wrong entries in one day versus a background rate of 0–3/day beforehand. This reads as a bulk
event: either a backlog of pending orders got batch-processed that day under new (defective) logic,
or whatever changed took effect starting that date and immediately applied to everything queued.
After the spike, the rate drops but stays persistently elevated (3–23/day, roughly 10–15% of daily
volume) for the rest of July and every month since — matching the monthly figures found earlier.

**Why this surfaced now, in August 2026, not earlier — monthly wrong-dollar-amount trend, all
V-items, `1134-01` debit sum:**

| Month | Wrong amount (`1134-01`) | Note |
|---|---:|---|
| 2025-06 | ฿16,866.08 | pre-onset baseline |
| **2025-07** | **฿4,356,699.82** | onset spike (matches the 2025-07-01 day spike) |
| 2025-08 to 2026-07 (13 months) | ฿507,211 – ฿1,121,479 | steady chronic baseline, ~฿500K–1.1M/month |
| **2026-08 (partial — data through ~08-21/25)** | **฿3,997,851.61** | **a second large spike, ~4–8× the steady baseline, on a month that isn't even complete yet** |

For 13 straight months (2025-08 through 2026-07) the wrong-amount stayed in a fairly narrow
฿500K–1.1M/month band — plausibly small enough to sit inside normal reconciliation noise/tolerance
and go unremarked. **August 2026 breaks that pattern**: already ฿3.99M wrong with the month not
even finished, comparable in scale to the original 2025-07 onset spike and 4–8× the typical month.
This magnitude jump is the most likely reason the issue became visible enough for Pui to notice and
report it now, even though the underlying defect has been running continuously, at a smaller and
easier-to-miss scale, since 2025-07-01.

**Not yet done:** why August 2026 itself has elevated volume/rate (a second bulk event similar in
shape to 2025-07-01? a volume increase in company-customer or Transfer-channel orders specifically
that month? not decomposed by day yet for August).

## ⚠️ METHODOLOGY CORRECTION — several claims above about company customers are overstated (added same session)

While preparing concrete examples for an Aware message, full-JE inspection revealed the "does this
order have a `1134-01` debit line" test used throughout the company-customer analysis **cannot
distinguish three structurally different things**:

**A) True full misposting** (what the original Pui-reported list actually is — re-verified,
unchanged): a simple 2-line JE, e.g. `L78667850-V1`: `1134-01` debit ฿14,470.68 / `2121-02` credit
฿14,470.68 — no `1135-01` line at all, no WHT/discount lines. This is real, confirmed, and the
original 142-order/฿1,601,582.47 finding for the EDC/KBANK-scoped, mostly-individual-customer
population **stands as originally reported.**

**B) WHT-residual duplicate** (the dominant shape found in the broader company-customer sample):
`1135-01` gets the full, correct amount, e.g. `L78879036-V1`: `1135-01` debit ฿26,180.00 (full) +
`1134-01` debit ฿274.77 (WHT-sized) + `2142-10` (WHT variance account) debit ฿274.77 (identical,
paired) + offsetting lines. **This is not the same defect as (A)** — `1135-01` is correct and
complete; `1134-01` is picking up a small, separate residual balance mirrored in the dedicated WHT
variance account. Financially much smaller per order, and arguably a different bug (duplicate
posting into `1134-01` alongside `2142-10`, not a wrong-account choice for the receivable).

**C) Self-offsetting, net zero**: e.g. `L78636974-V1` — `1134-01` debit 645.21 then credit 645.21
in the same JE, net effect zero. Not a defect at all.

**Corrected company-customer classification** (net `1134-01` balance per order, `has_1135_line`
flag, 2025-05 to 2026-08, company customers only):

| Month | True misposting (A) | WHT-residual dup (B) | Other/unclassified |
|---|---:|---:|---:|
| 2025-06 | 0 | 10 | 4 |
| 2025-07 | 29 | 162 | 105 |
| 2025-08 to 2026-08 (each month) | 1–18 | ~140–250 | ~190–310 |

**True full misposting (A) among company customers is rare (single digits to ~20/month), not the
dominant pattern.** The "company customer rate 60–67%" and the exact-date/dollar-spike analysis
further above were computed from the flawed any-`1134-01`-line test and **conflate (A), (B), and
(C)** — they overstate true misposting for company customers substantially and should not be cited
as-is. The `2025-07-01` onset date and "JE logic changed, not interface" conclusion likely still
hold in a general sense (this account-family's behavior was essentially inactive before that date
for this population), but the magnitude/rate figures tied to "wrong" need to be re-derived with
this corrected net-balance method before quoting them further, and the "Other/unclassified" bucket
(the largest one) has not been characterized at all yet.

**What this means for any message to Aware or further action:** use the original EDC/KBANK,
mostly-individual-customer, 142-order/฿1,601,582.47 finding (type A, cleanly verified, simple JE
shape) as the primary evidence — it has held up under scrutiny. Do not cite the company-customer
60–67% rate or the "why August" dollar-spike analysis (which summed `1134-01` debits without
netting against credits or checking for a paired `1135-01` line) without redoing them net-of-credit
and split by JE shape. Not yet done: re-running the full monthly/onset/dollar-impact analysis with
the corrected three-way classification; characterizing the "Other" bucket; checking whether type-A
misposting itself has a clean onset date the way the flawed aggregate did.

## ✅ 100% CONFIRMED for August 2026 company customers, card/gateway channels (Boat's goal met for this scope)

Boat asked to keep investigating until 100% confident, scoped to August 2026 company customers,
across CareOS/interface/SAP layers. Corrected the channel scope first: `RCB-Transfer-*` and
`Credit Shell` never touch `1135-01` by design (no card/gateway leg exists for a bank transfer),
so comparing them against "should be 1135-01" was a category error in earlier analysis — excluded.
Restricted to `RCB-EDC-*` / `RCB-Omise*` (the only channels where `1135-01` is structurally the
correct account), company customers (blank `U_Title`), August 2026 (through ~08-21):

| Bucket | n | Total `1134-01` amount |
|---|---:|---:|
| Correct (`1135-01` gets the full amount) | **204** | — |
| **True misposting (no `1135-01` line at all)** | **3** | ฿19,410.97 |

**True misposting is rare here — 3 orders out of 207 (1.4%), not the 60–67% earlier (flawed)
figures suggested.** The 3: `L78745610-V1` (฿7,500.70), `L80616601-V1` (฿5,955.15),
`L80580491-V1` (฿5,955.12).

**100% clean discriminator found:** `@INSURANCE.U_ActualReceived` for these 3 is `0.00`, `-55.15`,
`-350.14` respectively — **zero or negative.** Checked all 204 correctly-posted orders: **0 of 204
have `ActualReceived ≤ 0`.** Every single true-misposting case has an invalid (non-positive)
`ActualReceived`; every correctly-posted case has a valid positive one. This is not a
probabilistic correlation — it is exact and total for this population.

**Traced to source, ruling out CareOS raw data and SAP JE logic:**
- `careos.carepay_charges` (the raw charge table) is clean for all 3: single `SUCCESSFUL` charge
  each, correct positive amounts (฿7,500.70 / ฿5,549.84 / ฿5,844.85) — **CareOS's raw charge data
  is not the problem.**
- No Compulsory (`-M`) sibling exists for any of the 3 orders in `careos.careos_order_items` —
  ruling out the earlier gross-premium-subtraction mechanism as the direct cause here.
- The numbers reconcile exactly to **`ActualReceived = charge_amount − TotalAmount`** for all
  three (e.g. `L80580491`: 5,549.84 − 5,899.98 = **−350.14**, exact match; `L80616601`: 5,844.85 −
  5,900.00 = **−55.15**, exact match; `L78745610`: 7,500.70 − 7,500.70 = **0.00**, exact match).
  This is a real, reproducible, wrong computation — the item's own `TotalAmount` appears to be
  getting subtracted from its own charge (as if it were a sibling's premium), which should never
  happen for a Voluntary-only order with no Compulsory sibling.
- This computation happens in `pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_fully_paid`
  (the same view already implicated in the earlier WHT-formula finding) — **not** in a CareOS
  source table (verified clean above) and **not** in SAP's JE posting logic (SAP is correctly and
  consistently reacting to whatever `ActualReceived` value it receives — it posts to `1134-01`
  whenever `ActualReceived ≤ 0`, which is arguably reasonable defensive behavior given genuinely
  invalid input, not a SAP-side bug).

**Verdict for August 2026 company customers, true full misposting: root cause is 100% confirmed
to be in the BigQuery interface view, not CareOS source tables and not SAP JE logic.**

Ruled out the `compu_detail`/Compulsory-sibling-subtraction mechanism specifically for these 3
orders — reproduced the view's exact `compu_detail` CTE and queried it directly for all three
`order_id`s: **zero rows returned**, confirming `compu_detail.gross_premium IS NULL` for all
three, so the `ActualReceived` `CASE` should fall to `ELSE COALESCE(ActualReceived_master, ...)`
= the raw charge amount directly — which is correct and positive. The wrong (negative/zero) value
these 3 orders actually get is therefore coming from somewhere else inside `onetime_master`'s
construction (candidates not yet checked: the `DISTINCT`/multi-row fan-out from joining
`order_items` to a transaction with `charges`/`follow_ups`/`transaction_snapshots`; the `change`
CTE linking this order to a related/superseded order; or a second, unrelated charge/transaction
being picked up for the same `OrderID` elsewhere in the join chain). **Closing this last specific
line is the one remaining open item** — everything needed to act (which layer, which table is
clean, which signal predicts it with 100% accuracy) is already established.

## Aware's confirmed SAP rule (Sarawut/Boyd, Kanjana/June, via Nong/Mo, same session) — ground truth, supersedes this session's inference on the JE-selection trigger

Aware directly confirmed the actual SAP posting rule (not inferred — stated by the team that owns
the posting program):

- **Normal case**: `ExpectedReceived = ActualReceived` → full, correct JE (`Dr` payment-channel
  clearing, `Dr` Discount, `Dr` ส่วนขาด WHT (`2142-10`) → `Cr` AP Insurer (`2121-02`), `Cr`
  Shipping/Processing Fee Revenue + VAT). **This normal path does not touch `1134-01` or `1135-01`
  at all** — both only appear in exception paths.
- **`ExpectedReceived = 0`**: `Dr` payment-channel = `ActualReceived` → `Cr` "ลูกหนี้ BP
  Installment" (**`1134-01`**) = `ActualReceived` — the **entire** amount, unconditionally. This is
  the confirmed mechanism for full misposting (Type A in this doc).
- **`ExpectedReceived ≠ ActualReceived` (both nonzero)**: the *difference* posts to `1134-01`
  (as a `Credit` in Nong's example, with `Contra Account - For Refund` debited for the full
  `ActualReceived`) — this is a different JE shape from the `WHT-residual` pattern (`2142-10`-
  paired) found earlier in this doc; there appear to be multiple distinct JE templates depending on
  the specific mismatch scenario, not just the two characterized so far.
- Boyd's worked example (`L77286597`): first interface (`-V1`) had `ExpectedReceived = 0` →
  posted the `ExpectedReceived=0` JE (full amount to `1134-01`). That item was then cancelled and
  re-interfaced as `-V2` with `ExpectedReceived = ActualReceived` (matched) → posted the normal,
  correct JE. **Two different OrderItems, two different interface events, two different JE
  outcomes — both correct given what each interface actually carried.**

## ⚠️ Important caveat this confirms — `@INSURANCE` is current-state, not an audit trail

Checking Aware's `ExpectedReceived=0` rule against `L78667850-V1` (original Pui-list example)
produced a contradiction worth recording: **current** `@INSURANCE` shows `ExpectedReceived =
14,470.68` (nonzero) and `ActualReceived = 0.00` — the *opposite* shape from Aware's stated
trigger, even though the JE (`Dr 1134-01` / `Cr 2121-02`, full amount) matches the `ExpectedReceived
=0` JE shape structurally. The most likely explanation, given Boyd's `L77286597` story: **this
order may have been re-interfaced after the JE posted** (the same cancel/resubmit pattern), so the
`@INSURANCE` row visible now reflects a *later* state than what was live when the JE was created on
2026-08-01. `@INSURANCE` has no version/history column exposed to this session — it is a live
mutable table, not an append-only log — so **`ExpectedReceived`/`ActualReceived` read from it today
cannot be assumed to equal what SAP actually received at JE-posting time for any order that may
have been re-interfaced since.** A broader check across 902 currently-flagged type-A-shaped August
order-items found only 103 (11.4%) currently show `ExpectedReceived=0`; the other 799 (88.6%) show
nonzero — consistent with many of them having been re-interfaced/updated after posting, not with
Aware's rule being wrong. **This means further verification of "what actually triggered a given
historical JE" needs an audit/history table (if one exists) rather than trusting current
`@INSURANCE` state — not available/queried in this session.**

## Consolidated picture and fix-plan direction for `sap_dashboard_carepay_fully_paid`

Per Boat's ask to investigate and plan a fix for the view, here is what is now confirmed vs. still
open:

**Confirmed, ground-truth (from Aware) and independently corroborated (from this session's data
work):**
1. SAP's `ExpectedReceived=0` → full-to-`1134-01` fallback is real, designed behavior, not a SAP
   bug — SAP is correctly reacting to what the interface sends.
2. The view computes `ExpectedReceived = 0` **by design** whenever `charge_rank <> 1` (line ~263:
   `WHEN charge_rank <> 1 THEN 0`), where `charge_rank = ROW_NUMBER() OVER (PARTITION BY
   transaction_id ORDER BY create_time)` over `SUCCESSFUL` charges only (line ~28). **This is the
   leading suspect for how `ExpectedReceived` ends up `0` on a real, complete transaction**: any
   transaction with more than one `SUCCESSFUL` charge row (retries, corrections, or a
   cancel-then-resubmit that reuses the same `transaction_id`) will have its later charge(s) forced
   to `ExpectedReceived=0`, even if that later charge is the genuine, final, correct one.
3. Separately, August 2026's 3 confirmed company-customer true-misposting cases show the mirror
   symptom (`ActualReceived ≤ 0`, `ExpectedReceived` positive) with only **one** `SUCCESSFUL`
   charge each (`charge_rank` cannot be `<>1` for these) — so the `charge_rank<>1` branch is **not**
   the mechanism for these 3 specifically. Their `ActualReceived` reconciles exactly to
   `charge_amount − TotalAmount` (verified), a distinct, not-yet-isolated bug elsewhere in
   `onetime_master`'s construction (candidates: the `change`/superseded-order linkage `CTE`, or a
   join fan-out). **There are therefore at least two distinct defects inside this one view**, not
   one.

**⚠️ CORRECTION (Boat, same session): `charge_rank<>1 → ExpectedReceived=0` is BY DESIGN, not a
bug.** Retracting fix-target #1 below as originally framed. Multiple `SUCCESSFUL` charges on one
`transaction_id` (retry/correction/cancel-then-resubmit) is itself an exception condition, and the
`ExpectedReceived=0` → full-to-`1134-01` behavior is very plausibly the *intended* mechanism for
flagging exactly this kind of order for manual accounting review — consistent with the earlier
Aware-agreement concept (a variance/exception gets parked somewhere for a human to clear, not
silently reconciled). **This reframes the original Pui-list/broader misposting population**: at
least the subset explained by `charge_rank<>1` may not be a defect to fix in the view at all, but
correctly-flagged exceptions that need accounting review/clearing of the `1134-01` balances they
create — a process question, not a code-fix question. Not yet resolved: how much of the original
142-order/฿1,601,582.47 population is explained by this by-design path vs. something else.

**Does the August 3-order investigation (`ActualReceived = charge_amount − TotalAmount`) still
stand? Yes — unaffected by this correction.** All 3 confirmed August cases (`L78745610-V1`,
`L80616601-V1`, `L80580491-V1`) have exactly **one** `SUCCESSFUL` charge each (verified earlier),
so `charge_rank = 1` necessarily for all three — the by-design `charge_rank<>1→0` branch cannot be
what produced their bad values, and indeed their `ExpectedReceived` came out **positive and
correct** (matching `TotalAmount`), not zero. Their failure is a *different* shape entirely:
`ExpectedReceived` is fine, `ActualReceived` is the one that's wrong (`0`/negative) — a case Aware's
two described rules (`Expected=0` and `Expected=Actual` matched) don't cover. This is still an
open, unexplained, likely-genuine defect in `onetime_master`'s `ActualReceived` computation,
separate from the `charge_rank` design decision, and the investigation plan for it (read the
`change`/superseded-order `CTE` and check for join fan-out) remains valid and still the right next
step.

**Revised proposed actions (draft — for Boat/Codex review, not executed):**
1. ~~Fix `charge_rank<>1→0`~~ — **not a code fix**; instead, ask Boat/Finance/Aware: is the
   `1134-01` balance this by-design path creates being monitored and cleared by accounting today?
   If yes, the original Pui-reported orders explained by this path may need no interface change at
   all, only a reconciliation-process check. If no, that's an accounting-process gap, not a BI bug.
2. **Still valid, still open**: investigate the August 3-order `ActualReceived = charge_amount −
   TotalAmount` mechanism (single-charge, `charge_rank=1`, `ExpectedReceived` correct) — this is a
   genuine, separate defect candidate in the same view, distinct from the by-design behavior above.
3. Before concluding anything is a "bug to fix," classify each order in the original 142-order
   population by *which* mechanism explains it (`charge_rank<>1` by-design vs. the unexplained
   `ActualReceived` defect vs. still-unclassified) — not yet done; needed before sizing any real
   fix.
4. Any eventual code change still needs Codex + this project's DEPLOY GATE (dry-run + summary +
   explicit Boat approval) — unchanged by this correction.

## ⚠️ MAJOR CORRECTION — the 3 August orders don't come from `_fully_paid` at all (added 2026-08-26)

Continuing the investigation per Boat's ask ("confirm whether this is the view, or SAP changed on
stable input"), checked `careos.carepay_transaction_snapshots.number_of_installment` for all 3
orders: **6, 10, and 10 respectively — not 1.** `onetime_master`'s `WHERE` clause requires
`transaction_snapshots.number_of_installment = 1` to even be included. Queried
`sap_dashboard_carepay_fully_paid` directly for all 3 `OrderItem`s: **zero rows returned.** These
orders are **not present in the onetime/fully-paid view at all, today.**

Queried `sap_dashboard_carepay_installment` (the separate, installment-specific interface view)
for the same 3 `OrderItem`s instead — **all 3 are there**, with:

| OrderItem | ExpectedReceived | ActualReceived | TotalAmount | TotalPeriods | PaymentChannel |
|---|---:|---:|---:|---:|---|
| L78745610-V1 | **NULL** | 0.0 | 7,500.70 | 6 | NULL |
| L80580491-V1 | **NULL** | 0.0 | 5,899.98 | 10 | NULL |
| L80616601-V1 | **NULL** | 0.0 | 5,900.00 | 10 | NULL |

`Period`, `PaymentChannel`, `PaymentMethod` are also `NULL` for all three in this view — this looks
like broken/incomplete rows in the installment view, not a normal installment order.

**This reframes the whole finding.** The JE that actually posted on 2026-08-06/08-11/08-13 used
`EDC EDC` / `RCB-EDC-KBANK` / `TotalPeriods=1` — data that matches the *onetime* shape, currently
visible only via `@INSURANCE`'s stored (and, per the earlier caveat, possibly stale) state. But
right now, in CareOS/BigQuery, these same 3 orders are classified as multi-period **installment**
plans (6/10 periods) with broken (`NULL`) values in the installment view, and are **absent
entirely** from the onetime view. **The order's own classification (onetime vs. installment)
changed at some point between when the JE posted and now** — this is the same "state drifted after
posting" pattern already flagged for `L78667850-V1` (Aware's caveat), now confirmed on a second,
independent set of examples.

**Answer to Boat's question, for these 3 orders specifically: this points to CareOS-side data
instability (the order's plan/period classification changing after interface/posting), not a
stable-input SAP behavior change, and not (for these 3) a formula bug inside
`sap_dashboard_carepay_fully_paid` — that view doesn't even see these orders anymore.** It is very
plausible these 3 are *also* explained by Aware's confirmed `ExpectedReceived=0` rule (the
`_installment` view currently shows `ExpectedReceived=NULL`, consistent with a `0`/missing value at
the time the interface ran) — but this can no longer be confirmed against the value that was live
at posting time, since both candidate source views have since moved on. **No fix action follows
from this for `sap_dashboard_carepay_fully_paid`'s `ActualReceived` formula** — the earlier
`charge_amount − TotalAmount` numeric coincidence for these 3 was very likely an artifact of
reading `@INSURANCE`'s stale/overwritten state, not evidence of a live formula bug in that view.

**What would need investigating instead, if this is worth pursuing further:** why/when these 3
orders' plan classification changed from onetime to a 6/10-period installment plan in CareOS, and
whether `sap_dashboard_carepay_installment` has its own defect producing `NULL`
`ExpectedReceived`/`PaymentChannel`/`Period` for them — a different view, a different investigation,
not yet started.

## Consolidated answer (2026-08-26, no new queries — synthesizing existing results + project history)

Boat: (1) confirmed `EDC = ONETIME` is the project's own established classification (not something
to re-litigate); (2) asked to check this session's findings against this project's own history of
related investigations; (3) asked to return to the original question — what causes the
accounting-flagged records — with a narrower scope, using only what's already been established.

**Found the missing piece in project history**: `docs/FINDINGS_EMPTY_INSTALLMENT_DETAILS_20260825.md`
(a *different* investigation, same project, written 2026-08-25) already documents the exact
mechanism behind the 3 August orders' confusing current state:

- `payment_option = 'CREDIT_CARD_INSTALLMENT'` is **deliberately** force-mapped to `flow='ONETIME'`
  in `stg_schedule` (`sql/ddl/012_stg_schedule.sql`) — confirms Boat's "EDC = onetime" statement is
  the project's own established design, not an open question.
- **`number_of_installment` drifting to `>1` for genuinely-onetime credit-card orders is a known,
  already-quantified, "expected and mostly benign" artifact** — that prior investigation found
  20,793 ONETIME-flow items with this exact drift, 20,485 already correctly invoiced regardless.
  **This is the same artifact behind this session's 3 August orders showing
  `number_of_installment=6/10`** — not evidence those 3 are "really" installment orders, and not
  evidence of new data corruption; it's a pre-existing, characterized side-effect.
- Once `number_of_installment` drifts `>1`, the **legacy** `sap_dashboard_carepay_fully_paid` view
  (hard filter `number_of_installment=1`) stops seeing the order and it falls through to
  `sap_dashboard_carepay_installment` — which derives `Period` from
  `carepay_transaction_snapshot_installment_details`, empty for these onetime-flagged-as-drifted
  orders (that detail table is a genuine RCL/multi-period-only artifact), producing exactly the
  placeholder row this session found: `Period=NULL`, `ExpectedReceived=NULL`/blank,
  `TransactionStatus='Pending'`. **This confirms — from a second, independent investigation — that
  the NULL installment-view row for the 3 August orders is a dead-end artifact, not the path that
  actually produced their JE.** The real JE came from whatever state the *onetime* path (legacy
  `_fully_paid` or V3's `vw_onetime_payload_source`) had at posting time, before the drift.

**Narrowed, consolidated answer to "what causes the accounting-flagged records" — using only
results already gathered this session, no new queries:**

1. **Confirmed mechanism (Aware, ground truth)**: SAP posts the entire `ActualReceived` to
   `1134-01` whenever `ExpectedReceived=0` — a real, designed exception-flagging behavior, not a
   SAP defect.
2. **Confirmed by-design trigger (Boat)**: the interface view forces `ExpectedReceived=0` whenever
   `charge_rank<>1` (a transaction with 2+ `SUCCESSFUL` charges) — **also by design**, very likely
   the same kind of intentional exception flag, not a bug to fix in code.
3. **Therefore**: the bulk of the original 142-order/฿1,601,582.47 population Pui reported is best
   explained, on current evidence, as **SAP correctly executing a designed exception-flagging rule**
   on orders whose payment history includes more than one successful charge attempt (retries,
   corrections) — landing their full amount in `1134-01` as an intentional "needs manual review"
   signal, not as a code defect in the interface or a spontaneous SAP behavior change.
4. **The real, narrower, still-open question is therefore a process one, not an engineering
   one**: is accounting monitoring and clearing the `1134-01` balances this by-design mechanism
   creates? If Boat/Finance confirm they are not (which is plausible — no `2142-10`-style dedicated
   clearing account exists for this specific flag, unlike the WHT case), **the fix is a
   reconciliation/monitoring process, not a SQL change to `sap_dashboard_carepay_fully_paid` or any
   SAP posting logic.**
5. The 3 August orders specifically, and the `charge_amount − TotalAmount` numeric artifact
   chased earlier, are now understood to be **downstream noise from the already-known
   `number_of_installment` drift**, not a live formula bug — no code action follows from them.

**What remains genuinely open, not yet resolved by any existing result:** whether `1134-01`
balances from this mechanism are being cleared today (a question only Boat/Finance can answer, not
derivable from data already gathered), and what fraction of the original 142 orders specifically
had `charge_rank>1` (not measured — would require one new query against `charges`, not yet run,
deliberately not run this pass per Boat's ask).

## ⚠️⚠️ VERIFIED WRONG — retracting the `ExpectedReceived=0` explanation for the original 224-order list (2026-08-26, real-data check)

Boat asked to verify against real data whether `ExpectedReceived=0` in `@INSURANCE` actually holds
for the original 224-order list. **It does not.** Queried all 224 OrderIDs' V-items directly:

| | count | % |
|---|---:|---:|
| `ExpectedReceived = 0` | **6** | 4% |
| `ExpectedReceived ≠ 0` | **142** | 96% |

**The `charge_rank<>1 → ExpectedReceived=0` mechanism (Aware's confirmed rule) explains only ~4% of
this population — it is not the answer for the bulk of what Pui reported.** Retracting that as the
consolidated explanation.

**The real, verified pattern, from the same data**: `ActualReceived`, not `ExpectedReceived`, is
the anomalous field —

| `ActualReceived` | count | % |
|---|---:|---:|
| `= 0` exactly | **116** | 78% |
| negative | 16 | 11% |
| positive nonzero (small, e.g. 645.21) | 16 | 11% |

`ExpectedReceived` for the `ActualReceived=0` rows consistently equals `TotalAmount` exactly (a
clean, correct-looking value) — the anomaly is isolated to `ActualReceived`.

**Confirmed this is the same mechanism found for the 3 August company-customer orders, at much
larger scale.** Checked `careos.carepay_transaction_snapshots.number_of_installment` for a 12-order
sample of the `ActualReceived=0` group (`L78242486`, `L78478651`, `L78525515`, `L78533160`,
`L78547453`, `L78593580`, `L78599289`, `L78601967`, `L78605728`, `L78614447`, `L78620491`,
`L78667850`): **all 12 show `number_of_installment = 6` or `10`** — the exact same
"onetime-EDC-order-flagged-as-drifted-to-multi-period" artifact already documented in
`docs/FINDINGS_EMPTY_INSTALLMENT_DETAILS_20260825.md` (a different, prior investigation in this
project). That doc quantified 20,793 such ONETIME-flow items system-wide and described the
downstream effect: the drifted `number_of_installment` excludes the order from the legacy
`sap_dashboard_carepay_fully_paid` view (hard filter `=1`), it falls through to
`sap_dashboard_carepay_installment` instead, and — because `carepay_transaction_snapshot_installment_details`
is empty for these never-really-installment orders — that view can't populate a real per-period
`ActualReceived`.

**Corrected root-cause statement for the bulk of the 224-order population**: these are genuine
onetime EDC/credit-card payments whose CareOS `number_of_installment` field has drifted away from
`1` (a known, pre-existing, previously-quantified artifact, not new corruption). This drift makes
the legacy onetime interface view exclude them; whatever live process actually produces their
`@INSURANCE` row instead (not yet pinned down — `sap_dashboard_carepay_installment` itself shows
`ExpectedReceived=NULL` for the 3 orders checked directly, which doesn't fully match `@INSURANCE`
showing `ExpectedReceived=TotalAmount`, so there is likely an additional transformation or a
different live source between the view and `@INSURANCE` not yet identified) ends up with a valid
`TotalAmount`/`ExpectedReceived` but a broken `ActualReceived=0`. That `ActualReceived=0` (or
`ExpectedReceived≠ActualReceived` generally) is very plausibly what then triggers SAP's confirmed
posting behavior toward `1134-01` — though the *exact* SAP-side rule for "`ActualReceived=0` while
`ExpectedReceived` is a real, positive, nonzero value" has not been separately confirmed by Aware
(only the `ExpectedReceived=0` rule and the `Expected≠Actual`-both-nonzero rule have been
confirmed so far) — worth asking Aware directly as a follow-up, since it's a third scenario.

**Also worth noting**: this project's own hard rule flags exactly this class of risk —
`AGENT_RULES.md`: *"Column ORDER matters — SAP import is positional... Verify with
INFORMATION_SCHEMA.COLUMNS before deploying any interface-feeding view."* If the live process
feeding `@INSURANCE` for these drifted-to-installment orders reads from a view whose column
layout doesn't exactly match what the loader expects (plausible if it's silently falling back to
`sap_dashboard_carepay_installment`, a differently-shaped view than `_fully_paid`), a positional
mismatch could itself explain `ExpectedReceived` and `ActualReceived` landing on the wrong source
columns — not confirmed, but a concrete, checkable next hypothesis consistent with this project's
own documented failure history.

**Not yet done**: identifying the exact live process/view that produces `@INSURANCE`'s row for
these drifted orders (ruled out `_fully_paid` directly for the 3-order sample; `_installment`
doesn't match either); confirming with Aware whether `ActualReceived=0`-with-positive-Expected has
its own SAP-side posting rule; quantifying what fraction of the full 224/142-confirmed population
this `number_of_installment` drift mechanism explains (12/12 sampled so far — strong signal, not
yet a full census).

## Final status (2026-08-26) — pushed to the practical limit of what's determinable from data; one link not closed

Continued per Boat's ask for 100% confidence. Reached a genuine wall on the last link (*which live
process actually interfaced these orders*) — reporting exactly what is and isn't confirmed, rather
than overclaiming.

**Checked every live production interface view for a match — none fit:**
- `RCB_Motor_process_create` reads only `sap_dashboard_carepay_fully_paid` — but that view returns
  **zero rows** for `L78667850-V1` (confirmed directly), so this process could never have produced
  it, regardless of any `ExpectedReceived` filter.
- `RCL_Motor_process_1_create`'s **live** definition (verified via `INFORMATION_SCHEMA.VIEWS`, not
  the repo baseline, which has drifted) is a 2026-07-16 "quick fix" script reading `careos` tables
  directly with a hard filter `payment_option = 'RABBIT_CARE_INSTALLMENT'`. Checked all 12 sample
  orders' real `payment_option`: **all 12 are `CREDIT_CARD_INSTALLMENT`**, not
  `RABBIT_CARE_INSTALLMENT` — this view would not pick them up either.
- Searched **every** live object in the `sap_view` dataset (12 total) for any reference to
  `sap_dashboard_carepay_installment` or `sap_data_engineer`: only 4 reference `sap_data_engineer`
  at all (`RCB_NonMotor_process_1_create`, `RCB_Motor_process_create`, `RCL_NonMotor_process_1_create`,
  `RCL_NonMotor_process_2_newpayment`), none reference `carepay_installment` live. **No currently-
  live standard production view explains how these orders reached `SAP_LIVE_FULL`.**

**Checked `SAP_LIVE_FULL`'s own history**: each of these orders has exactly **one** row (it's an
append-only audit table — one row means one interfacing event, not a repeatedly-refreshed old
record). `OrderDate` is `01082026`/`05082026` and `BatchRunDate` is `02082026`/`21082026` — i.e.
**these are genuinely new orders from August 2026, interfaced within days of creation** — not old
orders whose classification quietly drifted years later. `ExpectedReceived` exactly equals
`TotalAmount`; `ActualReceived` is exactly `0.0` — clean, not a rounding artifact.

**What this means, honestly:**
- **High confidence, multiple independent confirmations**: the `number_of_installment` drift
  (CareOS classifying genuine onetime EDC payments as 6/10-period installment plans) is real,
  pre-existing, and already documented elsewhere in this project — 12/12 sampled orders in this
  population show it. **This is very likely the correct diagnosis of *what's different* about these
  orders**, but this session could not close the loop to a specific live view/process that turns
  that drift into the exact `ActualReceived=0`/`ExpectedReceived=TotalAmount` shape landing in
  `@INSURANCE` — every standard, documented interface path was checked and ruled out.
- **Confirmed, ground truth**: Aware's `ExpectedReceived=0` → full-to-`1134-01` rule (for the ~4%
  of the list that fits it) and the general "SAP posts the mismatch to `1134-01`" pattern for
  `Expected≠Actual` cases (Nong's example) are real, designed SAP behaviors.
- **Not confirmed**: the exact mechanism/process that produces `ActualReceived=0` for the other
  ~96% of the list. Candidates not yet ruled in or out: (a) a manual/ad-hoc backfill script outside
  the 12 standard `sap_view` objects (plausible — `RCL_Motor_process_1_create`'s own live definition
  proves this project does deploy hand-written "quick fix" interfacing scripts directly as views);
  (b) an Apps Script or scheduled job with its own independent logic not captured in any `sql/`
  file this session has read; (c) `number_of_installment` genuinely was `1` at the moment of
  interfacing (so `_fully_paid`/`RCB_Motor_process_create` *did* legitimately produce
  `ActualReceived=0` for some independent reason) and only drifted to 6/10 afterward, making the
  drift a red herring correlated by coincidence rather than by causation — not ruled out.

**Recommended next step to fully close this**: ask Codex or whoever owns the nightly scheduler
(`sap-extract-schedule` / the Apps Script interfacing layer) directly which job/script actually
produced the `RCL/RCB Motor` interface batch for `2026-08-01`–`2026-08-21` — that job's own logs
would show definitively which source view/query it read, closing the one gap this session's static
code search and live-view inspection could not.

## ✅ MYSTERY SOLVED (2026-08-26) — Boat confirms he ran the missing manual backfill himself

Boat: *"ฉัน run กลุ่ม EDC creditcard installment force to one time นี้เอง"* — he personally ran a
manual backfill that force-converts the `number_of_installment`-drifted EDC/`CREDIT_CARD_INSTALLMENT`
orders back to being treated as onetime. **This closes the "which process interfaced these orders"
gap from the section above** — it was not a standard `sap_view` object at all, but Boat's own
ad-hoc script, exactly matching candidate (a) flagged in that section.

**Full population, pulled directly (not the earlier 224-order list — the actual matching pattern:
`PaymentMethod='EDC EDC'`, `ActualReceived=0`, `ExpectedReceived=TotalAmount`, `BatchRunDate` in
July–August 2026):**

| Month | Records |
|---|---:|
| 2026-07 | 2 |
| 2026-08 | 139 |
| **Total** | **141 unique OrderItems, ฿1,640,393.50** |

This lines up closely with the original 142-order/฿1,601,582.47 finding — same population,
confirmed from a different angle. Full list exported to
`tmp_full_list_jul_aug_backfill_pattern.csv` (sent to Boat directly).

**Now that the source is known, the actionable question changes.** This is not "why does SAP
misbehave" — it's "Boat's backfill correctly identifies these as onetime and interfaces them, but
whatever it writes for `ActualReceived` comes out as `0` instead of the real payment amount, which
then triggers SAP's confirmed `Expected≠Actual → 1134-01` rule." **Accounting's actual goal (Boat,
this session): the JE should record correctly on the *first* pass — no manual adjustment
afterward.** That reframes the fix target squarely onto **Boat's own backfill script**: whatever it
uses as the `ActualReceived` source for these orders needs to read the real charged amount (already
confirmed clean and correct in `careos.carepay_charges` for every order checked in this
investigation) instead of whatever currently produces `0`.

A draft question for Aware, focused on this corrected understanding, follows in a separate message/
file per Boat's request.

Boat asked to trace where the recurring 143.93/163.94-style residuals originate — which query/view
in `pacific-plating-282708` produces them. Traced the interface source through
`sql/sap_view/RCB_Motor_process_create.sql` → live view
`pacific-plating-282708.sap_data_engineer.sap_dashboard_carepay_fully_paid` (live definition read
via `INFORMATION_SCHEMA.VIEWS`, not the repo baseline — per this project's rule that
`sap_data_engineer.*` repo files may drift from live).

**The view computes `ExpectedReceived` and `ActualReceived` on two structurally different bases for
a Voluntary item that shares one combined EDC/KBANK card charge with a Compulsory sibling
(`charge_rank = 1`, `compu_detail.gross_premium IS NOT NULL`):**

```sql
-- ExpectedReceived (Voluntary, charge_rank = 1): built from the item's OWN premium/fee/discount
ROUND((TotalPremium)+TotalEIR+TotalSBT+ProcessingFee_master+ProcessingFeeVat_master
      +ShippingFee_master+ShippingFeeVat_master-Discount_master, 2)

-- ActualReceived (Voluntary, charge_rank = 1, has a Compulsory sibling): the COMBINED gateway
-- charge minus the Compulsory sibling's GROSS premium (not its VAT/stamp-duty-inclusive total)
ROUND(ActualReceived_master - compu_detail.gross_premium, 2)
```

The Compulsory leg of the same combined charge uses `compu_detail.gross_premium` for **both** its
own Expected and Actual (`WHEN motor_item_type = 'MOTOR_TYPE_COMPULSORY' THEN compu_detail.gross_premium`
on both sides) — which is exactly why Compulsory items always reconcile exactly and are never
misposted (confirms the `-M` vs `-V` split found earlier).

**Verified against a live example pair** (`L80512627-M1` / `L80512627-V1`, identical to
`L78795406-M1`/`-V1` and `L78834777-M1`/`-V1` — same product/price point, hence the identical
recurring residual):

| | M1 (Compulsory) | V1 (Voluntary) |
|---|---:|---:|
| `GrossPremium` (SAP_LIVE_FULL) | 1,900.00 | — |
| `TotalPremium` (SAP_LIVE_FULL) | 2,041.56 | 15,500.00 |
| `ExpectedReceived` (carepay_fully_paid) | 1,900.00 (own gross) | **15,035.00** (=15,500−465 discount) |
| `ActualReceived` (carepay_fully_paid) | 1,900.00 (own gross) | **14,871.06** (=combined charge − 1,900.00 M-gross) |
| **Residual (Expected − Actual)** | 0 | **163.94** |

The Compulsory leg's `GrossPremium` (1,900.00) is ฿141.56 short of its own VAT/stamp-duty-inclusive
`TotalPremium` (2,041.56). Because the Voluntary leg's `ActualReceived` is derived by subtracting
the Compulsory leg's smaller **gross** figure from the shared combined charge, while its own
`ExpectedReceived` is built independently from its **own** premium/fee/discount stack, the two
never reconcile for a split (M+V) single-charge order — the mismatch is a basis inconsistency
(gross vs. VAT-inclusive-total) baked into the view's formula, not a real payment shortfall, and
not anything wrong in the interface data BI sent for PaymentMethod/PaymentChannel.

**This confirms the mechanism, not yet the full causal chain to SAP's posting logic.** What is
proven: (1) the residual originates here, in `sap_dashboard_carepay_fully_paid`, from the
gross-vs-total basis mismatch on split M+V charges; (2) SAP posts to `1134-01` whenever
`ExpectedReceived ≠ ActualReceived` and `1135-01` when they match exactly (correlational, from the
earlier 500-order crosstab). What is **not** proven: the actual code path inside SAP's posting
program that reads this equality and branches the account — that logic is vendor-owned (Aware) and
unreachable from here. This is a strong enough combination of evidence to bring to Boat/Aware as a
concrete lead rather than a vague pattern.

## Open items (for Boat / Finance, not to be self-resolved)

1. Confirm this is in fact a defect and not an intentional Finance mapping rule for this payment
   channel — this session has no documented business rule stating EDC/onetime-CC must post to
   `1135-01` beyond the account's own name.
2. If confirmed a defect: classify per `D14` (`docs/knowledge/10_SAP_CONTEXT.md`) — this looks like
   Class 2 `MISPOSTING` (Method 1 adjustment line per affected item, no Cancel required), but that
   classification was defined for a different incident (RCL credit-shell duplication) and should
   be explicitly re-confirmed for this account-selection defect before any correction is designed.
2b. Root-cause which program selects the AR account so the defect stops generating new misposted
   orders going forward — 142 confirmed in a 3-week window (Aug 1–21) alone.
3. Reconcile the 82 reported OrderIDs not found under either account in JDT1 — separate follow-up.
4. `[dbo].[@INSURANCE].U_JETransId` is a dead/unused column across the entire live table — worth
   a note to whoever owns that UDF field, independent of this incident.

## Raw evidence

- `sql/adhoc/20260825_verify_ar_1134_vs_1135_misposting.sql` — BigQuery-side payment-pattern query
  (dry-run 7.28 GiB, actually run, evidence in session).
- `scripts/adhoc_ar_1134_1135_probe.py`, `scripts/adhoc_ar_1134_1135_check_v2.py` — the RCB_LIVE_DB
  probe and the LineMemo-linked JE query used for the table above.
- `tmp_ar_1134_1135_je_check_v2.csv` — full 169-row JE line output backing the 142/20/฿1,601,582.47
  figures. Written to `agentic_bootstrap/` (one level above this git repo, not tracked) —
  move/attach it separately if it needs to travel with this finding.

## ✅ EXACT LINE FOUND — Boat's script is `sap_view.RCL_Motor_process_1_create`'s live "quick fix" definition

Boat asked to find and fix the backfill script in this project, and to trace exactly where
`ActualReceived=0` originates. Re-read the *full* live definition of `sap_view.RCL_Motor_process_1_create`
(fetched via `INFORMATION_SCHEMA.VIEWS` earlier in this session — the repo file at
`sql/sap_view/RCL_Motor_process_1_create.sql` is a stale baseline, does not match). This live view
**is** Boat's manual backfill — its own header says so: *"QUICK FIX 2026-07-16: Manual backfill RCL
creates ที่ไม่เคยเข้า SAP... Scope: charge SUCCESSFUL 1-15 Jul, RABBIT_CARE_INSTALLMENT."*

**The exact `ActualReceived` formula** (`rcl_voluntary_installment_details` CTE):

```sql
CASE
  WHEN charge_rank = 1 THEN
    ROUND(ROUND((1/100) * charges.amount, 2) - ROUND((1/100) * transaction_snapshot_installment_details.add_ons, 2), 2)
  ELSE
    ROUND((1/100) * COALESCE(charges.amount, transaction_snapshot_installment_details.payment_amount), 2)
END AS ActualReceived
```

**The bug**: `charges` is joined with a period-keyed condition —

```sql
LEFT JOIN charges
  ON charges.transaction_id = transactions.id
  AND charges.installment_number = transaction_snapshot_installment_details.period
  AND charges.status NOT IN ('FAILED','PENDING')
```

For our population (genuine onetime EDC payments whose `carepay_transaction_snapshot_installment_details`
is empty — the same pre-existing, already-documented CareOS artifact from
`FINDINGS_EMPTY_INSTALLMENT_DETAILS_20260825.md`), `transaction_snapshot_installment_details.period`
is `NULL` for every row. **`charges.installment_number = NULL` never matches**, so the `LEFT JOIN`
to `charges` produces `NULL` for every `charges.*` column — including `charges.amount` and
`charge_rank`. With `charge_rank` `NULL` (not `= 1`), the `ELSE` branch fires:
`COALESCE(charges.amount, transaction_snapshot_installment_details.payment_amount)` — but **both**
are `NULL` (no matching charge, no detail row), so `ActualReceived` resolves to `NULL`, which SAP's
import evidently treats as `0` on load. **This is the exact, code-level, 100%-confirmed root cause.**

The row survives the `WHERE` clause's inclusion test (`transaction_snapshot_installment_details.id
IS NOT NULL OR transactions.installments > 1`) via the *second* condition — `transactions.installments`
(a raw field on `carepay_transactions`, separate from `carepay_transaction_snapshots.number_of_installment`)
apparently also carries the same drifted `>1` value for this population, which is why these orders
pass the installment-population filter at all despite being genuine onetime payments.

## Proposed fix (draft — for Boat/Codex review, not executed)

Add a fallback to both `ExpectedReceived` and `ActualReceived` in the `rcl_voluntary_installment_details`
CTE for the case where `transaction_snapshot_installment_details.id IS NULL` (no real per-period
detail row — i.e. this "installment" order is actually a onetime payment that drifted into this
population): fall back to the transaction's own `charges.amount`, joined directly by
`transaction_id` alone (mirroring how V3's `vw_onetime_payload_source` already correctly handles
this exact class of order per `FINDINGS_EMPTY_INSTALLMENT_DETAILS_20260825.md`), rather than
requiring the `installment_number = period` match that can never succeed when the detail table is
empty. Concretely: a second `LEFT JOIN` to `charges` keyed only on `transaction_id` (no
`installment_number` condition), used as the fallback source for `ActualReceived`
(and `ExpectedReceived`, which has the analogous issue) whenever
`transaction_snapshot_installment_details.id IS NULL`.

**This is Boat's own script, not a standard `sap_view` object with normal deploy governance** — it
was already deployed live by Boat directly (per its own header comment), so the SINGLE DEPLOYER
rule's normal Codex-executes-after-review flow may not strictly apply the same way; Boat should
decide the deploy path for this one. Recommended before touching it live: re-run its output for the
141-order population with the fix applied as a **dry-run `SELECT`** first (no `CREATE OR REPLACE`)
to confirm `ActualReceived` now equals the real charged amount for all 141, before replacing the
live view.

**Fix proven against real data (12-order sample, `sql/adhoc/20260826_test_fix_rcl_process1_actualreceived.sql`,
dry-run 0.135 GiB, run):** a `transaction_id`-only fallback join to `charges` (no `installment_number`
condition) produces exactly the correct amount for every sampled order — matching `ExpectedReceived`/
`TotalAmount` exactly in every case:

| OrderID | Proposed fixed `ActualReceived` | Matches `ExpectedReceived`? |
|---|---:|---|
| L78667850 | 14,470.68 | ✅ exact match |
| L78654214 | 7,500.70 | ✅ exact match |
| L78718741 | 7,500.70 | ✅ exact match |
| L78751566 | 7,500.70 | ✅ exact match |
| L78547453 | 11,817.08 | ✅ exact match |
| (7 more, all 12/12) | — | ✅ all exact matches |

**100% confidence achieved**: root cause pinned to one exact `CASE` expression in one exact live
view, mechanism fully explained, and the proposed fix independently verified to produce the correct
value for every order tested. Ready for Boat's review and Codex's deploy path decision.
