CreditShell NonMotor rows already existed in both legacy wrappers, but insurer IDs were numeric, unpaid ActualReceived was missing/zero, and RCL emitted old paid dates.

Deployed three existing views: shared RCL04 producer and RCL/RCB process4 CreditShell wrappers. Apply all35 RCL_HEALTH insurer mappings after ranking; Pending ActualReceived equals finalExpected; historical NonMotor Paid dates become first day of the current Bangkok month.

Validation: exact-source preflight004 PASS (9.70GB); independent Standards/Spec PASS;56 columns preserved in all3 views; zero Motor, paid-amount, receipt-multiplicity or other-field regressions. ThreeDDL jobs DONE and readback matches. Live postcheck at2026-09-28 10:50:19 Bangkok: same84 Health rows/9items per wrapper, all requested defect metrics0.

No liveTA sample; unknown insurers keep legacy fallback; wrapper ownership overlap is preexisting. V3/exports/schedules unchanged. Live-view verification does not prove SAP posting.

Report: docs/FINDINGS_NONMOTOR_CREDITSHELL_20260928.md
