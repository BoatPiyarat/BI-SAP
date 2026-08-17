# Mo RCL recovery V3 module

Status: corrective design after Class-A BLOCK of commit `b36e12b`; implementation pending review

## Interface and seam

The module exposes one build interface:

```sql
CALL sap_integration_v3.sp_build_mo_rcl_recovery(p_request_id);
```

The caller supplies only an immutable, previously seeded request ID. Mapping, Phase-1 membership,
canonical value derivation, quarantine, gate evidence, and payload hashing remain inside the
module. Export is a separate interface that accepts the same request ID and may read only that
request's immutable PASS snapshot.

## Immutable request contract

- Seeding is insert-only. Reusing a request ID fails; it never deletes or replaces prior scope.
- Each requested `(OrderID, reported_period)` must still classify as
  `STILL_MISSING_SILENT_DROP` at build time: no real SAP InvoiceNo, exclusion, or validation row.
- Every input pair resolves to exactly one ordinary RCL OrderItem. Unknown, RCB/Onetime, RCL_CMI,
  and ambiguous mappings are quarantined.
- Holds and gate evidence are append-only at `(request_id, OrderItem, rule_code)` grain.
- The snapshot stores `payload STRUCT<56 reviewed STRING fields>`, `payload_hash`, request ID, and
  build timestamp. Audit fields are outside the payload and cannot alter SAP column positions.
- A request can be built once. Retry reruns validation and refuses to overwrite prior evidence.

## Canonical derivation

- The full period spine comes from `stg_schedule`, never from only the reported period.
- Status is derived, not normalized: exactly one qualified successful event for a period means
  `Paid`; no event means `Pending`; multiple events require the reviewed additional-payment path
  and are held here.
- Paid InvoiceNo mirrors `sap_mirror_state` verbatim whenever SAP has a Paid/Cancelled value.
  Otherwise it is generated only through `fn_invoice_no(third_party_id)`.
- Paid PaymentDate comes from the successful event under the reviewed period-lock/cutoff rule.
  Pending PaymentDate is the canonical empty string.
- PaymentMethod and PaymentChannel resolve through the approved effective-dated mapping registry.
  No literal status/channel spelling is translated from the legacy dashboard.
- The legacy installment relation may provide the remaining reviewed financial/policy fields, but
  every field is explicitly selected, formatted to the 56-string contract, and reconciled back to
  its source. SQL NULL is never silently converted for a required field; optional fields receive
  only their reviewed canonical empty/zero representation.

## Whole-item quarantine

An OrderItem is accepted only when all its periods pass. Any failed period quarantines its entire
spine. Other items may continue, per Boat's 2026-08-17 decision, only when the candidate file still
passes the file-level one-flow and exact-schema gates.

Required evidence per request:

- input pairs = classified pairs = mapped pairs + held mapping pairs;
- accepted rows = `SUM(TotalPeriods)` and exact integer periods `1..N` per item;
- successful charges for accepted items = Paid candidate periods, with no duplicate event period;
- every nonaccepted item has at least one durable hold/validation reason;
- exact 56 field names/types/ordinals equal the live reviewed
  `v3_unit5_newpayment_delivery_ready` contract;
- no SQL NULL or literal `"NULL"`, exact Paid/Pending vocabulary, valid dates, finite two-decimal
  numerics, approved masters, InvoiceNo immutability, and candidate hash/count evidence;
- exact SQL dry-run through `scripts/bq_safe_query.sh` before deployment or execution.

## Export rule

The exporter selects the 56 fields explicitly from `payload` for one PASS request ID and verifies
the retained count and hash immediately before `EXPORT DATA`. It may write only a shadow prefix
until Boat gives a separate current-session production `deploy OK`. An empty PASS population does
not produce an interface file.

Boat supplied that scoped production approval on 2026-08-17 for Mo-list PASS files only. It becomes
executable only after Class-A PASS and exact candidate evidence. The final pre-delivery rehearsal
must also prove that previously reported importer failures cannot recur:

- complete `1..TotalPeriods` spines (LogID 21178 regression) and exact `INSURANCE_RCB_` basename;
- InvoiceNo length <=30 and immutable mirror value for previously Paid/Cancelled rows;
- OrderItem length <=30, PolicyNo length <=50, and all five dates valid under the open period;
- confirmed InsurerCode and payment mappings, CompanyDB=`RCB`, required Paid fields, and exact
  `Paid`/`Pending` status-dependent emptiness;
- financial/spine conservation, including no RCB TotalEIR interpretation in this RCL file;
- exact snapshot row count/hash unchanged between the gate and production copy.

After production delivery, completion still requires SAP pickup, terminal import result, fresh
mirror, and exact identity reconciliation; bucket delivery alone is not gap closure.
