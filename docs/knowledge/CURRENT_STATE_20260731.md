# CURRENT STATE — 2026-07-31 (AUTHORITATIVE)

**READ THIS FIRST.** ทุก agent (Claude Code / Codex) ต้องอ่านไฟล์นี้ก่อนเริ่มงานทุกครั้ง
ไฟล์นี้ **supersede** ทุกสรุปที่ agent เคยรายงานไว้ก่อน 2026-07-31 — agent ทุกตัว out of date

Verified against repo commit `19c49cf` (branch `p0/stg-sap-state`) + gcloud output 2026-07-31
**Deadline: July close = 2026-08-03 14:00 ICT**

> Tag ทุก claim: `[CONFIRMED]` = มีหลักฐานตรง อ้างได้ · `[OPEN]` = ยังไม่ปิด ห้ามอ้างเป็นข้อสรุป
> `[RETRACTED]` = เคยเขียนผิด ห้ามใช้ · `[WAITING HUMAN]` = ไม่ใช่งาน agent

---

# §1. LOCKED RULES (Boat confirmed 2026-07-31 — ห้าม re-litigate)

| ID | Rule | หมายเหตุ |
|---|---|---|
| **RULE-01** | `PaymentDate_effective = GREATEST(real_payment_date, open_period_start)` | payment จริง 20/06/2026 → ส่ง `01072026` เมื่อเลย closing period แล้ว · payment จริงที่อยู่ใน open period → ใช้ค่าจริง |
| **RULE-02** | `BatchRunDate = last_day(open_period)` = **`31072026`** เสมอ สำหรับ open period | บัญชีใช้ BatchRunDate คลุมรอบบัญชี · SAP ไม่มี cancellation date จึงใช้ BatchRunDate แทน |
| **RULE-03** | Q3a multi-DocEntry ใน period เดียวกัน → **ตัวล่าสุด** โดยใช้ `UpdateDate DESC, UpdateTime DESC` **ห้ามใช้ `BatchRunDate`** | Aware confirm 2026-07-31 · **เก็บชั้น status และชั้น InvoiceNo ไว้** (Paid แล้วไม่กลับเป็น Pending ได้) |
| **RULE-04** | `Cancelled` = **terminal** — order ที่ Cancelled แล้วห้าม re-interface | ตรงกับ R6 ในกฎธุรกิจเดิม |
| **RULE-05** | Scope 2026-08-03 = **(ก) + (ค) + (ง)** · **(ข) SLIP** | ดู §1.1 |
| **RULE-06** | ใช้ **legacy `sap_view.*`** ห้าม cutover V3 ก่อน 08-03 | V3 ปัจจุบันผลิต interface file = 0 ไฟล์ |
| **RULE-07** | **Hold ทั้ง 01/08** ยังไม่นำเข้าจนกว่า InsuranceGroup ใหม่พร้อม | hard deadline 15/08 · ดีที่สุด 01/08 · กำลังดี 03/08 · ยังใช้ได้ 06/08 |
| **RULE-08** | เพิ่ม `payment_date_clamped BOOL` ใน staging | **ไม่เก็บ** `payment_date_original` — CareOS production คือ original |

## §1.1 Population นิยาม (RULE-05)
| กลุ่ม | นิยาม | สถานะ | ความเสี่ยง |
|---|---|---|---|
| **(ก)** | July transaction ที่ยังไม่เข้า SAP เลย | ✅ IN SCOPE | ต่ำ — posting ใหม่ ไม่แตะของเดิม |
| **(ค)** | ของเดือนก่อนที่ค้าง ย้ายมา July | ✅ IN SCOPE | กลาง — restamp → trigger amplification ต้องรู้จำนวนก่อน |
| **(ง)** | newpayment ที่ Pending บน SAP ต้องเป็น Paid ตาม PaymentDate จริง (ผ่าน RULE-01) | ✅ IN SCOPE | ต่ำ-กลาง — update status ไม่ใช่แก้ยอด |
| **(ข)** | รายการยอดผิด รวม CMI 002a / credit-shell 002b | 🔶 **SLIP** — หลัง 06/08 | **สูงสุด** — แก้เงินที่ post แล้ว ต้อง FA sign-off + GL check |

