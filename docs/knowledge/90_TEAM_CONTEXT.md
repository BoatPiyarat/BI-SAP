# 90_TEAM_CONTEXT.md
Version: 1.0 (2026-07-16) — ความรู้ระดับทีม/องค์กร ไม่ผูกกับ SAP project
ใช้ซ้ำได้กับทุกโปรเจกต์ของทีม BI

---

## คนสำคัญ

| ใคร | บทบาท | Note การสื่อสาร |
|---|---|---|
| K.Paul | Head of BA & Process Improvement — direct manager | Chat: สั้น, bullet, bottom-line-first (English) |
| K.Michael | CEO — final decision | Cost-focused; materials เป็น English, PowerPoint brand template |
| K.Tum | Senior DA | เจ้าของ scope BI restructure |
| K.Toon | BI Analyst (3 ปี) | |
| K.Pim | BI Analyst | ชอบ project มากกว่า routine |
| K.Jump | Junior (ex-intern) | |
| K.Pa | AI BA/PMO (emerging) | |
| K.Bell | Finance stakeholder | เจ้าของ Claude seats ฝั่ง Finance |
| Attila | DevOps/Infra | ติดต่อผ่าน **devops-tribe** หรือ DM (ไม่ monitor infra-tribe) |
| Aware | Vendor ภายนอก | เจ้าของ WireGuard tunnel + SAP hourly pull — ส่วนของ Aware ห้ามแตะ |

## Working preferences (Boat)

- Query fix/edit → ส่ง **full query copy-paste ได้** เสมอ ไม่ใช่ diff; dialect = BigQuery Standard SQL
- ภาษา: Thai สำหรับ discuss/อธิบาย, English สำหรับ material ถึง K.Paul/K.Michael
- ตัวเลข benchmark/ประมาณการ → flag ว่าเป็น estimate + แสดงที่มา ก่อนเข้าเอกสาร stakeholder
- Workstream ใหญ่จบ → retrospective + draw.io + data dictionary + Confluence Markdown

## AI Governance / AI-for-BI

- **3 Pillars:** Self-Service Adoption / Centralized Admin Control / Single Source of Truth
- Claude Team 9 Standard seats: BI 5, Finance (K.Bell) 3, PMO-Ops 1
- Core narrative: SAP project เผยอาการของการไม่มี data warehouse (3 dataset ซ้ำซ้อนไร้เอกสาร,
  tribal knowledge, Phase 2 ค้างตั้งแต่ 2025, Finance จับ data-quality incident เองรายเดือน)
  → warehouse เดียว + governed self-service AI แก้ครั้งเดียวใช้ทุกทีม
- Mind map หลัก: framework center = context + business rules + SQL templates;
  AI tools รอบนอก = swappable

## Asset locations

- GitHub: `sap-interface-repo` (queries, templates, PHASE6_DEPLOY) — ⚠️ ยัง upload ไม่ครบ ณ 07-16
- Google Drive: SAP folder `1S8RvxMHW54U3GcRHRgkh7k4xjvPUV6kH` (drawio, Global Standard v2.1)
- Confluence: data dictionary (56 columns), standards

## บทเรียน investigate (จาก INCIDENT-001 — ใช้ได้ทุกโปรเจกต์)

1. อย่าเชื่อ hypothesis แรกที่ดูสมเหตุสมผล — verify ด้วยข้อมูลจริงเสมอ
2. Field ที่ "ดูเสถียร" อาจไม่เสถียรจริง — ถาม domain expert ก่อนเชื่อ data quality
3. ตรวจต้นตอ (charge/transaction level) ก่อนไล่ขึ้นชั้น matching/join
