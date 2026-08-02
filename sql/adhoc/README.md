# sql/adhoc
Query เฉพาะกิจที่ใช้ซ้ำ (จาก urgent sessions ก.ค. 2026):
- action_classifier.sql / gap_diagnostic.sql / mirror_comparison.sql
- quickfix_edc_onetime.sql / quickfix_rcl_newpayment_charge_driven.sql / cancel_resend_v4.sql
เก็บไว้เป็นจุดตั้งต้น — เป้าหมายระยะยาวคือแปลงเป็น stored procedures ตาม DATA_PREP_DESIGN
- `20260802_unit5_file_role_population_gate.sql`: split releasable events into CREATE/NEWPAYMENT
  and fail closed unless each CREATE order item has the exact `1..TotalPeriods` schedule spine.
- `20260802_unit5_payload_source_coverage.sql`: verify one contract-source variant per expanded
  CREATE/top-up/Pending row and per NEWPAYMENT event before building the 56-column shadow.
