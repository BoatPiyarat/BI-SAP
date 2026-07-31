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

Archive failure fails closed: no SAP delivery without evidence.

Proposed logical path:
`gs://<restricted-archive>/sap-interface/YYYY/MM/DD/<run_id>/<BU>/<original_file_name>`.

CSV contains PII and financial data. Use restricted uniform bucket access, encryption and retention
chosen by Boat/security, and access logging. Never commit file content or signed URLs. Do not invent
expiration while this is the only file-level audit evidence; evaluate retention policy/object lock.

Monitor archive write, delivery write, SAP pickup, and SAP import separately. Function status is
not export success. Reconciliation links manifest SHA/run ID → filename → LogID → sanitized result.
