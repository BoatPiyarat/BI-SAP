-- Stage 2A: verify SAP-absent RCB Motor obligations in their owning legacy view.
-- Read-only; candidate list comes from event-assurance-20260910-173140.
WITH candidates AS (
  SELECT * FROM UNNEST([
    STRUCT('L80822481-V1' AS OrderItem, 1 AS Period, 'chrg_68xv0010q7so946clx2' AS InvoiceNo),
    ('L78771539-M1', 1, 'chrg_68y13gptns7bucd6e3f'),
    ('L78771539-V1', 1, 'chrg_68y13gptns7bucd6e3f'),
    ('L78836864-V1', 1, 'chrg_68xqbxai8ch1ns8gdoc'),
    ('L78913168-V1', 1, 'chrg_68y4v192yluft6ixndl'),
    ('L78839783-V1', 1, 'chrg_68y1ldagxzd05un7497'),
    ('L78728862-V1', 1, 'chrg_68yeh2pdix50fn7aial'),
    ('L78786362-V1', 1, 'chrg_68yfxjoibtrjchz9mkl'),
    ('L80767558-M1', 1, 'chrg_68yh3tfcyb0b7bqjfyi'),
    ('L80767558-V1', 1, 'chrg_68yh3tfcyb0b7bqjfyi'),
    ('L78829687-M1', 1, 'chrg_68yhga6ebzckb4y8z5n'),
    ('L78829687-V1', 1, 'chrg_68yhga6ebzckb4y8z5n'),
    ('L80787253-V1', 1, 'chrg_68yi7cq80exgbzldkg8'),
    ('L78872605-V1', 1, 'chrg_68yiu3lh2pa13mhnkoc'),
    ('L78949211-M1', 1, 'chrg_68yjkpwxjbxmtnce8m8'),
    ('L78949211-V1', 1, 'chrg_68yjkpwxjbxmtnce8m8'),
    ('L78904966-V1', 1, 'chrg_68yjsqigpzkzl8sts4s'),
    ('L80830168-M1', 1, 'chrg_68yjco49s3xtzcyje82'),
    ('L80830168-V1', 1, 'chrg_68yjco49s3xtzcyje82'),
    ('L79131040-V1', 1, 'chrg_68yk707sb5x53q2mgig'),
    ('L80837829-V1', 1, 'chrg_68yjcd5ge93o31i1qeo'),
    ('L78877604-V1', 1, 'chrg_68yfpbu5d0ulkdwdvnr'),
    ('L80592168-M1', 1, 'chrg_68ykkk4q2yykn64lp1e'),
    ('L80592168-V1', 1, 'chrg_68ykkk4q2yykn64lp1e'),
    ('L80592857-V1', 1, 'chrg_68ykts3rh0yho96h0n2'),
    ('L78879371-M1', 1, 'chrg_68ykv5djqwovy0jfuqx'),
    ('L78879371-V1', 1, 'chrg_68ykv5djqwovy0jfuqx'),
    ('L80838182-V1', 1, 'chrg_68ykw2suwbq44dualsh'),
    ('L80800265-V1', 1, 'chrg_68yl14sj3rglmeyxfq6'),
    ('L78964863-V1', 1, 'chrg_68yl2sysgxjn6zs37qc'),
    ('L79331333-V1', 1, 'chrg_68yg34qrsmpgti3hd8j'),
    ('L78796009-V1', 1, 'chrg_68yl9upfjh1kkp6pr09'),
    ('L80760389-V1', 1, 'chrg_68ykdptck64mh90nbus'),
    ('L78836644-V1', 1, 'chrg_68yk1u1jp7ca3zx4l8r'),
    ('L78908827-M1', 1, 'chrg_68ylkw1l9z4i1sz4vpn'),
    ('L78908827-V1', 1, 'chrg_68ylkw1l9z4i1sz4vpn')
  ])
),
view_rows AS (
  SELECT OrderItem, SAFE_CAST(Period AS INT64) AS Period,
    NULLIF(TRIM(InvoiceNo), '') AS InvoiceNo, TransactionStatus
  FROM `pacific-plating-282708.sap_view.RCB_Motor_process_create`
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
