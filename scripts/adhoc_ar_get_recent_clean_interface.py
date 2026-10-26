import os
import pyodbc

USER = os.environ["RCB_DB_USER"]
PASSWORD = os.environ["RCB_DB_PASSWORD"]
conn_str = f"DRIVER={{SQL Server}};SERVER=172.25.25.3,1433;DATABASE=RCB_LIVE_DB;UID={USER};PWD={PASSWORD};"
conn = pyodbc.connect(conn_str, timeout=30)
cur = conn.cursor()

for oi in ["L78772038-V1"]:
    cur.execute("""
        SELECT U_OrderItem, U_ExpectedReceived, U_ActualReceived, U_TotalAmount,
               U_Discount, U_ProcessingFee, U_ProcessingFeeVat, U_ShippingFee, U_ShippingFeeVat,
               U_PaymentMethod, U_PaymentChannel, U_BatchRunDate, U_PaymentStatus
        FROM [dbo].[@INSURANCE] WHERE U_OrderItem = ?
    """, oi)
    cols = [d[0] for d in cur.description]
    for row in cur.fetchall():
        print(f"--- {oi} ---")
        for c, v in zip(cols, row):
            print(f"{c}: {v}")
    print("\nfull JE:")
    cur.execute("""
        SELECT j.Account, a.AcctName, j.Debit, j.Credit
        FROM JDT1 j LEFT JOIN OACT a ON a.AcctCode = j.Account
        WHERE j.LineMemo LIKE ?
        ORDER BY j.Line_ID
    """, f"{oi}_%")
    for row in cur.fetchall():
        print(row)

cur.close()
conn.close()
