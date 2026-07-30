# COST_CONTROL.md — minimize spend, redesign agent lanes, budget framework
Added 2026-07-29 | Referenced by `docs/AGENT_RULES.md`
⚠️ ทุกตัวเลขราคาต่อหน่วยในไฟล์นี้คือ **ประมาณการจากความเข้าใจ list price** — **ห้ามนำเข้าเอกสาร
stakeholder จนได้ตรวจกับ cloud.google.com/pricing และ claude.com/pricing แล้ว**

---

# PART 1 — ต้นทุนจริงมาจากไหน (เรียงตามขนาด ตามหลักฐานในโปรเจกต์นี้)

| # | ตัวขับต้นทุน | หลักฐานที่เห็นในโปรเจกต์ |
|---|---|---|
| 1 | **คนของ Boat** | 2 สัปดาห์เต็มไปกับ investigate/แก้มือ — แพงกว่าทุกอย่างรวมกัน |
| 2 | **BigQuery scan ซ้ำซ้อน** | `COUNT(*)` บน view timeout 120s หลายครั้ง, diagnostic เดิมรันซ้ำหลายรอบ, `SELECT DISTINCT *` บนตารางกว้าง, agent 2 ตัว query ของเดียวกัน |
| 3 | **Agent tokens** | session ยาว, verification verbose, Codex เกือบ verify config tables ที่ Claude Code ทำเสร็จแล้ว |
| 4 | **BigQuery storage** | `SAP_LIVE` daily amplification จริง: 289.623× (07-26), 2,036.103× (07-27), 25.000× (07-28) = จ่ายค่าเก็บซ้ำ + ทุก query ที่แตะมันแพงขึ้น |
| 5 | Infra (Scheduler/Workflows/Cloud Run/GCS/Eventarc) | เล็กมาก ระดับ free tier ถึงเศษดอลลาร์ |

**ข้อสรุป:** ประหยัดที่ #2 และ #3 ได้ทันทีด้วยวินัย ไม่ต้องเปลี่ยนสถาปัตยกรรม / #4 ประหยัดได้ทันทีที่ clean

---

# PART 2 — วัดของจริงก่อน (รันครั้งเดียว ได้ตัวเลข baseline)

**2.1 ค่า BigQuery ที่ใช้ไปแล้ว 30 วัน แยกตามผู้ใช้**
```sql
SELECT
  user_email,
  COUNT(*) AS jobs,
  ROUND(SUM(total_bytes_billed)/POW(1024,4), 3) AS tib_billed,
  ROUND(SUM(total_bytes_billed)/POW(1024,4) * 6.25, 2) AS est_usd   -- ⚠️ ตรวจ unit price ก่อนใช้
FROM `pacific-plating-282708.region-asia-southeast1.INFORMATION_SCHEMA.JOBS_BY_PROJECT`
WHERE creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
  AND job_type = 'QUERY' AND state = 'DONE'
GROUP BY user_email ORDER BY tib_billed DESC;
```

**2.2 Query 20 ตัวที่แพงที่สุด (คือเป้าของการ optimize)**
```sql
SELECT
  ROUND(total_bytes_billed/POW(1024,3), 2) AS gib_billed,
  TIMESTAMP_DIFF(end_time, start_time, SECOND) AS sec,
  user_email, creation_time,
  SUBSTR(REGEXP_REPLACE(query, r'\s+', ' '), 1, 200) AS query_head
FROM `pacific-plating-282708.region-asia-southeast1.INFORMATION_SCHEMA.JOBS_BY_PROJECT`
WHERE creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
  AND job_type = 'QUERY' AND state = 'DONE'
ORDER BY total_bytes_billed DESC LIMIT 20;
```

**2.3 Storage: ตารางไหนกินที่ (และ SAP_LIVE บวมแค่ไหน)**
```sql
SELECT table_schema, table_name,
  ROUND(SUM(total_logical_bytes)/POW(1024,3), 2) AS gib_logical,
  ROUND(SUM(total_logical_bytes)/POW(1024,3) * 0.020, 2) AS est_usd_per_month  -- ⚠️ ตรวจราคา
FROM `pacific-plating-282708.region-asia-southeast1.INFORMATION_SCHEMA.TABLE_STORAGE`
WHERE table_schema IN ('sap_integration_v2','sap_integration_v3','careos','SAP')
GROUP BY 1,2 ORDER BY gib_logical DESC LIMIT 30;
```

