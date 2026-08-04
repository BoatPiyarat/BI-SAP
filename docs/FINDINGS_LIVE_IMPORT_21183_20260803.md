# LIVE import result — Upload LogID 21183 (2026-08-03)

Status: CONFIRMED SUCCESS; production evidence retained without raw email or PII.

## Header

- Environment: `RCB_LIVE_DB`
- Status: `success`
- ImportType: `INSURANCE_RCB`
- Upload LogID: `21183`
- File: `RCB_MOTOR_INSURANCE_RCB_06_V3_DAILY_NEWPAYMENT_20260803_V3DAILY-20260803-113257-55042e7c_000000000000.csv`
- Email timestamp: `2026-08-03T19:45:16+07:00`
- Gmail message ID: `19fc7a839d5dbe3a`

Mailbox scope was exactly label `notification SAP upload`, sender
`rcare_sap_b1@rabbitcare.com`, last one hour, and body marker `RCB_LIVE_DB`. One message matched.
UAT2/`RCB_ISSUE_DB` was excluded.

## Attachment evidence

The supplied TXT attachment reports success and contains these non-PII SAP references:

- `RCL-JE-InstallmentRCL`: `260810010`
- `RCL-JE-InstallmentRCL`: `260810011`
- `RCL_BPInstallment-RecconNo`: `99337`

This is stronger than delivery or pickup evidence: SAP returned a terminal import result with
accounting references. Row-level reconciliation against the refreshed SAP mirror remains a
separate step; the outer email status does not replace that check.

Raw email/attachment content remains outside the repository. No Gmail label was changed.

## Post-import mirror reconciliation — 2026-08-04

Boat confirmed the SAP-interface filename is a delivery-time rename of archive run
`V3DAILY-20260803-113257-55042e7c`, whose original archive basename begins `INSURANCE_RCB_`.
The supplied TXT log has no row count. A post-import extract/load/mirror refresh followed by a
read-only exact-identity check found 558 delivered archive identities, all 558 present in
`sap_mirror_state` with `TransactionStatus='Paid'`, and zero missing. The query estimated
73,208,397 bytes; evidence recorded 2026-08-04T21:03:24+07:00. This proves the refreshed SAP-mirror outcome for the delivered identities; it
does not replace the future persisted attachment-detail/ACK ingestion requirement.
