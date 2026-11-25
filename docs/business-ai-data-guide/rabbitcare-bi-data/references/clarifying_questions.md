# Clarifying-question bank

Harvested from how BI actually answers requests (Teams / email, Nov 2025 – Nov 2026). Asking the
first three questions removes most of the back-and-forth BI sees today.

## The core three (ask before almost any number)

1. **หน่วยนับ** — "ต้องการ *ยอดเงิน (เบี้ย)* หรือ *จำนวนออร์เดอร์* / จำนวนกรมธรรม์ / จำนวนคัน?"
   (BI's own most-used question: "จำนวนยอดขายหรือจำนวนออร์เดอร์คะ")
2. **ยกเลิก / change order** — "รวมหรือไม่รวมรายการที่ยกเลิก และออเดอร์ที่ยกเลิกเพื่อเปลี่ยนเป็นออเดอร์ใหม่ (change order)?"
3. **วันที่ + ชนิดเดือน** — "นับตามวันไหน (สร้างออร์เดอร์ / ชำระเงิน / เริ่มคุ้มครอง / ประกันอนุมัติ /
   แจ้งงานประกัน / เดือนที่สร้างลีด) และเป็น *เดือนปฏิทิน* หรือ *รอบคอม 16–15*?"

## Ask when relevant

| Trigger in the question | Ask |
|---|---|
| "ยอด", "เบี้ย", "premium", "GWP" | Gross (รวม VAT+อากร) / หลังหักส่วนลด / ยอดที่ลูกค้าชำระจริง / สุทธิหลังหักยกเลิก / net premium? |
| ผ่อน / installment / RCL | "ตาม order (ยอดเต็มสัญญา) หรือตามที่ลูกค้าจ่ายเข้ามาจริง?" |
| "Database", "Fresh", "Renew" | หมายถึง *lead type* หรือ *ทีมของ agent*? |
| team / agent / SV | ทีม ณ วันไหน — snapshot ของรอบ หรือทีมปัจจุบัน? รวมคนลาออก/ย้ายทีมไหม? |
| Motor | รวม พ.ร.บ. (CMI) ไหม? รวม Motorbike ไหม? |
| "Non-Motor" | Health / Travel / PA / Life ตัวไหนบ้าง? |
| "ไม่ตรง", "ผิด" | ตัวเลขของคุณคือเท่าไร มาจากแหล่งไหน (dashboard หน้าไหน / ไฟล์ / Ads Manager) ขอ export หรือ screenshot |
| "วันนี้", "ล่าสุด" | ต้องการข้อมูล as-of เวลาไหน? (ข้อมูลรายวันอาจยังไม่ครบ — ดู freshness) |
| CR / conversion | cohort ตามวันสร้างลีด หรือวันสร้างออร์เดอร์? online leads เท่านั้นไหม? window กี่เดือน? |
| RR / renewal rate | Motor หรือ Health? รวมสถานะ create ไหม? cohort เดือนหมดอายุไหน? |
| report ใหม่ / ประจำ | รูปแบบ, รอบ refresh, ผู้รับ — แล้วส่งให้ BI ทำเป็น report จริง |

## Department defaults (use as the *suggested* answer, still confirm)

| Department | Usual definition they mean |
|---|---|
| Marketing (performance / channel) | Orders attributed to the **lead-created month**; **fresh** premium only (renewal excluded); cost = leads × CPL; cancels excluded when stated. "Database" split = Retainer lead type + New leads handled by Database-team agents. |
| Accounting / Finance | **Payment date** basis; posting after month close → 1st of next open month (SAP rule); include change orders; distinguish amount per order vs actually received; per-installment due date. |
| Sales SV / managers | **Commission cycle 16th→15th**; premium = paid invoice price (after discount); SV metric = net after cancellations/clawbacks; team = cycle snapshot. |
| Operations / Submission | Per-insurer, submission / approval status; New vs Renewal flag. |
| Executives | GWP (gross premium) by order created date from `report_orders`, expects near-real-time — always state freshness. |

## Route elsewhere (not an analytics question)

- **Single-order lookups** ("เช็คออร์เดอร์ L… ให้หน่อย", voucher sent?) → CareOS / Operations.
- **Exception approvals** ("ขออนุโลม…") → approval chain by email; BI applies after approval.
- **Commission disputes** → the /commission portal request form (order number + expected calculation).