**Date basis ทั้งหมด = `PaymentDate`** (ไม่ใช่ `GREATEST(OrderDate, PolicyDate)` ที่เคยใช้)
**Format ทุก date field = `DDMMYYYY` 8 ตัว มี leading zero** (F3) — `31072026` ไม่ใช่ `2026-07-31`

## §1.2 Period lock — ต้องสร้าง ยังไม่มี `[OPEN]`
RULE-01/RULE-02 ต้องรู้ว่า period ล็อกหรือยัง แต่**ไม่มีที่เก็บในระบบเลย**
ต้องสร้าง `sap_period_lock (period, open_period_start, lock_datetime, locked_by, locked_at)`
→ Boat input เอง: `2026-07` → `open_period_start = 2026-07-01`, `lock_datetime = 2026-08-03 14:00 ICT`

---

# §2. 🔴 RULE-03 ไม่ใช่การแก้ ORDER BY บรรทัดเดียว — BLOCKER ที่ต้องรู้ก่อนสั่งงาน

**อ่านจากไฟล์จริงแล้ว: `sap_mirror_doc` ไม่ได้ project `UpdateDate` / `UpdateTime` เลยแม้แต่คอลัมน์เดียว**
(`024_sap_mirror_doc.sql` — SELECT DISTINCT list จบที่ `BatchRunDate`)
→ **`025` order by `UpdateDate`/`UpdateTime` ตอนนี้ไม่ได้ คอลัมน์ไม่มีอยู่**

## §2.1 และ RULE-02 **ทำลาย** dedup ของ `024` ที่ใช้อยู่
`024` dedup ด้วย:
```sql
ROW_NUMBER() OVER (PARTITION BY DocEntry
                   ORDER BY SAFE.PARSE_DATE('%d%m%Y', BatchRunDate) DESC)
```
เมื่อ RULE-02 บังคับให้ทุก record ใน open period ได้ `31072026` เหมือนกันหมด →
**`BatchRunDate` กลายเป็นค่าคงที่ → dedup นี้ non-deterministic ทันที**
→ การเปลี่ยนไป `UpdateDate DESC, UpdateTime DESC` **ไม่ใช่ตัวเลือก แต่ถูกบังคับโดย RULE-02**
สอดคล้องกับ STEP B ที่พบว่า key ที่ไม่มี `UpdateTime` ทิ้ง legitimate same-day state ไป **191 ตัว**
(297,413 → 297,604)

## §2.2 ⚠️ กับดักที่เคยทำ production ล่มจริง — ห้ามพลาดซ้ำ
`019_fix_column_reordering_bug.sql` บันทึกไว้ว่า **SAP import อ่านคอลัมน์ตาม POSITION ไม่ใช่ชื่อ header**
เคสจริง 2026-07-26: `SELECT * EXCEPT(PaymentDate), <expr> AS PaymentDate` ย้าย `PaymentDate` ไปท้าย
→ เลื่อนทุกคอลัมน์ถัดไป → NonMotor production run ล่ม

**ข้อบังคับเมื่อเพิ่มคอลัมน์ใน `024`:**
- ✅ เพิ่ม `UpdateDate`, `UpdateTime` เป็น **2 คอลัมน์สุดท้าย** ต่อจาก `BatchRunDate` เท่านั้น
- ✅ ต้องเพิ่มใน **ทั้ง 4 UNION branch** (`SAP_LIVE_2024`, `SAP_LIVE_2025`, `SAP_LIVE_2026`, `SAP_LIVE`) โดยลำดับคอลัมน์ **เหมือนกันเป๊ะทุก branch** (BigQuery `UNION ALL` จับคู่ตาม position)
- ✅ เก็บเป็น **native type** (`UpdateDate` = DATE, `UpdateTime` = INT64 รูปแบบ HHMM) **ห้าม format เป็น string** ไม่งั้น ordering ผิด
- 🚫 ห้ามแทรกกลาง ห้ามใช้ `SELECT * EXCEPT(...)` แล้วเติมกลับ

