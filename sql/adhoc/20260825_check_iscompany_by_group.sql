SELECT
  human_id,
  JSON_VALUE(data, '$.policyHolder.isCompany') AS isCompany,
  JSON_VALUE(data, '$.policyHolder.companyName') AS companyName,
  'blank_title_1134' AS grp
FROM `pacific-plating-282708.careos.careos_orders`
WHERE human_id IN ('L77373437','L78675120','L77477877','L78787060','L77517974','L78390037','L78801567','L77481201','L78796702','L77394843','L78787744','L77667277','L77481188','L77629008','L77267823','L77274885','L78331619','L77511727','L78835717','L77577128')

UNION ALL

SELECT
  human_id,
  JSON_VALUE(data, '$.policyHolder.isCompany') AS isCompany,
  JSON_VALUE(data, '$.policyHolder.companyName') AS companyName,
  'individual_title_1134' AS grp
FROM `pacific-plating-282708.careos.careos_orders`
WHERE human_id IN ('L78636974','L78424522','L78494054','L78498797','L78493899','L77344699','L77357126','L77396293','L78623114','L77198914','L77282637','L77307405','L77310539','L77316612','L77318554','L77337074','L77370008','L78390343','L77335625','L78583167');
