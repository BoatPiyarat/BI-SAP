-- READ ONLY investigation. No mutation.
SELECT
  ts.id AS snapshot_id, ts.transaction_id, ts.number_of_installment, ts.create_time,
  (SELECT COUNT(*) FROM `pacific-plating-282708.careos.carepay_transaction_snapshot_installment_details` d
     WHERE d.snapshot_id = ts.id) AS installment_detail_rows,
  t.payment_option, t.status AS transaction_status
FROM `pacific-plating-282708.careos.carepay_transaction_snapshots` ts
JOIN `pacific-plating-282708.careos.carepay_transactions` t ON t.id = ts.transaction_id
WHERE ts.transaction_id = 'ba4d5146-bafe-4021-8914-416e5de1ac02'
ORDER BY ts.create_time;
