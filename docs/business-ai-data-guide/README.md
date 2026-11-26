> **Moved 2026-11-26:** this skill now lives in its own repository `rabbitcare-bi-data-skill` (separate from BI-SAP).
> This folder is a frozen snapshot; make new changes in the new repo.

# Business AI Data Guide (pacific-plating-282708)

คู่มือ data สำหรับ AI ของ business user — ให้ AI ถามนิยามก่อนคำนวณ และดึงข้อมูลจากตารางที่ถูกต้อง

| Path | คืออะไร |
|---|---|
| `rabbitcare-bi-data/` | Claude Skill (SKILL.md + references/) — ไฟล์ที่แจกให้ user |
| `DESIGN_PROPOSAL_SELF_SERVICE_DATA_LAYER.md` | ข้อเสนอ design (English) — skill → governed views → semantic layer |

## วิธีติดตั้ง (Claude)

1. Zip โฟลเดอร์ `rabbitcare-bi-data/` (ให้ `SKILL.md` อยู่ในโฟลเดอร์ชั้นแรกของ zip)
2. Upload ผ่านหน้า Skills ใน claude.ai settings — admin แจกทั้ง org ได้ (org-provisioned skill)
   หรือ user upload เอง (ชื่อเมนูอาจเปลี่ยนตามเวอร์ชัน claude.ai)
3. User ต้องมี BigQuery connector ที่สิทธิ์อ่าน dataset ที่อนุญาตเท่านั้น (ดู proposal §3)

## Version

- **v1.1 (2026-11-25)** — Google Drive added as a secondary source (policy decks, KPI config, SAP data dictionary,
  onboarding deck); commission cycle/basis corrected; freshness corrected; open conflicts in `docs/INPUTS_NEEDED.md`.
- **v1 (2026-11-25)** — knowledge harvested from Teams, email, repo and BigQuery (see
  `rabbitcare-bi-data/references/sources.md`): clarifying-question bank, domain files (commission,
  finance, sales/marketing), mismatch playbook, change-order and freshness patterns, time-zone conventions.
- v0 (2026-11-25) — date basis, metrics, tables, query patterns.

## Maintain

- แก้นิยามที่ `references/*.md` แล้ว zip/upload ใหม่ — Git คือ source of truth
- รายการ ⚠️ TO CONFIRM ต้องปิดกับ Finance/BI ก่อนบอก user ว่าเป็นตัวเลข certified
- ตัวเลข evidence ทุกตัวในไฟล์มี source table + วันที่ query (2026-11-25)
