# SAP INCIDENT LOG

Local canonical incident addenda. The pre-existing Drive incident library remains historical
evidence; new incidents are versioned here and synchronized to Drive.

---

## INCIDENT-002 — CMI double-deduction in credit-shell

- **Status:** OPEN — scope being quantified by Claude Code
- **Confidentiality:** internal team only; do not notify outside the team until authoritative
  population and money impact are evidenced
- **Operational incident label:** 263 transactions, supplied with the 2026-07-29 design evidence;
  this is not yet a BigQuery measurement that may be quoted externally
- **Concrete case:** `L80524847`, observed 2026-07-28
- **Live diagnostic provenance:** `pacific-plating-282708.sap_integration_v2.RCL 04_new order credit shell`,
  evidence committed in `5171adb` at 2026-07-29 23:47:45 ICT. Exact query timestamp was not
  retained, so its diagnostic population is not the authoritative incident scope.

### Mechanism

The credit-shell path ranks charge rows using `charge_rank PARTITION BY transaction_id`. Multiple
charge rows can reach one `(OrderItem, Period)`, and `add_ons` is deducted per charge row instead
of once at the output grain. The path also repeats nonzero `ExpectedReceived` on later rows. All
three orders inspected in the incident evidence violated the repeated-row rule.

### Violated canonical rules

1. Rows 2+ within one `(OrderItem, Period)` must have `ExpectedReceived=0`.
2. `add_ons` must be deducted once per `(OrderItem, Period)`, not once per charge row.
3. CMI is identified only by
   `careos.careos_order_items.motor_item_type = 'MOTOR_TYPE_COMPULSORY'`, never `packageType`.

### Correction and prevention

For records whose `ExpectedReceived` is wrong or negative, Aware requires Cancel + new Paid
(correction method 2). Do not issue correction files before the scope, per-item target set, and
approval are complete. Forward prevention requires item-period-grain de-fanout and the two
validation rules above; SQL changes are owned by Claude Code and are not authorized by this entry.

### Scope warning

The broad duplicate-pair diagnostic in `docs/FINDINGS_CREDITSHELL_DUPLICATE_20260729.md` and the
263-transaction incident label are different measurements with different provenance. Do not merge,
subtract, or cite either as final incident scope until Claude Code returns the authoritative
transaction list, source object, query timestamp, and impact calculation.