## §2.3 ลำดับที่ต้องทำ (3 ขั้น ห้ามข้าม)
```
1. 024: เพิ่ม UpdateDate + UpdateTime ท้าย select list ทั้ง 4 branch
        + เปลี่ยน dedup เป็น ORDER BY UpdateDate DESC, UpdateTime DESC, DocEntry DESC
        ⚠️ SELECT DISTINCT + คอลัมน์ใหม่ = grain เปลี่ยน → ต้องวัด row count ก่อน/หลัง
           คาดว่า +191 (ตาม STEP B) ถ้าเกินกว่านั้นมาก = มีอย่างอื่นผิด ต้องหยุด
2. 025: เปลี่ยนเฉพาะ tiebreaker ชั้น 3 (ชั้น 1–2 คงเดิมตาม RULE-03)
3. วัด delta แล้วรายงาน ก่อน deploy — ห้าม deploy พร้อมแก้
```

## §2.4 ORDER BY ใหม่ของ `025` (แทนที่บล็อกเดิมทั้งบล็อก)
```sql
      ROW_NUMBER() OVER (
        PARTITION BY U_OrderItem, U_Period
        ORDER BY
          -- ชั้น 1 — RULE-04: Cancelled terminal / Paid ไม่กลับเป็น Pending (คงเดิม)
          CASE WHEN TransactionStatus IN ('Cancelled', 'Cancelled (Change order / Rejected)') THEN 0
               WHEN TransactionStatus IN ('Paid', 'paid') THEN 1
               ELSE 2 END,
          -- ชั้น 2 — non-empty InvoiceNo ชนะ (คงเดิม)
          CASE WHEN IFNULL(U_InvoiceNo, '') != '' THEN 0 ELSE 1 END,
          -- ชั้น 3 — RULE-03: recency จาก UpdateDate/UpdateTime
          --   เดิม: SAFE.PARSE_TIMESTAMP('%d%m%Y', BatchRunDate) DESC  ← REMOVED
          --   เหตุผล: RULE-02 ทำให้ BatchRunDate เป็นค่าคงที่ใน open period (§2.1)
          UpdateDate DESC,
          UpdateTime DESC,
          -- ชั้น 4 — deterministic tiebreak สุดท้าย (คงเดิม)
          DocEntry DESC
      ) AS rn
```
และเปลี่ยน tag `resolution_confidence` — Aware ตอบแล้ว ไม่ใช่ provisional อีก:
```sql
    IF(docs_considered > 1, 'MULTI_DOC_RESOLVED_BY_RECENCY', 'UNAMBIGUOUS') AS resolution_confidence
```
🚫 **ห้ามลบ `docs_considered`** — ยังต้องใช้สังเกตการณ์ว่ามี multi-doc period กี่ตัว

## §2.5 Blast radius ที่ต้องเช็คก่อน deploy
Consumer ของ `sap_mirror_doc` / `sap_mirror_state` ที่ต้องตรวจว่าไม่พึ่ง column position:
`002_sp_refresh_sap_state` · `026_collapse_stg_sap_state_to_view` · `034_expected_state_exclusion_rules`
· `037_fix_expected_invoice_no_null_unsafe` · `038_orderitem_alias_and_adj_invoice_minting`
· `039_sap_correction_log_and_b1_pilot` · `041_pilot_shadow_corrections_*` · `042_sap_fa_verification`

---

# §3. VERIFIED INFRA STATE — 2026-07-31

## §3.1 `[CONFIRMED]` ปิดแล้ว
- **P0 credential rotation CLOSED**: `sap-db-password` version 2 created `2026-07-31T11:32:25` (enabled)
  · version 1 (created `2026-07-20T08:41:41`, ตัวที่ถูก exposed) → **STATE: disabled**
- **Extract ทำงานได้ด้วย password ใหม่**: execution `sap-extract-job-k95ws`
  1 chunk / **61,133 rows** / `caught_up=True` / watermark `2026-07-30T14:53:24 → 2026-07-31T11:34:33`
  output `gs://rcb-bronze-zone/SAP/production_database/Results2026_07_31_6fb20167.json`
