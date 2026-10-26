-- Stage 2B: verify SAP-absent RCB NonMotor obligations in their owning legacy view.
-- Read-only; candidate list comes from event-assurance-20260910-173140.
WITH candidates AS (
  SELECT * FROM UNNEST([
    STRUCT('L78638675-1' AS OrderItem, 1 AS Period, 'chrg_68ms2ck8k04homeroib' AS InvoiceNo),
    ('L80726568-1', 1, 'chrg_68tdm238qxfssex0f13'),
    ('L80776755-1', 1, 'chrg_68vro1aufsnkcknsi21'),
    ('L80742388-1', 1, 'chrg_68whk42yg2htwbbw3eo'),
    ('L79845317-1', 1, 'chrg_68x2su39udcxmrl9a8b'),
    ('L80369146-1', 1, 'chrg_68xn81c95f61fgbtz80'),
    ('L80800036-1', 1, 'chrg_68y5by3yt9g62ffnjj7'),
    ('L80824645-1', 1, 'chrg_68y5n133wev8zjejer3'),
    ('L80791314-1', 1, 'chrg_68yg9s07flggo3p1sa7'),
    ('L79362790-1', 1, 'chrg_68ygqe77r647i86qj2b'),
    ('L80835965-1', 1, 'chrg_68ygux71s4ppmjek56i'),
    ('L79288431-1', 1, 'chrg_68yi5oz3n8nj6d9qmbp'),
    ('L80680923-1', 1, 'chrg_68yisxs36iypc7s44p4'),
    ('L80674121-1', 1, 'chrg_68yit4av70ho21vs3zn'),
    ('L80814204-1', 1, 'chrg_68yk10t0ynr7l6gko7u')
  ])
),
view_rows AS (
  SELECT OrderItem, SAFE_CAST(Period AS INT64) AS Period,
    NULLIF(TRIM(InvoiceNo), '') AS InvoiceNo, TransactionStatus
  FROM `pacific-plating-282708.sap_view.RCB_NonMotor_process_1_create`
)
SELECT
  c.*,
  COUNT(v.OrderItem) AS key_rows,
  COUNTIF(v.InvoiceNo = c.InvoiceNo) AS exact_rows,
  ARRAY_AGG(DISTINCT v.InvoiceNo IGNORE NULLS ORDER BY v.InvoiceNo LIMIT 10) AS view_invoices,
  ARRAY_AGG(DISTINCT v.TransactionStatus IGNORE NULLS ORDER BY v.TransactionStatus LIMIT 10)
    AS view_statuses,
  IF(COUNTIF(v.InvoiceNo = c.InvoiceNo) > 0, 'IN_EXPECTED_VIEW', 'MISSING_FROM_EXPECTED_VIEW')
    AS view_assurance_status
FROM candidates AS c
LEFT JOIN view_rows AS v USING (OrderItem, Period)
GROUP BY c.OrderItem, c.Period, c.InvoiceNo
ORDER BY view_assurance_status, c.OrderItem;
