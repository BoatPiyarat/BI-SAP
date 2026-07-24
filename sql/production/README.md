# sql/production
วางไฟล์ production query ปัจจุบันที่นี่ (คนละไฟล์ต่อ flow) เพื่อให้ agent อ่าน/แก้เป็น diff ได้:
- rcl_installment.sql        (RCL 05 paid/newpayment — ตัวที่มี follow_ups bug)
- rcb_onetime_fully_paid.sql (sap_dashboard_carepay_fully_paid TUNED 2026-07-11)
- rcb_cancel_new.sql         (02 cancel-new TUNED 2026-07-07 — dup filter commented!)
- credit_shell_recursive.sql (RCL 04 ตัวใหม่ recursive chain)
หมายเหตุ: ไฟล์เหล่านี้อยู่ในแชท Claude ก่อนหน้า — copy จากที่รันจริงล่าสุดเสมอ
