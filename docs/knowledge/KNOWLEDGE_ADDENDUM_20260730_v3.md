# ADDENDUM 2026-07-30 v3 — CONFIRMED FACTS, RETRACTIONS & PROJECT MIGRATION SURFACE

Source: design-review session (Boat + Claude), 2026-07-30
ปลายทางที่ต้อง append: `docs/knowledge/10_SAP_CONTEXT.md` (§A, §B) และไฟล์ใหม่
`docs/tasks/TASK_MIGRATE_PROJECT_sap-b1-374202.md` (§C)
วิธี verify ทุกข้อในเอกสารนี้: อ่านจาก repo จริงที่ commit `19c49cf` (branch `p0/stg-sap-state`) เท่านั้น

> **สถานะการอ้างอิง:** ข้อที่ tag `[CONFIRMED]` = มีหลักฐานตรงแล้ว อ้างได้
> `[OPEN]` = ยังไม่ปิด ห้ามอ้างเป็นข้อสรุป | `[RETRACTED]` = เคยเขียนไว้ผิด ต้องเลิกใช้

---

# §A. NEW CONFIRMED FACTS (2026-07-30)

## A1. `sap-extract-job` ไม่เขียนกลับ SAP เลย — zero column `[CONFIRMED]`
Deployed job มี SAP statement เดียวคือ `SELECT *` จาก `[RCB_LIVE_DB].[dbo].[@INSURANCE]`
พร้อม predicate:
```
DATEADD(MINUTE, (UpdateTime/100)*60 + (UpdateTime%100), CAST(UpdateDate AS DATETIME2)) > ?  -- watermark
  AND <same expression> <= ?                                                                -- run end
  AND U_InsuranceGroup <> 'B2B'
```
ไม่พบ `UPDATE` / `INSERT` / `MERGE` / `DELETE` / transaction commit / mark-as-exported write-back ใด ๆ
Job เขียนเฉพาะ GCS: JSON extract + watermark state + run log

- Watermark: `gs://rcb-bronze-zone/SAP/_extract_control/_watermark_state.json`
  (ถ้าไม่มี control file → เริ่มจาก `2026-07-09T17:00:00Z`)
- **ไม่มี** retry-failed-rows branch และ **ไม่ select ด้วย `U_BatchRunDate`**
  → historical DocEntry กลับเข้า extract ได้เมื่อ `UpdateDate`/`UpdateTime` ถูกเปลี่ยนให้ตกใน window
  หรือ watermark ถูก reset

## A2. "Unidentified SAP writer" = RESOLVED — เป็น interface file ของ BI เอง `[CONFIRMED]`
เดิม STEP 1 สรุปว่ามี unidentified writer แก้ SAP production (จาก `DocEntry 1080044` ที่มี
`U_BatchRunDate = 2026-07-28`) → **Boat ยืนยัน 2026-07-30 ว่าเป็นการ import interface file
ของ BI เองในช่วงนั้น ซึ่งมีปริมาณสูงผิดปกติ**

หลักฐานที่ตรงกัน:
| Extract run | File date | Rows | ตรงกับ |
|---|---|---:|---|
| `9f39a504` | 2026-07-27 | 60,404 | ช่วง import หนัก |
| `b4906132` | 2026-07-28 | **60,385** | **= BQ distinct DocEntry ของ batch 2026-07-27 เป๊ะ** |
| `d9426736` | 2026-07-29 | 58,619 | = SQL source row count ของ batch 2026-07-28 เป๊ะ |

เทียบวันปกติ: `c1b12db5` = 681 rows, `73e121a0` = 1,593, `303e7fe4` = 5,454

`U_BatchRunDate` เป็น column ที่มาในตัว interface file (ตาม format rule F3) → DocEntry ได้ค่า batch date
ใหม่จากไฟล์ที่ import ไม่ใช่จาก mutation ลึกลับ **ปิดประเด็นนี้ ไม่ต้องสืบ writer ต่อ**

