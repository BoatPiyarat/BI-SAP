# Review — 043 deterministic hard-gate PASS evidence (deterministic-retry section)

**Queue entry:** RQ-20260801-1637-043-deterministic-gate-evidence · **Class:** A · **Reviewer:** Claude Code
**Verdict:** **PASS — chain ③ is technically ready for Boat's explicit repoint decision.**

## Hard gate

`only_in_024 = 0` and `only_in_incremental = 0` at 1,662,648 rows both sides — the exact result the
RQ-1520 conditions required, produced by the reviewed deterministic procedures
(`deploy_024/043_deterministic_*`, fresh 024 immediately before the comparison, full job
provenance, dry-runs + ceiling throughout). Watermark advanced (2026-08-01/809), consistent with
the prior run.

## 025 delta — arithmetic and interpretation verified

- Row count 1,300,230 before/after; **cross-check closes exactly**: 1,296,900 (pre-change
  baseline) + 3,330 (Boat-confirmed source growth, chain ② evidence) = 1,300,230.
- Zero old-only/new-only keys, zero DocEntry-winner changes, zero status changes — the tie flips
  never changed which document wins at `(U_OrderItem, U_Period)` grain, only payload content of
  already-winning DocEntries.
- 885 raw InvoiceNo changes = 449 NULL→'' + 436 ''→NULL (sums ✓), zero empty↔real and zero
  real↔different-real. The semantic-zero conclusion is **independently justified**: every consumer
  predicate this reviewer has verified in prior passes (025 layer-2 pick, 018 `delta_type`, 030)
  reads InvoiceNo through `IFNULL(U_InvoiceNo, '') != ''`, under which NULL and '' are the same
  value. The NULL↔'' churn is also coherent with the diagnosis: cross-source ties (2,602) are
  exactly where representation differences between shards would surface.
- 4,067 payload changes ≤ the measured 8,538 flip-capable bound ✓.

## Readiness statement (the RQ's question)

All mandatory pre-repoint conditions from `2026-08-01-1a8216f-claude.md` NOTE 2 are met: gate 0/0
with deterministic selectors live in both 024 and 043, and the 025-level delta measured — not
assumed — and semantically zero. What remains is exactly what should remain: (1) Boat's explicit
repoint decision (nightly chain still on 024's full CTAS — correct that no repoint happened inside
this evidence unit); (2) the optional future source-priority semantics for the 2,602 cross-source
ties, correctly framed as a Boat/Aware business decision, not a technical gap.

Queries used: 0 (arithmetic + cross-evidence reconciliation).
