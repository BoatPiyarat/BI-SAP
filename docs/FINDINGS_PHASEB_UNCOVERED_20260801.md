# Phase-B uncovered classification — 2026-08-01

Read-only/Class A. This supersedes the earlier 13,659 uncovered count after expected_state changed.

Job `phaseb_uncovered_classification_20260801_223400`, started 2026-08-01 15:33:48 UTC,
duration 25.487s; dry-run/processed 9,090,343,015 bytes, billed 9,091,153,920 bytes, ceiling
21,474,836,480, location `asia-southeast1`.

- Uncovered: 12,689 records / 12,676 order_items.
- 12,395 Paid records / 12,395 items are absent from both 56-column source views.
- 278 Pending ONETIME records have no charge event.
- 16 Pending RCL records / 3 items have the item in a source view but the period is absent.
- Flow/status: ONETIME Paid 12,387; ONETIME Pending 278; RCL Pending 16; RCL_CMI Paid 8.
- The output-date diagnostic sees 12,341 July and 54 August rows in the paid/absent class. This is
  `expected_payment_date`, not an assertion about raw CareOS PaymentDate. The production export
  must independently join raw charge_time and assert August count zero.

Do not synthesize the missing 56-column payload. Re-measure after reviewed Rule-2 qualification
staging is deployed/refreshed; many rows may be correctly excluded rather than exported.
