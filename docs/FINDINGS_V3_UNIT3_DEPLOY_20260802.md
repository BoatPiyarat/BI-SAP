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

After Boat clarified that Pending has no payment mapping and confirmed reuse of existing payment
semantics, 057 seeded 12 non-credit V2 mappings (`bqjob_r3b616eb0badb2256_0000019fc2d7b990_1`).
SAP evidence refresh `bqjob_r3b81d5d95da429ab_0000019fc2d5d906_1` processed 616,047,307 bytes;
READY inventory `bqjob_r6b76d06b5b40be9b_0000019fc2d69e7d_1` processed 209,541,536 bytes.
The rerun `bqjob_r5ef5a2bfeab12b59_0000019fc2d81cd1_1` produced 753 releasable and 432 held
events. UNKNOWN remains 14; notification detail is 446 rows. Verification
`bqjob_r37153dd27598434c_0000019fc2d9407b_1` processed 27,348 bytes and every gate blocker is zero.

Two late-bound failures occurred before the successful CALL and wrote no holds: ambiguous USING
join (`bqjob_r4723eed31cc365fb_0000019fc2b90c72_1`) and source/live staging drift
(`bqjob_r3aa5259308a4702b_0000019fc2ba3f1c_1`). The final procedure reads the required raw mapping
fields at their CareOS source grain, avoiding a false backfill of existing staging rows.
