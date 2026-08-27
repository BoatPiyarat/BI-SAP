# V3 promoter permission-rehearsal workflow deployment attempt

Date: 2026-08-27 18:35 ICT

Source commit: `53f857f`

Intended mutation: deploy the Class-A-PASSed permission-rehearsal source to
`v3-nightly-orchestrator` while keeping delivery disabled and Scheduler paused.

## Result

**REJECTED BEFORE REVISION CREATION.** Operation
`operation-1787830579537-65a05be9ca722-81d0e3fe-3da346f3` failed Workflow parsing at
`main.yaml:94:53`:

```text
parse error: ... mismatched input '{' ...
- rehearsal_error_text: ${json.encode_to_string(default(map.get(e, "body"), {}))}
```

The caret identifies the nested empty-map literal in the expression. The deployment command
returned exit code 1.

## Preserved production controls

- Pre-attempt live revision: `000010-daf`, ACTIVE.
- Pre-attempt service account:
  `919786098205-compute@developer.gserviceaccount.com`.
- Canonical Scheduler: PAUSED at `30 20 * * *` / `Asia/Bangkok`.
- The failed parser operation did not create or activate a new Workflow revision.
- No Workflow execution or delivery was requested by the deployment command.

## Retry gate

Do not retry until the smallest parser-compatible source correction passes the structural checker,
both Class-A axes, and is committed. Re-verify live revision `000010-daf` and Scheduler PAUSED before
the retry.
