# SAP INCIDENT LOG

Local canonical incident addenda. The pre-existing Drive incident library remains historical
evidence; new incidents are versioned here and synchronized to Drive.

---

## D16 incident split — do not merge these populations

### INCIDENT-002a — CMI identifier change (263-class)

- **Status:** OPEN — scope being quantified by Claude Code
- **Confidentiality:** internal team only; do not notify outside the team until authoritative
  population and money impact are evidenced
- **Operational incident label:** 263-class, supplied with the 2026-07-29 design evidence;
  this is not yet a BigQuery measurement that may be quoted externally
- **Mechanism:** CMI identification changed; canonical identifier is
  `careos.careos_order_items.motor_item_type = 'MOTOR_TYPE_COMPULSORY'`, never `packageType`.
- **Boundary:** this is the “CMI issue” still pending. It is not the credit-shell double-deduction
  population and must not inherit the 244-order figure.

### INCIDENT-002b — credit-shell double-deduction

- **Status:** OPEN — cause-aligned diagnostic population is **244 orders**, not yet a correction
  population and not stakeholder-citable.
- **Source:** D16 evidence in `42b7c0a`; `sap_integration_v2.RCL 04_new order credit shell`.
- **Mechanism:** multiple charge rows reach one `(OrderItem, Period)` and `add_ons` is deducted per
  charge row instead of once at the output grain.
- **Boundary:** separate from INCIDENT-002a. The 244 figure must pass SAP-side posted-state and
  FA-verification controls before it can become a correction population.

### Violated canonical rules

1. Rows 2+ within one `(OrderItem, Period)` must have `ExpectedReceived=0`.
2. `add_ons` must be deducted once per `(OrderItem, Period)`, not once per charge row.
3. CMI is identified only by `motor_item_type = 'MOTOR_TYPE_COMPULSORY'`; this rule belongs to
   INCIDENT-002a and is not evidence that every double-deduction row belongs to it.

### Correction and prevention

For records whose `ExpectedReceived` is wrong or negative, Aware requires Cancel + new Paid
(correction method 2). Do not issue correction files before the scope, per-item target set, and
approval are complete. Forward prevention requires item-period-grain de-fanout and the two
validation rules above; SQL changes are owned by Claude Code and are not authorized by this entry.

### Scope warning

The 559/71 symptom populations are **⚠️ SUPERSEDED — DO NOT CITE**. D16 showed they were computed
from an output symptom rather than a confirmed cause. Keep four tracks separate:
INCIDENT-002a (263-class CMI identifier), INCIDENT-002b (244 credit-shell double-deduction
candidates), the 224 unexplained orders, and the onetime M1/V1 split finding.
