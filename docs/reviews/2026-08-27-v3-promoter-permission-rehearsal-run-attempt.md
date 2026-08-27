# V3 promoter permission-rehearsal run attempt

Date: 2026-08-27 18:43 ICT

Runner commit: `d00ba13`

Lower bound: `2026-08-27T11:43:26.2324809Z`

## Result

**REJECTED BEFORE EXECUTION CREATION.** The runner constructed the intended JSON but Windows
PowerShell's native-command argument handoff removed the embedded key quotes. `gcloud workflows
run` returned:

```text
INVALID_ARGUMENT: input json string is in incorrect format:
JSON parse error at offset 1: invalid character 'p' looking for beginning of object key string
```

The command returned exit code 1 and produced no Workflow execution name.

## Production state proof

- Latest execution census after the failed attempt still has newest execution
  `3fe07607-15d4-4a29-b2a3-ba5d2ce65e6c`, started
  `2026-08-26T13:23:38.406612757Z`; therefore there is no execution at or after the rehearsal lower
  bound.
- Canonical Scheduler remains PAUSED at `30 20 * * *` / `Asia/Bangkok`.
- No promoter request was made because Workflow execution creation failed at CLI input validation.

## Retry gate

Do not retry until the installed CLI's supported `--flags-file` mechanism is encoded as a fixed
operator input, reviewed on both Class-A axes, and committed. The retry must remain a single exact
execution with delivery false and Scheduler PAUSED.
