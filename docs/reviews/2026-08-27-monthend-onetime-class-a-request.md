# Claude Code Class-A request — reusable month-end ONETIME candidate/export query

Status: **NOT SENT / awaiting exact external-egress approval**. The safety reviewer rejected the
Claude Code invocation because this internal SQL plus the named deployment standards would be sent
to an external Claude destination. No repository source was transmitted.

Artifact under review:
`sql/operator/20260827_monthend_missing_sap_onetime.sql`

Artifact state: untracked working-tree file supplied by the user. Review the exact bytes with
SHA-256 `03a9111dd0b90c92d08f41773b5ae7fdefd515ea90a3807725aee22ec78d010d`; do not edit it.

Read these sources first:

- `docs/AGENT_RULES.md`;
- `docs/design/SAP_INTERFACE_PRE_EXPORT_GATE.md`;
- `docs/AGENT_REVIEW_PROTOCOL.md`;
- `sql/ddl/048_july_export_shadow_and_archive.sql`;
- `sql/operator/20260826_export_v3_onetime_create_manual.sql`.

Review only; do not run BigQuery, deploy, write GCS, execute a Workflow, call a procedure, or
mutate any repository or production state.

Return two separate axes and one final `PASS` or `BLOCK` verdict:

1. **Standards/Safety** — BigQuery Standard SQL, mandatory safe-query/cost path, exact 56-column
   positional contract, complete canonical pre-export validation, NULL/date/time-zone safety,
   immutable InvoiceNo/archive behavior, deterministic deduplication, and read-only claims.
2. **Spec** — whether it truthfully finds only Paid ONETIME/CREATE rows in the chosen ICT calendar
   month that are absent from terminal SAP delivery/ACK, conserves every held row with a durable
   reason, and emits a manually exportable payload without mixing installment/change-order/inflight
   populations.

Pay particular attention to population grain and joins, ICT month boundaries, duplicate charge
events, multi-statement result visibility, required-field validation, and whether the advertised
manual-export readiness is stronger than the gates actually implemented.

Report numbered load-bearing findings with file/line evidence. A source PASS would not authorize
execution or export.
