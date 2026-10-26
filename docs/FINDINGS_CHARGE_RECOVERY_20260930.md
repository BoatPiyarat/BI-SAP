# 2026 charge-driven SAP recovery — 30 September 2026

177 interface rows across 159 orders were uploaded to production at 23:21:44 ICT. The file carries THB 898,995.29 of ActualReceived. Size and MD5 were verified against the validated local CSV. SAP pickup/import/posting is not yet verified.

## Delivered file

- Bucket: `gs://interface-file/RCB_MOTOR/INSURANCE_RCB_01_CREATE_RECOVERY_20260930_232138.csv`
- GCS generation: `1790785304135095`; bytes: `112142`.
- SHA-256: `6170ceea355b513ca0edfd5850384f4f199ddc080e1eab3a56bfc3c3266bcfa9`.
- MD5/base64: `cWJMcEFA1YnF5Cu90ru6tw==`.
- Source: current `pacific-plating-282708.sap_view.RCB_Motor_process_create`, captured in an immutable local snapshot.
- Independent reviewer: PASS for the exact 177 rows. Fresh SAP/source preflight at 2026-09-30 16:20:28 UTC returned zero blockers. Header/order, 56 columns, CSV round-trip, source allocations and create-only GCS precondition all passed.
- Legacy `paid` status and every business value were retained. Only documented optional EndorsementNo/RefOrder NULLs became empty CSV fields.

The 159 associated source charges total THB 1,651,581.41. This is deliberately an item-level release: held sibling allocations total THB 752,586.12 across 58 invoices. Do not confuse source-charge totals with the file's THB 898,995.29. Source allocations conserve across released and held items.

## Reconciliation and lists

Baseline query timestamp: **2026-09-30 14:46:23.688793 UTC / 21:46:23.688793 ICT**. Source tables are `careos.carepay_charges`, `carepay_transactions`, `careos_orders`, `careos_order_items`, and `sap_integration_v2.SAP_LIVE_FULL`, all in project `pacific-plating-282708`. View checks used ten current `sap_view` payment/create/change routes, with a later targeted recheck. Query job IDs/timestamps are retained in `docs/evidence/charge_recovery_20260930/`.

Scope is effective **charge time in calendar 2026, Asia/Bangkok**, using `COALESCE(payment_date, update_time, create_time)`. Successful future-dated records are quarantined. Release additionally enforces the existing policy/order year restrictions. A 2026 payment on an older policy is visible in reconciliation but does not automatically qualify for export.

The baseline contains **288,635 successful charge IDs**, THB **1,528,048,860.89** at charge-header grain, allocated to **329,902 item/payment obligations**. SAP receipt evidence is invoice-and-status presence, not GL/JE or amount reconciliation.

| Final disposition | Payment obligations |
|---|---:|
| Uploaded; SAP acceptance pending | 177 |
| Current view covers the event, but whole-item validation holds it | 4,115 |
| No verified view coverage / unresolved identity or source exception | 136 |
| Working recovery list | **4,428** |

The working list has **4,121 distinct charges / 4,048 distinct orders** and consists of **4,427 missing-candidate obligations plus one previously known scenario**. It must not be called 4,428 confirmed lost transactions. Forty-eight obligations absent in the initial view snapshots appeared during a later live-view recheck; all were captured and held. Source/view state changed during the session, so the report preserves timestamps rather than pretending all checks share one database snapshot.

Local artifacts, kept outside OneDrive because payloads can contain customer data:

- `C:/dev/sap-recovery-20260930/missing_interface_2026.csv`: complete 4,428-row working list with source charge, invoice, order/item, flow, disposition and reasons.
- `C:/dev/sap-recovery-20260930/remaining_2026.csv`: 4,251 held/unresolved obligations.
- `C:/dev/sap-recovery-20260930/uploaded_2026.csv`: 177 uploaded obligation identities.
- `C:/dev/sap-recovery-20260930/other_source_exceptions_2026.csv`: 52,939 other quarantine/exclusion obligations, separate from the recovery list.
- `C:/dev/sap-recovery-20260930/delivery_manifest.json`: exact file hash, destination, generation and checks.