## A3. Amplification เป็น STRUCTURAL BEHAVIOR ไม่ใช่ incident เดี่ยว `[CONFIRMED]`
กลไกจริง (3 องค์ประกอบ ทุกตัวทำงาน "ถูกต้อง" ตาม design ของตัวเอง):
```
BI import interface file จำนวนมาก
   → SAP แก้ UpdateDate/UpdateTime ของ ~60K แถว
   → watermark extract ดึงแถวเดิมกลับมาใหม่ทั้งชุด (ถูกต้องตาม predicate ของมัน)
   → loader เป็น plain append (ไม่ใช่ MERGE) → แถวซ้ำทับถมใน SAP_LIVE
```
**นัยสำคัญ: จะเกิดซ้ำทุกครั้งที่มี import รอบใหญ่** ไม่ใช่เหตุการณ์เดียวจบ
→ ต้องคาดหมายว่าจะเกิดอีกในรอบ interface ถัดไป

## A4. Daily amplification จริง — "45x" ที่เคยอ้างต่ำกว่าความจริงมาก `[CONFIRMED]`
Source: `SAP_LIVE` (BQ) vs `[RCB_LIVE_DB].[dbo].[@INSURANCE]` group by `U_BatchRunDate`
Comparison query ผ่าน `scripts/bq_safe_query.sh` @ **2026-07-30 09:10:41 UTC** (dry-run 133,186,480 bytes)
⚠️ SQL Server execution timestamp **ไม่ได้ถูกบันทึก** — ห้ามแต่งขึ้นมา

| Batch date | Source rows | BQ rows | BQ distinct DocEntry | BQ/source |
|---|---:|---:|---:|---:|
| 2026-08-15 | 5 | 5 | 5 | 1.000× |
| 2026-07-29 | 27 | 27 | 27 | 1.000× |
| 2026-07-28 | 58,619 | 1,465,475 | 58,619 | **25.000×** |
| 2026-07-27 | 2,076 | 4,226,950 | 60,385 | **2,036.103×** |
| 2026-07-26 | 8,578 | 2,484,385 | 66,952 | **289.623×** |
| 2026-07-25 | 817 | 1,584 | 1,584 | 1.939× |
| 2026-07-24 | 4,476 | 11,900 | 11,846 | 2.659× |
| 2026-07-23 | 851 | 1,578 | 1,578 | 1.854× |
| 2026-07-22 | 997 | 1,494 | 1,494 | 1.498× |
| 2026-07-21 | 1,791 | 3,011 | 3,011 | 1.681× |

**Peak จริง = ~2,036× ในวันเดียว (2026-07-27) ไม่ใช่ 45×** — เลข 45× เดิมมาจาก aggregate 3 วัน
(151K→6.86M) ซึ่งกลบความรุนแรงของวันที่แย่ที่สุด → **ห้ามอ้าง "45x" ต่อ ทุกจุดที่เขียนไว้ต้องแก้**

## A5. Baseline duplication ~2.19× ในวันปกติ — finding ใหม่ ยังไม่เคยถูก flag `[OPEN]`
วันที่ไม่มี import หนัก (21–25/07) ก็ **ไม่ใช่ 1:1** — เฉลี่ย ~2.19× (1.50×–2.66×)
เป็นคนละเรื่องกับ acute amplification 26–28/07 → **ควรเปิดเป็น finding แยก ห้ามผสมกับ
INCIDENT-SAP-MIRROR-20260726**

## A6. Real loss — ยังไม่ปิด `[OPEN]`
BQ distinct DocEntry **ไม่ต่ำกว่า** source row count ในทุกวันที่มีข้อมูล และเท่ากันเป๊ะ 3 วัน
(28/07, 29/07, 15/08) → **REAL LOSS NOT OBSERVED BY COUNT**
แต่**ยังไม่ใช่ข้อพิสูจน์ว่า loss = 0** เพราะ source ให้มาแค่ daily row count ไม่ใช่ distinct-DocEntry set
→ count ที่เท่าหรือมากกว่า พิสูจน์ set inclusion ไม่ได้
**ต้องปิดด้วย:** anti-join ของ source DocEntry list กับ `SAP_LIVE` หรือ source-side distinct-DocEntry count

## A7. `2026-07-29` = 27 แถวทั้งสองฝั่ง — ห้ามอ่านว่า "ปัญหาหายแล้ว" `[CONFIRMED]`
27 = 27 คือ **ต่ำผิดปกติทั้งสองฝั่ง** (วันปกติ 817–4,476) → เป็นสัญญาณของ extract ที่ยังไม่ครบรอบ
(สอดคล้องกับ `sap-extract-schedule` ที่ยัง 401 UNAUTHENTICATED ต้องกด manual) **ไม่ใช่หลักฐานว่า
loader ถูกแก้แล้ว**
`2026-08-15` (5 แถว, `RF*`/`RR*`/`RC*` prefix) = future-dated anomaly ที่รู้อยู่แล้ว เป็น**ค่าในข้อมูล
ไม่ใช่วันที่รัน query**

