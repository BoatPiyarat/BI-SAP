# Date basis — "ยอดขายนับตามวันไหน?"

The same order has up to six different dates. A month's "sales" changes a lot depending on which
one you pick.

**Evidence (pacific-plating, `analytics_reports.report_orders`, orders created 2026-01-05 →
2026-11-25, queried 2026-11-25 ~07:40 UTC):** of 153,278 orders, **54,868 (35.8%)** have a policy
start date in a *different calendar month* than the order-created date, and 4,538 (3.0%) were paid
in a different month than created. So "Nov sales by created date" and "Nov sales by policy start
date" are materially different numbers — always ask.

**Worked example — October 2026, gross premium net of cancellation, Motor+Health, excl. test
customers incl. 'test div' (`report_order_items`, pattern P2, re-queried 2026-11-25 ~09:30 UTC):**

| Counted by | Policies | Gross premium (฿) |
|---|---|---|
| Order created date | 18,958 | 182,550,094 |
| Payment date | 18,597 | 178,811,559 |
| Policy start date | 18,683 | 176,870,234 |
| Insurer approval date | 16,744 | 164,300,591 |

Same month, same data — a ฿18M (≈10%) spread between the highest and lowest basis. (Illustration of
the method only; not a certified monthly figure.)

## The dates

| Date | Column (report tables) | Raw source | Meaning (TH) | Who uses it |
|---|---|---|---|---|
| Order created | `report_order_items.create_at_date`, `report_orders.created_at_date` | `careos_orders.create_time` / `careos_order_items.create_time` | วันที่สร้างออร์เดอร์ในระบบ CareOS (ลูกค้าตกลงซื้อ/agent ปิดการขาย) | Sales team, agent daily performance, marketing conversion |
| Payment date | `report_order_items.paid_date`, `report_orders.paid_date` | `carepay_charges.payment_date` where `status='SUCCESSFUL'` | วันที่ลูกค้าชำระเงินสำเร็จ (งวดแรก / เต็มจำนวน) | Finance cash / collection, SAP interface (PaymentDate) |
| Policy start date | `policy_start_date` | `careos_order_items.policy_start_date` | วันที่ความคุ้มครองเริ่ม | **P&L / accounting revenue recognition**, renewal planning |
| Insurer approval date | `report_order_items.approval_time`, `report_orders.approved_date` | `careos_order_items.approval_time` | วันที่บริษัทประกันอนุมัติ / ออกกรมธรรม์ (policy uploaded) | **Insurer-side production / reconciliation with insurers** |
| Submitted to insurer | `submit_time` | `careos_order_items.submit_date` | วันที่ส่งงานให้บริษัทประกัน | Operations / back-office SLA |
| Cancellation date | `cancel_time`, `report_orders.cancellation_date` | `careos_order_items.cancel_time` | วันที่ยกเลิก | Cancellation & clawback analysis |
| Commission month | `commission_month` | `analytics_dimensional_modelling.dim_commission_months` | รอบ commission วันที่ 16 → 15 ของเดือนถัดไป (เช่น "Ending on Y2026 M11 D15" = 16 Oct–15 Nov 2026) | Agent commission, sales targets |
| Lead created | `report_leads.created_at_date` | CareOS leads | วันที่สร้างลีด | **Marketing** (orders attributed to the lead-created month), CR cohorts |
| QC approved | — (engine) | CareOS QC status | วันที่ QC ผ่าน | NonMotor commission gate (by the 18th) |

## How to explain the difference to a user (use this wording)

> ขึ้นอยู่กับว่าจะเอาตัวเลขไปใช้มุมไหนครับ/ค่ะ
> - **มุมทีมขาย / ผลงาน agent** → นับตาม *วันที่สร้างออร์เดอร์* เพราะสะท้อนวันที่ปิดการขายได้จริง
> - **มุมการเงิน / เงินเข้า** → นับตาม *วันที่ชำระเงิน* เพราะเป็นวันที่เงินเข้าบริษัทจริง (และเป็นวันที่ส่งเข้า SAP)
> - **มุมบัญชี P&L (รับรู้รายได้)** → นับตาม *policy start date* เพราะรายได้รับรู้เมื่อความคุ้มครองเริ่ม
> - **มุมบริษัทประกัน** → นับตาม *วันที่ประกันอนุมัติ (policy approve date)* เพราะประกันนับยอดผลิตจากกรมธรรม์ที่ออกแล้ว
> - **มุม commission** → นับตาม *รอบ commission (16–15)* ซึ่งไม่ตรงกับเดือนปฏิทิน
>
> ตัวเลขแต่ละแบบจึงไม่เท่ากันและไม่ผิดทั้งคู่ — สำคัญที่ต้องระบุให้ชัดว่าใช้แบบไหน

## Traps

- **Calendar month ≠ commission month.** "ยอดเดือนพฤศจิกายน" for the sales team often means the
  commission month ending 15 Nov. Ask.
- **Policy start can be in the future.** Orders created this month for renewals often start next
  month. A "this month by policy start date" number will grow after month-end.
- **Approval date is NULL until the insurer approves** (≈13% of 2026 orders in `report_orders`
  have no `approved_date` yet). Counting by approval date excludes pending work — say so.
- **Installment (RCL) orders have many payment dates.** `paid_date` in report tables is the
  first/qualifying payment; per-installment cash is in `careos.carepay_charges` (one row per charge).
- **"Sales" for commission uses two dates at once** — paid in the cycle *and* submitted (Motor) / QC'd
  (NonMotor) by the cut-off. It will not match any single-date report. See `domain_commission.md`.
- **SAP posting date ≠ payment date** after month close (moved to the 1st of next open period).
- **Time zone — two different conventions (measured 2026-11-25):**
  - **CareOS order/item timestamps** (`careos_orders`, `careos_order_items`, and the `report_*` tables built
    from them: `create_time`, `approval_time`, `cancel_time`, `policy_start_date`, `created_at_timestamp`)
    already hold **Bangkok wall-clock time** even though typed TIMESTAMP (the latest order showed ~7 h *ahead*
    of real UTC). Use `DATE(ts)` — **do not** convert again (converting moved 20% of Nov-2026 items to the wrong day).
  - **CarePay timestamps** (`carepay_charges.payment_date`, `create_time`) are **true UTC** → use
    `DATE(ts, 'Asia/Bangkok')`.
  - The commission engine uses `DATE(carepay_charges.payment_date)` without conversion, so payments made
    00:00–06:59 Bangkok may land on the previous day / week — ⚠️ reported to BI.
  - ⚠️ BI to confirm both conventions; they are evidence-based, not documented.
- **SAP / accounting close uses its own rules** (a payment in a closed accounting period is moved to
  the next open period). Never try to reproduce SAP posting dates — send the user to BI.
