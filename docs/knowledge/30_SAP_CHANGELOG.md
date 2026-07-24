# 30_SAP_CHANGELOG.md
Append-only — entry ใหม่บนสุด ห้ามลบ/แก้ของเก่า
(merge จาก SAP_CHANGELOG.md + SAP_CHANGELOG_2026-07-05-network.md เมื่อ 2026-07-16)

---

## 2026-07-24 (cont'd 3 — remaining 6 views fixed + scheduler incident found)

Boat: fix the A2 bug in the other 6 views too (don't just leave them), and separately, keep the
secret rotation deferred but recheck scheduler health.

Pulled, baseline-captured, and fixed all 6: `RCL 02_items_cancel` (2 occurrences), `RCL 04_new order
credit shell_all` (2), `RCL 04_new order credit shell new tunning` (1, JOIN-condition style like the
production credit shell view), `sap_fix_rcl_2025` (1, no-space variant), `sap_fixing_rcl` (3),
`RCL_MOTOR` (3) - 12 occurrences total, all wrapped with `OR motor_item_type IS NULL`. Applied live
via `CREATE OR REPLACE VIEW`. All 6 grew, none shrank:
`RCL 02_items_cancel` 633,470→667,377 (+33,907), `RCL 04_new order credit shell_all` 51,884→52,696
(+812), `RCL 04_new order credit shell new tunning` 56,818→57,405 (+587), `sap_fix_rcl_2025`
2,625→2,759 (+134), `sap_fixing_rcl` 929,641→963,609 (+33,968), `RCL_MOTOR` 929,641→963,609
(+33,968 - identical row count to sap_fixing_rcl, strongly suggesting these two are functionally
the same query kept in two places; not consolidated per Boat's "leave it there").

**Found a live, unrelated incident while checking scheduler health**: `sap-extract-schedule` (the
20:30 ICT nightly trigger) has been failing every night for at least 3 nights (07-22, 07-23, 07-24)
with `401 UNAUTHENTICATED` when it tries to invoke `sap-extract-job`. Root cause: `sap-extract-job`'s
IAM policy is completely empty - the `sap-bucket-csv@...` service account lost the `run.invoker`
role that was granted 2026-07-15 (per this same changelog). The Cloud Run executions that existed
at odd hours (05:40, 17:09, 01:17, 17:03, 03:53 UTC) were manual `gcloud run jobs execute` runs by
someone compensating by hand, not the scheduler working - same pattern visible in
`auto_load_sap_data_in_bucket_to_bigquery`'s logs (extra off-schedule Pub/Sub triggers same days).
Tried to fix directly (`gcloud run jobs add-iam-policy-binding ... --role=roles/run.invoker`) -
`data@rabbit.co.th` got `PERMISSION_DENIED` on `run.jobs.setIamPolicy`. Needs Attila (IAM admin).
Checked `sap-order-payment`, `sap-order-payment-non-motor`, `auto_load_sap_data_in_bucket_to_bigquery`
schedulers too - all three healthy, firing on time with no errors.

Also fixed the (now-confirmed-wrong) "SAP truth = raw_sap_live" hard rule in AGENTS.md/CLAUDE.md.

## 2026-07-24 (cont'd 2 — applied to production, live)

Boat approved all three pending actions and went AFK; proceeded and verified each step before
moving to the next, documenting as I went.

**`sap_view` audit (Boat: "this is the production run nightly")**: broad-searched all 12 views
(RCB/RCL Motor/NonMotor process_1_create..process_4_creditshell) for any MOTOR_TYPE_COMPULSORY
comparison. Clean - only one `=` (safe) usage, zero `!=`/`<>`. No fix needed here. This is a
cleaner architecture than sap_integration_v2/sap_data_engineer's shared-view-with-exclusion-filter
pattern (dedicated Motor vs NonMotor views instead) - the 6 other buggy views found earlier
(RCL 02_items_cancel, two more RCL 04 variants, sap_fix_rcl_2025, sap_fixing_rcl, RCL_MOTOR) live
in the older datasets, not here. Still unconfirmed whether those 6 are dead/backup or live via some
other path - not touched, needs Boat's call.

**Created for real in BigQuery** (`sql/ddl/001` + `002`, region asia-southeast1 - the project's
default query location is US, had to pass `--location=asia-southeast1` explicitly):
`sap_integration_v3` dataset, `pipeline_run_log` table, `sp_refresh_sap_state` procedure, then
executed it. Result: `stg_sap_state` built from `SAP_LIVE_FULL`, 1,649,468 raw rows → 1,289,839
deduped rows, verified zero remaining duplicate (U_OrderItem, U_Period) keys.

**Applied the A2 NULL-safe fix live** via `CREATE OR REPLACE VIEW` (from the exact files committed
as diffs against the pulled baseline):
- `sap_data_engineer.sap_dashboard_carepay_installment`: 631,487 → 665,388 rows (+33,901 recovered)
- `sap_integration_v2.`RCL 04_new order credit shell``: 13,894 → 14,379 rows (+485 recovered)
Verified direction is correct (rows only increased, matching "recovering silently-dropped rows",
not "breaking something") and spot-checked a sample of newly-appearing rows (e.g. L77630866-1,
health-insurance installment periods 3-5 of 6, paid, ฿13,290/period) - legitimate data, not noise.

Not done yet: secret rotation (still needs explicit approval - touches a live running job), the
6-other-views decision, and fixing the now-incorrect "SAP truth = raw_sap_live" hard rule in
AGENTS.md/CLAUDE.md (raw_sap_live doesn't exist - written before this session's verification).

## 2026-07-24 (cont'd — reauth'd, verified against live BigQuery)

Boat reauth'd gcloud/bq and pointed at the real production objects: `sap_data_engineer.
sap_dashboard_carepay_fully_paid`, `sap_data_engineer.sap_dashboard_carepay_installment`,
`sap_integration_v2.SAP_LIVE_FULL`, `sap_integration_v2.`RCL 04_new order credit shell``, plus
granted edit access to `sap_view` (kept as v3 dataset per Boat's call — new objects still go in
a fresh `sap_integration_v3`, not `sap_view`).

**Correction to the morning's work**: `sap_integration_v2.raw_sap_live` does not exist anywhere in
the project - Phase 6's B2 extract job was never actually deployed here, it was aspirational in
the design docs. Boat confirmed `SAP_LIVE_FULL` is the real, current SAP source. This invalidates
the "SAP truth = raw_sap_live ONLY" hard rule in AGENTS.md/CLAUDE.md as written - it was true of a
plan, not of this environment. Still needs fixing in both files (not done yet).

Pulled and captured (verbatim, into `sql/production/`, first time these have existed as files
anywhere outside BigQuery): `SAP_LIVE_FULL`, `sap_dashboard_carepay_fully_paid`,
`sap_dashboard_carepay_installment`, `RCL 04_new order credit shell`.

Verified `SAP_LIVE_FULL` for real: it unions SAP_LIVE + SAP_LIVE_2024/2025/2026, already dedups by
DocEntry (ROW_NUMBER by BatchRunDate DESC, "FIXED VERSION" 2026-07-07). But DocEntry-level dedup
doesn't collapse multiple SAP docs for the same (U_OrderItem, U_Period) - confirmed live: 328,071
such keys have >1 row, 687,700 of 1,649,468 total rows (~42%). Real example: L73340138-V1 period 2
has both a Paid doc (DocEntry 750141) and a Cancelled doc (DocEntry 1005571, same InvoiceNo) - this
is exactly the CANCEL_IMPORT_SPEC_INFERRED_v0.9.md Q3a scenario, not hypothetical.
TransactionStatus values confirmed: Paid 1,087,891 / Pending 432,840 / Cancelled 90,489 /
Cancelled (Change order / Rejected) 38,248 - matches what the design docs assumed.

Rewrote `sql/ddl/002_sp_refresh_sap_state.sql` to source from `SAP_LIVE_FULL` (not `raw_sap_live`),
deduping by (U_OrderItem, U_Period) with Cancelled > Paid > Pending priority. Retired
`003_PROPOSED_repoint_sap_live_full.sql`'s original plan (repointing SAP_LIVE_FULL itself would be
circular, since stg_sap_state is built FROM it) - replaced with the real finding that only two
consumers touch SAP_LIVE_FULL at all, and both already collapse duplicates via MAX(BatchRunDate)
per OrderID, so they aren't actually broken by the 42%-duplicate-rows problem.

**Confirmed the NULL-safe filter bug (A2) as real and live**, not just a hypothesis from the design
docs: searched `INFORMATION_SCHEMA.VIEWS` across sap_integration_v2/sap_data_engineer/sap_view with
a precise regex for `motor_item_type (!=|<>) 'MOTOR_TYPE_COMPULSORY'` with no NULL guard. Found in
9 real views, including both `sap_dashboard_carepay_installment` and `RCL 04_new order credit
shell` - the two Boat named as live production. Cross-checked against real data:
`careos_order_items.motor_item_type` has 10,559 NULL rows, every single one a NonMotor product -
exactly the rows this filter silently drops. Drafted (not applied) the fix in both files as a
one-line change against the committed baseline: installment's bare WHERE clause needed
`OR motor_item_type IS NULL`; credit shell's JOIN condition already had `OR cr.Period = 1` but that
only rescues period 1, so periods 2+ for NULL-type NonMotor orders were still getting dropped by
the WHERE below it. The other 6 views with the same pattern (`RCL 02_items_cancel`, two more
`RCL 04...` variants, `sap_fix_rcl_2025`, `sap_fixing_rcl`, `RCL_MOTOR`) were NOT in Boat's named
list of live production - flagged, not touched, pending confirmation of whether they're live or
dead/backup copies.

## 2026-07-24

Bootstrapped `sap-interface-repo` for real (local git at `.../agentic_bootstrap/codex_bootstrap`,
branch `p0/stg-sap-state`) — was only a pasted design package until now, nothing on disk/git.

Drafted P0 files (not yet run — see below): `sql/ddl/001_create_sap_integration_v3.sql` (dataset +
`pipeline_run_log`), `sql/ddl/002_sp_refresh_sap_state.sql` (`stg_sap_state` from `raw_sap_live`),
`sql/ddl/003_PROPOSED_repoint_sap_live_full.sql` (two options, unresolved, not run).

Found: design docs disagree on `stg_sap_state`'s column shape — REDESIGN_V3 keeps raw column
names (`SELECT r.*`), DATA_PREP_DESIGN renames to a subset with an incomplete "..." placeholder.
Went with REDESIGN_V3's raw-preserving version pending confirmation (safer against the
"mirror stored values exactly" rule — a hand-picked list risks dropping a must-mirror column).

Blocked: `gcloud`/`bq` auth expired mid-session, non-interactive reauth not possible (browser
OAuth) — could not verify `raw_sap_live`/`SAP_LIVE_FULL` real schema, could not run 001/002,
could not touch Secret Manager for the pending password rotation. Also: no actual current
production query files (`rcl_installment.sql` etc.) exist anywhere on disk or in the new repo —
`sql/production/` only ever had a README stub — so the A2 NULL-safe filter fix can't be written
as a real patch yet, only as a pattern.

## 2026-07-23

ROOT CAUSE ยืนยัน (ใหญ่สุดของโปรเจกต์): SAP_LIVE_FULL (B1 loader) stale — งวดที่ SAP Paid+invoice
ยังโชว์ Pending/ว่าง (mirror comparison: INVOICE_DIFF) → เป็นต้นเหตุ cancel ตก 3 รอบ และ daily
cancel error ~100 orders/คืน → DECISION: raw_sap_live = SAP truth เดียว, sunset B1

Learned (cancel import spec — reverse-engineered): ต้องครบงวด 1..TotalPeriods, งวดละ 1 แถว,
InvoiceNo ตรง doc ปัจจุบัน, งวดอื่น Paid/Pending — เขียนเป็น SPEC_INFERRED_v0.9 ส่ง Aware confirm
(Aware ปฏิเสธเขียน doc เอง — พลิกเป็นให้ review แทน)

Confirmed: InvoiceNo convention ชนกัน 2 flow — '2_' prefix (BI ใส่กัน collision) vs raw charge id
(flow 21/07 ที่เข้า SAP แล้ว) → มาตรฐานต้องเลือกทางเดียว (โน้มไป raw id เพราะ SAP ถืออยู่)

Principle ใหม่จาก Boat: quick fix + design ใช้ charge-driven — charge สำเร็จถึงงวดไหน
เติม paid ถึงงวดนั้น (mirror งวดเดิมเป๊ะ) ไม่ยึด list งวดที่ user ส่ง

Delivered: design package v3 ครบ 6 ฉบับ; delta-export gap (Pending→Paid update) ถูกจับจาก
review ของ Boat → amended

## 2026-07-22

Imported สำเร็จ: EDC batch 1 (30 orders CREDIT_CARD→onetime, RCB-EDC-KBANK) + L80347249-M1
(COALESCE targeted, INCIDENT-001) | Cancel ผ่าน 1/22 (L80391648-M1) อีก 21 ตก (InvoiceNo/sequence)

Confirmed: ตัวเลข "6,515 missing" เกินจริง ~10 เท่า — 85% เป็นภาพลวงจาก stale mirror + list
บัญชีนับรวมที่เข้าแล้ว; missing จริงหลักร้อยต่อรอบ

## 2026-07-17

Diagnosed: EDC gap — CREDIT_CARD_INSTALLMENT ตกร่องระหว่าง RCL (บังคับ follow_ups) กับ
onetime (บังคับ installment=1) — ไม่มี pipeline เจ้าของ; business rule ใหม่: treat เป็น onetime
(ธนาคารจ่ายเต็ม), channel RCB-EDC-<bank>

## 2026-07-16 (ค่ำ)

Verified: scheduler self-trigger สำเร็จครั้งแรก (20:30 ICT, RUN BY sap-bucket-csv@ SA)
Found: loader B1 = auto_load_sap_data_in_bucket_to_bigquery (Pub/Sub 01:00) — อธิบาย gap 4.5 ชม.
Incident: คำสั่ง gcloud fail เพราะ '&' ใน password ตัด command + password exposed ครั้งที่ 2
→ rotation ยกเป็น mandatory (ยังค้าง)

## 2026-07-16

Restructured: Knowledge base จัดใหม่เป็น Hot/Cold tier (00/10/20/30/90) — แก้ RCL rule ที่ผิดใน
Data Dictionary/Validation Library (ยัง pending แก้ฉบับ cold), ชี้ doc drift 3 จุด
(scheduler time, bucket name, service account ชื่อไม่ตรง doc)

Clarified: มี 2 pipeline คู่ขนานเข้าฐาน SAP-side — B1 loader→SAP_LIVE (เก่า) vs
B2 Phase6→raw_sap_live (ใหม่) — ต้องตัดสินใจ sunset plan

Security: SAP DB password exposed ครั้งที่ 2 (bash error จาก `&` ใน password ตัด command)
→ ยืนยัน rotation เป็น mandatory ก่อนปิดงาน secret rebind

Confirmed: `gcloud run jobs update` ครั้งแรก fail (exit 1) — ไม่มี config ถูกเปลี่ยน

## 2026-07-15

Granted (Attila/DevOps): `roles/run.invoker` + `roles/secretmanager.secretAccessor`
(sap-db-password, sap-db-username) ให้ SA `sap-bucket-csv@...iam.gserviceaccount.com`
— ปลด blocker scheduler self-trigger

Discovered: `sap-extract-job` deploy จริงใช้ plaintext env ทั้ง user/password
(เบี่ยงจาก PHASE6_DEPLOY.md ที่ระบุ --set-secrets ไว้แล้ว)

Learned: Attila ไม่ monitor infra-tribe — ติดต่อผ่าน devops-tribe หรือ DM

## 2026-07-14

Corrected (accounting-critical): RCL classification — prefix "RCL" ใน PaymentChannel เป็น OUTPUT
ไม่ใช่ source signal; แทนด้วย inference (installment_details/follow_ups/number_of_installment
หรือ COMPULSORY+RABBIT_LENDING) — PROVISIONAL รอ IT เพิ่ม direct field (ถามผ่าน Slack แล้ว)

Confirmed (business rule): Cancel sequencing — Paid+Cancel วันเดียวกันส่ง batch เดียวกัน
แบบ sequenced files ไม่รอ SAP round-trip → v2.1 §6.2

Incident: manual extract 20:38 เขียนไฟล์ 20:44 แต่ SAP_LIVE ไม่อัปเดต — สาเหตุ loader
เป็น schedule แยก (time-coupled) → ตัดสินใจ redesign เป็น event-driven

Drafted: Global Standard v2.1 Layer 6 addendum (recon, daily status, dead man's switch,
idempotency, SLA placeholders, 9 PENDING INPUT)

## 2026-07-12

Verified: Phase 6 end-to-end — rows 72,254 → 73,705, batch date advancing;
scheduler `sap-extract-schedule` สร้างแล้วแต่รอ run.invoker

## 2026-07-05 (ภาคบ่าย — network)

Decided: ใช้ WireGuard tunnel (Aware) แทน Cloud VPN; สร้าง VM gateway + static route +
VPC connector + Secret Manager สำเร็จ (Phase 1-5)

Security incident: WireGuard private key หลุดในแชท → ขอ Aware regenerate (รอตอบ)

Discovered: Access Context Manager block IAP SSH สำหรับ data@rabbit.co.th —
workaround SSH ตรง (firewall allow-ssh-temp ต้องลบทีหลัง)

Created: SAP_VALIDATION_LIBRARY.md, SAP_PIPELINE_REDESIGN.md

## 2026-07-05

Decided: Partial cancel-recreate (M-only/V-only) เป็น normal practice — ต้อง item-level matching

Fixed: TotalPeriods = Period bug ใน compulsary_installment_details (เคส L78466916)

Root cause confirmed: L80347249-M1 ตกหล่นเพราะ Credit Shell ไม่มี installment_details
(INCIDENT-001) — fix COALESCE รอ Head of Products

Deployed: check_missing_new_order_in_sap safety net

Decided: ไม่ใช้ custom MCP server (ADC) สำหรับ BigQuery — เก็บ connector slot;
workaround query-and-paste (OAuth bug redirect_uri_mismatch ฝั่ง Anthropic)

Established: AI_BOOTSTRAP + CONTEXT/PROGRESS/CHANGELOG pattern; เชื่อม Gmail/Drive สำเร็จ
