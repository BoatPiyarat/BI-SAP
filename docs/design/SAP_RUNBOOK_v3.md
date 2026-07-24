# SAP Pipeline Runbook v3 — Debug / Manual Run / Urgent Request
Date: 2026-07-23 | Audience: ทีม BI ทุกคน (ไม่ต้องรู้ประวัติโปรเจกต์ก็ทำตามได้)
หลัก: ทุกอย่างในนี้ทำได้โดยไม่ต้องแก้ code — ผ่าน parameter + คำสั่งสำเร็จรูป

---

## 1. เช้านี้เช็คอะไร: "เมื่อคืนวิ่งครบไหม" (2 นาที)

```sql
-- Q1: สถานะทุก step ของ run ล่าสุด
SELECT step, status, rows_in, rows_out, started_at, ended_at,
       TIMESTAMP_DIFF(ended_at, started_at, SECOND) AS sec, error_message
FROM `sap_integration_v3.pipeline_run_log`
WHERE run_id = (SELECT MAX(run_id) FROM `sap_integration_v3.pipeline_run_log`
                WHERE run_type = 'NIGHTLY')
ORDER BY started_at;
```
อ่านผล: ทุก step `SUCCESS` = จบ | step ไหน `FAILED` = ไปตาราง §3 | **ไม่มีแถวของเมื่อคืนเลย** = workflow ไม่ถูกยิง → §3 กรณี W0

เสริม: หน้า Pipeline Status บน dashboard แสดงตารางเดียวกันนี้แบบไฟเขียว/แดง

## 2. Manual run ทีละจุด (เมื่อรู้แล้วว่าพังตรงไหน)

ทุก step รันซ้ำได้ปลอดภัย (idempotent — MERGE/REPLACE ทั้งหมด) ตามลำดับนี้เท่านั้น:

| # | Step | คำสั่ง (Cloud Shell / BQ console) |
|---|---|---|
| 1 | Extract (SAP→BQ) | `gcloud run jobs execute sap-extract-job --region=asia-southeast1 --wait` |
| 2 | SAP state | `CALL sap_integration_v3.sp_refresh_sap_state('FULL');` |
| 3 | Recon | `CALL sap_integration_v3.sp_run_recon('FULL');` |
| 4 | Staging (dim/events/schedule) | `CALL sap_integration_v3.sp_refresh_order_dim('FULL'); CALL ...payment_events('FULL'); CALL ...schedule('FULL');` |
| 5 | Engine | `CALL sap_integration_v3.sp_build_expected_state('FULL');` |
| 6 | Validate | `CALL sap_integration_v3.sp_validate('FULL');` → เช็ค `SELECT rule, COUNT(*) FROM sap_validation_error WHERE run_id=@run GROUP BY rule` |
| 7 | Export | `CALL sap_integration_v3.sp_export_delta('FULL');` |
| ทั้งเส้น | Workflow เต็ม | `gcloud workflows execute wf-sap-pipeline --location=asia-southeast1` |

กติกาความปลอดภัย:
- ห้ามข้าม step 6 ไป 7 เด็ดขาด (validation คือกันชนเดียวก่อนไฟล์ถึง SAP)
- รัน step กลางใหม่ → ต้องรัน step ถัดจากนั้นให้จบเส้นเสมอ (5→6→7)
- Export ซ้ำวันเดียวกัน: sp_export_delta เช็ค export_archive ก่อน — แถวที่ export แล้วไม่ออกซ้ำ (ไฟล์ใหม่มีเฉพาะส่วนเพิ่ม)

## 3. ตารางอาการ → วินิจฉัย → แก้

| อาการ | วินิจฉัย (query/คำสั่ง) | ทางแก้ |
|---|---|---|
| **W0** ไม่มี run เมื่อคืนเลย | `gcloud workflows executions list wf-sap-pipeline --limit=3` + เช็ค scheduler `gcloud scheduler jobs describe sap-pipeline-trigger` | ยิง manual ทั้งเส้น (§2 แถวสุดท้าย); ถ้า scheduler PAUSED → resume |
| **E1** Extract FAILED: connection/login | ดู log job: `gcloud logging read 'resource.labels.job_name="sap-extract-job"' --limit=50 --freshness=1d` — หา pyodbc error | VPN/WireGuard ล่ม → เช็ค VM `sap-wireguard-gateway` (restart ได้); login fail → password rotate ไม่ sync → เทียบ Secret Manager กับ SQL Server |
| **E2** Extract SUCCESS แต่ rows_extracted = 0 ผิดปกติ | `SELECT * FROM sap_extract_control ORDER BY run_timestamp DESC LIMIT 3` — watermark กระโดดไหม | ถ้า watermark ผิด: `UPDATE sap_extract_control` ถอย watermark แล้วรัน extract ใหม่ (idempotent, MERGE by DocEntry) |
| **V-fail** step validate มี BLOCK จำนวนมาก | `SELECT rule, detail, COUNT(*) FROM sap_validation_error WHERE run_id=@run GROUP BY 1,2 ORDER BY 3 DESC` | แก้ตาม rule; item ที่ fail ไม่ถูก export (ที่เหลือไปต่อปกติ) — ไม่ต้องหยุดทั้งระบบ |
| **X1** ไฟล์ไม่โผล่ใน gs://interface-file | `SELECT * FROM pipeline_run_log WHERE step='export'` + `gsutil ls -l gs://interface-file/<BU>/ | tail` | ถ้า sp สำเร็จแต่ไฟล์ไม่มี = สิทธิ์ GCS → เช็ค SA ของ BQ EXPORT DATA |
| **S1** SAP import error กลับมา (log จาก Aware) | upload log เข้า `sap_import_result` แล้ว `SELECT error_type, COUNT(*) ... GROUP BY 1` | duplicated = แถวเคยเข้าแล้ว (ตรวจ recon ว่าทำไม delta ไม่กัน); InvoiceNo = เทียบ `stg_sap_state.sap_invoice_no` กับไฟล์; sequence = เช็ค V2 ว่าหลุดได้ไง — ทุกเคสเปิด incident ลง INCIDENT_LOG |
| **F1** Recon MISSING ค้าง > D+2 | `SELECT * FROM recon_careos_interface WHERE status='MISSING' AND age_days>2` | ดูว่า item ติด validation (→แก้ข้อมูล) หรือ export แล้ว SAP ไม่รับ (→ดู sap_import_result) |
| **D1** Dashboard freshness แดง (sap_state เก่า) | เทียบ `MAX(extracted_at)` ใน raw_sap_live กับตอนนี้ | = extract ไม่วิ่ง → E1/W0 |

