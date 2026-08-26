# V3 Scenario 2 manual fallback — RCL first-period CREATE

Scenario 2 is deliberately **hold-only**. The RCL CREATE InvoiceNo transformation is not approved,
so there is no 56-column export query, file generation, GCS upload, scheduler, or SAP import step.

1. Build the reviewed gate for the exact run:
   `CALL sap_integration_v3.sp_build_v3_rcl_first_create_hold_gate('<run_id>');`
2. Set the same run ID in
   `sql/operator/20260826_report_v3_rcl_first_create_holds.sql` and execute it read-only.
3. Confirm the summary has `gate_status='BLOCKED_NO_APPROVED_INVOICE_MAPPING'`,
   `ready_identity_rows=0`, router conservation, and exact durable-hold conservation.
4. Give the raw/staged/event/source InvoiceNo variants to the business owner. Do not remove a
   prefix, synthesize an InvoiceNo, reuse the Scenario 3 payload, or create an interface file.
5. After a separately documented InvoiceNo decision, implement a new 56-column candidate builder,
   Class-A review it, dry-run it, deploy it separately, and run a fresh build. This hold gate is not
   an implicit approval for that later artifact.

Rollback is withholding any future Scenario 2 release artifact and leaving this gate active. Since
the gate emits no interface rows and has no scheduler, rollback never deletes GCS/SAP evidence and
never changes V2 or another V3 scenario.
