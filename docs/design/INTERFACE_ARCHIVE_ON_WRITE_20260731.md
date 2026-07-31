# Interface archive-on-write — design only

Status: proposed; do not deploy or write `gs://interface-file`.

SAP removes interface objects after pickup; the bucket retains only placeholders. D3 therefore
cannot prove the exact bytes SAP consumed.

## Write sequence

1. Serialize once; archive and delivery must use identical bytes.
2. Compute SHA-256, size, row count, header/column count, contract version, BU, process, run ID,
   BatchRunDate, and source query/job ID.
3. Write to a restricted archive with `ifGenerationMatch=0` to prevent overwrite.
4. Read metadata back and verify hash/size.
5. Copy that verified generation to `gs://interface-file/<BU>/`.
6. Persist a sanitized manifest and mark delivery ready only after both writes succeed.

Archive failure fails closed: no SAP delivery without evidence. Fail-closed is valid only when the
same failure sends a sanitized alert to a confirmed on-call human. A log entry or an email sent
only to `data@rabbit.co.th` is insufficient because that mailbox does not reach Boat directly.
Before deployment, Boat must choose and test delivery to `piyaratt@rabbit.co.th`, Slack, or an
explicitly confirmed forward/on-call route. Alert content must not contain CSV rows, PII, raw SAP
messages, credentials, or signed URLs.

Proposed logical path:
`gs://<restricted-archive>/sap-interface/YYYY/MM/DD/<run_id>/<BU>/<original_file_name>`.

CSV contains PII and financial data. Use restricted uniform bucket access, encryption and retention
chosen by Boat/security, and access logging. Never commit file content or signed URLs. Do not invent
expiration while this is the only file-level audit evidence; evaluate retention policy/object lock.

Monitor archive write, delivery write, SAP pickup, and SAP import separately. Function status is
not export success. Reconciliation links manifest SHA/run ID → filename → LogID → sanitized result.
An archive alert is the required counterpart to fail-closed delivery; without it, archive failure
would become the fourth silent outer-status failure pattern after function status, healthy-vs-login
`rows=0`, and HTTP 503 after a committed BigQuery LOAD.
