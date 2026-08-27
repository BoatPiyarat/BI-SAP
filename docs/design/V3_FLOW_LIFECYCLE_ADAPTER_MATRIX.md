# V3 flow lifecycle adapter matrix

Status: source-only Class-A design. Current production evidence is job
`codex_v3_nine_flow_audit_20260827_115853`, recorded in
`docs/reviews/2026-08-27-v3-nine-flow-audit-result-evidence.md`.

## Shared downstream contract

DDL 100 already provides the generic `v3_flow_export_claim` ledger, exact byte/name-bound delivery
marker, and `vw_v3_flow_export_lifecycle` pickup→import→row-ACK view. Do not build nine copies of
that downstream state machine. Each flow instead needs a narrow upstream adapter that proves its
own immutable release identities and payload, then creates exactly one generic claim.

An adapter may create a claim only after all of these are true:

1. the exact flow/run readiness row has `release_ready_count>0`, zero interface rows, no blocker,
   and an exact unexpired activation approval;
2. a durable flow-specific snapshot binds every released business identity to one 56-column
   payload JSON and SHA-256;
3. identity, snapshot, ready object, and summary counts are bijective and conserved;
4. the ready object's ordered name/type contract matches the canonical 56-column object;
5. no identity has an active archive/delivery claim and the export token is unused;
6. archive creation or manual-delivery evidence is byte/name/generation-bound before the generic
   claim advances to `DELIVERED`;
7. the generic lifecycle view later proves exact pickup, one terminal import log, and row-level
   ACK/rejection conservation.

Mapping or business approval must be resolved before steps 1–3 are implemented for a held flow.
Do not turn hold rows into release identities merely to satisfy this contract.

## Exact matrix

| Flow | Preparation and payload | Immutable release identity | Lifecycle adapter | Human path today | Current release blocker |
|---|---|---|---|---|---|
| `ORDINARY_ONETIME_CREATE` | DDL 085 manifest + `v3_onetime_create_ready` | `v3_unit5_payload_identity`, role `CREATE_ONETIME` | DDL 101 registers exact manual-delivery evidence into DDL 100 | Export fallback: `sql/operator/20260826_export_v3_onetime_create_manual.sql` | no fresh durable ready run; Unit 2 thresholds/bootstrap required |
| `RCL_FIRST_PERIOD_CREATE` | DDL 087 hold summary; no release payload object | absent | absent | Hold report only: `sql/operator/20260826_report_v3_rcl_first_create_holds.sql` | approved InvoiceNo mapping, then 56-column snapshot/identity/adapter |
| `RCL_LATER_PERIOD_NEWPAYMENT` | DDL 088 summary + immutable spine + `v3_rcl_later_newpayment_ready` | role `NEWPAYMENT_RCL_LATER` plus spine snapshot | DDL 100 native archive and lifecycle | Export fallback: `sql/operator/20260825_export_fresh_v3_newpayment_interface.sql` | fresh normal build has zero ready rows; Unit 2 thresholds/bootstrap required |
| `EDC_ONETIME` | DDL 092 hold summary + `vw_v3_edc_onetime_payload_source` | absent; payload view is mutable | absent | Hold report only: `sql/operator/20260826_report_v3_edc_onetime_holds.sql` | release approval/non-KBANK mapping, then snapshot/identity/adapter |
| `RCL_CMI` | DDL 091 hold summary + `vw_v3_rcl_cmi_payload_source` | absent; payload view is mutable | absent | Hold report only: `sql/operator/20260826_report_v3_rcl_cmi_holds.sql` | CMI payment mapping approval, then snapshot/identity/adapter |
| `PLAIN_CANCEL` | DDL 093 hold summary + `vw_v3_plain_cancel_payload_source` | absent; payload view is mutable | absent | Hold report only: `sql/operator/20260826_report_v3_plain_cancel_payload_holds.sql` | FA batch approval, then immutable cancel identity/snapshot/adapter |
| `CHANGE_ORDER_CANCEL` | DDL 094 hold summary + `vw_v3_change_order_cancel_payload_source` | absent; payload view is mutable | absent | Hold report only: `sql/operator/20260826_report_v3_change_order_cancel_payload_holds.sql` | Aware supersession decision and FA approval, then identity/snapshot/adapter |
| `CREDITSHELL_REPLACEMENT` | DDL 090 dependency summary; no release payload object | absent | absent | Hold report only: `sql/operator/20260826_report_v3_creditshell_dependency_holds.sql` | item map, exact cancel ACK, literal approval, payload, identity, and adapter |
| `PAYMENT_ADJUSTMENT_INTENT` | DDL 095 registry/hold summary + `vw_v3_payment_adjustment_payload_source` | no approved release identity | absent | Hold report only: `sql/operator/20260826_report_v3_payment_adjustment_intent_holds.sql` | durable approved intent/release approval, then identity/snapshot/adapter |

## Deployment order per independently released flow

1. Resolve only that flow's named human mapping/approval blocker.
2. Build its immutable snapshot/identity and set ready count from that exact snapshot—not from the
   mutable payload view.
3. Add a narrow DDL 100 adapter and a real read-only/export human fallback; Class-A review both.
4. Deploy the adapter without activating a Scheduler or exporting a file.
5. Run one fresh build with delivery disabled and rerun the nine-flow audit.
6. Capture exact flow activation prestate under DDL 098; keep every other blocked flow unchanged.
7. Execute one separately approved export/delivery and follow DDL 100 through pickup/import/ACK.
8. Add a recurring flow scheduler only after a flow-scoped Workflow/procedure entrypoint exists.
   Never point multiple scenario schedulers at the current global Workflow.

Scenario 1 or Scenario 3 remains the shortest safe production slice after the Unit 2 threshold
input is supplied. None of the other seven may skip its mapping/approval step to become the first
release.