## A8. Corrected overwrite diff — accounting-overwrite gate CLEARED `[CONFIRMED]`
Source: `pacific-plating-282708.sap_integration_v2.SAP_LIVE`; corrected comparison query timestamp
**2026-07-30 14:27:28 UTC**. Population = **63,757 DocEntries** that had a target batch date and
more than one observed batch date, split before classification:

- **54,055 WITH_BEFORE** — last observed state with `U_BatchRunDate < 2026-07-26` compared with
  first observed state in 26–28/07.
- **9,702 NO_BASELINE** — no state observed before 26/07; excluded from POPULATION/MUTATION rather
  than treating absence of evidence as a default value.

Across the 54,055 WITH_BEFORE records, all monetary fields in scope had
**POPULATION = 0 and MUTATION = 0**:
`U_ActualReceived`, `U_ExpectedReceived`, `U_TotalPremiumAmt`, `U_GrossPremiumAmt`, `U_VATAmt`,
`U_StampDutyAmt`, `U_RefundAmt`, and `U_RefundAmountAfterFee`.

`U_PolicyNo` was predominantly legitimate population: 9,911 default→real versus 39
non-empty→different-non-empty mutations (0.072% of WITH_BEFORE). The 39 rows collapse into a small
set of repeated policy corrections, including punctuation correction and policy issuance alongside
`PENDING → POLICY UPLOADED`; this is negligible relative to the population and is not evidence of
a mass overwrite. This gate therefore **CLEARS the accounting-overwrite hypothesis**. The incident
remains open for storage/cost and prevention work.

The previous ฿645.21 stop came from comparing earliest versus latest observations across the whole
lifecycle, which mixed normal progression into the overwrite test. It is retracted as evidence of
mass monetary overwrite.

`DocEntry 2345730` has **no BEFORE observation prior to 26/07**, so it is not part of the corrected
baseline comparison. Three observed states are retained for human review:

| U_BatchRunDate | UpdateDate/Time | PolicyStatus | Actual | Expected | Payment evidence |
|---|---|---|---:|---:|---|
| 2026-07-26 | 2026-07-27 03:41 | Pending | 2,200.00 | 2,200.00 | no invoice/date/method |
| 2026-07-27 | 2026-07-28 04:13 | Pending | 2,200.00 | 2,200.00 | no invoice/date/method |
| 2026-07-28 | 2026-07-29 03:54 | Paid | 1,554.79 | 2,200.00 | invoice + PaymentDate 2026-07-28 + method/channel |

The simultaneous invoice, PaymentDate and payment-method population is consistent with a partial
payment event, not a discount (`U_Discount = 0`). Status remains **WAITING HUMAN — Boat will verify
with FA in the SAP UI**. Open question: why is the record `Paid` when Actual 1,554.79 is below
Expected 2,200.00 by 645.21?

This assessment remains a **LOWER BOUND**: states written between extract runs but never observed
by BigQuery are unrecoverable.

## A9. ฿645.21 — ห้ามใช้เป็น fingerprint ของ order `[CONFIRMED]`
645.21 คือ **เบี้ย พ.ร.บ. มาตรฐานของรถยนต์นั่งไม่เกิน 7 คน** → โผล่ในหลายพัน order
**ห้ามสรุปว่า `DocEntry 2345730` กับ pilot `L77828566` เป็น order เดียวกันเพราะตัวเลขตรงกัน**
(ข้อนี้เป็นการแก้ข้อสรุปผิดที่เกิดขึ้นในเซสชันนี้เอง — ดู §B4)

## A10. Bucket correction — root-cause statement เดิมชี้ผิด bucket `[CONFIRMED]`
Bucket ที่ deploy จริง: **`gs://rcb-bronze-zone/SAP/production_database/`**
ชื่อ bucket ใน root-cause statement เดิม **ไม่มีอยู่จริง** → ทุกจุดต้องใช้ path จริงข้างต้น
(หมายเหตุ: service account ชื่อ `sap-bucket-csv@...` ยังมีอยู่จริง อย่าสับสนระหว่างชื่อ SA กับชื่อ bucket)

