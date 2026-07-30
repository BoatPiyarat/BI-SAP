# Return Triage — 26-29 July away window

Compiled live from `pipeline_run_log`, `SAP_LIVE`, BQDTS transfer-run history, Cloud Logging, and
`INFORMATION_SCHEMA` — not from memory of the handover doc. Covers what actually happened, not
what was supposed to happen.

## 1. Extract / freshness, per night

| Date (ICT) | Extract pressed? | Result | SAP_LIVE loaded OK? | V3 chain ran? | Staleness at 22:00 ICT check |
|---|---|---|---|---|---|
| 07-26 | Yes, 4× (19:34, 20:43, 23:32, and 07-27 00:54) | All succeeded | Yes | Yes (old chain, pre-collapse) | Not stale — dead-man's-switch SUCCEEDED |
| 07-27 | Yes, 1× (22:04) | Succeeded | Yes, but see below | Yes (21:00:36 UTC → correct post-fix timing) | **STALE — alert fired, "39 ชม."** (see note) |
| 07-28 | Yes, 2× (20:19 failed exit 1, retried 20:27 succeeded) | Recovered on retry | Yes, but see below | Yes (21:00:46 UTC) | **STALE — alert fired again, "39 ชม."** |
| 07-29 (as of this check, 13:17 ICT) | Not yet due | — | — | Not yet due | — |

**Note on the two staleness alerts**: the extract itself DID run both nights, but the real loader
(`sap-order-payment-initial-phase`) crash-looped on an out-of-memory error (1024 MiB limit) for
~16 minutes around 2026-07-29 02:43-02:59 UTC before finally succeeding — see the bigger finding
below. The dead-man's-switch firing was **correct**, not a false alarm: `MAX(U_BatchRunDate)` really
was stale at each 22:00 ICT check because the loader hadn't finished yet.

**🚨 New finding, not in the handover doc — needs attention before Phase B**: `SAP_LIVE` has grown
from **151,024 rows (07-26 baseline) to 6,858,653 rows now**, while distinct `DocEntry` only grew
106,873→122,169 (ratio ~1.4 → ~56 rows/DocEntry). Root cause: the loader's memory-limit crash-loop
(confirmed in Cloud Logging: repeated "Memory limit of 1024 MiB exceeded" + container restarts)
combined with the loader doing a plain `INSERT` (not `MERGE`) — each restart very likely re-inserted
the same file's rows. **Downstream impact: none confirmed** — `SAP_LIVE_FULL`/`sap_mirror_doc` both
dedup per-DocEntry correctly and show sane, non-exploded row counts (1,658,647 as of 07-28, in line
with expected growth). This is a real storage/cost concern and an active loader bug, not (currently)
a correctness problem for anything V3 produces. **Not fixed — outside `sap_integration_v3`, needs
your/Attila's call** (increase the loader's memory limit, and/or make the insert idempotent).

### 2026-07-30 read-only daily comparison

Boat supplied daily counts from both `sap_integration_v2.SAP_LIVE` and SAP SQL Server
`[RCB_LIVE_DB].[dbo].[@INSURANCE]`; source-query execution timestamp was not captured. Codex
re-ran the BigQuery side with distinct DocEntry at **2026-07-30 09:10:41 UTC / 16:10:41 ICT**
through `scripts/bq_safe_query.sh` (dry-run estimate **133,186,480 bytes / 0.124 GiB**).

Loader amplification varies materially by day. Actual BQ-row/SQL-source-row multipliers are:
07-21 1.681×, 07-22 1.498×, 07-23 1.854×, 07-24 2.659×, 07-25 1.939×,
**07-26 289.623×, 07-27 2,036.103×, 07-28 25.000×**, 07-29 1.000×, and
08-15 1.000×. Full counts and provenance are in
`docs/FINDINGS_SAP_MIRROR_20260726.md` §“ADDENDUM 2026-07-30”.

BigQuery distinct DocEntry was never lower than the supplied SQL row count and matched exactly on
07-28 (58,619), 07-29 (27), and 08-15 (5). Therefore no real loss is observed by aggregate count,
but zero loss is not proven: the supplied SQL output lacks the source DocEntry set required for an
anti-join. **Set-level real-loss verification remains OPEN.** No loader fix or cleanup was made.

## 2. Alerts — which fired, where, and whether delivery is confirmed working