Charge money repeats across sibling obligation rows. **Never sum `charge_amount_thb` from the obligation CSV without deduplicating by charge_id.** The separate source-quarantine population is not asserted to be an SAP-interface loss.

## Findings and root causes

### Covered but held

The main verified release barriers are incomplete policy numbers and inconsistent legacy RCL status/empty-value formatting. Counts below are nonadditive `(owner view, OrderItem)` validation groups, not charge counts:

| Failed gate | Groups |
|---|---:|
| PolicyNo blank or absent | 3,421 |
| RCL status not exactly Paid/Pending | 3,080 |
| RefundAmountBeforeFee/AfterFee not a valid two-decimal number | 514 each |
| Missing BillingAddress | 407 |
| Lead not PURCHASED | 400 |
| Missing ExpectedDate | 203 |

Other holds include source allocation variance, unknown payment mappings, duplicate events, incomplete required values and change/credit-shell predecessor review. Each item's full reason set is in the CSV. Old carried SAP Paid dates are not confused with newly received payments; the date gate distinguishes carried receipts. Required source values were not invented to force an export.

### The 136 without verified coverage

| Evidence-backed classification | Obligations | Root cause / disposition |
|---|---:|---|
| Lead not PURCHASED | 73 | Source qualification fails. Repair/resolve CareOS lead state or record an explicit exclusion; do not bypass it. |
| Existing SAP period with a different invoice | 38 | Invoice/allocation conflict, not permission to resend. Needs charge-to-SAP-document mapping; never rewrite a stored InvoiceNo. |
| Change-order route | 10 | Ordinary create excludes change-order items; matching payment is upstream but not verified in a valid replacement route. Preserve predecessor/mapping gates. |
| Older RCL receipt outside the rolling window | 8 | Live `sap_integration_v2.RCL 05_paid by period` requires a recent charge/outstanding receipt starting at the first day two months ago. Older missing 2026 receipts can no longer reopen the item. |
| SAP classification changed between reads | 5 | Held as snapshot/state drift. `SAP_LIVE_FULL` currently ranks a DocEntry by UpdateDate alone; missing UpdateTime/tie-breaking is a confirmed structural risk, not yet proven as the cause of every changed classification. |
| FULL_PAYMENT + Rabbit Lending compulsory upstream gap | 1 | Known `L80161278-M1`, THB 645.21 charge. No matching installment dashboard row; ordinary RCL create requires RABBIT_CARE_INSTALLMENT. Needs a narrowly defined CMI adapter, not broad FULL_PAYMENT admission. |
| Upstream event present; owner gate unresolved | 1 | `L80963499-M1`; remains explicitly unresolved, not assigned an invented cause. |

Earlier September first-charge-only/additional-payment and ordinary CMI wrapper bugs cannot simply be repeated as current causes: captured live definitions already contain subsequent changes. This report uses today's definitions.

## Proposed fixes — V2 / sap_view only, not deployed

1. **V2 backlog eligibility:** `sql/production/RCL_05_paid_by_period_2026_backlog_proposal_20260930.sql` is a complete SELECT-only proposal. Replace the two-month eligibility window with Bangkok-local effective charge time in 2026, excluding future timestamps, while preserving invoice-aware terminal checks. Targeted regression at 2026-09-30 16:28:38 UTC admits **4 of 5 affected items**. `L79988680-V1` remains ineligible; an additional blocker remains. This is a partial recovery proposal, not a proven complete fix for all eight obligations. The fixed year makes it a 2026 recovery option, not an evergreen production filter.
2. **sap_view contract:** `sql/production/RCL_Motor_newpayment_contract_proposal_20260930.sql` contains the complete current view SELECT plus position-preserving REPLACE expressions. Normalize known paid/pending case, Pending invoice/payment-date blanks and the documented optional EndorsementNo/RefOrder blanks. Preserve Paid monetary/date values. Unknown statuses remain unchanged and require the separate downstream fail-closed gate. Dry-run **9.190 GiB** passed; population equivalence and deployment readiness are not established.
3. **V2 SAP evidence determinism:** add UpdateTime and a stable content tie-break to DocEntry latest-state selection in `SAP_LIVE_FULL`, retaining its consumer schema. First compare state distributions and capture tied examples; do not overwrite the view from this report alone.
4. **Required source data:** retain an item-level exception ledger for missing PolicyNo, purchaser qualification and invalid numeric/date fields. Correct authoritative CareOS data or approved mappings; do not replace required values with guessed defaults.
5. **CMI/change/identity exceptions:** design explicit event/receipt adapters for the one FULL_PAYMENT CMI case and verified old/new change relationships. Existing invoice conflicts require document proof before recovery.

