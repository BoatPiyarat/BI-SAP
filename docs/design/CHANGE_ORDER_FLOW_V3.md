# V3 change-order flow — source-only preparation

Status: **Class A / not deployed / not approved for export** (2026-08-02).

## Boundary

An ordinary change-order is a link in `careos.cancelled_change_orders`: the old order is the
superseded SAP document and the current order is its replacement. It is not Q3a winner selection
and it is not automatically an INCIDENT-002b correction. The 244 cause-aligned INCIDENT-002b
orders and 224 unknown-cause orders remain outside this flow pending Boat's direction.

This linked population is structurally disjoint from plain cancellation. A linked pair never uses
the plain-cancel literal/track; an `is_cancelled_effective` item without a change-order link never
enters this flow or credit shell. Plain cancel is a separate future track that clones the old SAP
56-column document and changes only TransactionStatus to `Cancelled`; it has no replacement map.

The July V3 exporter correctly holds replacement rows as `CHANGE_ORDER_SEPARATE_FLOW`. The hold is
not evidence that the old SAP document may be cancelled.

## Three independent lanes

1. `CANCEL_OLD`: read the winning rows from `sap_mirror_state`, require the complete period spine,
   preserve the current `InvoiceNo` and all 56 positional fields, and change only
   `TransactionStatus` to `Cancelled (Change order / Rejected)`.
2. `CREATE_REPLACEMENT`: use the V3 expected-state/payload contract for the current order. It must
   pass the same qualification, exclusion, formatting, 56-column, and July-only controls as the
   normal exporter.
3. `CREDIT_SHELL_PAYMENT`: requires a reviewed old/new payment linkage. Its PaymentDate is the old
   cancellation BatchRunDate, ActualReceived is the carried amount, PaymentChannel is CreditShell,
   and PaymentMethod uses the RCB/RCL CreditShell mapping. Existing live spelling variants are a
   mapping gate; the implementation must not invent a new literal.

These lanes are never unioned until each has an explicit eligibility result. A failure in one lane
must not silently release either of the others.

## Hard preflight gates

- Exactly one active `sap_period_lock` row.
- Old order exists in SAP; cancel never creates a missing historical document.
- Old order is not already terminal.
- SAP period spine is exactly `1..TotalPeriods`, one winning row per period.
- Paid SAP rows retain a non-empty immutable InvoiceNo.
- Replacement exists in V3 expected state and Paid rows have InvoiceNo and PaymentDate.
- July-only runs reject any replacement PaymentDate on or after 2026-08-01.
- Old→new order-item mapping must be unambiguous before 56-column payload construction.
- Aware must answer whether an explicit Cancelled document is required; FA/Boat must approve the
  batch. `READY_FOR_AWARE_FA_REVIEW` is evidence readiness, not delivery authority.

`sql/adhoc/20260802_change_order_preflight.sql` produces order-pair readiness and fail-closed hold
reasons without mutation. It intentionally stops before payload generation because the direct
order-level link does not itself prove an unambiguous item-level mapping.

## Required next evidence

1. Run the preflight with dry-run, 20 GiB ceiling, and `asia-southeast1`; retain job ID, UTC query
   timestamp, processed/billed bytes, counts by `preflight_status`, and the distinct source
   TransactionStatus inventory. The inventory must justify the accepted Paid/Pending literal set;
   unknown case variants remain fail-closed.
2. Prove old→new item mapping by a reviewed business key; suffix similarity alone is insufficient.
3. Obtain Aware's cancellation requirement and exact accepted CreditShell literals.
4. Produce three shadow payloads, validate each against the canonical 56-column contract, and
   perform exact row/key/amount reconciliation before any Class A deploy or export request.

