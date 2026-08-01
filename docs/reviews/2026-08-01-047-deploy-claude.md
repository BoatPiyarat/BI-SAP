# Review — 047 repoint deploy evidence (`01e7b20`)

**Queue entry:** RQ-20260801-2000-047-repoint-deploy-evidence · **Class:** A · **Reviewer:** Claude Code
**Verdict:** **PASS** — chain ③ cutover is live, correctly deployed, and safe to observe through
the 21:00 ICT scheduled run.

## Independent live verification (reviewer's own, per the deploy-time reminder in the 6efcf1e review)

Fetched the post-cutover routine via metadata (0 bytes) and compared mechanically:
- **Live body = the reviewed 047 new body, line-for-line identical.** 10 executable calls;
  `sp_refresh_sap_mirror_doc_incremental('NIGHTLY:scheduled')` present; full-024 call absent;
  `sp_refresh_interface_daily_status()` retained as the final call.
- **SHA256 independently computed over the live body = `11f40bbe…c4afa692` — exactly the hash the
  evidence reports.** Author and reviewer measured the same live object and got the same digest.

## The "11th call" wording — the evidence is right, my prose was wrong

Owning the count error: pre-cutover live had **10** executable calls and the blocked 047 had **9**;
my RQ-1917 prose said "11th call"/"10 calls" — off by one on both sides. The operative evidence in
that review was the mechanical line diff (which found the genuinely missing
`sp_refresh_interface_daily_status` — real defect, correct fix), so the verdict chain is
unaffected, but the numbers in the prose were mine and wrong. Codex's evidence handled the
discrepancy exactly right: reconciled it against live metadata instead of propagating either count.

## Process

Job provenance complete (deploy 0-byte DONE, metadata verify with timestamp); the claim boundary is
correctly drawn — deployment evidence is **not** scheduled-run success. The first 21:00 ICT
execution remains the operational verification: watch `pipeline_run_log` for the
`sap_mirror_doc_incremental` step, watermark advance past `2026-08-01/809`, and normal downstream
steps; the byte-identical rollback stays one paste away in 047.

Queries used: 1 routine-metadata fetch (0 bytes billed).
