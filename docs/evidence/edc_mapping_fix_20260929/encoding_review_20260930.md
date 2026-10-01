# Encoding-preservation delta — independent review

**PASS** for the narrow four-file delta from a96039b (two candidate views and their rollbacks). Existing final deployment review otherwise remains applicable.

Checked git diff, authoritative views_verified.json, current source_hashes.json, and encoding_validation.json. Motor change differs only in comment em dash. vw_onetime_payload_source restores comments and four Title string literals verbatim from live API metadata; mapping logic, amount/date/InvoiceNo expressions are unchanged by this delta. Both rollback bodies match authoritative live definitions. All 20 current source hashes independently recomputed and match. Targeted nonmapping comparison reports zero changed groups at 2026-09-30 07:37:12 UTC.

Specific limitation: authoritative live Title literals themselves contain mojibake. This change preserves existing live output; it does not repair or certify Thai text quality. Do not describe it as a Thai-title correction. Prior limit remains: procedure definitions/source and gate fixtures reviewed, not full procedure branch execution. No reviewer BQ queries or production mutation.
