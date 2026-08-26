# V3 business-scenario production matrix

Status date: 2026-08-26 ICT. This file distinguishes approved numbering from proposed flow slots.
An unnumbered design or legacy view is not production authorization.

| No. | Business scenario | Current production state | Release gate |
|---:|---|---|---|
| 1 | Ordinary RCB/ONETIME successful-payment CREATE | Routine deployed; fresh run built; zero released, all candidates held | Resolve named mapping/required-value holds before activation |
| 2 | Ordinary RCL first-period paid CREATE, not Credit Shell | Hold-only source; corrected artifact awaits final Class-A review | Business approval of RCL CREATE InvoiceNo mapping plus 56-column builder |
| 3 | Ordinary RCL later-period NEWPAYMENT, not Credit Shell | Routine deployed; fresh run built; zero released, all candidates held | Resolve named mapping/balance/contract holds before activation |
| 4–9 | Number-to-flow mapping not defined in an authoritative repository source | Not deployable by scenario number | Boat must confirm numbering before implementation/deployment |

The repository does define the remaining business populations below, but it does not assign them
to Scenario numbers 4–9:

- ordinary plain cancellation (unlinked cancellation, exact SAP status `Cancelled`);
- linked change-order cancellation (exact SAP status `Cancelled (Change order / Rejected)`);
- replacement Credit Shell after linked-cancel SAP ACK;
- one-period compulsory RCL/CMI;
- `CREDIT_CARD_INSTALLMENT` treated as ONETIME/EDC;
- additional-payment/correction populations, which require a durable marker to distinguish them.

These labels must not be force-fit into 4–9 without a business-owned mapping. In particular,
plain cancellation and linked change-order cancellation cannot cross-route, and Credit Shell cannot
release until linked cancellation has row-level SAP ACK. EDC bank mappings, change-order item maps,
accepted CreditShell literals, and correction-vs-additional-payment identity are unresolved gates.

## Evidence required per scenario before activation

1. Exact population and non-overlap assertions against all other scenarios.
2. Explicit 56-column projection and bilateral ordinal/name/type contract check.
3. Every owned identity ends released, excluded, or in a named durable hold.
4. Class-A Standards PASS and Spec PASS for the exact commit.
5. Authenticated BigQuery dry-run under the cost ceiling and production deployment job ID.
6. Fresh run with immutable/run-bound manifest and ready/hold conservation.
7. Read-only human fallback plus create-only delivery marker and rollback procedure.
8. Dedicated non-overlapping scheduler identity; scheduler stays paused when ready rows are zero or
   any business/mapping approval is unresolved.
9. Exact GCS generation/CRC evidence, SAP pickup evidence, import result, and row-level ACK/reject.

No current scenario has authorization in this file to write `gs://interface-file/**`.