## A11. Credential exposure ครั้งที่ 3 `[PARTIAL — ROTATION CLOSED 2026-07-31; HYGIENE OPEN]`
Deployed source archive มี **plaintext SAP credentials ใน deployment helper files**
- `10_SAP_CONTEXT.md` §GOVERNANCE บันทึกไว้เองว่า credential เคยหลุด **≥2 ครั้ง** → นี่คือครั้งที่ 3
- Vector ใหม่ (source archive) คนละทางกับเดิม (chat) แต่ root cause เดียวกัน: credential hygiene
  ไม่เคยถูกแก้เชิงระบบ
- **CLOSED:** SAP DB credential version 2 enabled `2026-07-31T11:32:25Z`; exposed version 1
  disabled. Live extract job ใช้ `secretKeyRef key=latest` อยู่แล้ว; metadata แสดง reference
  ไม่ใช่ plaintext value.
- **OPEN:** purge credential-bearing source archive, ตรวจ git/build/history, จำกัด access และแยก
  rotate/migrate legacy SMTP plaintext env metadata.
- ยืนยันแล้วว่าไม่มีการ print ค่าจริงและ temporary local copy ถูกลบแล้ว

## A12. `bq_safe_query.sh` ถูก BLOCK — guardrail มี fail-open bug `[OPEN]`
Codex BLOCK commit `a56f6d1` (`docs/reviews/2026-07-30-a56f6d1-codex.md`) — 2 ข้อที่ substantive:
1. **Byte parsing fails open เป็น `0`** → ถ้า dry-run JSON shape ไม่ตรงคาด จะถือว่า 0 bytes แล้ว
   **ปล่อยให้ query จริงรันโดยไม่มีการเช็คเลย** = guardrail เบี่ยงป้องกันตัวเองในจุดที่ควรป้องกันที่สุด
2. `--force` ยังส่ง `--maximum_bytes_billed=20 GiB` → estimate เกิน 20 GiB ไม่สามารถ proceed
   ได้จริงตามที่โฆษณา = doc ขัดกับ behavior จริง

Required fix: treat absent/unparseable `totalBytesProcessed` เป็น error (ห้ามเป็น 0);
resolve `--force` semantics; เพิ่ม offline parser test (current JSON, nested JSON, explicit zero,
missing field, malformed value, threshold equality, threshold+1)
**ห้ามถือว่า cost guardrail enforced จริงจนกว่าข้อนี้ปิด**

---

# §B. RETRACTIONS — ข้อสรุปที่ต้องเลิกใช้

| # | ข้อที่ต้องเลิกใช้ | เหตุผล | แทนด้วย |
|---|---|---|---|
| B1 | **UN-RETRACTED 2026-07-31:** loader crash-loop อ่านไฟล์เดิมซ้ำ | 149 successful LOAD jobs prove full-file commits during OOM retries | `[CONFIRMED — leading explanation]`; A2/A3 is contributing factor |
| B2 | "มี unidentified writer แก้ SAP production" | Boat ยืนยันว่าเป็น interface import ของ BI เอง | A2 |
| B3 | "ต้องหยุด nightly manual triggering / hold Attila IAM ticket" (คำแนะนำของ Claude ในเซสชันนี้) | Premise หายไปพร้อม B2 — extract ทำถูกทุกอย่าง | ปิด Attila IAM ticket ได้ตามปกติ ไม่ต้อง hold |
| B4 | "฿645.21 ตรงเป๊ะกับ pilot `L77828566` → อาจเป็น order เดียวกัน" (คำกล่าวของ Claude ในเซสชันนี้) | 645.21 = เบี้ย พ.ร.บ. มาตรฐาน ไม่ใช่เลขเฉพาะ order | A9 |
| B5 | "SAP_LIVE bloat = 45×" | Aggregate กลบ peak จริง | A4: peak ~2,036× ต่อวัน |
| B6 | bucket B1 ในแผนเก่าเป็นจุดเกิดปัญหา | ไม่พบ bucket ชื่อนั้น | A10: `gs://rcb-bronze-zone/SAP/production_database/` |
| B7 | ตัวเลข **559 / 71** | SUPERSEDED (posted-vs-rejected methodology error + คำนวณจากอาการแทนสาเหตุ) | รอ population ที่ผ่าน review |
| B8 | 401 orders / ฿267,775.28 / pilot `L77828566` เป็นข้อสรุป | Historical 401 ไม่มี job ID/query timestamp และผสม sub-shape; 042 schema แก้ใน source แล้วแต่ยังไม่ deploy; pilot ยังไม่มี FA/SAP/JE/import evidence. Fresh job `d16_002a_split_20260801_111420` (2026-08-01 04:14:25.294 UTC) แยก grain แต่ไม่ reproduce 401 และยังรอ Class A review | ห้ามอ้าง historical 401 เป็นตัวเลขจริง และห้ามเลื่อน pilot จน evidence control ครบ |
| B9 | "watermark ถูก reset/ลบ/ไม่ advance" | 14 generations เดินหน้าต่อเนื่อง ไม่มี reset/gap/failure-to-advance; 60,404→60,385→58,619 ลดลง ไม่เข้ากับ replay จาก default | A1/A3 และ watermark evidence 2026-07-30 |

