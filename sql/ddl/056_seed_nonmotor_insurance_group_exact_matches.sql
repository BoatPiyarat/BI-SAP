-- SOURCE ONLY / Class A configuration mutation. Do not apply without deploy approval.
-- Boat supplied the complete SAP InsuranceGroup master on 2026-08-03. Only exact case-sensitive source
-- literals in this list are approved. ERROR, missing, ambiguous, or any future unknown value remains
-- held by Unit 3 and is copied to the daily completeness notification with order_item.
-- SAP Business Unit Codes (reference only; not the RCB/RCL file role): Cancer BU-0010,
-- Corporate BU-0006, Health BU-0003, Home/Miscellaneous BU-0012, Inter BU-0004, Life BU-0005,
-- Motor BU-0001, Motorbike BU-0007, Personal Accident BU-0008, TA BU-0017.

MERGE `pacific-plating-282708.sap_integration_v3.insurance_group_registry` t
USING (
  SELECT * FROM UNNEST([
    STRUCT('nonmotor-health-rcb-20260801' AS mapping_id,'Health' AS source_insurance_group,
      'NONMOTOR' AS product_scope,'RCB' AS business_unit,'Health' AS sap_insurance_group),
    STRUCT('nonmotor-health-rcl-20260801','Health','NONMOTOR','RCL','Health'),
    STRUCT('nonmotor-life-rcb-20260801','Life','NONMOTOR','RCB','Life'),
    STRUCT('nonmotor-life-rcl-20260801','Life','NONMOTOR','RCL','Life'),
    STRUCT('nonmotor-cancer-rcb-20260803','Cancer','NONMOTOR','RCB','Cancer'),
    STRUCT('nonmotor-cancer-rcl-20260803','Cancer','NONMOTOR','RCL','Cancer'),
    STRUCT('nonmotor-corporate-rcb-20260803','Corporate','NONMOTOR','RCB','Corporate'),
    STRUCT('nonmotor-corporate-rcl-20260803','Corporate','NONMOTOR','RCL','Corporate'),
    STRUCT('nonmotor-home-rcb-20260803','Home','NONMOTOR','RCB','Home'),
    STRUCT('nonmotor-home-rcl-20260803','Home','NONMOTOR','RCL','Home'),
    STRUCT('nonmotor-inter-rcb-20260803','Inter','NONMOTOR','RCB','Inter'),
    STRUCT('nonmotor-inter-rcl-20260803','Inter','NONMOTOR','RCL','Inter'),
    STRUCT('nonmotor-miscellaneous-rcb-20260803','Miscellaneous','NONMOTOR','RCB','Miscellaneous'),
    STRUCT('nonmotor-miscellaneous-rcl-20260803','Miscellaneous','NONMOTOR','RCL','Miscellaneous'),
    STRUCT('nonmotor-motor-rcb-20260803','Motor','NONMOTOR','RCB','Motor'),
    STRUCT('nonmotor-motor-rcl-20260803','Motor','NONMOTOR','RCL','Motor'),
    STRUCT('nonmotor-motorbike-rcb-20260803','Motorbike','NONMOTOR','RCB','Motorbike'),
    STRUCT('nonmotor-motorbike-rcl-20260803','Motorbike','NONMOTOR','RCL','Motorbike'),
    STRUCT('nonmotor-personal-accident-rcb-20260803','Personal Accident','NONMOTOR','RCB','Personal Accident'),
    STRUCT('nonmotor-personal-accident-rcl-20260803','Personal Accident','NONMOTOR','RCL','Personal Accident'),
    STRUCT('nonmotor-ta-rcb-20260803','TA','NONMOTOR','RCB','TA'),
    STRUCT('nonmotor-ta-rcl-20260803','TA','NONMOTOR','RCL','TA')
  ])
) s
ON t.mapping_id=s.mapping_id
WHEN NOT MATCHED THEN INSERT (
  mapping_id,source_insurance_group,product_scope,business_unit,sap_insurance_group,
  effective_start,effective_end,approval_state,evidence_type,evidence_reference,
  approved_by,approved_at,created_at,retired_at,reason
) VALUES (
  s.mapping_id,s.source_insurance_group,s.product_scope,s.business_unit,s.sap_insurance_group,
  DATE '2026-08-01',NULL,'APPROVED','BUSINESS_BLUEPRINT_AND_LIVE_QUERY',
  'transferConfig/6914e2e2-0000-2f6b-afc8-c82add6cb068; Boat complete SAP master input 2026-08-03',
  'Boat',CURRENT_TIMESTAMP(),CURRENT_TIMESTAMP(),NULL,
  'Exact case-sensitive match between live NonMotor product_category and supplied SAP master; unknowns hold'
);
