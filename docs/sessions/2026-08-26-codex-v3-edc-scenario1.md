# 2026-08-26 — Scenario 1 EDC hold-only production split

- Source snapshot `547e72b` passed Class-A Standards and Spec review, but its first production call
  failed before publication because live `stg_payment_events` has no payment method/channel fields.
- Corrected exact snapshot `54d669b` sources method/channel from `careos.carepay_charges`, holds
  missing/duplicate/NULL raw evidence, dry-ran at 0 bytes, and passed Class-A Standards and Spec.
- Initial deployment job: `bqjob_r3ad858105b6ddc96_000001a03ec9fd81_1`.
- Failed pre-publication call: `bqjob_r25bf4202ad1bdc6a_000001a03eca87c6_1`; no summary/detail rows
  were written.
- Corrected deployment job: `bqjob_r2b2a0ef1a972c86b_000001a03ecc020f_1`.
- Successful hold build: `bqjob_r6b892b9ca97dabd8_000001a03ecc24ab_1` for
  `V3NIGHTLY-2026-08-26T13:23:38-e830fff2`.
- Reconciliation source: `v3_edc_onetime_event_summary` and `v3_edc_onetime_event_hold`, queried
  2026-08-26 after the successful build. Results: 5,067 events, 5,067 classified, 1,550 already
  acknowledged, 90 unapproved bank/method, 0 structurally ready KBANK release rows, 0 interface.
- Gate remains `HOLD_ONLY_ZERO_INTERFACE_ROWS`; no scheduler, delivery ledger, or GCS object changed.
- Human run/report SQL is in `sql/operator/20260826_run_v3_edc_onetime_holds.sql` and
  `sql/operator/20260826_report_v3_edc_onetime_holds.sql`.