**2.4 ต้นทุนต่อคืนของ pipeline (หลังมี run_log ครบ)** — join `pipeline_run_log` กับ JOBS_BY_PROJECT
ด้วยช่วงเวลา แล้วได้ "bytes billed ต่อ run" → ใช้ประเมินค่ารายเดือนของ automation จริง

---

# PART 3 — กติกาลดต้นทุน (เพิ่มเข้า AGENT_RULES ทั้งหมด)

## 3.1 Hard cost guardrails
- **บังคับผ่านโค้ด:** query BigQuery ที่ไม่ใช่ metadata ทุกครั้งต้องเรียก
  `scripts/bq_safe_query.sh` เท่านั้น — ห้ามยิง `bq query` ตรง. Metadata-only คือ `bq show/ls/head`
  หรือ query ที่จำกัดอยู่ใน `INFORMATION_SCHEMA`/`__TABLES__`. Claude Code เพิ่ม wrapper ใน
  commit `a56f6d1`; class-A review ปัจจุบัน BLOCK เพราะ missing-byte parser fail-open และ
  `--force` ยังติด hard cap 20 GiB. ระหว่างรอแก้ ห้ามใช้ `--force` และห้าม bypass wrapper.
- **ทุก query ที่ไม่ใช่ metadata ต้อง `--dry_run` ก่อน** ถ้า dry-run บอก > **20 GB** ให้หยุดถามก่อนรัน
- ใส่ `--maximum_bytes_billed=21474836480` (20 GiB) กับทุก `bq query` เป็น default —
  query หลุดจะ fail ทันทีแทนที่จะกินเงิน (นี่คือกันชนที่สำคัญที่สุดข้อเดียว)
- **นับแถวด้วย metadata ไม่ใช่ `COUNT(*)`**: ใช้ `INFORMATION_SCHEMA.TABLE_STORAGE` /
  `__TABLES__.row_count` (ฟรี, ทันที) — `COUNT(*)` บน view ใหญ่คือสิ่งที่ทำให้ timeout 120s มาแล้ว
- **ห้าม `SELECT *` / `SELECT DISTINCT *`** บนตารางกว้าง — BigQuery คิดเงินตามคอลัมน์ที่อ่าน
  เลือกคอลัมน์ที่ใช้จริงเท่านั้น (ประหยัดได้หลายเท่าโดยไม่เสียอะไร)
- **1 query = หลาย metric**: รวม diagnostic เป็น query เดียวที่คืนหลายคอลัมน์/`STRUCT` แทนยิง 10 ครั้ง
  (แต่ละครั้ง re-scan ตารางเดิม) — pattern ที่เราเสียเงินไปมากที่สุดในสองสัปดาห์นี้
- **Explore ด้วย `TABLESAMPLE SYSTEM (1 PERCENT)`** ก่อน แล้วค่อยรันเต็มเมื่อรู้ว่าถูกทาง
- **Materialize diagnostic**: ผลที่จะถูกอ้างซ้ำ → เขียนเป็นตารางเล็กใน v3 (`diag_*`) แล้ว query ตารางนั้น
  ห้าม re-scan careos ทุกครั้งที่อยากดูตัวเลขเดิม
- **อ้าง commit hash แทน re-verify**: มีหลักฐานแล้วห้ามตรวจซ้ำ (เช่น config tables verify ใน `9825e97`)
- Dashboard/Looker: ต่อกับ **summary table ที่ refresh ตามรอบ** ไม่ใช่ view ที่ scan ตารางใหญ่ทุกครั้ง
  ที่มีคนเปิดหน้า

## 3.2 Token guardrails (ค่า agent)
- อ่านเฉพาะที่ต้องใช้: hot tier (00/10/20) + `AS_BUILT_V3` + task doc ของงานนั้น
  **ห้ามอ่าน `docs/design/**` ทั้งโฟลเดอร์ถ้าไม่ได้ทำงานกับมัน**
