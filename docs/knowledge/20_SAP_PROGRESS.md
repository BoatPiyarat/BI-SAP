# 20_SAP_PROGRESS.md
Last Updated: 2026-07-25 (cont'd, real export mechanism found) (overwrite ได้ — สถานะปัจจุบันเสมอ)
Overall: ~74% | โหมดปัจจุบัน: **P0 A2 fix ครบทั้ง 8 views แล้ว (live)** — เจอ+แก้ **year-hardcode gap ใน
sap_view.RCB_NonMotor_process_1_create** (0→95 แถวโผล่) — **dead-man's-switch deploy จริงแล้ว** (BQ
scheduled query 22:00 ICT ทุกวัน + failure email) — เจอ**การค้นพบใหญ่**: pipeline จริงคือ sap-extract-job
→ sap-order-payment-initial-phase → SAP_LIVE (ไม่ตรงกับที่ design docs สมมติ) — รอ Attila แก้ scheduler
IAM (401, ล่ม 3 คืน) — secret rotation: ตามคำสั่ง Boat ไม่ rotate ตอนนี้

---

## 🎯 REAL EXPORT MECHANISM FOUND — 2026-07-25 (Boat AFK, "fix missing from SAP" request)

Boat asked to fix the `MISSING_FROM_SAP` gap (48,993 order-periods, ~108M THB in 2026), run a
one-time backfill, and add it to the pipeline. Before touching anything that writes toward real
SAP, traced how `gs://interface-file/` (the bucket SAP actually pulls from hourly) really gets
fed - this had never been verified all session; every fix so far touched query *logic*, not the
actual export step.

**Found the real chain, finally**: Cloud Scheduler (`sap-order-payment` /
`sap-order-payment-non-motor`, confirmed healthy earlier tonight) → Pub/Sub topics
(`motor-order-payment-sap-interface` / `non-motor-order-payment-sap-interface`) → Cloud Functions
(`rcb-motor-order-payment-1` → `rcb-motor-order-payment-sap-bucket-1`, same 2-stage pattern for
NonMotor and ADB Motor) → `gs://interface-file/{RCB_MOTOR,RCB_NONMOTOR,ADB_MOTOR}/`. Confirmed via
real `EXTRACT`-type BigQuery jobs (not `EXPORT DATA` SQL - a different job type, missed on first
search): 61 extracts in the last 7 days, most recent hours before this check. **This pipeline is
alive and running regularly.** The bucket looking "empty" just now is the same ephemeral-file
pattern found earlier tonight for the bronze zone - files get pulled and consumed quickly, not a
sign of failure.

Along the way, also found (and ruled out as the actual export path) an **older, separate,
already-broken** pipeline: BigQuery scheduled queries `SQ_SAP_2025_new_create_order` /
`_cancelled_order` / `_credit_shell` / `_cancelled_change_order`, writing into
`SAP.SQ_sap_daily_order_payment`, refreshed by `truncate_sap_order_payment_table`. These use the
*old* non-RCL-prefixed views (`04_new order credit shell`, `03_cancel change orders`, etc.), not
tonight's `sap_view.RCB_Motor_process_*`. `SQ_SAP_2025_new_create_order`'s transfer config state is
literally `FAILED`, last touched 2026-06-17 - over a month stale. Not investigated further since
it's confirmed not the live path; flagged as another dead pipeline worth cleaning up eventually.

**The real finding, and it changes the whole picture**: there is **no equivalent automated export
for RCL (installment) at all** - checked the complete Cloud Functions list, nothing named
rcl-anything exists. RCB Motor, RCB NonMotor, and ADB Motor each have a real 2-stage
scheduler→function pipeline; RCL has nothing. This isn't a new discovery - it's exactly problem
**A7** from `SAP_INTERFACE_REDESIGN_V3.md` ("RCL flows ไม่มี daily scheduler... ทั้งสาย RCL เป็น
manual"), now empirically confirmed against real infrastructure rather than taken on faith. It
directly explains why `RABBIT_CARE_INSTALLMENT` was ~70% (34,434 of 48,993) of the
`MISSING_FROM_SAP` recon: **it's not a bug scattered across many queries - it's one missing piece
of automation.**

**Did not attempt the actual fix** (generate + push a real RCL export to `gs://interface-file/`,
or build new export automation) while Boat is AFK. This would be the single most consequential
action possible in this entire pipeline - it creates real records SAP will import - and:
1. There's no established RCL bucket-folder convention to follow (unlike RCB_MOTOR/RCB_NONMOTOR/
   ADB_MOTOR, which are established patterns)
