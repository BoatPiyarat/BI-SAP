# 00_AI_BOOTSTRAP.md
Version: 2.0 (restructured 2026-07-16)
วิธีใช้: ไฟล์ชุด Hot tier (00/10/20/30/90) คือ Project Knowledge ที่ AI ต้องอ่านทุกแชท
Cold tier เก็บใน Drive/GitHub — upload เฉพาะเมื่อทำงานเรื่องนั้นโดยตรง

---

## Hot tier (โหลดทุกแชท)

| ไฟล์ | เนื้อหา | Update policy |
|---|---|---|
| 00_AI_BOOTSTRAP.md | สารบัญ + กติกา | แก้เมื่อโครงสร้างเปลี่ยน |
| 10_SAP_CONTEXT.md | Business rules, architecture, design principles ที่ "จริงจนกว่าจะแก้ตั้งใจ" | แก้เฉพาะเมื่อ rule เปลี่ยนจริง พร้อมลง CHANGELOG |
| 20_SAP_PROGRESS.md | สถานะปัจจุบัน + open items | **Overwrite ได้** อัปเดตท้ายทุก session |
| 30_SAP_CHANGELOG.md | ประวัติการตัดสินใจ | **Append-only** — entry ใหม่บนสุด ห้ามลบของเก่า |
| 90_TEAM_CONTEXT.md | คน, working preferences, AI governance (ไม่ผูกกับ SAP) | แก้เมื่อทีม/นโยบายเปลี่ยน |

## Cold tier (reference — upload ตามงาน)

| ไฟล์ | ใช้เมื่อ |
|---|---|
| SAP_Data_Dictionary_Confluence.md | ทำงานกับ schema 56 คอลัมน์ / triage SAP error |
| SAP_VALIDATION_LIBRARY.md | เขียน/รัน consistency check |
| SAP_INCIDENT_LOG.md | investigate incident ใหม่ (ดู pattern เดิม) |
| PHASE6_DEPLOY.md, SAP_NETWORK_SETUP_GUIDE.md | deploy/แก้ infra |
| SAP_Global_Standard_v2.1_Layer6_Addendum.md | ออกแบบ Layer 6 (recon/monitoring) |
| SAP_PIPELINE_REDESIGN.md | อ้างอิงเหตุผล design (ส่วนใหญ่ merge เข้า 10_CONTEXT แล้ว) |
| draw.io diagrams | ปรับ architecture |

## กติกาสำคัญ

1. **ห้ามใส่ credential/PII ในไฟล์ใดๆ** — ใช้ placeholder + อ้างอิง Secret Manager
2. จบ session ที่มีข้อสรุป → อัปเดต 20_PROGRESS (overwrite) + 30_CHANGELOG (append) ทันที
3. ถ้าไฟล์ hot ขัดกับไฟล์ cold → hot ชนะ (ใหม่กว่า) แล้วไปแก้ cold ตาม
4. ข้อมูลที่ยังไม่ยืนยัน ให้ tag `⚠️ PROVISIONAL` หรือ `⏳ PENDING` เสมอ — AI ห้าม treat เป็นข้อเท็จจริง

## ไฟล์เก่า → ใหม่ (mapping สำหรับ archive)

- RabbitCare_BI_Claude_Team_Context_1.md → แตกเข้า 10/20/90 (archive ได้)
- SAP_CONTEXT.md (v2.1 เดิม) → 10_SAP_CONTEXT.md (แก้ RCL rule แล้ว)
- SAP_PROGRESS.md (07-05) → 20_SAP_PROGRESS.md (archive ของเดิม)
- SAP_CHANGELOG.md + SAP_CHANGELOG_2026-07-05-network.md → merge เป็น 30_SAP_CHANGELOG.md
- AI_BOOTSTRAP.md เดิม → ไฟล์นี้
