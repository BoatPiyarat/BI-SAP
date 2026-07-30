# Finding — 224 unexplained credit-shell symptom orders

Status: OPEN, out of scope for INCIDENT-002a and INCIDENT-002b.

D16 (`42b7c0a`) segmented the earlier 559-order symptom population by CMI sibling and confirmed
duplication mechanism. **224 orders had neither factor**. Their cause is unknown; they must not be
assigned to the CMI identifier issue, the credit-shell double-deduction incident, or the onetime
M1/V1 split.

The 224 figure is a diagnostic count from the D16 2×2 analysis, not a correction population.
Before any stakeholder reporting or remediation, establish cause and then pass the
`POSTED_WRONG` gate plus `sap_fa_verification`.