2. A one-time backfill of 34,434 periods needs validation-stage review first (hard rule: "never
   bypass validation before export, no exceptions including urgent") - haven't built/wired
   sp_validate for this yet
3. This needs Boat's own review before anything real ships to SAP, full stop

**What's ready for Boat's decision, not yet built**: extending the RCB pattern to RCL - a new
Pub/Sub topic + Cloud Function (or reusing `sap_view.RCL_*` process views, already fixed/verified
tonight, as the source query) + a new Cloud Scheduler job, matching the existing 3-flow pattern.

## ✅ POLICY CONFIRMED + RECONCILIATION EMAIL SENT — 2026-07-25

**Boat's rule, confirmed**: once an order shows Paid periods then Cancelled in SAP, that's final -
never modify it. This resolves the open design question from the `stg_sap_state` repoint work
above - the 5 reverted `sap_view` views don't need "fixing," their current behavior (treat any
Cancelled-order signal as "leave alone") is already correct. What was actually needed instead was
a **reporting mechanism**, not automated correction.

Built `sql/adhoc/reconcile_careos_vs_sap_cancelled_installments.sql`: for cancelled installment
(RCL) orders, compares CareOS's real paid-period count against SAP's. Key finding while building
this: a cancel-send mirrors **every** period to `TransactionStatus = 'Cancelled'` (verified live,
e.g. `L78210940-V1` - all 6 periods show Cancelled regardless of real history) - so current status
can't tell you what was actually paid before cancellation. `U_InvoiceNo` can: it's only populated
once a period was actually invoiced, so "non-empty invoice among Cancelled periods" = "was paid
before cancellation." Credit Shell orders (`U_OrderID LIKE 'C#%'`) excluded - different
single-invoice-on-period-1 pattern, would otherwise look like hundreds of false positives.

**Results**: 1,072 cancelled installment orders checked, 85 mismatches. 58 are off by exactly 1
period - almost certainly the customer's last payment landing at/around cancellation time, not a
real gap. **6 show a genuine 2+ period gap** (up to 5 periods missing) - these are real and worth a
look: `L73727249`, `L74670396`, `L76394133` (5 periods each), `L73400356`, `L73683565`,
`L76993090` (2 periods each).

**Sent as a Gmail draft** to `rc_sap_interfaceresult@rabbit.co.th` (no direct-send tool available,
by design - draft is ready for Boat to review and send). Purely informational per the policy above -
no SAP/CareOS data touched.

---

## 🔥 IN-FLIGHT

1. **Cancel batch 21 items** — ตก 3 รอบ (root cause สุดท้าย: SAP เก็บหลาย doc ต่องวด + InvoiceNo ต้องตรง doc ปัจจุบัน)
   → v4 พร้อม (one-row-per-period, Paid priority) แต่**รอคำตอบ Aware Q3a ก่อนยิง** (spec inferred ส่งแล้ว)
   → ⚠️ business flag: ลูกค้าจ่ายงวดต่อหลัง CareOS cancel — รอ FA confirm intent (cancel+refund?)
2. **RCL new-payment quick fix (27 orders)** — หลักใหม่จาก Boat: **charge-driven full schedule**
   (charge ถึงงวดไหน เติม paid ถึงงวดนั้น, mirror งวดเดิมเป๊ะ InvoiceNo ห้ามแตะ) — query v3 พร้อม รอ sample run
