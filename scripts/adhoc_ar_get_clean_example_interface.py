import os
import pyodbc

USER = os.environ["RCB_DB_USER"]
PASSWORD = os.environ["RCB_DB_PASSWORD"]
conn_str = f"DRIVER={{SQL Server}};SERVER=172.25.25.3,1433;DATABASE=RCB_LIVE_DB;UID={USER};PWD={PASSWORD};"
conn = pyodbc.connect(conn_str, timeout=30)
cur = conn.cursor()

cur.execute("""
    SELECT U_OrderItem, U_OrderId, U_ExpectedReceived, U_ActualReceived, U_TotalAmount,
           U_Discount, U_ProcessingFee, U_ProcessingFeeVat, U_ShippingFee, U_ShippingFeeVat,
           U_PaymentMethod, U_PaymentChannel, U_BatchRunDate, U_PaymentStatus, U_TotalPeriods
    FROM [dbo].[@INSURANCE] WHERE U_OrderItem = 'L77161975-V1'
""")
cols = [d[0] for d in cur.description]
for row in cur.fetchall():
    for c, v in zip(cols, row):
        print(f"{c}: {v}")

cur.close()
conn.close()
