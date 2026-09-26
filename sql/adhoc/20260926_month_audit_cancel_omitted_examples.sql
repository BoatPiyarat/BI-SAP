SELECT o.source_view,o.OrderItem,o.period,o.invoice_no,o.TransactionStatus,d.order_created_at,d.cancel_time
FROM `pacific-plating-282708._script8bfe4ff9b4d90206402b9a2b5cf0ebb8e2883c49.cancel_output` o LEFT JOIN `pacific-plating-282708._script854956d6400364d5179432334ac884bec17498b8.dimensions` d ON d.order_item=o.OrderItem
WHERE o.OrderItem IN ('L79959262-V1','L80035402-V1','L80236849-V1','L80326899-V1','L80421949-1','L80489632-V1','L80517642-1') AND o.period=1
ORDER BY o.OrderItem,o.source_view,o.invoice_no;