- **Secret binding ทำถูกอยู่แล้ว ไม่ใช่ plaintext**: `SAP_DB_USER` / `SAP_DB_PASSWORD` ใช้
  `secretKeyRef key=latest` → rotation ไม่ต้อง redeploy/rebind (Job สร้าง container ใหม่ทุก execution)
- **`secretmanager.secretAccessor` ผูกที่ระดับ secret** (ไม่ใช่ per-version) → version ใหม่อ่านได้เอง
  และ**ไม่เกี่ยวกับ `run.invoker` ที่ยังค้าง**
- **Boat's project roles**: `bigquery.admin`, `cloudscheduler.admin`, `editor`, `secretmanager.viewer`
  + โดน `PERMISSION_DENIED` บน `run.jobs.setIamPolicy` → **หลักฐานว่า basic Editor ไม่ครอบ setIamPolicy**

## §3.2 `[CONFIRMED RESOLVED]` — scheduler OAuth fix verified end-to-end
Scheduler ถูกตั้งผิดตั้งแต่ `userUpdateTime=2026-07-17T03:44:51Z` และล่มทุกคืนตั้งแต่ 2026-07-22:
ใช้ OIDC ID token เรียก Cloud Run Admin API ซึ่งต้องใช้ OAuth access token. Cloud Run Job ไม่มี
HTTPS endpoint ของตัวเอง จึงต้องเรียก Admin API; `uri` เดิมถูกต้องและไม่ได้เปลี่ยน.

Boat แก้ 2026-07-31 โดยใช้ default compute SA:
```bash
gcloud scheduler jobs update http sap-extract-schedule \
  --location=asia-southeast1 --project=pacific-plating-282708 \
  --oauth-service-account-email="919786098205-compute@developer.gserviceaccount.com" \
  --oauth-token-scope="https://www.googleapis.com/auth/cloud-platform"
```
หลักฐานหลังแก้: `oidcToken` หาย, `oauthToken` ปรากฏ; scheduler log
`2026-07-31T14:16:30Z` คืน status 200. Execution `kqcjd` มี `RUN BY =
919786098205-compute@developer.gserviceaccount.com`; manual executions `k95ws`/`kcwbw` มี
`RUN BY = data@rabbit.co.th`, จึงใช้ RUN BY เป็น audit trail แยก automated/manual ได้.

การข้ามจาก 401 ไป 200 ยืนยันว่า IAM ไม่เคยเป็นตัวบล็อก: default compute SA มี `run.jobs.run`
ผ่าน `roles/editor` อยู่แล้ว. `run.invoker` สำหรับ `sap-bucket-csv@` ลดจาก P0 blocker เป็น **P3
hygiene** เพื่อสลับกลับไปใช้ SA ที่แคบกว่าในอนาคต.

**บทเรียนถาวร**: `401 UNAUTHENTICATED` = token/authentication; `403 PERMISSION_DENIED` = IAM.
สมมติฐานเดิมว่า 401 เกิดจาก IAM และคำทำนายว่าจะเจอ 403 หลังเปลี่ยน token ถูก retract.

## §3.3 `[APPLIED]` retryConfig เปลี่ยนแล้ว (`userUpdateTime 2026-07-31T05:24:34Z`)
`maxRetryDuration` `0s` → `600s` · เพิ่ม `retryCount: 3`
เหตุผล: retry ไม่จำกัด = เสี่ยงสั่ง execution ซ้ำ = amplification โดยตรง

## §3.4 `[NEW]` Infra ที่ไม่เคยมีในเอกสาร (จาก Aware)
- `172.25.25.2` = **SAP Terminal Server (RDP)** — เดิม repo มีแค่ `172.25.25.3` (SQL, `RCB_LIVE_DB:1433`)
- `\\SAP-B1-DBS\tmp\UAT2\RabbitUpload\Insurance_RCB` = **UAT2 interface upload path**
- **UAT2 = environment จริง ใช้ทดสอบได้** → G3 gate บังคับ dry-run เข้า UAT2 ก่อน production เสมอ
- `[OPEN]` **GAP**: เอกสารเรามีครบแค่ฝั่ง GCS (`gs://interface-file/<BU>/INSURANCE_RCB_*`)
  แต่**ไม่มีอะไรอธิบาย hop จาก GCS → Windows share นี้** ใครทำ ทำเมื่อไหร่ → ต้องถาม Aware
