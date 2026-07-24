# 30_SAP_CHANGELOG.md
Append-only — entry ใหม่บนสุด ห้ามลบ/แก้ของเก่า
(merge จาก SAP_CHANGELOG.md + SAP_CHANGELOG_2026-07-05-network.md เมื่อ 2026-07-16)

---

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
