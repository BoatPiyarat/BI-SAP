# Session — charge recovery

## 2026-09-30 — 2026 charge reconciliation and scoped legacy recovery

Boat explicitly authorized a charge-driven 2026-only reconciliation, a reusable query, V2/sap_view fix proposals, and immediate upload of valid missing rows covered by current views. This scoped instruction supersedes the older blanket production-bucket prohibition for this recovery only. It does not authorize view deployments or V3 changes.

Uploaded 177 validated RCB Motor rows across 159 orders, carrying THB 898,995.29, at 23:21:44 ICT to `gs://interface-file/RCB_MOTOR/INSURANCE_RCB_01_CREATE_RECOVERY_20260930_232138.csv`. Generation 1790785304135095, size and MD5 verified. Independent review passed; a fresh source/SAP preflight found zero blockers. SAP acceptance remains unverified.

Final working list: 4,428 obligations = 177 uploaded + 4,115 covered but held + 136 without verified coverage, including one known scenario. Source baseline: 2026-09-30 14:46:23.688793 UTC. See `docs/FINDINGS_CHARGE_RECOVERY_20260930.md` for sources, nonadditive hold counts, proposals and limits. Two SELECT-only proposals were prepared; no live definitions or V3 objects changed. An isolated handoff branch preserves the original checkout's divergence and unrelated work.


Git handoff remains local. Automatic approval review blocked the push; `gh repo view` confirmed the remote is public. No push/PR occurred. User publication preference requested separately from the already completed bucket upload.

User decision: keep the handoff local. Do not publish this branch, report, or evidence to the public GitHub repository. The approved bucket upload remains complete.