- 🚫 **ห้ามเขียน username / credential ใดๆ ลง repo** — เก็บที่ Secret Manager / access register นอก repo

## §3.5 `[CONFIRMED]` Interface contract mapping ที่ต้องรู้
`RefundAmountBeforeFee` (interface column) = **`U_RefundAmt`** (SAP UDF)
— ยืนยันจาก DDL ของเราเอง (`007_sap_live_full_all_bu.sql`, `024_sap_mirror_doc.sql`)
→ แผนทดสอบ "Refund Amount to Insurer" จะเขียนลง `U_RefundAmt` ซึ่งเดิมหมายถึง refund ให้**ลูกค้า**
→ `[OPEN]` ต้องเช็ค usage ก่อนส่งไฟล์ UAT2: ถ้า `U_RefundAmt` มีข้อมูลอยู่แล้ว = ฟิลด์เดียวสองความหมาย
  ไม่มี discriminator → reconcile ย้อนหลังไม่ได้ถาวร → ต้องขอฟิลด์แยกจาก Aware
  **และรวมเข้ากับคำขอ cancel/refund date columns เป็น contract change ครั้งเดียว**

## §3.6 `[CONFIRMED]` Amplification มาเป็น burst ผูกกับ nightly interface import
Execution `k95ws` (manual, `2026-07-31T11:34:17Z`) ครอบคลุม window 20h41m และดึง 61,133 rows.
Execution `kqcjd` (scheduler, `2026-07-31T14:16:27Z`) ครอบคลุม window
`11:34:33Z–14:16:42Z` 2h42m และดึง **0 rows**, แต่ watermark ขยับและ `caught_up=True`.
จึง refute สมมติฐาน recurring SAP-side process ที่แตะ ~60K rows ต่อเนื่อง และ confirm ว่า ~60K
เป็น burst ผูกกับ nightly interface import cycle (`sap-order-payment` และ
`sap-order-payment-non-motor` เวลา 01:30 ICT / 18:30 UTC).

**rows=0 มีสองความหมาย ห้ามเหมารวม**:
- healthy: มี `success: N chunks, 0 rows`, watermark ขยับ, `caught_up=True`;
- login failure: `rows=0`, `chunks_processed=0`, watermark ไม่ขยับ และไม่มี `success:`
  (precedent: SQL Server login timeout 3 ครั้งเมื่อ 2026-07-28).

`[OPEN, non-urgent]` ตรวจว่า interface file มี ~60K rows จริงหรือไม่; ถ้าน้อยกว่ามากอาจมี SAP
recalculation cascade. `[OPEN]` DocEntry overlap test (31/07 vs 27/07) ไม่บล็อก July.
`[OPEN]` `WARNING: chunk got 61133 rows, exceeds threshold 20000` — เขียน 1 chunk ไม่ split
  → ไฟล์เดียว ~167MB · loader memory pressure · ไม่มี partial progress ถ้าล่มกลางทาง
`[OPEN]` SAP_LIVE row count / daily amplification table **stale** — เลข `8,324,155` ห้ามอ้าง.

## §3.7 `[CONFIRMED]` Extract freshness lag ~19 ชั่วโมงกระทบ July close
Nightly interface import เข้า SAP ประมาณ 01:30 ICT แต่ extract รัน 20:30 ICT. Reconcile ก่อน
deadline `2026-08-03 14:00 ICT` จะเห็น SAP state ล่าสุดเพียงรอบ 20:30 ICT ของ 02/08; ไฟล์ที่ส่ง
เช้า 03/08 จะยังไม่อยู่ใน mirror. `[WAITING HUMAN]` Boat ต้องเลือก manual extract ที่อนุมัติเฉพาะ
กิจหนึ่งรอบก่อน reconcile (แนะนำ) หรือเพิ่ม morning schedule ถาวร. ระหว่างยังไม่ตัดสินใจ
**ห้าม manual trigger** เพราะ automation ทำงานแล้วและการกดเพิ่มทำให้ amplification ซ้ำฟรี.

---