3. **EDC batch 2 (~70 orders จาก list บัญชีชุด 2)** — รอบัญชี confirm channel mapping ธนาคารอื่นนอกจาก KBANK
4. **Secret Manager rebind + password rotation** — ⚠️ ค้างตั้งแต่ 16/07! plaintext ยังอยู่ใน job config
   และ password exposed แล้ว 2 ครั้ง — สถานะ: secret sap-db-password ยังไม่มี version, ขั้นตอนอยู่ใน chat/runbook

## ⏳ WAITING ON OTHERS

- Aware: confirm cancel import spec v0.9 (ส่งแล้ว — โดยเฉพาะ Q3a: หลาย doc ต่องวด อ้าง InvoiceNo ตัวไหน)
- บัญชี: (a) EDC channel matrix (b) Credit Shell = จ่ายครบงวดเดียว OK? (c) intent 21 cancel ที่จ่ายต่อหลังยกเลิก
- IT Leong: Credit Shell ไม่มี installment_details = by design หรือ bug + ขอ direct RCL field (ถามใน group แล้ว)
- Head of Products: COALESCE fix (INCIDENT-001) — ใช้ targeted ไปแล้ว 1 เคส (L80347249-M1 เข้า SAP 22/07)

## ✅ DONE เพิ่มจาก 16/07

- Scheduler self-trigger verified (20:30 ICT, SA sap-bucket-csv@) — Phase 6 automation ครบฝั่ง extract
- เจอ loader B1 = `auto_load_sap_data_in_bucket_to_bigquery` (Pub/Sub 01:00) → อธิบาย incident 07-14
- **ROOT CAUSE ใหญ่: SAP_LIVE/SAP_LIVE_FULL = stale mirror** (mirror comparison 23/07 ยืนยัน INVOICE_DIFF)
  → DECISION: raw_sap_live คือ SAP truth เดียว, sunset B1 (ดู 10_CONTEXT)
- Urgent batches เข้า SAP: 30 EDC + L80347249-M1 + L79189867-1 (self-resolved) + cancel 1 (L80391648-M1)
- EDC gap วินิจฉัยครบ: CREDIT_CARD_INSTALLMENT ไม่มี pipeline เจ้าของ (ตกร่อง 2 flow) — เจอ 2 list รวม ~100 orders
- InvoiceNo convention conflict ยืนยัน: '2_' prefix (BI, กัน collision) vs raw charge id (flow 21/07)
- **Design package v3 ครบ 6 ฉบับ** (REDESIGN / E2E / DATA_PREP / RUNBOOK / DASHBOARD / CANCEL_SPEC) — รอ review/decisions
- Delta-export gap ใน design ถูกจับได้จาก review ของ Boat (new payment Pending→Paid) → amend แล้ว + generalize เป็น charge-driven

## 🚧 P0 STATUS (2026-07-24 session — reauth done, verified against live BigQuery)

- ✅ `sap-interface-repo` ตั้งจริงแล้ว (local git, branch `p0/stg-sap-state`) ที่
  `.../02 SAP/Phase1.1/agentic_bootstrap/codex_bootstrap`
