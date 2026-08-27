# V3 promoter local test evidence

Recorded: 2026-08-27 12:08 ICT
Source: `infra/sap_delivery_promoter/` at reviewed commit `65bd74a`
Review: `docs/reviews/2026-08-27-65bd74a-promoter-claude.md` — PASS

Pinned dependencies from `requirements.txt` were installed into the unique temporary directory
`C:\Users\Developer\AppData\Local\Temp\v3_promoter_deps_20260827_1208`. No repository or global
Python package was changed.

Command, run from `infra/sap_delivery_promoter/` with that directory as `PYTHONPATH`:

```text
py -3.13 -m unittest -v test_main.py
```

Result: **PASS — 10 tests in 0.099s**. Covered quoted newlines, wrong/duplicate/reordered headers,
invalid UTF-8, malformed quoting, legacy one-name rejection, exact production-name binding,
wrong data-row width, wrong header count, and the two-name success response.

This is source/unit evidence only. No container was built, no Cloud Run service or IAM binding was
created, and no GCS object was read or written.
