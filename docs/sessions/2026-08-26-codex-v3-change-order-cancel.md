# 2026-08-26 — V3 linked change-order cancellation production preparation

- Exact snapshot `eac9c70` passed Class-A Standards and Spec review.
- Deployment job: `bqjob_r410a880b72c452e5_000001a03edcd5f2_1`.
- Hold build job: `bqjob_r2dc4ea3a8ae00c41_000001a03eddd42c_1` for ownership run
  `V3NIGHTLY-2026-08-26T13:23:38-e830fff2-CANCEL-HOLD`.
- Read-only reconciliation after the build: 27,878 input items, 27,878 classified items, 70,860
  prepared 56-column payload rows, and zero interface rows.
- Holds: 6 items / 6 rows await Aware/FA approval; 27,344 / 70,396 have invalid predecessor
  status; 270 / 0 are absent from the mirror; 211 / 346 fail required-value validation; 35 / 61
  have invalid spines; 11 / 41 lack a Paid first period; 1 / 10 requires a separate Paid transition.
- Gate is `HOLD_ONLY_ZERO_INTERFACE_ROWS`. No scheduler, archive/delivery ledger, SAP component,
  GCS object, pickup, import, or ACK state changed.