- ⚠️ **CORRECTION ใหญ่: `raw_sap_live` ไม่มีอยู่จริง** — Phase 6 B2 extract job ไม่เคย deploy จริงใน
  project นี้ (เป็นแค่แผนใน design docs) — Boat ยืนยัน: **`sap_integration_v2.SAP_LIVE_FULL` คือ SAP
  source จริงที่ใช้อยู่ตอนนี้** ตรงข้ามกับ hard rule เดิมใน AGENTS.md/CLAUDE.md ("SAP truth = raw_sap_live
  ONLY") ที่เขียนไว้ก่อนเช็คจริง — ต้อง**แก้ hard rule นี้ในสองไฟล์นั้นด้วย** (ยังไม่ได้แก้)
- ✅ Verified `SAP_LIVE_FULL` จริง (schema 56 คอลัมน์ ดึงมาแล้ว, ดู view definition ใน
  `sql/production/SAP_LIVE_FULL.sql`): union SAP_LIVE + SAP_LIVE_2024/2025/2026, dedup ด้วย DocEntry
  (ROW_NUMBER by BatchRunDate DESC) — แต่**ยังมี duplicate ที่ (U_OrderItem, U_Period) 328,071 keys
  (687,700/1,649,468 แถว = ~42%)** เพราะ dedup แค่ระดับ DocEntry ไม่ใช่ระดับ period — ตัวอย่างจริง:
  L73340138-V1 period 2 มีทั้งแถว Paid (DocEntry 750141) และ Cancelled (DocEntry 1005571) — ตรงกับ
  CANCEL_IMPORT_SPEC Q3a เป๊ะ
- ✅ TransactionStatus จริง: Paid 1,087,891 / Pending 432,840 / Cancelled 90,489 /
  Cancelled (Change order / Rejected) 38,248 — ตรงกับที่ design assume ไว้พอดี
- ✅ `sql/ddl/002_sp_refresh_sap_state.sql` — **แก้แล้ว** ให้ source จาก `SAP_LIVE_FULL` แทน
  `raw_sap_live`, dedup by (U_OrderItem, U_Period) priority Cancelled>Paid>Pending — ยังไม่รัน
  (ต้อง approve ก่อน — สร้าง dataset+ตารางใหม่ ไม่กระทบของเดิม)
- ✅ `sql/ddl/003_...` — **แผนเดิม (repoint SAP_LIVE_FULL) ตกไป** เพราะ SAP_LIVE_FULL คือ source จริง
  ไม่ใช่ mirror เก่าที่ต้องแทนที่ (ทำแบบเดิมจะ circular) — เช็คจริงแล้วพบว่ามีแค่ 2 consumer ที่แตะ
  SAP_LIVE_FULL (fully_paid's `sap_batchrun`, credit shell's `sap_cancelled`) และทั้งคู่ทำแค่
  `MAX(BatchRunDate)` ต่อ OrderID — **ไม่โดน duplicate bug จริง** (MAX กันซ้ำในตัวอยู่แล้ว) — เป็นแค่
  cleanup ไม่ใช่ live bug
- ✅ **A2 NULL-safe filter bug — ยืนยันจริง, แก้จริง, LIVE ใน BigQuery ทั้ง 8 views แล้ว (2026-07-24):**
  พบ `motor_item_type != 'MOTOR_TYPE_COMPULSORY'` แบบไม่กัน NULL ใน **9 views จริง** — เช็ค `sap_view`
  (12 views, nightly จริง) แยกต่างหาก: **สะอาด** เจอแค่ 1 จุดที่ใช้ `=` (safe) ไม่ต้องแก้
  ยืนยันด้วยข้อมูลจริง: `careos_order_items.motor_item_type` มี NULL 10,559 แถว ทุกแถวเป็น NonMotor
  → **Applied จริงแล้วทั้ง 8 views** (`CREATE OR REPLACE VIEW`, bq CLI, location asia-southeast1),
  ทุกตัวแถวเพิ่มขึ้น ไม่มีลดลง = ไม่มี regression:
  - `sap_dashboard_carepay_installment`: 631,487 → 665,388 (+33,901)
  - `RCL 04_new order credit shell`: 13,894 → 14,379 (+485)
  - `RCL 02_items_cancel`: 633,470 → 667,377 (+33,907)
  - `RCL 04_new order credit shell_all`: 51,884 → 52,696 (+812)
  - `RCL 04_new order credit shell new tunning`: 56,818 → 57,405 (+587)
  - `sap_fix_rcl_2025`: 2,625 → 2,759 (+134)
  - `sap_fixing_rcl`: 929,641 → 963,609 (+33,968)
  - `RCL_MOTOR`: 929,641 → 963,609 (+33,968, identical to sap_fixing_rcl — likely same underlying query,
    confirms these two are redundant copies of each other; not consolidated, Boat said fix + leave as-is)
  Boat's call: fix all 8 (not just the 2 confirmed-production ones), leave everything else about these
  files untouched (no consolidation of the redundant copies).
- ✅ **`sap_integration_v3.stg_sap_state` — สร้างจริงแล้วใน BigQuery** (dataset + `pipeline_run_log`
  ผ่าน `001`, proc `sp_refresh_sap_state` ผ่าน `002`, รันแล้วผ่าน `CALL`)
  → 1,649,468 แถวใน SAP_LIVE_FULL → **1,289,839 แถวหลัง dedup, 0 duplicate key เหลือ** (verified)
- ⏸️ **Secret rotation — Boat's call: keep it, don't rotate now.** Deferred, not forgotten.

## 🆘 NEW INCIDENT (found while rechecking scheduler health, 2026-07-24)

**Symptom**: `sap-extract-schedule` (Cloud Scheduler, fires 20:30 ICT daily, on time every night) —
the HTTP call it makes to trigger `sap-extract-job` fails every night with `401 UNAUTHENTICATED`.
Confirmed via Cloud Logging for 2026-07-22, 07-23, 07-24 — **3 nights running**. The Cloud Run job
executions that DID exist (05:40, 17:09, 01:17, 17:03, 03:53 UTC — all off-schedule) were someone
manually running `gcloud run jobs execute sap-extract-job` by hand to compensate, not the automation
working. `auto_load_sap_data_in_bucket_to_bigquery` (the B1 loader, Pub/Sub-triggered, 01:00 ICT) also
shows extra off-schedule triggers on the same days — consistent with the same person manually
re-running the downstream loader too after manually running the extract.

**Root cause**: `gcloud run jobs get-iam-policy sap-extract-job` returns an **empty policy** — the
`sap-bucket-csv@...` service account (the one Cloud Scheduler uses for its OIDC token) has no
`roles/run.invoker` binding on this job. It was granted 2026-07-15 (see 30_SAP_CHANGELOG.md) but is
gone now — never diagnosed why (redeploy resetting IAM? manual revert? not investigated further).

**Fix** (prepared, NOT applied — `data@rabbit.co.th` got `PERMISSION_DENIED` on `run.jobs.setIamPolicy`,
this needs someone with IAM admin on the project, i.e. Attila per 90_TEAM_CONTEXT.md):
```
gcloud run jobs add-iam-policy-binding sap-extract-job \
  --region=asia-southeast1 --project=pacific-plating-282708 \
  --member="serviceAccount:sap-bucket-csv@pacific-plating-282708.iam.gserviceaccount.com" \
  --role="roles/run.invoker"
```

**Other SAP scheduler jobs checked, all healthy** (blank status = success in Cloud Scheduler logs):
`sap-order-payment` (01:30 ICT), `sap-order-payment-non-motor` (01:30 ICT),
`auto_load_sap_data_in_bucket_to_bigquery` (01:00 ICT) — all firing on schedule, no errors.

**Lesson**: nobody noticed for 3 nights because someone was quietly running it manually - the "dead
man's switch" the design docs proposed (Page 1 / 22:00 alert) would have caught this on night one.
Worth prioritizing that alert.

## 🗺️ REAL ARCHITECTURE DISCOVERED (2026-07-24) — supersedes design docs' B1/B2 framing

While investigating the "is SAP_LIVE_FULL missing records" question, traced the actual live pipeline
end to end. It does **not** match REDESIGN_V3/10_SAP_CONTEXT's B1 (legacy CSV, sunset) vs B2 (Phase 6,
target `raw_sap_live`) story:

