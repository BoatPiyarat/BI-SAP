-- READ ONLY. Check all snapshots for the transaction to see if a newer, complete snapshot
-- superseded an earlier empty one.
SELECT ts.id AS snapshot_id, ts.transaction_id, ts.number_of_installment, ts.update_time, ts.create_time,
  (SELECT COUNT(*) FROM `pacific-plating-282708.careos.carepay_transaction_snapshot_installment_details` d
     WHERE d.snapshot_id = ts.id) AS detail_row_count
FROM `pacific-plating-282708.careos.carepay_transaction_snapshots` ts
WHERE ts.transaction_id = '2b2e0899-6d8c-4a36-a00e-f6134449f8eb'
ORDER BY ts.update_time DESC, ts.id DESC;