# §4. RETRACTED — ห้ามอ้างอีก (agent ทุกตัวต้องเลิกใช้)

| # | ข้อที่ต้องเลิกใช้ | แทนด้วย |
|---|---|---|
| R1 | "loader crash-loop อ่านไฟล์เดิมซ้ำ" เป็น root cause ของ amplification | watermark re-extract + plain-append loader (§3.6) |
| R2 | "มี unidentified SAP writer แก้ SAP production" | Boat ยืนยันว่าเป็น interface import ของ BI เอง |
| R3 | "ต้อง hold งานรอ Attila/run.invoker ก่อน scheduler ใช้ได้" | OAuth + default compute SA ทำงานแล้ว; run.invoker เหลือ P3 hygiene (§3.2) |
| R4 | "฿645.21 ตรงกับ pilot `L77828566` → อาจเป็น order เดียวกัน" | 645.21 = เบี้ย พ.ร.บ. มาตรฐาน ไม่ใช่ fingerprint ของ order |
| R5 | "SAP_LIVE bloat = 45×" | peak รายวันจริง ~2,036× (27/07) |
| R6 | "`gs://sap-bucket-csv` เป็นจุดเกิดปัญหา" | `gs://rcb-bronze-zone/SAP/production_database/` (bucket ชื่อนั้นไม่มีจริง) |
| R7 | ตัวเลข **559 / 71** | SUPERSEDED (posted-vs-rejected error + คำนวณจากอาการแทนสาเหตุ) |
| R8 | **401 = ปัญหา IAM** และคำทำนายว่าหลังแก้ token จะเจอ 403 | เปลี่ยน OIDC→OAuth แล้วได้ 200; IAM ไม่เคยเป็น blocker (§3.2) |
| R9 | "job ยังใช้ plaintext env var ต้อง rebind" | ใช้ `secretKeyRef key=latest` อยู่แล้ว ไม่ต้อง rebind (§3.1) |
| R10 | ขอ `roles/run.admin` / `run.jobs.update` เพิ่ม | ขัด policy บริษัท + ไม่มีหลักฐานว่าต้องแก้ binding ซ้ำ → ขอแค่ `run.invoker` |
| R11 | `attemptDeadline 180s` เสี่ยงสั่ง job ซ้ำ | overstated — endpoint `:run` คืนค่าเร็ว job รัน async |
| R12 | RULE-03 = แก้ ORDER BY บรรทัดเดียวใน `025` | ต้องแก้ `024` ก่อน (§2) — `UpdateDate`/`UpdateTime` ไม่มีใน `sap_mirror_doc` |
| R13 | Date basis = `GREATEST(OrderDate, PolicyDate)` สำหรับ July close | **`PaymentDate`** (RULE-01) |
| R14 | 401 = ปัญหา IAM ที่ Attila ต้องแก้อย่างเดียว | token type เป็น blocker จริง; OAuth ผ่าน end-to-end โดยไม่เปลี่ยน IAM |
| R15 | 401/71 · 401 orders / ฿267,775.28 / pilot `L77828566` เป็นข้อสรุป | BLOCK `5abaed3` ยังไม่ปิด — ห้ามอ้างเป็นตัวเลขจริง |

**หลักการ**: ข้อสรุปที่ "อธิบายได้สวย" คือตัวที่เสี่ยงที่สุด — ห้ามเลื่อนสถานะเป็น fact
ถ้ายังไม่มี Boat / FA / Aware ยืนยัน

---

# §5. LANE ASSIGNMENT (AGENT_TEAMING Rule 5)

| Lane | ขอบเขต |
|---|---|
| **Claude Code** | `sql/**`, `scripts/**`, `docs/sessions/**` · ทุกอย่างที่ต้อง query BigQuery / gcloud / deploy |
| **Codex** | `docs/**` (ยกเว้น `docs/sessions/**`), `CLAUDE.md`, `AGENT_RULES.md`, knowledge, changelog, review |
| **Boat** | architectural decision · requirement · FA/Aware/Attila coordination · gcloud ที่ต้องสิทธิ์เขา |