- `sap-extract-job` (Cloud Run Job, pyodbc → real SAP SQL Server `RCB_LIVE_DB`) genuinely runs, genuinely
  pulls real rows (confirmed via its own run logs, e.g. 47,888 rows in one run), and writes NDJSON to
  `gs://rcb-bronze-zone/SAP/production_database/`
- That GCS write triggers (Eventarc) the Cloud Run **service** `sap-order-payment-initial-phase`, which
  loads the rows into **`sap_integration_v2.SAP_LIVE`** and deletes the source file
- So **`SAP_LIVE` is the real, fresh, direct-from-SAP-DB table** — not a legacy stale mirror. It's been
  running since 2026-07-09, 14/14 runs SUCCESS, zero errors, watermark current to within ~15 min as of
  this session. `raw_sap_live` (the name in every design doc) was never built - the docs describe a plan,
  not what got deployed.
- `gs://sap-bucket-csv` (the vendor CSV-drop bucket the docs describe) **does not exist in this project.**
- Practical implication: the scheduler incident above is more serious than "a redundant legacy path
  stalled" - it's the only ingestion path into fresh `SAP_LIVE` data. Data is fine because people have
  been running it manually; it would go stale if that stopped.

**Docs to eventually reconcile** (not done yet): 10_SAP_CONTEXT.md's B1/B2 section, REDESIGN_V3's
target architecture diagram, and the 2026-07-23 changelog's "SAP_LIVE_FULL = stale mirror" root-cause
entry all describe an architecture that isn't what's actually running.

