# SAP workspace map — งาน SAP อยู่ที่ไหน

อัปเดต 2026-10-26 (Piyarat / Boat). เอกสารนี้บอกว่างาน SAP interface แต่ละเรื่องเก็บไว้ที่ไหน และสถานะล่าสุดของแต่ละเรื่อง
ใช้เป็นจุดเริ่มต้นก่อนเปิดไฟล์อื่น

## 1. โฟลเดอร์หลัก

| ที่อยู่ | เก็บอะไร |
|---|---|
| `03 Project - Partner/02 SAP/Phase1.1/agentic_bootstrap/codex_bootstrap` | Git repo หลัก (code, SQL, design, `docs/knowledge`, `docs/FINDINGS_*.md`) เริ่มทุกงานจากที่นี่ |
| `.../agentic_bootstrap/migrated_from_motor_commission_20261026/` | ไฟล์งาน SAP ก.ย.–ต.ค. 2026 ที่เคยวางผิดที่ใน Motor Commission Engine (ย้ายมา 26 ต.ค. 2026) มี evidence JSON/xlsx ที่อาจมีข้อมูลลูกค้า **ห้าม commit/อัปโหลดสาธารณะ** |
| `.../agentic_bootstrap/wt_*`, `codex_*`, `creditshell_review_*` | git worktree ของ branch งานแต่ละเรื่อง (`git worktree list` ดูได้) |
| `.../agentic_bootstrap/handoff_claude_20261001_nonmotor_changeorder/` | Handoff NonMotor change-order 1 ต.ค. |
| Google Drive: SAP interface development / careos-sap-daily-routine | **Master** ของ daily routine CareOS→SAP (แก้ที่ Drive เท่านั้น) https://drive.google.com/drive/folders/1-dVcorTnzcYamGw3cOvzC77NyOgfNqZx |

งาน Motor Commission (คำนวณค่าคอม, payroll) อยู่ที่ `06 Sales/Motor Commission/Motor Commission Engine` แยกจาก SAP แล้ว

## 2. งานที่ย้ายมา (อยู่ใน `migrated_from_motor_commission_20261026/`)

| เรื่อง | Path | สรุป / สถานะ |
|---|---|---|
| SAP Interface v1.1 (CREDIT_CARD_INSTALLMENT) | `sap_interface_v1_1/` | เริ่ม 30 ส.ค. จาก batch SQL ที่สร้างจาก `sap_dashboard_carepay_fully_paid`; มี PROJECT_CONTEXT + validation |
| EDC bank mapping | `outputs/edc_bank_mapping_impact_20260929/`, `edc_kbank_status_20260929/` | เดิม view hardcode `PaymentChannel='RCB-EDC-KBANK'` ทั้งที่ EDC มีหลายธนาคาร; PR #3 |
| EDC mapping fix → **superseded** | `outputs/edc_mapping_fix_20260929/` | ห้ามใช้ข้อเสนอ EDC→Omise ใน workbook เดิม (ดู `SUPERSEDED.txt`) |
| EDC suffix correction (ฉบับที่ใช้จริง) | `outputs/edc_suffix_correction_20260930/` | EDC ยังเป็น EDC เปลี่ยนเฉพาะ bank suffix ตาม CareOS; deploy 15 views + 3 procedures, review PASS WITH NOTES |
| Cancel diagnostic | `outputs/sap_cancel_diagnostic_20260929/FINDINGS.md` | ตรวจรายการ cancel ที่ส่ง SAP (read-only) |
| NonMotor earlier-period gap | `outputs/sap_period_gap_fix_20260929/` | NonMotor payment ถูกข้ามเมื่อ installment หลังจ่ายแล้ว; deploy 29 ก.ย. 14:33 (approval ใน `APPROVAL_20260929.md`) |
| Month-end reconciliation ก.ย. | `sap_monthend_*.py`, `outputs/SAP_reconciliation_20261002_0900/`, `SAP_RECONCILE_CONTINUATION_20261002.txt`, `sap-request-20261001/` | Paid/Pending/Cancel recon ณ 2 ต.ค. 09:00; checkpoint ระบุกติกา BatchRunDate/PaymentDate |
| Receipt identity fix | `SAP_RECEIPT_FIX_READ_ME.txt`, `sap_receipt_guard.py`, `outputs/sap_receipt_identity_fix_20261006/` | InvoiceNo ที่ import สำเร็จแล้ว (เช่น `2_charge`) ต้องคงเดิม; แก้ใน local review generator เท่านั้น |
| Generator fix proposal | `SAP_INTERFACE_GENERATOR_FIX_PROPOSAL_20261006.txt` | ลำดับแก้ generator: eligibility → payment mapping → period spine → amount/date → serialization |
| Request 14 ต.ค. (credit) | `sap_request_20261014_*.py/.sql` | เตรียม/ส่ง credit + scenario records |
| 1–15 ต.ค. delivery + timeout | `outputs/sap_1_15_oct_20261016/` | NonMotor function timeout 60s→300s; อัปโหลด RCL Motor create แล้ว สถานะ `UPLOADED_PENDING_SAP_ACK` **ห้ามส่งซ้ำก่อนเช็ค SAP ack**; `LONG_TERM_FIX.txt` = ข้อเสนอระยะยาว (ยังไม่ deploy) |
| Reliability (NonMotor workers + watchdog) | `outputs/sap_reliability_20261017/DEPLOYMENT_PLAN.txt` | 4 workers + dispatcher + hourly watchdog; เงื่อนไขก่อนเปิดใช้ระบุในแผน |
| SAP updated lists 17 ต.ค. | `outputs/sap_updated_lists_20261017/` | review รายการจาก sheet + `COWORK_DAILY_TASK.txt` (spec daily task ต้นฉบับ) |
| Requests 19/22/23 ต.ค. | `outputs/sap_request_20261019/`, `sap_request_20261022/`, `sap_sheet_request_20261022/`, `sap_request_20261023/`, `sap_check_requested_2026102{1,2}.py` | 4-item recovery 19 ต.ค. (ดู `docs/FINDINGS_FOUR_ITEM_RECOVERY_20261019.md`), change-order 22 ต.ค. (ดู `docs/FINDINGS_CHANGE_ORDER_REQUEST_20261022.md`) |
| Daily routine (mirror) | `outputs/shared_routine/` | สำเนา 18 ต.ค. ของ careos-sap-daily-routine; master อยู่ Google Drive |

## 3. กติกาที่ต้องรู้

- สคริปต์ใน `migrated_from_motor_commission_20261026/` เป็นบันทึกการรันครั้งเดียว บางไฟล์ยังอ้าง path เดิม
  `06 Sales/Motor Commission/Motor Commission Engine/...` ถ้าจะรันซ้ำให้เปลี่ยนเป็น path ใหม่ในโฟลเดอร์นี้ (โครงสร้างย่อยเหมือนเดิม)
- Evidence `.json/.xlsx/.csv` มีเลข order/ใบเสร็จ/ยอดเงิน เก็บใน OneDrive เท่านั้น ไม่ commit (ดู `.gitignore`)
- Live view definition ใน BigQuery คือ source of truth ตรวจ `bq show` ก่อนสรุปทุกครั้ง
- ก่อนส่ง interface ซ้ำ ต้องเช็ค SAP acknowledgement และ receipt ledger
