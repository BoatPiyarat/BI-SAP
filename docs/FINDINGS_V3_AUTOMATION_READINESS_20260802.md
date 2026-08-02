# V3 automation readiness — 2026-08-02

## Outcome

V3 is not yet safe to activate as the sole nightly interface. The deployed workflow revision
`000003-3e1` ends at Unit 1. Unit 2 and Unit 4 have production evidence, Unit 3 remains deliberately
closed pending approved mapping rows, and generic daily Unit 5 delivery plus Unit 6 result/report
automation do not yet exist.

The source increment in `052`/`054` makes this boundary machine-enforced. Unit 3 now records one
run summary. The release gate then blocks Unit 5 unless the same run has exactly one successful
Unit 1 completion, Unit 2 output with zero UNKNOWN rows, a Unit 3 evaluation with zero mapping
holds, and exactly one OPEN accounting period. Gate results are durable even when the final
`ASSERT` stops the run.

## Current blockers

1. Unit 2's last evidenced run still had 14 payment-event UNKNOWN rows (`FINDINGS_V3_UNIT2_SHADOW_20260802.md`).
2. No approved payment-mapping registry seed exists. NonMotor InsuranceGroup mappings for raw
   PaymentDate on/after 2026-08-01 also remain fail-closed pending SAP-master evidence.
3. July-only `048`/`049` cannot be reused as a daily exporter: they are scoped to July, one folder,
   and deduplicate at schedule grain, which would lose legitimate same-period top-up events.
4. Row-level SAP-result ingestion, post-import Unit 1 refresh, completeness snapshot, and proven
   human alert delivery are not yet wired into the workflow.

## Cutover rule

Do not pause V2 or enable a recurring V3 delivery scheduler until Units 5–6 are implemented and a
shadow E2E rehearsal proves exact-byte 56-column output, ACK/reject ingestion, second mirror
refresh, zero conservation residual, and alert delivery. Scheduler mutation remains a separate
production gate.

