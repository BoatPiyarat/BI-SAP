# Independent review — user-confirmed principal delta

Reviewer /root/review_downstream, read-only static review. **PASS for the four SELECT candidates.**
User explicitly authorizes live view repair and confirms both principal fields equal the new charge
amount for additional receipts. This closes the previous principal business-rule blocker.

Exactly two dashboard projection expressions change. Existing raw-rank-derived is_additional_receipt
selects ActualReceived for both principal fields; ordinary zero-Expected rows are not misclassified.
CMI sets this flag false. Ordinary/CMI values, interests, row selection and column positions are unchanged.
The three downstream SELECTs are identical to the reviewed September27 candidates. SAP-carried source
queries are not modified.

Before deployment: restore auth; capture fresh definitions/schema and check drift; preserve rollback;
run fresh composed preflight including all eight formerly flagged cases, full payload differences,
lineage failures, principal formula, duplicates and complete spines; verify schema types/order.
Deploy in dependency order; four replacements are not atomic. Retain rollback and verify read-back.
No manual interface-file export or completed SAP import is required to establish view-only deployment.
V3 remains held; report SAP posting separately.

Named risk: runtime lineage assertion intentionally fails on newly encountered unsent nonzero receipts
without lineage. Fresh preflight must establish the assertion passes. This review is static approval,
not a claim of completed live verification or deployment.