## §5.1 คำตอบเรื่อง lane ที่ Boat ถาม
- **`L80352060`** → **Claude Code ไม่ใช่ Codex** เพราะต้อง resolve จาก `sap_mirror_doc` + CareOS
  = query BigQuery ซึ่งอยู่นอก lane ของ Codex (Codex รายงานเองว่าไม่แตะ BigQuery object)
  Codex เข้ามาทีหลังเมื่อมีข้อสรุปให้บันทึก
- **`L78496990`** → `[WAITING HUMAN]` **Boat ทำเอง** จะมาอธิบายเพื่อสรุปเข้า knowledge
  🚫 agent ห้ามแตะ ห้ามเสนอตัวเลขแก้ไข
- **`DocEntry 2345730`** → `[WAITING HUMAN]` Boat ตรวจกับ FA บน UI

## §5.2 ข้อผิดพลาดของ agent ที่เกิดซ้ำ — ต้องระวัง
- Claude Code รายงาน review debt ผิด (บอก "6 OPEN, mine: 0" — จริง **8 OPEN, ตัวเองต้องรีวิว 6**)
- Claude Code บอก "all done" ตอนที่ repo ไปไกลกว่านั้นแล้ว 4 commits
- Claude Code หยุดผิดตาม Rule 5 (untracked file ที่ไม่ใช่ domain ตัวเอง = non-destructive ให้ report แล้วทำต่อ)
- Claude Code ล้ำเข้า domain Codex (`docs/`)
- Codex label timestamp ไม่ตรง git commit จริง **3 ครั้ง** (RQ-1530, RQ-1615, RQ-1800)
→ **ต้องอ่านไฟล์จริงยืนยันทุกครั้ง ห้ามเชื่อ agent summary**

---

# §6. OPEN ITEMS

## §6.1 บล็อก July close (2026-08-03 14:00)
| Pri | Item | Owner |
|---|---|---|
| P0 | สร้าง `sap_period_lock` + input `2026-07` (§1.2) | Claude Code + Boat |
| P0 | **G1: วัด population (ก)(ค)(ง) ก่อนแก้อะไร** (§7) | Claude Code |
| P0 | `024` เพิ่ม `UpdateDate`/`UpdateTime` + เปลี่ยน dedup (§2.3) | Claude Code |
| P0 | `025` เปลี่ยน tiebreaker ชั้น 3 + tag (§2.4) | Claude Code |
| P0 | วัด Q3a delta — **`InvoiceNo` เปลี่ยนกี่ key** (กระทบ R3 → cancel reject) | Claude Code |
| P1 | `payment_date_clamped BOOL` ใน staging (RULE-08) | Claude Code |
| CLOSED | Scheduler OIDC→OAuth (§3.2) — verified HTTP 200; automatic run แรกต้อง verify `2026-08-01T13:30:00Z` | Boat |

## §6.2 Track 2 — InsuranceGroup (hard deadline 15/08)
| Pri | Item | Owner |
|---|---|---|
| P1 | ดึง mapping logic จาก scheduled query `6914e2e2-0000-2f6b-afc8-c82add6cb068`<br>`bq show --transfer_config --format=prettyjson projects/919786098205/locations/asia-southeast1/transferConfigs/6914e2e2-0000-2f6b-afc8-c82add6cb068`<br>**ศึกษา logic/structure เท่านั้น ไม่ต้องใช้ query เดิม** | Claude Code |
| P1 | เพิ่ม InsuranceGroup ใหม่ใน design: Life, nonLife, Health, TA, PA, Home, Cancel, etc.<br>(แยกย่อยเพิ่มจาก Motor/NonMotor) มีผล transaction date ตั้งแต่ 1 Aug | Codex |
| P1 | **Hold register สำหรับ 01/08** — EXCLUDED ≠ DELETED ต้องนับได้ทุกวันว่าค้างเท่าไหร่ | Codex |