**หลักการที่ได้จากเซสชันนี้:** ทั้ง B3 และ B4 เป็นข้อสรุปที่ Claude เสนอเองแล้วต้องถอนภายในเซสชันเดียว
→ ยืนยันกฎเดิมว่า **ข้อสรุปที่ยังไม่มี Boat/FA/vendor ยืนยัน ห้ามเลื่อนสถานะเป็น fact**
โดยเฉพาะข้อสรุปที่ "อธิบายได้สวย" ซึ่งเป็นตัวที่เสี่ยงที่สุด

---

# §C. PROJECT MIGRATION — `pacific-plating-282708` → `sap-b1-374202`

สถานะ: **PLANNED, ยังไม่เริ่ม** | ยังไม่มีการอ้างถึง `sap-b1-374202` ที่ใดใน repo (clean slate)

## C1. Migration surface — นับจาก repo จริง (commit `19c49cf`)
`pacific-plating-282708` ปรากฏ **569 ครั้ง** ใน **80 ไฟล์**:

| ประเภทไฟล์ | จำนวนไฟล์ |
|---|---:|
| `.sql` | 66 |
| `.md` | 11 |
| `.py` / `.yaml` / `.json` | 2 |
| `.sh` | 1 |

Dataset ที่ถูกอ้าง (นับจาก qualified reference):

| Dataset | ครั้ง | ต้องย้ายไหม? |
|---|---:|---|
| `sap_integration_v3` | 220 | ✅ ย้าย (ของเราเอง) |
| `careos` | 215 | ⏳ **CONFIRM — source system, อาจไม่ใช่ของ SAP project** |
| `sap_integration_v2` | 67 | ✅ ย้าย (มี audit evidence — ดู C4) |
| `sap_data_engineer` | 19 | ⏳ CONFIRM |
| `sap_view` | 10 | ✅ ย้าย (legacy production views — ยังผลิตไฟล์ SAP จริง) |
| `hydra_customer_prod` | 8 | ⏳ **CONFIRM — source system** |

**Region: ทุก dataset อยู่ `asia-southeast1`** (ยืนยันจาก `region-asia-southeast1` ใน
INFORMATION_SCHEMA query 6 จุด) — ⚠️ default query location ของ `bq` CLI คือ `US` ต้องส่ง
`--location=asia-southeast1` เสมอ (บทเรียนที่บันทึกไว้แล้วใน changelog)

## C2. 🔴 ตัวบล็อกที่ใหญ่ที่สุด: bucket ที่ vendor อ่าน
| Bucket | ครั้ง | เจ้าของ/ผู้อ่าน | ผลต่อ migration |
|---|---:|---|---|
| `gs://interface-file` | 46 | **SAP pull ทุก 15 นาที (:00/:15/:30/:45), Aware เป็นเจ้าของ cadence** | 🔴 **ย้ายไม่ได้ตามใจ** |
| `gs://rcb-bronze-zone` | 17 | extract output + watermark | 🟠 ต้องตัดสินใจ |
| bucket B1 ในแผนเก่า | 10 historical references | ไม่พบ bucket จริง (A10) | ⚪ ไม่ต้อง migrate |

**ข้อเท็จจริงทางเทคนิค: GCS bucket ย้ายข้าม project โดยตรงไม่ได้** (ชื่อ bucket เป็น global namespace,
ผูกกับ project ที่สร้าง) มี 2 ทาง:
- **(ก) เก็บ bucket ไว้ที่ project เดิม + ให้ cross-project IAM** — Aware ไม่ต้องแก้อะไรเลย
  path เดิมทำงานต่อ ✅ **แนะนำทางนี้**