## 🔍 sap_view COMPLETENESS AUDIT (2026-07-24) — "no CareOS charge silently dropped" check

Boat asked to verify the new `sap_view` production process (12 views: RCB/RCL × Motor/NonMotor ×
create/cancel/change/creditshell/newpayment) doesn't silently drop records. Pulled and read all 12,
plus 5 more upstream dependencies not yet examined this session (`04_new order credit shell`,
`03_cancel change orders`, `02_items_cancel`, `1_nonMotor_new order`, `2_nonMotor_items_cancel` -
distinct from the `RCL 04...`-prefixed ones already A2-fixed).

**Found and fixed**: `RCB_NonMotor_process_1_create` had `interface.OrderDate LIKE '%2025%'` hardcoded
into its WHERE clause. Since the anti-join against `SAP_LIVE_FULL` already restricts results to
"not yet in SAP," this date filter was pure leftover, not load-bearing - and it meant **every 2026-dated
NonMotor Health/Travel one-time order was silently excluded from ever being proposed for SAP creation**.
The view had been producing **zero rows for months** (checked: 0 before fix). Confirmed against real
data before fixing: ~3,097 `RCB_HEALTH` rows dated 2026, of which 91 were genuinely absent from SAP
(most of the rest apparently got there via manual intervention). Fixed (deleted the filter line),
applied live: **0 → 95 rows** now surfaced.

**Everything else checked out clean**: the other 11 `sap_view` views either have no date restriction or
an already-open-ended one (e.g. `RCL_Motor_process_4_creditshell` already says
`OrderDate LIKE '%2025%' OR LIKE '%2026%'` - will need `%2027%` added eventually, not urgent). The 5
additional dependency views checked for the A2 NULL-unsafe pattern - all clean.

**Not done**: a full formal reconciliation (charge-driven expected population vs. combined output of
all 12 views) - what's been done is a targeted read-through + spot-check, which is how this specific
bug was found. A full reconciliation would be a bigger, separate piece of work if more assurance is
wanted later.

## ✅ DEAD-MAN'S-SWITCH — deployed 2026-07-24

Built and deployed (see `sql/ddl/004_dead_mans_switch.sql`):
- `sap_integration_v3.vw_dead_mans_switch` — freshness check on `SAP_LIVE.U_BatchRunDate`
  (excludes ~5 anomalous future-dated rows found earlier, which would otherwise always read FRESH)
- `sap_integration_v3.sp_check_dead_mans_switch` — RAISEs if stale >26h
- BigQuery scheduled query "sap_dead_mans_switch", daily 15:00 UTC (22:00 ICT).
- **Recipients (settled)**: Boat asked for piyaratt@rabbit.co.th + rc_bi@rabbit.co.th. BQDTS native
  failure-email only supports one recipient (owner, data@rabbit.co.th) — left that on as a backup,
  added a real multi-recipient path via Cloud Monitoring: log-based metric
  `sap_dead_mans_switch_failure` → alert policy `SAP dead-man's-switch failure`
  (alertPolicies/2008919338975126785) → 2 email channels. **Verified end-to-end**: forced a test
  failure, confirmed via Monitoring API that the metric ingested it, reverted immediately. **Boat
  confirmed the test alert email actually arrived** — fully closed, nothing else to check here.

## 🔎 sap_view 6-OTHER-VIEWS USAGE CHECK — answered 2026-07-24