## §6.3 ค้างอยู่ ไม่บล็อก July (เตือนเรื่อยๆ ตามที่ Boat สั่ง)
| Item | Owner |
|---|---|
| `L80352060` — resolve กลไก | Claude Code |
| `L78496990` — อธิบาย + สรุปเข้า knowledge | **Boat** |
| CMI 002a BLOCK `5abaed3`: แยก sub-mechanism · เติม `042` schema · หา FA evidence | Claude Code |
| Review debt **8 OPEN** (Claude Code 6 / Codex 2) | ทั้งคู่ |
| `bq_safe_query.sh` fail-open parser (BLOCK RQ-1800) | Claude Code |
| `U_RefundAmt` usage check ก่อนทดสอบ UAT2 (§3.5) | Claude Code |
| `sap_mirror_doc` MERGE (แทน full CTAS) — cost ~100× | Claude Code |
| Migration `pacific-plating-282708` → `sap-b1-374202` (§C8 มี 6 คำถามรอ Boat) | Boat + Codex |
| GCS → Windows share hop ยังไม่มีเอกสาร (§3.4) | ถาม Aware |
| Interface contract change: refund field + cancel/refund date columns (F3 format) | ถาม Aware |
| Alert เมื่อ scheduler ไม่ใช่ 2xx (Boat สร้างเองได้ด้วย `editor`) | Boat |
| `run.invoker` grant — P3 hygiene เพื่อกลับไปใช้ narrow SA; ไม่บล็อก scheduler | Attila |
| เลือก manual extract ที่อนุมัติเฉพาะกิจก่อน reconcile 03/08 หรือ morning schedule ถาวร (§3.7) | Boat |
| Loader memory limit / chunk ไม่ split (§3.6) | Boat + Attila |

---

# §7. GATES — ห้ามข้าม

| Gate | เงื่อนไขผ่าน |
|---|---|
| **G1** | วัด population + Q3a delta ครบ **ก่อนแตะ SQL หรือสร้างไฟล์ใดๆ** |
| **G2** | RULE-01/02/03 ผ่าน review (Codex) ก่อน generate ไฟล์แรก |
| **G3** | Dry-run ไฟล์ 1 ชุดเข้า **UAT2** ก่อน production เสมอ — ตอนนี้มี UAT2 แล้ว ไม่มีเหตุผลจะข้าม |
| **G4** | ก่อน 08-03 14:00 — reconciliation ยืนยัน 0 MISSING · mismatch ≤ ±฿10 ต่อ order (aggregate ก่อนเทียบ ไม่ใช่ per row/period) |

## §7.1 G1 — 6 ตัวเลขที่ต้องวัด (ยังไม่ได้สั่ง รอ Boat confirm)
1. Population (ก) / (ค) / (ง) แต่ละกลุ่ม: กี่ record · กี่ order · ยอดรวม — **date basis = `PaymentDate`**
2. Q3a delta: กฎใหม่ vs กฎเดิม เปลี่ยน winner กี่ key
3. **ในนั้น `InvoiceNo` เปลี่ยนกี่ key** ← กระทบ R3 → cancel/adjustment reject ตรงๆ
4. `UpdateDate` / `UpdateTime` เป็น NULL กี่ key — โดยเฉพาะกลุ่ม undated ที่รู้อยู่แล้ว
   (45-row `SaleOrder` + 442 จาก 496 `Invoice` rows) **ถ้ากลุ่มนี้ NULL ด้วย กฎใหม่ก็แยกไม่ได้
   → ต้อง route เข้า human queue ไม่ auto-pick**
5. `024` row count ก่อน/หลังเพิ่มคอลัมน์ — คาด **+191** ถ้าเกินมากต้องหยุด (§2.3)
6. (ค) จะ restamp กี่ record = ประมาณ amplification ที่จะเกิด

## §7.2 กฎการทำงานที่บังคับตลอด
- ทุก query ต้องแนบ **query timestamp จริง** และ job ID — ห้ามแต่งขึ้น
- ทุกตัวเลขต้องระบุ source table + วันที่ดึง
- SAP truth source = **`sap_integration_v2.SAP_LIVE_FULL`** (`raw_sap_live` ไม่เคยมีอยู่)
- `SAP_LIVE` อยู่ใต้ **append-only hold** — ห้าม clean / dedup / truncate / delete (audit trail)
- ห้าม deploy พร้อมแก้ — แก้ → วัด → รายงาน → review → deploy
- ห้ามแตะ vendor-owned component (WireGuard tunnel · SAP pull cadence · SAP import program)
