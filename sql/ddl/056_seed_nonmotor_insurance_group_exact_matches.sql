-- SOURCE ONLY / Class A configuration mutation. Do not apply without deploy approval.
-- Boat supplied the SAP master on 2026-08-02. The linked live accounting query emits Health and
-- Life as exact master literals; Cancer, Home, ERROR, missing, and ambiguous values remain held.

MERGE `pacific-plating-282708.sap_integration_v3.insurance_group_registry` t
USING (
  SELECT * FROM UNNEST([
    STRUCT('nonmotor-health-rcb-20260801' mapping_id,'Health' source_insurance_group,
      'NONMOTOR' product_scope,'RCB' business_unit,'Health' sap_insurance_group),
    STRUCT('nonmotor-health-rcl-20260801','Health','NONMOTOR','RCL','Health'),
    STRUCT('nonmotor-life-rcb-20260801','Life','NONMOTOR','RCB','Life'),
    STRUCT('nonmotor-life-rcl-20260801','Life','NONMOTOR','RCL','Life')
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
  'transferConfig/6914e2e2-0000-2f6b-afc8-c82add6cb068; Boat master input 2026-08-02',
  'Boat',CURRENT_TIMESTAMP(),CURRENT_TIMESTAMP(),NULL,
  'Exact case-sensitive match between live NonMotor product_category and supplied SAP master'
);
