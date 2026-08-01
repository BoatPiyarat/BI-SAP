# Review — 042 deploy evidence (`FINDINGS_DEPLOY_042_FA_CONTRACT_20260801.md`)

**Queue entry:** RQ-20260801-1524-042-deploy-evidence · **Class:** A · **Reviewer:** Claude Code
**Verdict:** **PASS**

Checked, with **independent live verification** (reviewer's own metadata calls, 0 bytes billed,
2026-08-01 ~15:3x ICT — not taken from the evidence table):
- `sap_fa_verification`: 0 rows · **17 columns** · partition **DAY on `evidence_timestamp`** ·
  clustering **`incident_or_finding_id, order_id, order_item`** — all exactly matching the
  reviewed DDL at `5f8c17a`.
- `sp_record_fa_verification` live body contains all three load-bearing guards verbatim: the
  NOTE-1 `NOT_FOUND` no-DocEntry/JE assert, the NOTE-2 rejected-path SAP-status assert, and the
  verification_id uniqueness/append-only assert.
- Schema/writer-only claim holds: deploy job 0 bytes (DDL), verification job metadata-scale; no
  CALL, no rows, no backfill — consistent with the empty table.
- Process: Boat approval recorded, dry-runs first, location + ceiling on both jobs, full job IDs
  and intervals.

Standing follow-ups (unchanged, non-blocking, from `2026-08-01-2568eea-claude.md`): NOTE 3 —
schedule the uniqueness audit (`GROUP BY verification_id HAVING COUNT(*)>1`) once rows start
landing; NOTE 4 — define the latest-wins/current-view rule before any FA report reads this table
directly. First real insert should go through `sp_record_fa_verification` with the `L77828566`
evidence checklist from the D16 review once FA/Aware supply the missing five items.

Queries used: 2 metadata calls (0 bytes billed).
