# V3 Unit 3 deployment and release gate — 2026-08-02

Run: `V3NIGHTLY-2026-08-02T09:02:26-b36e1712`.

- 052 deploy: `bqjob_r37991330ed53c828_0000019fc2b5acd2_1`; corrected redeploys
  `bqjob_r6727473a21d76b5b_0000019fc2b9dc9c_1` and
  `bqjob_r6c00c7cf4cd150e2_0000019fc2bc1d93_1`.
- 055 deploy: `bqjob_r2bd553d9f34dcffe_0000019fc2b630ff_1`.
- 054 deploy: `bqjob_r75e5a779fcb528fc_0000019fc2b67cae_1`.
- 056 seed: `bqjob_r71608841d64caffc_0000019fc2b73391_1`, four Health/Life rows.
- Three-step CALL: `bqjob_r5f623e09c7c0f71a_0000019fc2bc8d81_1`, successful.
- Verification: `bqjob_r172e9bda44a7fbf6_0000019fc2be2f29_1`, 74,034 bytes.

Actual result: 1,185 READY events, 1,185 held, 0 releasable. All holds are
`HOLD_PAYMENT_MAPPING`. UNKNOWN notification rows = 14; mapping-held events = 1,185; notification
detail rows = 1,199. Every release-gate blocker count is zero. Unit 5 file construction remains
blocked because there is no approved payment mapping; generating an empty file or bypassing the
registry would violate the closed-mapping rule.

Two late-bound failures occurred before the successful CALL and wrote no holds: ambiguous USING
join (`bqjob_r4723eed31cc365fb_0000019fc2b90c72_1`) and source/live staging drift
(`bqjob_r3aa5259308a4702b_0000019fc2ba3f1c_1`). The final procedure reads the required raw mapping
fields at their CareOS source grain, avoiding a false backfill of existing staging rows.

