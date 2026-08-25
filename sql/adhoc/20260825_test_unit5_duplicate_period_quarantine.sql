-- Offline BigQuery fixture for DDL 059's duplicate-period and retry-idempotency behavior.
CREATE TEMP TABLE identities AS
SELECT 'run' pipeline_run_id,'NEWPAYMENT' file_role,'L1-V1' order_item,2 period,
  'charge-a' charge_id,'same-invoice' invoice_no
UNION ALL
SELECT 'run','NEWPAYMENT','L1-V1',2,'charge-b','same-invoice';

CREATE TEMP TABLE payload AS
SELECT 'L1-V1' OrderItem,'2' Period,'same-invoice' InvoiceNo,
  '1870.00' ExpectedReceived,'1870.00' ActualReceived
UNION ALL
SELECT 'L1-V1','2','same-invoice','1870.00','1870.00';

INSERT INTO identities
VALUES ('run','NEWPAYMENT','L2-V1',3,'charge-c','invoice-c');
INSERT INTO payload
VALUES ('L2-V1','3','invoice-c','100.00','100.00'),
       ('L2-V1','3','unbound-extra-invoice','0.00','100.00');
INSERT INTO identities
VALUES ('run','NEWPAYMENT','L3-V1',4,'charge-d','same-invoice-d');
INSERT INTO payload
VALUES ('L3-V1','4','same-invoice-d','200.00','200.00'),
       ('L3-V1','4','same-invoice-d','200.00','200.00');
INSERT INTO identities
VALUES ('run','NEWPAYMENT','L4-V1',4,'charge-e','invoice-e');
INSERT INTO payload
VALUES ('L4-V1','4','invoice-e','300.00','300.00'),
       ('L4-V1','2','historical-a','300.00','300.00'),
       ('L4-V1','2','historical-b','0.00','300.00');

ASSERT (SELECT COUNT(*) FROM identities)=(
  SELECT COUNT(*) FROM identities i
  WHERE EXISTS (SELECT 1 FROM payload p
    WHERE p.OrderItem=i.order_item AND SAFE_CAST(p.Period AS INT64)=i.period
      AND p.InvoiceNo=i.invoice_no))
  AS 'identity conservation must count matched identities, not multiplied payload rows';

CREATE TEMP TABLE period_identity_count AS
SELECT order_item,period,COUNT(*) identity_count
FROM identities GROUP BY order_item,period;

CREATE TEMP TABLE payload_one AS
SELECT * EXCEPT(identity_rank)
FROM (
  SELECT p.*,ROW_NUMBER() OVER (
    PARTITION BY OrderItem,SAFE_CAST(Period AS INT64),InvoiceNo
    ORDER BY TO_JSON_STRING(p)) identity_rank
  FROM payload p)
WHERE identity_rank=1;

CREATE TEMP TABLE payload_period_count AS
SELECT OrderItem AS order_item,SAFE_CAST(Period AS INT64) AS period,COUNT(*) payload_count
FROM payload GROUP BY order_item,period;

CREATE TEMP TABLE payload_duplicate_item AS
SELECT DISTINCT order_item FROM payload_period_count WHERE payload_count>1;

CREATE TEMP TABLE holds AS
SELECT i.order_item,i.period,i.charge_id,i.invoice_no,
  'HOLD_MULTIPLE_PAYMENT_EVENTS_SAME_PERIOD' hold_code
FROM identities i
JOIN period_identity_count c USING(order_item,period)
LEFT JOIN payload_duplicate_item di USING(order_item)
JOIN payload_one p
  ON p.OrderItem=i.order_item AND SAFE_CAST(p.Period AS INT64)=i.period
 AND p.InvoiceNo=i.invoice_no
WHERE c.identity_count>1 OR di.order_item IS NOT NULL;

ASSERT (SELECT COUNT(*) FROM holds)=5
  AS 'identity and payload duplicate shapes must hold every bound charge identity';
ASSERT (SELECT COUNT(*) FROM (
  SELECT order_item,period,charge_id,COUNT(*) n
  FROM holds GROUP BY 1,2,3 HAVING n!=1))=0
  AS 'hold rows must remain unique at charge identity';
ASSERT (SELECT COUNT(DISTINCT order_item) FROM holds)=4
  AS 'duplicate-period quarantine must identify all four whole items';

CREATE TEMP TABLE notifications AS
SELECT 'run' pipeline_run_id,'HOLD_RECEIPT_BALANCE_MISMATCH' reason_code
UNION ALL SELECT 'run','HOLD_MULTIPLE_PAYMENT_EVENTS_SAME_PERIOD'
UNION ALL SELECT 'other-run','HOLD_MULTIPLE_PAYMENT_EVENTS_SAME_PERIOD';

DELETE FROM notifications
WHERE pipeline_run_id='run'
  AND reason_code IN
    ('HOLD_RECEIPT_BALANCE_MISMATCH','HOLD_MULTIPLE_PAYMENT_EVENTS_SAME_PERIOD');

ASSERT (SELECT COUNT(*) FROM notifications WHERE pipeline_run_id='run')=0
  AS 'retry cleanup must remove both Unit 5 notification codes';
ASSERT (SELECT COUNT(*) FROM notifications WHERE pipeline_run_id='other-run')=1
  AS 'retry cleanup must not touch another run';

SELECT 'PASS' AS fixture_status,5 AS held_identities,4 AS held_items;
