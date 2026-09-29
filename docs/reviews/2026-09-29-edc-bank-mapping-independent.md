# EDC mapping proposal — independent Class-A review

Verdict: **PASS WITH NOTES for the investigation/proposal only. No deployment or export approval.** Reviewed report SHA256: fc2ec4630a3f70be61cd7ae8414d4c90a176eb1282c0ed16a06b59548f1ca952. Artifact-only review; zero new BigQuery queries.

1. Traceability — counts tie to named SQL and snapshots: definitions 10:27:01, profile 10:27:21, impact 10:29:09 UTC on 2026-09-29.
2. Provenance — fresh evidence and historical registry evidence_reference retained; this report hash fixes reviewed content.
3. NULL-safety — proposal explicitly holds unknown/NULL/ambiguous mappings; diagnostic LEFT JOIN retains unmatched links. Implementation remains future work.
4. Ordering — no new winner-selection implementation; arbitrary/latest order-level charge selection expressly prohibited.
5. Column order — no interface altered; future 56-column positional regression is required.
6. Grain — profile is charge-level; current impact explicitly joined links, not unique exports. 34 matched non-EDC links (16+9+9) and 17 unmatched confirmed; matched EDC links zero.
7. Distribution — six-bank counts independently confirmed: BAY 9,708; KTB 2,764; KBANK 2,147; UOB 361; BBL 339; SCB 75; TMB 5 and unspecified 1; total 15,400. One BAY charge is RABBIT_CARE_INSTALLMENT.
8. Knowledge — five registry approvals correctly limited to ONETIME/MOTOR/CREDIT_CARD_INSTALLMENT/non-credit-shell from 2026-08-01. SCB absent. All six method/channel pairs occur in CASE and Paid mirror history, without claiming general approval. KBANK-only predicates and scenario hold in sp_build_v3_edc_onetime_holds verified.
9. Scope — source-only proposal; no implementation, registry change, history correction, scheduler mutation or export.
10. Rollback — not applicable to report; fresh definition and separate reviewed deploy required for future changes.
11. Cost hygiene — reviewer reused supplied JSON/SQL; no repeated scans. No cost claims made by report.
12. Honest labelling — static scan limited to 96 views / 81 routines in four datasets; absent static downstream references not confused with no external consumers. Usage history not confused with GL correctness.

Specific note (nonblocking): sentence “NonMotor has method=EDC for any EDC source” should name RCB_NonMotor_process_2_cancel specifically. Its blanket EDC method branch is verified; RCB_HEALTH instead uses explicit provider-qualified method branches. Avoid implying all NonMotor views share the same unknown-bank fallback defect.

Residual safety conditions are correctly proposed: exact charge lineage/allocation, effective-date semantics, unique approved mapping, preserved posted identities, six-bank plus unknown/duplicate/non-EDC fixtures, and no scenario activation from mapping alone.