- (ข) สร้าง bucket ใหม่ + เปลี่ยน path ที่ Aware pull — **ต้องประสาน Aware และแก้ vendor-owned
  component ซึ่งขัดกับกฎ `AGENT_RULES.md` "Do not touch vendor-owned components"**

## C3. Infrastructure ที่ผูกกับ project และต้องสร้างใหม่ทั้งหมด
| Component | ชนิด | หมายเหตุ |
|---|---|---|
| `sap-extract-job` | Cloud Run Job | + VPC connector |
| `sap-connector` | **VPC connector → `172.25.25.3`** | 🔴 **WireGuard tunnel เป็นของ Aware — network ผูกกับ project ต้องให้ Aware ร่วม** |
| `sap-order-payment-initial-phase` | Cloud Run service | loader |
| `trigger-sap-order-payment-initial-phase` | Eventarc trigger | + Pub/Sub topic (ชื่อมี project number ฝังอยู่) |
| `auto_load_sap_data_in_bucket_to_bigquery` | Cloud Scheduler `0 1 * * *` Asia/Bangkok | |
| `sap-extract-schedule` | Cloud Scheduler | ⚠️ ปัจจุบัน 401 UNAUTHENTICATED ค้างอยู่ |
| `sap_state_and_recon_refresh` | Scheduled query / chain | |
| `rcb-motor-order-payment-sap-bucket-1` | Cloud Function | timeout fix 300s→540s **unverified** ว่า deploy แล้วหรือยัง |
| `sap-bucket-csv@pacific-plating-282708...` | Service account | ต้องสร้าง SA ใหม่ + IAM ทั้งชุด |
| Secret Manager secrets | SAP DB creds | 🔗 **รวมกับ A11 — rotate ครั้งเดียวที่ project ใหม่ ไม่ต้องทำสองรอบ** |

## C4. 🔴 สิ่งที่ **ไม่** ย้ายไปด้วย และจะหายถาวร
1. **`INFORMATION_SCHEMA.JOBS_BY_PROJECT` history** — นี่คือฐานหลักฐานของ:
   - การตัดสินว่า `sap_integrety_2025_RCL` เป็น dormant (90-day consumer check)
   - `COST_CONTROL.md` PART 2 per-user cost tracking ทั้งหมด
   → **หลังย้าย จะไม่มี history ให้ตรวจย้อน ต้องรอสะสมใหม่**
   **ต้อง export job history เป็นตารางจริงก่อนย้าย ถ้าอยากเก็บหลักฐาน**
2. **Time travel window (7 วัน)** — ไม่ติดไปกับ copy
3. IAM bindings, scheduled queries, query history, authorized views (ต้อง re-authorize),
   materialized views (ต้อง rebuild)
4. **Chain of custody ของ audit evidence** — ดู C5

## C5. ⚠️ Timing risk: ย้าย project ขณะที่ incident ยัง OPEN
สถานะปัจจุบัน: `INCIDENT-SAP-MIRROR-20260726` **OPEN**, accounting escalation (`DocEntry 2345730`)
**ยังไม่ปิด**, `SAP_LIVE` อยู่ภายใต้ **append-only hold ห้าม clean เพราะเป็น audit trail**

การ copy ตารางที่เป็นหลักฐานข้าม project ระหว่างที่ incident เปิดอยู่ = ประเด็น chain-of-custody
**กติกาที่ต้องทำก่อนย้าย (ไม่ยาก แต่ถ้าไม่ทำจะย้อนกลับไม่ได้):**
```sql
-- บันทึกก่อนย้าย: row count + distinct DocEntry + checksum ต่อ batch date
SELECT DATE(U_BatchRunDate) AS batch_date,
       COUNT(*) AS rows_,
       COUNT(DISTINCT DocEntry) AS docs,
       SUM(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS content_fingerprint
FROM `pacific-plating-282708.sap_integration_v2.SAP_LIVE` t
GROUP BY batch_date ORDER BY batch_date;
```
รันสคริปต์เดียวกันที่ project ใหม่หลัง copy → ตัวเลขต้องตรงทุกบรรทัด = พิสูจน์ได้ว่าหลักฐานไม่เปลี่ยน

