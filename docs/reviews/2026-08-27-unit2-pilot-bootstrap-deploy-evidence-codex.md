# Unit 2 pilot bootstrap production evidence — 2026-08-27

## Outcome

PASS. The approved one-time Unit 2 magnitude bootstrap completed in production. This action did
not run Units 1–5, enable delivery, change Scheduler/Workflow state, export a file, write GCS, or
send data to SAP.

## Approval and reviewed source

- Config: `UNIT2-PILOT-20260827-V1`
- Baseline: `V3NIGHTLY-2026-08-25T22:21:31-manual`
- Thresholds: records `25 / 0.05`; orders `10 / 0.05`; amount satang `500000 / 0.05`
- Effective window: `2026-08-27T21:51:46+07:00` through `2026-09-01T00:00:00+07:00`
- Approval: Boat; reference `Boat-chat-20260827-UNIT2-PILOT-20260827-V1`
- Reviewed reusable operator source: commit `759a0c2`
- Conservative proposal: commit `e8e7364`; Claude Class-A verdict PASS
- Filled execution artifact and deterministic substitution guard: commit `f3fc55e`
- Committed read-only preflight: commit `5381416`

## Authenticated checks before mutation

- Safe-query wrapper self-test: PASS, 7/7.
- Exact filled execution artifact dry-run: PASS, 0 bytes; no real query executed.
- Production preflight job: `codex_v3_unit2_preflight_20260827_2155`, DONE.
- Preflight result: active configs `0`; matching config IDs `0`; successful archive rows `1`;
  baseline summary rows `14`; magnitude-run rows `0`; distribution rows `0`; result rows `0`.

## Production execution

- BigQuery job: `codex_v3_unit2_bootstrap_20260827_2158`
- Region: `asia-southeast1`
- Terminal state: DONE; no error result.
- Transaction ID: `6a915130-0000-27ad-97fd-d4f547f32d08`
- Bytes processed: `395377826`; bytes billed: `519045120`
- Principal: `user:data@rabbit.co.th`

The procedure and outer operator assertions all passed. The committed effects were:

- magnitude configuration rows inserted: `1`
- baseline distribution cells inserted: `39`
- self-baseline magnitude-result cells inserted: `39`, all with empty breach reasons
- magnitude-run rows inserted: `1`, status PASS, compared cells `39`, breached cells `0`

## Remaining boundary

This PASS authorizes no additional production action. A fresh non-bootstrap Units 1–5 build with
delivery disabled is the next technical step, but it needs its own exact run authorization. Any
resulting threshold breach must hold the run; it must not be overridden merely to make the pilot
green.