- Session สั้น จบเป็นก้อน: ทำเสร็จ → commit → เขียน session note → **เปิด session ใหม่**
  (context ยาวคือค่าที่จ่ายทุก turn)
- ผลลัพธ์ยาวเขียนลงไฟล์ ไม่ต้อง echo ทั้งก้อนกลับมาในแชท (`| tail -20` พอสำหรับยืนยัน)
- ห้าม verbose retry loop: พลาด 2 ครั้งด้วยสมมติฐานเดียว → หยุด เปลี่ยนวิธี หรือถามคน
  (บทเรียน: cancel batch เดา 3 รอบ, SCHEDULE_GAP debug ยาว)
- ห้ามรัน agent 2 ตัวบนงานสืบสวนเดียวกัน (จ่าย token 2 เท่า ได้ข้อสรุปครึ่งใบ 2 อัน)

## 3.3 Storage
- `SAP_LIVE` เป็น append-only audit history: หยุด future reinsert growth แต่ห้าม clean historical
  rows ก่อน incident ปิด
- ตาราง `diag_*` / scratch ใหม่ทุกตาราง: ต้องกำหนด `expiration_timestamp` ตอนสร้างให้ลบตัวเองใน
  7–30 วัน ใช้ `sql/ddl/_TEMPLATE_new_table.sql`; ห้ามยกเว้นโดยไม่บันทึก
- Partition + cluster ตารางใหญ่ใน v3 และ **บังคับ partition filter** ในทุก query ที่แตะ

---

# PART 4 — แบ่งงาน agent ใหม่ (คุมต้นทุนเป็นหลัก)

## หลักใหม่: single-agent-by-default, ใช้ตัวที่สองเฉพาะเมื่อมี 2 lane ที่ไม่ทับกันจริง

| Lane | เจ้าของ | ต้นทุน | ทำอะไร |
|---|---|---|---|
| **EXPENSIVE (BigQuery/deploy)** | **Claude Code** | จ่าย BQ + token สูง | SQL, DDL, deploy, investigation ที่ต้อง query จริง — **ทีละคน ทีละงาน** |
| **CHEAP (docs/text)** | **Codex** | ~0 BQ, token ต่ำ | knowledge/design/changelog/progress/INPUTS_NEEDED/runbook, สรุป session note, ตรวจความสอดคล้องเอกสาร |

กติกาที่เปลี่ยนจากเดิม:
1. **Codex ไม่ query BigQuery เลยตามปกติ** — ต้องการตัวเลข → ขอผ่าน `docs/HANDOFF_QUEUE.md`
   ให้ Claude Code รันรวมในรอบเดียว (ลดการ scan ซ้ำ + ลด approval round-trip)
2. **Claude Code ไม่แตะ `docs/knowledge/**`** — เขียน `docs/sessions/<date>-claude.md` ให้ Codex fold
3. **Batch การขอตัวเลข**: Codex เก็บคำถามที่ต้องใช้ข้อมูลไว้ใน queue แล้วให้ Claude Code ตอบทีเดียว
   1 query หลาย metric (ห้ามยิงทีละคำถาม)
4. **งานสืบสวน = 1 agent เท่านั้น** (เช่น SAP_LIVE bloat) — ห้ามแบ่ง
5. **Cutover / production write = 1 agent, มีคนเฝ้า** — ไม่มี parallel
6. ก่อนเริ่มทุก session: `git log --oneline -10` + อ่าน `docs/sessions/` วันนี้ → ห้ามทำซ้ำ

---

# PART 5 — โครง Budget (เติมตัวเลขจาก PART 2)

