# RQ-20260802-1708 — Unit 2 shadow classifier self-review

Verdict: **PASS FOR SHADOW DEPLOYMENT ONLY**. Class A. This does not authorize payload release,
GCS write, scheduler cutover, or chaining Unit 3 from Unit 2.

Reviewed `sql/ddl/051_v3_unit2_shadow_classifier.sql` and the live-profile evidence. The source
keeps payment events and schedule rows in different physical tables, preserves multiple charges in
one period, uses a matching LIVE DocEntry+InvoiceNo for event ACK, holds immutable InvoiceNo
conflicts, requires an existing Paid/Pending SAP row before cancel/change, chooses one latest
archive row, and asserts event record+amount and schedule record conservation independently.
Re-running a run ID replaces only that run's shadow rows.

The source has no `EXPORT DATA`, GCS URI write, scheduler call, legacy-view mutation, or production
interface delivery. BigQuery DDL dry-run passed under the 20 GiB cap.

Acceptance remains blocked until the first shadow distribution is explained, unknown outcomes are
zero or explicitly resolved, an approved magnitude-threshold configuration is implemented, and
row-level LIVE result ingestion supplies reliable ACK/reject chronology. Those are release gates,
not blockers to creating and measuring the shadow tables.
