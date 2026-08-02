-- SOURCE ONLY / Class A config seed. V2 CASE literals cross-checked against SAP-success history.
-- Non-credit only. Credit-shell remains held until cancel ACK and its dedicated mapping decision.
MERGE `pacific-plating-282708.sap_integration_v3.payment_mapping_registry` t
USING (
  SELECT * FROM UNNEST([
    STRUCT('pay-onetime-motor-cci-edc-bbl-20260801' AS mapping_id,'ONETIME' AS flow,'MOTOR' AS product_scope,FALSE AS is_credit_shell,'CREDIT_CARD_INSTALLMENT' AS payment_source_type,'EDC' AS payment_method_source,'BANGKOK_BANK' AS payment_channel_source,'EDC EDC' AS sap_payment_method,'RCB-EDC-BBL' AS sap_payment_channel),
    STRUCT('pay-onetime-motor-cci-edc-kbank-20260801','ONETIME','MOTOR',FALSE,'CREDIT_CARD_INSTALLMENT','EDC','KASIKORN','EDC EDC','RCB-EDC-KBANK'),
    STRUCT('pay-onetime-motor-cci-edc-bay-20260801','ONETIME','MOTOR',FALSE,'CREDIT_CARD_INSTALLMENT','EDC','KRUNGSRI','EDC EDC','RCB-EDC-BAY'),
    STRUCT('pay-onetime-motor-cci-edc-ktb-20260801','ONETIME','MOTOR',FALSE,'CREDIT_CARD_INSTALLMENT','EDC','KRUNGTHAI','EDC EDC','RCB-EDC-KTB'),
    STRUCT('pay-onetime-motor-cci-edc-uob-20260801','ONETIME','MOTOR',FALSE,'CREDIT_CARD_INSTALLMENT','EDC','UOB','EDC EDC','RCB-EDC-UOB'),
    STRUCT('pay-onetime-motor-cci-card-rcb-20260801','ONETIME','MOTOR',FALSE,'CREDIT_CARD_INSTALLMENT','ONLINECARD','RCB','OMC Omise Credit Card','RCB-Omise Credit Card-BAY'),
    STRUCT('pay-onetime-motor-cci-card-omise-20260801','ONETIME','MOTOR',FALSE,'CREDIT_CARD_INSTALLMENT','ONLINECARD','OMISE','OMC Omise Credit Card','RCB-Omise Credit Card-BAY'),
    STRUCT('pay-onetime-motor-full-trf-kbank-20260801','ONETIME','MOTOR',FALSE,'FULL_PAYMENT','BANK_TRANSFER','KASIKORN','TRF Transfer','RCB-Transfer-KBANK'),
    STRUCT('pay-onetime-motor-full-direct-20260801','ONETIME','MOTOR',FALSE,'FULL_PAYMENT','DIRECT_PAYMENT','SERVICE_PROVIDER_UNSPECIFIED','DPM จ่ายตรงกับบริษัทประกัน','RCB-DIRECT PAYMENT'),
    STRUCT('pay-onetime-motor-full-qr-20260801','ONETIME','MOTOR',FALSE,'FULL_PAYMENT','QR_CODE','RABBIT_LENDING','OME Omise QR Prompt Pay','RCB-Omise QR Prompt Pay-BAY'),
    STRUCT('pay-rcl-motor-qr-20260801','RCL','MOTOR',FALSE,'RABBIT_CARE_INSTALLMENT','QR_CODE','RABBIT_LENDING','OME Omise QR Prompt Pay','RCL-Omise QR Prompt Pay-BAY'),
    STRUCT('pay-rcl-health-qr-20260801','RCL','NONMOTOR',FALSE,'RABBIT_CARE_INSTALLMENT','QR_CODE','RABBIT_LENDING','OME Omise QR Prompt Pay','RCL-Omise QR Prompt Pay-Health')
  ])
) s ON t.mapping_id=s.mapping_id
WHEN NOT MATCHED THEN INSERT (
  mapping_id,flow,product_scope,is_credit_shell,payment_source_type,payment_method_source,
  payment_channel_source,sap_payment_method,sap_payment_channel,effective_start,effective_end,
  approval_state,evidence_type,evidence_reference,approved_by,approved_at,created_at,retired_at,reason
) VALUES (s.mapping_id,s.flow,s.product_scope,s.is_credit_shell,s.payment_source_type,
  s.payment_method_source,s.payment_channel_source,s.sap_payment_method,s.sap_payment_channel,
  DATE '2026-08-01',NULL,'APPROVED','V2_CASE_AND_SAP_SUCCESS',
  'V2 fully-paid/installment CASE; bqjob_r3b81d5d95da429ab_0000019fc2d5d906_1',
  'Boat',CURRENT_TIMESTAMP(),CURRENT_TIMESTAMP(),NULL,
  'Existing V2 mapping retained for V3 non-credit daily processing');
