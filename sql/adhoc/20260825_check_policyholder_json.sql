SELECT
  JSON_VALUE(data, '$.policyHolder.title') AS title,
  JSON_VALUE(data, '$.policyHolder.customerType') AS customerType,
  JSON_VALUE(data, '$.policyHolder.type') AS ph_type,
  JSON_VALUE(data, '$.policyHolder.isCompany') AS isCompany,
  JSON_VALUE(data, '$.policyHolder.companyName') AS companyName
FROM `pacific-plating-282708.careos.careos_orders`
WHERE human_id = 'L80512627'
