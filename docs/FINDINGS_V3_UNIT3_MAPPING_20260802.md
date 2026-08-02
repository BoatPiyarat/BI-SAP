# V3 Unit 3 mapping findings — 2026-08-02

Status: source/design only. No registry row was seeded, no DDL was deployed, and no READY row was
released.

## READY inventory

For pipeline run `V3NIGHTLY-2026-08-02T09:02:26-b36e1712`, read-only job
`v3_unit3_ready_mapping_inventory_20260802_1921` (created `2026-08-02T12:20:00.399Z`) processed
209,496,187 bytes and billed 209,715,200 bytes under the 20 GiB cap.

- 1,185 READY payment events contain 15 distinct raw payment source tuples.
- The raw-PaymentDate 2026-08-01 slice contains 787 events: 784 Motor and 3 Health NonMotor.
- The 3 Health/RCL events (3 orders; source amount 542,165 minor units) remain held until an
  effective approved InsuranceGroup mapping exists.

## SAP-success evidence

Job `v3_unit3_refined_sap_evidence_20260802_1926` (created `2026-08-02T12:23:20.543Z`, processed
468,578,969 bytes and billed 468,713,472 bytes) used only rows where CareOS immutable
`(order_item, period, derived InvoiceNo)` matched `sap_mirror_doc` with a non-null DocEntry. It
proved that `(flow, payment option, source method, source channel)` is not a sufficient mapping key:
historical outputs also vary by product and credit-shell context. Even after adding `product_scope`
and `is_credit_shell`, several tuples retain multiple accepted historical outputs. V3 therefore
must not select the most frequent output automatically.

The Health InsuranceGroup mapping has unambiguous historical evidence:
`products/health-insurance + NONMOTOR + RCL -> Health`, 45,092 distinct SAP DocEntries. This is
evidence for review, not approval or a registry insert.

## Source response

- `011` preserves raw `insurance_group_source` in V3 staging.
- `013` preserves raw `payment_method_source` and `payment_channel_source`.
- `052` defines closed effective-dated registries, overlap/evidence assertions, and fail-closed
  Unit 3 holds.
- Payment mapping identity includes `flow`, `product_scope`, `is_credit_shell`, payment option,
  raw method, and raw channel.

No mapping may become `APPROVED` without an explicit evidence reference, approver, approval time,
and a non-overlapping effective interval.
