# Review — Chain ② RULE-03 deployment evidence (`FINDINGS_DEPLOY_CHAIN2_RULE03_20260801.md`)

**Queue entry:** RQ-20260801-1640-chain2-rule03-evidence · **Class:** A · **Reviewer:** Claude Code
**Verdict:** **PASS**

- **Job provenance:** complete for all nine steps (deploys 0-byte, refreshes and verifies with
  processed/billed under ceiling, dry-runs first, correct order 024 → refresh → 025 → refresh →
  shared-037 verify). The shared-037 step correctly verified instead of redundantly redeploying —
  resolving the chain-①/chain-② same-file question from the release order cleanly.
- **Population interpretation:** 024 pre-refresh 1,658,776 = the frozen pre-change baseline ✓;
  post-refresh 1,662,648 rows = distinct DocEntry with zero NULL UpdateDate/UpdateTime ✓ (the
  handoff's required checks). The +3,872 was **not self-accepted** — verification passed only
  after Boat confirmed the manual source import; growth is attributed to a human-confirmed cause,
  not waved through. Downstream +3,330 on 025 follows consistently (and reconciles exactly against
  the RQ-1637 measurement: 1,296,900 + 3,330 = 1,300,230).
- **025 verification:** zero duplicate `(U_OrderItem, U_Period)` keys, `MULTI_DOC_RESOLVED_BY_RECENCY`
  = 330,822/1,300,230 (25.4% — same ballpark as the 2026-07-26 "31% multi-doc" measurement on the
  older population, direction plausible given the E1-era source), zero tag mismatch, zero NULL
  `docs_considered` — RULE-03's observability contract intact.
- **≤8,538 bound:** the zero-delta expectation is explicitly superseded and the measured bound is
  quoted exactly as required by `2026-08-01-1a8216f-claude.md` NOTE 3; observed 5,566 first-run
  flips and the post-fix 0/0 gate sit consistently inside that framing.
- **Scope honesty:** the closing paragraph correctly states this proves deterministic *technical*
  equivalence only, leaving source-priority business semantics to Boat/Aware.

With this, chains ① ② and the 042 track are deployed + verified + reviewed; chain ③'s repoint is
the sole remaining deploy action, now purely a Boat decision (see the RQ-1637 review's readiness
statement).

Queries used: 0.