No V2/sap_view definition was replaced. No V3 DDL, data mutation, procedure call, scheduler change or fix was performed. Existing legacy views' internal dependencies were left unchanged.

## Reusable query

`sql/adhoc/20260930_charge_missing_interface_2026.sql` is the complete runnable BigQuery Standard SQL script. Set `scope_year` near its beginning to reuse it for another year. It creates temporary session tables only and has no explicit V3 dependency. It preserves every source charge, ranks over full history before the year filter, quarantines duplicate/missing invoice identities and unsupported routes, checks the exact receipt's status, recognizes the verified RCL first-period raw/2_ alias, and returns row-wise exceptions plus a conserved header summary.

Run from the SAP repository in PowerShell:

```powershell
& 'C:\Program Files\Git\bin\bash.exe' scripts/bq_safe_query.sh --project pacific-plating-282708 -f sql/adhoc/20260930_charge_missing_interface_2026.sql -- --format=json --max_rows=100000 > C:\dev\sap-charge-reconciliation.json
```

The CLI script result contains temporary-table messages followed by the final row array. The companion read-only capture helper is `scripts/20260930_capture_recovery_candidates.py`; supply an output directory outside OneDrive and a freshly captured `live_columns.json`. `scripts/20260930_validate_recovery.py` records the September-30 snapshot gate and is an audit artifact with fixed run paths/date, not an unattended future export job. Never directly upload discovery-query rows; rerun current-view, source/SAP, schema, whole-item and duplicate-delivery checks.

Queries used `scripts/bq_safe_query.sh`, its 20 GiB billing ceiling and dry-run guard. BigQuery scripts containing temporary-table creation can report a zero-byte dry-run estimate; that is not a zero-cost claim. The query jobs and actual-byte metadata remain the execution evidence.

## Verification and remaining limits

| Work | Built | Verified against live evidence | Still unresolved |
|---|---|---|---|
| Charge reconciliation and CSV lists | Yes | Conserved header/allocation counts; exact receipt matching; independent review | Candidate classification is not SAP-side GL verification |
| 177-row interface delivery | Yes | Immutable gate, fresh zero-blocker source/SAP check, 56-column round-trip, remote size/MD5/generation | SAP pickup/import/JE acceptance |
| V2 backlog proposal | SELECT-only | 4/5 targeted items eligible; dry-run/run evidence | One target and whole-population regression |
| sap_view contract proposal | SELECT-only | Dry-run and independent source review | Full regression/deploy approval |
| Other held/uncovered items | Listed | Reasons and source/view evidence retained | Source repairs, mappings and specified investigations |

Independent review passed the exact upload and the **source-only proposal handoff**. It did not approve deployment of either proposal. Original checkout divergence/unrelated work was preserved; the task is handed off on an isolated branch.

## Git handoff limitation

Local artifact commit: `ea03786c785538ffddd34120644ffa498b8b7bb2`, branch `codex/sap-2026-charge-recovery-20260930` in `C:/dev/sap-recovery-handoff-20260930`. Automatic approval review rejected the attempted push because it would transmit internal artifacts to a remote without explicit publication authorization. A read-only GitHub check confirmed `BoatPiyarat/BI-SAP` is public. No push or PR was created. Publishing requires explicit user approval; this does not affect the completed bucket upload or local deliverables.

User subsequently confirmed: **keep the handoff local**. No Git publication is planned.