## C6. Cost-minimisation rules สำหรับการย้าย
1. **ใช้ `bq cp` (copy job) ห้ามใช้ `CREATE TABLE AS SELECT`**
   copy job ภายใน region เดียวกัน = **ไม่มี query cost**; CTAS = คิดเงินตาม bytes scanned
   ยิ่งกับ `SAP_LIVE` ที่บวมระดับหลายล้านแถว ต่างกันมาก
2. **project ใหม่ต้องสร้าง dataset ที่ `asia-southeast1`** เท่านั้น — ถ้าพลาดเป็น `US`
   จะกลายเป็น cross-region copy (มีค่า transfer) และ **join กับ `careos` ข้าม region ไม่ได้เลย**
3. **ถ้า `careos` / `hydra_customer_prod` ไม่ย้ายด้วย** ทุก join จะเป็น cross-project
   (ทำได้ ไม่มีค่าใช้จ่ายเพิ่มถ้า region เดียวกัน) แต่ **ต้อง grant IAM ให้ SA ใหม่อ่าน dataset เดิม**
   → ข้อนี้ต้องตัดสินใจก่อนเริ่ม เพราะกระทบ 215 + 8 references
4. **โอกาสที่ควรใช้: landing `sap_mirror_doc` (MERGE by DocEntry) ที่ project ใหม่**
   downstream ทุกตัวปัจจุบันสแกน ~8.2M แถวเพื่อได้ข้อมูลจริง ~78K = เสีย **~105× ทุก query**
   → MERGE mirror ตัด scan cost ประมาณ 100× **โดยไม่ต้องลบ audit history สักแถว**
   (`SAP_LIVE` ยัง copy ไปเก็บเป็น frozen archive ตาม append-only hold)
   นี่เป็น cost win ที่ใหญ่ที่สุดในโปรเจกต์ตอนนี้ — ใหญ่กว่า dry-run wrapper หลายเท่า
5. **Double storage ชั่วคราว: ยอมรับได้** — เก็บทั้งสอง project จน incident ปิด storage cost
   เล็กกว่าความเสี่ยงเสียหลักฐานมาก
6. Diagnostic / scratch table ที่สร้างใหม่ต้องมี
   `OPTIONS(expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 30 DAY))` ตั้งแต่ต้น
   (project ใหม่ = ไม่มี legacy exception 7 ตาราง `_backfill_*`/`manual_close_*` ให้ต้องยกเว้น)

## C7. ⚠️ ห้าม sed project ID แบบเหมารวม
569 occurrences ใน 80 ไฟล์ — **แต่ `.md` 11 ไฟล์ส่วนใหญ่คือบันทึกหลักฐานย้อนหลัง**
(findings, reviews, changelog, session logs) ซึ่ง `pacific-plating-282708` ในนั้นคือ
**ข้อเท็จจริงว่าหลักฐานถูกเก็บที่ไหน** ไม่ใช่ config
- ✅ แก้: `.sql` (66), `.sh` (1), `.py`/`.yaml`/`.json` (2) → ควรทำเป็น **single constant/parameter**
  ไม่ใช่ sed ค่าใหม่ทับ (จะเจอปัญหาเดิมอีกรอบถ้าย้ายอีก)
- 🚫 ห้ามแก้: historical evidence ใน `docs/` — ให้เติมหมายเหตุว่า "หลักฐานชุดนี้เก็บที่
  `pacific-plating-282708` ก่อน migration <date>" แทน

## C8. ⏳ CONFIRM — คำถามที่ต้องตอบก่อนเขียน migration task
- (a) `careos` และ `hydra_customer_prod` ย้ายด้วยหรืออยู่ที่เดิม? (กระทบ 223 references)
- (b) `sap_data_engineer` ย้ายด้วยไหม? (มี view ที่ยังถูกใช้จริง เช่น
  `sap_dashboard_carepay_fully_paid` ที่เกี่ยวกับ onetime M1/V1 finding)
- (c) `gs://interface-file` — ยืนยันทาง (ก) เก็บ bucket ไว้ที่ project เดิม + cross-project IAM ใช่ไหม?
  (ถ้าใช่ Aware ไม่ต้องแก้อะไร = ทางที่ปลอดภัยที่สุด)