## 5.1 ต้นทุนเดินระบบ (recurring / เดือน) — ⚠️ ประมาณการ ต้องแทนด้วยค่าวัดจริง
| รายการ | สูตร | ค่าที่วัดได้ | หมายเหตุ |
|---|---|---|---|
| BigQuery query | TiB billed × unit price | ___ (จาก 2.1) | ตัวแปรใหญ่สุด ลดได้ด้วย PART 3 |
| BigQuery storage | GiB × ราคา/GiB/เดือน | ___ (จาก 2.3) | ลด future growth ด้วย loader fix; `SAP_LIVE` audit history ห้าม clean ก่อน incident ปิด |
| Cloud Run Job (extract) | วินาที × vCPU/mem | ~เศษดอลลาร์ | รันวันละครั้ง |
| Cloud Run service (loader) | ตามการใช้ | ___ | ⚠️ ตอนนี้ crash-loop = จ่ายเกินโดยไม่ได้ผล |
| Scheduler / Workflows / Eventarc | ตามจำนวน job/step | ~free tier | นับหลัก 30–100 executions/เดือน |
| GCS (bronze zone, interface files) | GiB/เดือน | ___ | ไฟล์ชั่วคราว ควรตั้ง lifecycle rule |
| WireGuard VM (e2-micro) | ~$6–7/เดือน (ประมาณการเดิมในเอกสาร) | ___ | ต้องเปิดตลอด |
| Looker Studio | ฟรี แต่ query ที่มันยิงคิดเงินใน BQ | ___ | ผูกกับ summary table |

## 5.2 ต้นทุนเครื่องมือ AI (recurring)
| รายการ | จำนวน | ราคา | หมายเหตุ |
|---|---|---|---|
| Claude Team seats | 9 (BI 5 / Finance 3 / PMO 1) | ตรวจ claude.com/pricing | ยืนยันแล้วในเอกสารเดิม |
| Codex / OpenAI | ___ | ตรวจราคาทางการ | ผมไม่ quote จากความจำ |
| API usage (ถ้าใช้ API key นอก seat) | ___ | ตามการใช้ | seat = เหมาจ่าย มี cap / API = จ่ายตามใช้ ไม่มี cap |

## 5.3 ต้นทุนโครงการที่เหลือถึง V3 done (one-time)
ประเมินเป็น **effort** ไม่ใช่เงิน (เพราะเป็นเวลาคน + agent):
| งาน | สถานะ | effort คร่าว |
|---|---|---|
| SAP_LIVE preservation + loader fix | ค้าง (ใหญ่สุด) | 1–2 session ของ Claude Code + ต้องหาเจ้าของ loader; no historical cleanup before incident closure |
| Cancelled status + 036 + regression | กำลังทำ | 1 session |
| Phase B (56 columns + golden test) | รอ fixtures | 2–3 session |
| Phase C (shadow export + cancel branch) | ยังไม่เริ่ม | 2–3 session |
| Phase D (cutover 3 ไฟล์ ทีละตัว) | ยังไม่เริ่ม | 3 สัปดาห์ปฏิทิน (มี 5-day shadow diff ต่อ type) |
| Recovery backlog (ในกรอบปีที่อนุมัติ) | รอ approve | 1 session + รอ SAP ack |

## 5.4 ต้นทุนที่ **ประหยัดได้** (ROI ของงานนี้ — ใช้คุยกับ K.Michael ได้)
| แหล่ง | ผลที่วัดได้ |
|---|---|
| เลิก manual import ตาม list ของ FA | ชั่วโมงคนของ BI + FA ต่อรอบ (นับจาก 3 รอบล่าสุด) |
| Import error รายคืน (~100 orders) → ~0 | ชั่วโมงแก้มือ + ความเสี่ยงบัญชี |
| `SAP_LIVE` daily amplification (สูงสุด 2,036.103× ในวันที่ตรวจ) → stop future reinsert growth | ค่า storage + ค่า scanของทุก query; append-only history retained until incident closure |
| Loader crash-loop → หยุด | ค่า compute ที่จ่ายทิ้งทุกคืน |
| `sap_integrety_2025_RCL` | Dormant/obsolete; no real consumer in 90 days, no notification needed; housekeeping/archive candidate only |

**วิธีนำเสนอ:** ค่า infra ของ V3 อยู่ระดับ**เศษเงินเทียบกับชั่วโมงคน** ที่มันประหยัด — ประเด็นขายไม่ใช่
"ลดค่า cloud" แต่คือ **เลิกจ่ายด้วยเวลาคนและความเสี่ยงบัญชี**