Checked 180-day BigQuery job history (query text, not just referenced_tables — that field only
captures underlying base tables for view queries, not the view name itself) for the 6 A2-fixed
views not on Boat's confirmed-production list:
- `RCL 04_new order credit shell_all` — used 2026-07-20 (4 days ago) by **you**
- `RCL 02_items_cancel` — used 2026-07-01 by **you + suphakornh@rabbit.co.th**
- `RCL_MOTOR` — used 2026-05-03 (~3 months ago) by you
- `RCL 04_new order credit shell new tunning`, `sap_fix_rcl_2025`, `sap_fixing_rcl` — **zero
  queries found in 180 days** — genuinely dead, candidates for eventual archival (not done, no
  action needed now — the A2 fix already applied to them is harmless either way)

## 🕵️ WHY THE IAM BINDING WAS MISSING — investigated 2026-07-24 (not a "disappeared" mystery)

Checked Cloud Audit Logs (60-day window) for every `SetIamPolicy` call referencing `sap-extract-job`.
Found exactly 2, both **DENIED**:
- 2026-07-13, via Cloud Shell (interactive) — someone (very likely Boat) already tried this exact
  `gcloud run jobs add-iam-policy-binding ... --role=roles/run.invoker` fix 11 days ago and hit the
  same `PERMISSION_DENIED` I hit tonight
- 2026-07-24 (tonight), my own attempt, same error

No successful `SetIamPolicy` call on this resource exists in the audit trail at all. Cross-checked
against the *working* pipeline (`sap-order-payment-initial-phase`, via Eventarc) - its trigger uses
`919786098205-compute@developer.gserviceaccount.com` (the project's default Compute service account,
likely with broad pre-existing permissions), **not** `sap-bucket-csv@...`. So this isn't a binding
that regressed - it most likely **never successfully applied in the first place**. The 2026-07-15
changelog entry ("Granted (Attila/DevOps): roles/run.invoker + roles/secretmanager.secretAccessor...
→ แก้ blocker scheduler self-trigger") most likely refers to the Secret Manager grant (which clearly
did work - the job successfully reads its DB credentials every run) - the `run.invoker` half appears
to have never gone through, silently, because whoever ran it (Boat, then me) lacked
`run.jobs.setIamPolicy` themselves. The pipeline "worked" anyway because everyone's been triggering
it manually with their own broader account permissions, which masked the scheduler-specific gap.

**Implication for Attila's fix**: this isn't "restore what was lost" - it's "grant this for the first
time," and it specifically requires his account (IAM Admin), not yours or mine.

## ⚠️ stg_sap_state REPOINT ATTEMPT — 2026-07-25 (partial success, one real bug caught + fixed)

Boat: wire `stg_sap_state` into real consumers instead of reading `SAP_LIVE_FULL` directly. Attempted
this across all 11 `sap_view` process views that reference `SAP_LIVE_FULL` (all of them except
`RCL_Motor_process_2_newpayment`, which doesn't touch it at all).

**Found two genuine, pre-existing bugs first** (unrelated to the repoint, hit while dry-running):
`RCL_Motor_process_3_cancel` and `RCL_NonMotor_process_2_newpayment` both reference
`U_EndorsementNo`, which doesn't exist (`SAP_LIVE_FULL`/`stg_sap_state` only have `EndorsementNo`,
no `U_` prefix) - **both queries wouldn't even parse**. These two views were completely broken
before tonight, silently. Fixed the column name in both (real bug fix, independent of source table).

**Repointed and verified 5 views as genuinely safe** (pure existence checks - "does this OrderItem
exist in SAP at all," no status filter - dedup can't change these results, confirmed by exact
zero row-count delta before/after): `RCB_NonMotor_process_1_create`, `RCL_NonMotor_process_1_create`,
`RCB_Motor_process_3_change`, `RCB_Motor_process_4_creditshell`, `RCB_NonMotor_process_2_cancel`.
**These are live on `stg_sap_state` now.**