- (d) `sap-b1-374202` เป็น project ที่มีอยู่แล้วหรือสร้างใหม่? มี dataset/ข้อมูลอะไรอยู่ก่อนไหม?
- (e) จะย้าย **ก่อน** หรือ **หลัง** ปิด INCIDENT-SAP-MIRROR-20260726 และ accounting escalution
  `DocEntry 2345730`? (**คำแนะนำ: ปิด accounting escalation ก่อน** — ย้าย project ระหว่างที่ยังมี
  monetary discrepancy ที่ยังไม่อธิบายได้ ทำให้ตอบคำถาม auditor ยากขึ้นมาก)
- (f) ต้องการเก็บ `INFORMATION_SCHEMA` job history ไว้เป็นตารางก่อนย้ายไหม? (ถ้าไม่ทำ = หายถาวร)

## C9. Sequencing ที่แนะนำ (ยังไม่ใช่คำสั่ง — รอ C8 ตอบก่อน)
```
0. ตอบ C8 (a)–(f) ให้ครบ
1. Export INFORMATION_SCHEMA job history → ตารางจริงที่ project เดิม   [C4.1]
2. บันทึก evidence fingerprint ของ SAP_LIVE (C5 query) ที่ project เดิม
3. สร้าง dataset ที่ sap-b1-374202 — ยืนยัน location = asia-southeast1  [C6.2]
4. สร้าง SA + IAM ใหม่ + Secret Manager พร้อม credential ที่ rotate แล้ว  [A11 + C3]
5. bq cp ตาราง (ห้าม CTAS) → verify fingerprint ตรงทุกบรรทัด          [C5, C6.1]
6. Parametrise project ID ใน .sql/.sh/.py (ห้ามแตะ docs)               [C7]
7. สร้าง Cloud Run / Scheduler / Eventarc ใหม่ — ยังไม่ enable         [C3]
8. Parallel run: project ใหม่เขียน shadow prefix เท่านั้น
   ห้ามเขียน gs://interface-file/** จนผ่าน parallel run               [AGENT_RULES]
9. Cutover เมื่อ Boat อนุมัติชัดเจน + rollback plan < 5 นาที
```

---

# §D. OPEN ITEMS (สรุปรวม)

| Pri | Item | เจ้าของ | อ้างอิง |
|---|---|---|---|
| P0 | Purge credential-bearing archive/history + restrict access; rotate/migrate legacy SMTP credential | Boat/DevOps | A11 |
| P0 | `DocEntry 2345730` → OrderItem/Period → cross-check pool 401 + import files 26–28/07 → live หรือ historical? | Claude Code | A8 |
| P1 | Fix fail-open parser ใน `bq_safe_query.sh` + parser tests | Claude Code | A12 |
| P1 | ตอบ C8 (a)–(f) ก่อนเขียน migration task | Boat | C8 |
| P1 | CMI population BLOCK `5abaed3` — แยก sub-mechanism, เติม `042` schema, หา FA evidence ให้ pilot | Claude Code | B8 |
| P2 | `sap_mirror_doc` MERGE by DocEntry (แก้ amplification ถาวร + cost ~100×) | Claude Code | A3, C6.4 |
| P2 | Set-level anti-join ปิดคำถาม real loss | Claude Code | A6 |
| P2 | เปิด finding แยกสำหรับ baseline duplication ~2.19× | Codex | A5 |
| P2 | แก้ทุกจุดที่อ้าง "45×" และ bucket B1 ที่ไม่มีจริง | Codex | A4, A10 |
| P2 | Retract B1/B2 ใน `FINDINGS_SAP_MIRROR_20260726.md` | Codex | B1, B2 |
| P3 | ปิด `sap-extract-schedule` 401 (Attila IAM) — ไม่ต้อง hold แล้ว | Boat/Attila | B3 |
| P3 | Verify `rcb-motor-order-payment-sap-bucket-1` timeout fix deploy จริงหรือยัง | Claude Code | C3 |
| P3 | Review debt: 4 OPEN (Claude Code) + 2 BLOCK ที่ยังไม่ตอบ | — | REVIEW_QUEUE |

⚠️ **Exec summary (`SAP_Executive_Progress_Summary_20260730.docx`) ขึ้นอยู่กับ A8:**
เอกสารระบุว่าเป็นปัญหาของ "**historical** orders" และ "no incorrect data has reached SAP"
→ **ถ้า A8 สรุปว่าเป็น live ทั้งสองประโยคผิด ต้อง hold เอกสารไว้จนกว่า P0 ข้อ 2 จะปิด**