## 4. Urgent Request ระหว่างวัน (FA ส่ง list มา ไม่รอ 20:30)

**ADHOC mode** — เส้นเดียวกับ nightly ทุกประการ (validation ครบ, delta กัน duplicate) แค่ scope แคบ + รันเดี๋ยวนั้น:

```bash
# ทางลัด 1 คำสั่ง (workflow รับ argument)
gcloud workflows execute wf-sap-pipeline --location=asia-southeast1 \
  --data='{"mode":"ADHOC","orders":"L80123456,L80234567,L80345678","refresh_sap":true}'
```
ภายใน workflow เมื่อ mode=ADHOC:
1. (option `refresh_sap:true`) รัน extract ก่อน → sap_state สดที่สุด ณ นาทีนั้น — ใช้เมื่อสงสัยว่า SAP เพิ่งเปลี่ยน; ถ้าไม่จำเป็นให้ false (เร็วกว่า ~10 นาที)
2. ทุก sp รันด้วย `run_scope='ADHOC:<orders>'` — process เฉพาะ order ใน list (BigQuery scan จิ๋ว)
3. Export ออกไฟล์ชื่อ `<YYYYMMDD_HHMM>_adhoc_01_create.csv` / `_02_cancel.csv` → SAP pull รอบชั่วโมงถัดไปเก็บเอง
4. แถวที่ export ลง archive ด้วย run_type='ADHOC' → รอบ nightly คืนนั้น**ไม่ส่งซ้ำ**อัตโนมัติ

SLA ที่บอก FA ได้: ส่ง list → ไฟล์พร้อมใน **<15 นาที** (ไม่ refresh SAP) หรือ **<30 นาที** (refresh) → เข้า SAP ใน pull รอบถัดไป

ข้อห้าม ADHOC:
- ห้ามใช้ bypass validation — ถ้า item ติด V-rule แปลว่าข้อมูลมีปัญหาจริง แจ้งกลับ FA พร้อม reason จาก `sap_validation_error` (มี template ใน §5)
- Cancel ที่มีเงินจ่ายหลัง CareOS cancel (recon flag `PAID_AFTER_CANCEL`) → ต้องได้ confirm intent จาก FA ก่อนทุกครั้ง

## 5. Template ตอบ FA (กรณี item ติด validation)

> รายการที่ขอ นำเข้าได้ N รายการ (ไฟล์เข้า SAP รอบ HH:00)
> ติดตรวจสอบ M รายการ ตามเหตุผลนี้ — รบกวนยืนยัน/แก้ข้อมูลก่อนนำเข้า:
> - Lxxxxxxx: ไม่มีรายการชำระเงินสำเร็จในระบบ
> - Lxxxxxxx: ยอด TotalAmount ไม่ balance (ต่าง x.xx)
> - Lxxxxxxx: มีการชำระเงินต่อหลังยกเลิก — ยืนยัน intent (cancel+refund?)

## 6. Escalation & ownership

| เรื่อง | ติดต่อ |
|---|---|
| WireGuard/tunnel, SAP hourly pull, import program | Aware (vendor) |
| GCP IAM/secret/infra | Attila — **devops-tribe** หรือ DM (ไม่ใช่ infra-tribe) |
| Business rule เงิน/บัญชี, intent cancel | FA (K.Bell team) |
| Cutoff calendar รายเดือน | Finance confirm → อัปเดต `sap_accounting_cutoff_dates` |
| Code/pipeline ทั้งหมด | BI (Boat) |

## 7. หลังแก้ทุกครั้ง (discipline)

1. ลง `30_SAP_CHANGELOG.md` (append-only) — เกิดอะไร แก้ยังไง
2. เคสใหม่ที่ runbook ไม่มี → เพิ่มแถวในตาราง §3 ทันที (เอกสารนี้โตจาก incident จริงเท่านั้น)
3. ถ้า root cause = pipeline bug → เปิด INCIDENT ใน SAP_INCIDENT_LOG ตาม template เดิม
