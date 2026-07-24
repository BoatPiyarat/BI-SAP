# SAP Pipeline Monitoring Dashboard — Design v1
Date: 2026-07-23 | Tool: Looker Studio (ต่อ BigQuery ตรง) | Refresh: 15 นาที
Audience: BI (ทุกหน้า) + FA/K.Paul (หน้า 1–2 พอ)

หลักออกแบบ: ทุกตัวเลขบน dashboard ต้อง**คลิกแล้วได้ list รายตัว** (drill to order_item) — ไม่มีตัวเลขลอย
Source ทั้งหมด = ตารางระบบที่ pipeline เขียนเองอยู่แล้ว (pipeline_run_log, recon, validation_error, sap_import_result, export_archive) → **ไม่มี query เพิ่มต้นทุนพิเศษ**

---

## Page 1 — Pipeline Status (คำถาม: เมื่อคืน/ตอนนี้ ระบบวิ่งไหม)

| Widget | นิยาม | เขียว/เหลือง/แดง |
|---|---|---|
| Run ล่าสุด (scorecard ใหญ่) | สถานะ run NIGHTLY ล่าสุด + เวลาจบ | SUCCESS / PARTIAL / FAILED-ไม่มี run |
| Step timeline (Gantt แนวนอน) | ทุก step ของ run ล่าสุด: เวลาเริ่ม-จบ-วินาที | step ไหนแดง = จุด debug (ลิงก์ RUNBOOK §3) |
| Step duration trend (line, 14 วัน) | วินาทีต่อ step ต่อวัน | จับ degrade ก่อนพัง (extract ช้าขึ้นเรื่อยๆ ฯลฯ) |
| ADHOC runs วันนี้ (table) | run_type='ADHOC': ใครยิง กี่ order ผลอะไร | — |
| Dead man's switch | มี run หลัง 20:30 วันนี้ไหม (หลัง 22:00) | แดง = ไม่มี → alert ซ้ำทาง email แล้ว |

## Page 2 — Completeness (คำถาม: เงินเข้าทุกบาทไปถึง SAP ไหม) ★ หน้าที่ FA ดู

นิยามหลัก (จาก recon): ทุกแถว `stg_payment_events` ต้องมีปลายทาง

| Widget | นิยาม |
|---|---|
| Funnel วันนี้ | charges SUCCESSFUL → routed → validated → exported → **acked in SAP** (5 แท่ง เห็นรั่วตรงไหนทันที) |
| Recon status (donut + table) | OK / PENDING_ACK (≤D+2) / **MISSING (>D+2)** / STATUS_CONFLICT / PAID_AFTER_CANCEL / UNROUTED |
| MISSING aging (bar) | อายุของ missing: 3-5 วัน / 5-10 / >10 — เป้า: แท่ง >10 = 0 |
| Backlog by flow (stacked) | missing แยก ONETIME/EDC/RCL/CMI/CS — จับ gap เชิงระบบรายประเภท (แบบเคส EDC จะโผล่ที่นี่เองตั้งแต่วันแรก) |
| Cancel sync | CareOS cancelled แต่ SAP ยัง active: จำนวน + aging |
| KPI: Completeness % | acked / expected (rolling 7 วัน, ตัด PENDING_ACK ออกจากตัวหาร) — เป้า ≥ 99.5% |

## Page 3 — Correctness (คำถาม: ที่ส่งไป ถูกไหม)

| Widget | นิยาม |
|---|---|
| Validation errors by rule (bar, 14 วัน) | V1–V6 จาก sap_validation_error — spike ของ rule ไหน = bug เพิ่งเกิด/ข้อมูลต้นทางเปลี่ยน |
| SAP import errors by type (bar, 14 วัน) | จาก sap_import_result: duplicated / InvoiceNo / sequence / not balance / status — **เป้าหลัง v3 = เส้นดิ่งลงเหลือ ~0** (ตัวพิสูจน์ redesign ต่อ K.Paul) |
| Error rate ต่อไฟล์ | error rows / total rows ต่อ export file |
| Invoice conflict watch | item ที่ invoice ในไฟล์ ≠ stg_sap_state (ควรเป็น 0 หลัง UDF) |
| Money spot-check | Σ TotalAmount exported ต่อวัน เทียบ Σ expected — diff ≠ 0 = สูตรเงินเพี้ยน |

## Page 4 — Freshness (คำถาม: ข้อมูลที่ใช้ตัดสินใจ สดแค่ไหน)

| Widget | นิยาม | Threshold |
|---|---|---|
| SAP truth age | NOW − MAX(extracted_at) ของ raw_sap_live | เขียว <26 ชม. / แดง >30 ชม. |
| Watermark lag ต่อ staging | NOW − watermark (order_dim / events / schedule) | <26 ชม. |
| Export → Ack lag | เวลาเฉลี่ย exported → acked (rolling 7 วัน) | เป้า ≤ D+1 |
| Extract volume trend | rows_extracted ต่อคืน 30 วัน | ดิ่งผิดปกติ = E2 ใน runbook |

## Alerts (นอก dashboard — ถึงคนโดยไม่ต้องเปิดดู)

| เงื่อนไข | ช่องทาง | ไปที่ |
|---|---|---|
| Workflow step FAILED | Slack (BI channel) ทันที | RUNBOOK §3 |
| ไม่มี NIGHTLY run ภายใน 22:00 | Slack + email | W0 |
| MISSING >D+2 เพิ่มขึ้น > X รายการ/วัน | Slack รายวัน 08:30 | F1 |
| Import error type ใหม่ที่ไม่เคยเห็น | Slack | เปิด incident |

## Implementation notes

- View ชั้นบางๆ ต่อ widget (`vw_dash_*`) — Looker ไม่ query ตารางใหญ่ตรง, ทุก view กรอง partition ล่าสุด → ต้นทุน query ต่ำ
- สิทธิ์: FA เห็น Page 1–2 (link แยก), BI เห็นครบ
- Phase: Page 1+4 สร้างได้ตั้งแต่ P0 (มี run_log + extract แล้ว), Page 2 ต้องรอ recon (P0-lite), Page 3 ครบที่ P2
