# Dashboard-only deployment authorization

User instruction in this session: "Please fix only `sap_dashboard_carepay_installment` to allow additional payment (Expected =0, Actual = new charge) right away, other refer to this view, i will review it later".

This explicitly narrows immediate deployment to this one legacy view and defers user review of downstream readers. It supersedes the prior source-only hold for this view and the local review-before-deploy/scoped legacy DDL restriction for this action. RCL newpayment/gate and V3 remain undeployed.

Change: remove the voluntary first-charge-only filter, use deterministic (create_time,id) rank, preserve ExpectedReceived=0 for rank>1, take ActualReceived directly from charges.amount/100, and prevent EIR reconciliation from reintroducing interest on extra rows. Preserve the 56-column output and compulsory first-charge rule. No principal mapping change.

Precheck succeeded for the two reported receipts and duplicate-key assertions. Prior broad candidate checks document the deterministic tied-charge effects and downstream concerns. Dashboard visibility is not proof of successful SAP import. The original definition and complete metadata are retained here; rollback.sql restores the previous SELECT.