**Caught a real bug before it did damage**: `RCB_Motor_process_create`'s row count jumped
1,579 → 16,578 after repointing - way too large to wave through. Sampled the new output: every row
was an order that had been **Paid, then later Cancelled**. `SAP_LIVE_FULL` kept both the historical
Paid row and the Cancelled row (its dedup is only by DocEntry), so this view's
`WHERE TransactionStatus IN ('Paid','paid')` check could still find "was this ever paid" evidence.
`stg_sap_state` collapses to one row per (OrderItem, Period) with Cancelled beating Paid by design -
so the same check now says "never paid," and the view wrongly proposed recreating 14,999
already-cancelled orders in SAP. **This would have been a real, damaging bug shipped straight into
the create-export pipeline if the count jump hadn't been sanity-checked.**

Given that, treated every non-zero-delta view as equally suspect (not just the confirmed one) and
**reverted 5 views back to `SAP_LIVE_FULL`**, since I couldn't verify their semantics were safe at
this hour with no one available to check: `RCB_Motor_process_create`, `RCL_Motor_process_1_create`,
`RCB_Motor_process_2_cancel_new`, `RCL_Motor_process_4_creditshell`, `RCL_Motor_process_3_cancel`
(this last one keeps its `EndorsementNo` fix - net improvement from completely-broken to working,
just on the original source). `RCL_NonMotor_process_2_newpayment` also stays on `SAP_LIVE_FULL`
(same `TransactionStatus IN Paid` risk pattern found in its `newpayment` CTE) with just its
column-name fix applied - went from broken to working.

**Net result**: 2 previously-broken views now work; 5 views now correctly deduped; 4 views
untouched in effect (reverted to their original behavior) pending a properly-designed fix. Verified
every final count against BigQuery directly before stopping - not just trusting the local files.

**What "properly-designed" would need**: any view that checks a specific status (e.g. "IN Paid") to
mean "already settled" needs a source that preserves *history*, not just current dominant status -
either keep reading `SAP_LIVE_FULL` for that specific check, or build a different dedup that
preserves "has ever been X" alongside "is currently X." Don't just swap the FROM clause on these 5
without that design work.

## ⬜ NEXT

1. **Get Attila to run the `run.invoker` fix** — active incident, 3+ nights and counting. Per the
   investigation above, this is a first-time grant, not a restore - only he can do it (you and I both
   confirmed lacking `run.jobs.setIamPolicy` ourselves)
2. ~~Investigate why the run.invoker binding disappeared~~ — **done above**
3. Decide dead-man's-switch email recipient (data@ vs personal vs Slack) — **done: piyaratt@ + rc_bi@ + data@, verified delivered**
4. Reconcile 10_SAP_CONTEXT.md / REDESIGN_V3.md architecture sections against the real pipeline found
   this session (SAP_LIVE fed by sap-extract-job → sap-order-payment-initial-phase, not B1/B2 as written)
   — **done, 2026-07-24**
5. Consider archiving the 3 genuinely-dead views (`RCL 04...new tunning`, `sap_fix_rcl_2025`,
   `sap_fixing_rcl`) — not urgent
6. **Design a real fix for the 5 reverted `sap_view` views** (see section above) before attempting the
   `stg_sap_state` repoint on them again - needs actual business input on what "already in SAP" should
   mean once an order's been through Paid→Cancelled, not a mechanical FROM-clause swap
7. P1–P4 ตาม migration plan ใน REDESIGN_V3 §4 / E2E §3 (ยังไม่แตะ) - now needs re-scoping given #4 above
8. If more assurance is wanted: full charge-driven completeness reconciliation across all 12 sap_view
   process views (not just the targeted read-through done this session)

## DECISIONS PENDING (จาก design review)

1. Orchestration: Cloud Workflows? 2. InvoiceNo standard (raw id + rank prefix) — บัญชี ack
3. ProcessingFee 100/103.3 (RCL) vs 100/107 (onetime) — ตัวไหนถูกต่อ flow ไหน (เจอ discrepancy ใหม่)
4. Backfill scope 5. EDC channel matrix 6. Parallel-run กี่วัน (เสนอ 5)
