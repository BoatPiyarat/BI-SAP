# Playbook: brand-new questions

Users of this skill design new projects. Their questions often have **no existing metric**.
Do not refuse and do not guess — turn the question into a definition first.

## Step 1 — Restate as a metric spec and get a "yes"

Write back, in the user's language, a short spec:

```
คำถาม:       <the user's question in one line>
ตัวชี้วัด:    <numerator> ÷ <denominator>  (or SUM/COUNT of …)
หน่วยนับ:    order / policy (item) / customer / lead / charge
ช่วงเวลา:    <dates>, นับตาม <date basis>
ขอบเขต:     product, channel, insurer, include/exclude cancelled, exclude test customers
แหล่งข้อมูล: <tables from tables.md>
สมมติฐาน:   <every assumption, numbered>
```

Ask: "ถูกต้องตามที่ต้องการไหม หรือมีจุดไหนต้องปรับ?" Only build after confirmation.

## Step 2 — Pick the grain before joining

Most wrong "new" numbers are join fan-outs. Decide the grain (one row per order? per item? per
customer? per lead?) and aggregate each table **to that grain before joining**. After the join,
check `COUNT(*)` equals `COUNT(DISTINCT grain_key)`.

## Step 3 — Prototype small, then scale

1. Dry-run. 2. Run on one month. 3. Spot-check 5 real rows (IDs only, no PII) against the
expected logic. 4. Run the full period.

## Step 4 — Report honestly

- Label: **"Exploratory — not a certified BI number"**.
- List assumptions and known gaps (NULL dates, pending approvals, data starting 2022-12-19).
- If the metric will be reused, end with: "ถ้าจะใช้ตัวเลขนี้ต่อเนื่อง แนะนำให้ส่ง definition นี้ให้ทีม BI
  เพื่อทำเป็น certified metric" and give the spec block so the user can forward it.

## Common new-question shapes and how to approach them

| Shape | Approach |
|---|---|
| "ลูกค้ากลุ่ม X ซื้อซ้ำไหม" (retention / repeat) | Grain = customer (`customer_id`); define the repeat window; renewals vs new purchases. |
| "ช่องทางไหนคุ้มที่สุด" (channel ROI) | Leads & spend from marketing reports, orders from report_order_items, same date basis & cohort. Spend data coverage ⚠️ — confirm with BI. |
| "ถ้าให้ส่วนลด Y% จะเกิดอะไรขึ้น" (what-if) | Build baseline from data, put the scenario math in a separate clearly-labelled step; never mix assumptions into the base query. |
| "ระยะเวลาตั้งแต่ … ถึง …" (lead time / SLA) | Use two timestamps on the same grain, convert both to Asia/Bangkok, report median and P90, not only average. Exclude NULL end-dates and say how many. |
| "ยอดของบริษัทประกัน X เทียบกับรายงานของเขา" | Use approval date basis; flag that insurer reports may follow their own cut-off. Reconciliation → BI. |
