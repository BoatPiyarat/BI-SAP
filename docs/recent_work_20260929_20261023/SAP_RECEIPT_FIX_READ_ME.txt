SAP receipt identity fix — 6 October 2026

Implemented in the LOCAL review generator. No SAP view, scheduled job, importer, or production bucket was changed. No new interface was uploaded.

Confirmed design from Boat, 6 October 2026
An existing successfully imported SAP InvoiceNo such as 2_charge is intentional. Carry that exact stored identifier into the existing Paid row of a newpayment spine, and use the stored predecessor identifier for cancellation. Do not regenerate or strip the prefix in the output. A genuinely new payment in another period has its own receipt identity. Internal source reconciliation may associate an RCL period-1 prefix only with period-qualified, unambiguous source evidence; that association never authorizes changing the stored SAP identifier.

Changes
- sap_receipt_guard.py centralizes receipt matching, preservation and local prior-interface inventory.
- sap_monthend_validate.py now copies these seven SAP-proven receipt fields: InvoiceNo, ExpectedReceived, ActualReceived, PaymentDate, PaymentMethod, PaymentChannel, TotalPeriods. BatchRunDate remains the current run date. Cancellation copies the same fields from its unique existing SAP item/period predecessor and retains the requested cancellation status.
- The available SAP snapshot contains only those receipt fields plus identity/status metadata. This is not a claim of full 56-field Paid or cancellation predecessor preservation. Other row checks remain in force; cancellation retains FULL_CANCEL_PREDECESSOR_PAYLOAD_PROOF_REQUIRED.
- Stored Paid dates are never shifted just to pass the current-month rule. An incompatible historical date holds the dependent payload.
- Source-proven first-period RCL alias matching rejects ambiguous raw/prefixed source identities and ambiguous SAP documents. A distinct receipt in the same period is not overwritten by the guard; the legacy one-row-per-period exporter still holds multi-receipt spines pending their separate supported path.
- Prior CSV discovery includes nested Q3 closing folders and manifest references in both Q3 closing and C:/dev/sap-* histories. Known missing/malformed/unsupported interface evidence blocks release. A local review file is possible delivery evidence, not proof it was uploaded or accepted.
- sap_monthend_export.py rechecks the frozen Paid payload and prior inventory immediately before serialization. Unchanged carried Paid rows may remain in a necessary complete spine; they are not classified as new receipts. New receipts already present in prior interfaces are held for acknowledgement reconciliation.
- Both validator and exporter refuse to write into the historical reconcile_20261002 run. Use an explicit new SAP_RECON_OUT directory containing freshly captured evidence.

Verification
16 focused regression tests PASS. Python compilation PASS.
Independent Class A static review PASS for local-only use. Reviewer inspected code; tests were run by the implementing agent.
See replay_summary.json for the executed full-validator replay on copied Oct 2 evidence, and prior_interface_inventory_errors.json for unresolved historical file evidence. These are offline results, not an October 6 live reconciliation or current backlog count. No interface files were emitted by replay. The original Oct 2 review files were preserved.

Files
sap_receipt_guard.py — shared rules
sap_monthend_validate.py — integrated validator
sap_monthend_export.py — integrated exporter
sap_monthend_run.py — read-only query wrapper/config; SAP_RECON_OUT override
test_sap_receipt_guard.py — focused regression cases
sap_receipt_fix_replay.py — isolated historical validator replay; writes only under its own outputs directory
implementation.patch — changes against the delivered Oct 2 scripts, plus the new guard/tests
package_manifest.json — SHA256 checksums

Run tests from this package directory
python -m unittest -v test_sap_receipt_guard.py

Run historical replay
python sap_receipt_fix_replay.py
It reads the established Q3 closing/reconcile_20261002 evidence and current local historical-interface inventory. Counts can change if that inventory changes. It does not run BigQuery or export interfaces.

Use with a fresh local generation run (PowerShell)
$env:SAP_RECON_OUT = 'C:\path\to\a\new\review-run'
python sap_monthend_validate.py
Inspect evidence/validation_outcomes.json and evidence/prior_interface_inventory_errors.json.
Only after fresh SAP/source/acknowledgement evidence and every existing gate passes:
python sap_monthend_export.py

Operational limits
This is a local single-run safeguard against the supplied SAP snapshot and inventoried files. It is not a transactional, cross-machine delivery ledger or an automatic SAP acknowledgement fetch. Do not run concurrent exporters or treat stale evidence as a live preflight. Production deployment/upload remains a separate action after exact-current evidence, implementation review and applicable approval. No live definitions were inspected or changed in this fix.

Scope remains the user's current-date/current-month output rule and 2026 successful-payment/cancellation event selection. Channel mappings, other amount rules, full cancellation predecessor capture and vendor importer changes were not implemented in this selected fix.
