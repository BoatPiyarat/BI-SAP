# Review: H4 Gmail baseline (`71c7afd`)

**Class:** A — stakeholder-facing baseline and operational conclusion
**Reviewer:** Codex
**Verdict:** **BLOCK**

| # | Checklist result |
|---:|---|
| 1 | **BLOCK:** the five-night window is traceable to named Gmail thread IDs and LogIDs, but the table has no `03_CHANGE` or `NONMOTOR 02_CANCEL` observation for 07/22. Their supported result is 4/4 observed nights, not 5/5. |
| 2 | **PASS:** cites Gmail threads/LogIDs and commit `71c7afd`; no BigQuery re-derivation. |
| 3 | N/A — no nullable SQL comparison. |
| 4 | N/A — no SQL ordering logic. |
| 5 | N/A — no interface schema/column change. |
| 6 | **PASS:** grain is calendar night × file type × attempt; retries on 07/26 are explicitly separated. |
| 7 | **PASS:** reports per-file/night status distribution, not only a total. |
| 8 | **BLOCK:** knowledge must not say all three files were wholly rejected 5/5. `04_CREDITSHELL` was whole-file error 4/5 and `success with error` on 07/25, which is partial rather than zero import. |
| 9 | **PASS:** author stayed in session/review artifacts; no SQL or knowledge edit in `71c7afd`. |
| 10 | N/A — no deployment. |
| 11 | N/A — Gmail artifact review; no BigQuery query. |
| 12 | **PASS WITH NOTE:** Gmail-threading error is prominently corrected with provenance. “Never cleanly succeeds” is clear only when defined as “no status exactly `success`; outcomes were `error` or `success with error`.” It must not be restated as “zero rows entered SAP.” |

Specific gap: the baseline supports a severe persistent failure, but not the requested
whole-file-rejection 5/5 wording. Supported statement: across the five-night baseline window,
`03_CHANGE` and `NONMOTOR 02_CANCEL` were whole-file errors on every observed night (4/4; absent
07/22), while `04_CREDITSHELL` was whole-file error 4/5 and partial `success with error` 1/5.

Author response requested once: narrow the queue/session headline to the supported denominators and
define “never cleanly succeeds” as no exact clean-success status.