| Alert | Fired during 26-29? | Real condition or false alarm? | Destination |
|---|---|---|---|
| Missed-extract (dead-man's-switch) | **Yes**, 07-27 and 07-28 (15:00 UTC checks) | Real — `SAP_LIVE` genuinely stale both times, tied to the loader crash-loop above | `data@rabbit.co.th` (failure email) |
| Column-contract guard | No (ran clean both nights) | N/A — no drift occurred | `data@rabbit.co.th` |
| Validation-regression | No (ran clean both nights) | N/A — no regression | `data@rabbit.co.th` |
| Interface-daily-status alert | **Yes**, every check since 07-27 (3 runs) | Same 7 `PAID_AFTER_CANCEL` rows every time (not new ones) — a design gap: this alert re-fires daily on an unresolved condition rather than only on new occurrences | `data@rabbit.co.th` |
| 07:00 daily digest | Fired daily (Gmail-based) | — | `piyaratt@rabbit.co.th` directly |

**Delivery confirmed working for real, not just configured**: the two genuine dead-man's-switch
firings (07-27, 07-28) are the first time this project's failure-email mechanism has actually fired
on a real condition end-to-end (previously only synthetically tested). **Still unconfirmed**:
whether the email actually reached anyone's inbox — that depends on whether `data@rabbit.co.th` was
checked during the window, which I can't verify from here.

## 3. Backlog: 07-27 baseline vs now (07-29)

**`delta_export`** (totals; per-flow breakdown now available, wasn't captured per-flow on 07-27):

| Category | 07-27 baseline | Now (07-29) | Change |
|---|---|---|---|
| OK | 1,084,402 | 1,087,489 | +3,087 |
| NEEDS_PAID_UPDATE | 3,585 | 2,125 | **-1,460 (improved)** |
| MISSING_NO_ROW_IN_SAP | 373,044 | 373,152 | +108 (flat) |
| UNEXPECTED_ALREADY_PAID | 1,312 | 1,403 | +91 |

**`interface_daily_status`**:

| Status | 07-27 baseline | Now (07-29) | Change |
|---|---|---|---|
| OK | 1,060,862 | 1,064,045 | +3,183 |
| MISSING | 341,245 | 340,051 | **-1,194 (improved)** |
| STATUS_CONFLICT | 59,459 | 59,501 | +42 (flat) |
| PENDING_ACK | 770 | 565 | -205 |
| PAID_AFTER_CANCEL | 7 | 7 | 0 (same rows, confirmed via alert repeating) |

**No concerning backlog growth.** Everything is flat or improved. This is good news, not a gap to
close before Phase B.

## 4. Legacy pipeline — did files go out, and import errors

**Files: yes, every night, confirmed at the log level.** Checked full log sequences for both
`rcb-motor-order-payment-sap-bucket-1` and `rcb-nonmotor-order-payment-sap-bucket-1` for the night
of 07-28→29: **all 8 Motor steps and all 4 NonMotor steps completed and wrote their GCS files**
before either function reported `crash`.

**The `crash` status itself, on all 3 nights (07-26, 07-27, 07-28), both functions**: root-caused
to `main.py` line 154, `send_email(...)` — an **SMTP authentication failure**
(`535 Username and Password not accepted`, a Gmail app-password that's expired/been revoked). This
is a **post-export notification step failing, not the export itself** — confirmed by log order
(every `stored in GCS` line appears before the crash). Real files are not lost; only the "here's a
summary" email is broken. Still worth fixing (someone relying on that email would think the run
succeeded silently or get no signal at all), but **not a data-loss incident**.

**Incidental good news, unverified provenance**: Motor step 08 (`RCL_Motor_process_4_creditshell`)
is now present and completing — this was flagged 2026-07-26 as a structural automation gap (no
export step existed for it). Either someone added it during the away window or it was already
being deployed when this investigation started - not confirmed which, just confirmed it now runs.

**Import errors (`sap_import_result`)**: **0 rows** — no logs were shared/loaded (expected; A3's
own design is manual ingestion only, nothing automatic to report here).

## 5. audit_010_careos_missing_in_sap_detail — same pattern check

**Confirmed: same code pattern as `sap_integrety_2025_RCL`** — its `sap_base` CTE does
`ROUND(SUM(U_TotalAmount), 2) ... GROUP BY SAP_OrderId, U_OrderItem, Period, U_ChassisNo` against
`SAP_LIVE_FULL` with no per-DocEntry/per-period dedup. **9.55% of (OrderID, OrderItem, Period) keys
have >1 document** (144,112 of 1,509,809) — same population as the RCL view.

**But the actual reported numbers are NOT corrupted, and no banner is needed.** The view's final
output filters `WHERE MatchStatus = 'Missing in SAP'` — i.e. it only ever surfaces rows with **zero**
matching SAP document. For those rows, `SAP_Amount` is `NULL` (nothing to sum), so the unguarded-SUM
bug never actually executes against what this view reports. The `MatchStatus` classification itself
is a simple existence check (`LEFT JOIN ... IS NOT NULL`), which is correct regardless of how many
SAP documents exist for a matched key. **Verdict: structurally similar code, but the specific
double-counting bug does not manifest in this view's actual output — no `⚠️ UNRELIABLE` banner
added, per the "don't touch/relabel unless actually wrong" instruction.**

**90-day usage confirmed** (re-verified): `piyaratt@rabbit.co.th`, 3 times — 2026-05-06, 2026-05-29
(×2), 2026-06-05. Genuine, if infrequent, real usage — consistent with the earlier finding.

---

## Anything to fix immediately before starting Phase B?

**No blocking correctness issue for Phase B.** `expected_state`, `delta_export`, and
`interface_daily_status` are all fresh, stable, and not corrupted by anything found in this triage.
Backlog is flat/improved. `audit_010` is confirmed reliable for what it reports.

**Two things worth a decision before or alongside starting Phase B, not because Phase B depends on
them, but because they're real and now confirmed**:
1. **The `SAP_LIVE` loader memory/duplication bug** (§1) — daily amplification measured at
   289.623× on 07-26, 2,036.103× on 07-27, and 25.000× on 07-28; a real active bug outside
   `sap_integration_v3`. Recommend raising the Cloud Run memory
   limit on `sap-order-payment-initial-phase` and/or confirming the insert path is idempotent.
2. **The SMTP credential failure** (§4) causing both legacy Cloud Functions to report `crash` every
   night — cosmetic for data delivery (confirmed files still land) but means nobody gets that
   notification email, and anyone reading Cloud Function status alone would wrongly think the
   pipeline is failing nightly.

Neither blocks Phase B work in `sap_integration_v3` — both are legacy/infrastructure items outside
this project's DDL scope, flagged for your decision rather than fixed unilaterally.
