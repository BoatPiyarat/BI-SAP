# Production authorization — 2026-09-28

User explicitly instructed applying the prepared fixes directly to the live views and reporting their
names and changes. User separately answered the accounting clarification: both principal fields for
additional receipts equal the new charge amount. No new deploy permission is required.

Scope: sap_data_engineer.sap_dashboard_carepay_installment (two final principal expressions),
sap_integration_v2.RCL 05_newpayment, sap_integration_v2.RCL 05_paid by period,
sap_view.RCL_Motor_process_2_newpayment. V3 remains held. No SAP record, interface-file write,
export invocation or scheduler mutation is part of this deployment.

Static independent review passes exact four SELECTs. Fresh metadata matches captured definitions;
verbatim rollback bodies retained in *_before.json and *_rollback.sql. Fresh preflight/schema and
post-deploy live checks remain mandatory. Apply dashboard → newpayment → gate → Motor wrapper.
The live Motor scheduler runs at 01:30 Asia/Bangkok; preparation occurs about 10:00 ICT.
