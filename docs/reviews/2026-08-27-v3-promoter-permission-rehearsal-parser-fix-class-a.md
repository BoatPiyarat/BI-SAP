# Class-A review — V3 promoter permission-rehearsal parser fix

Date: 2026-08-27

Fixed point: `0990965`

Scope:

- `infra/v3_nightly_orchestrator.workflows.yaml`
- `scripts/check_v3_promoter_permission_rehearsal.py`

## Reproduction and fix

The managed deploy operation rejected the exact source at `main.yaml:94:53`, with its caret on the
nested empty-map literal in:

```text
${json.encode_to_string(default(map.get(e, "body"), {}))}
```

A regression assertion requiring the parser-safe expression was added first and observed RED. The
only runtime-source change replaces the missing-body default `{}` with `""`; the same checker then
returned `PROMOTER_PERMISSION_REHEARSAL_STATIC=PASS`.

## Standards / safety — PASS

The correction is minimal, deterministic, and locked to the exact exception-body normalization
assignment. It does not add a call, side effect, success path, or fallthrough. The existing checker
continues to require the single authenticated POST, exact audience/body, exact 400 plus validator
text, both failure raises, branch ordering, delivery false, and recursive one-call census.

## Spec — PASS

Missing exception body now encodes as an empty JSON string rather than an empty JSON object. Neither
can match `missing required field: archive_bucket`; an expected promoter 400 body still encodes and
matches. Therefore only the required 400 validator rejection is accepted and every other outcome
raises. Default-false normal execution semantics are unchanged.

## Live-state nuance

After the rejected deploy, the Workflow remains revision `000010-daf`, ACTIVE, and Scheduler remains
PAUSED at 20:30 ICT. The resource `updateTime` advanced to `2026-08-27T11:36:20.161870900Z`; therefore
the evidence claims no new revision or execution, not zero control-plane metadata change.

## Final verdict

**PASS.** Safe to commit and retry the delivery-disabled Workflow deployment. Do not execute the
permission rehearsal until the successful deployment has its own reviewed and committed evidence.
