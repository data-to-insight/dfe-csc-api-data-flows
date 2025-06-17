from config import SQL_CONN_STR, USE_PARTIAL_PAYLOAD, SUPPLIER_KEY, API_ENDPOINT_LA
from auth import get_oauth_token
from db import update_partial_payloads, get_pending_records, update_api_success, update_api_failure
from api import process_batches
from utils import benchmark_section
import pyodbc
import json
from datetime import datetime
from utils import log_debug
from utils import announce_mode


@benchmark_section("main()")
def main():

    announce_mode()
    log_debug(f"Connecting to DB using: {SQL_CONN_STR}")
    try:
        conn = pyodbc.connect(SQL_CONN_STR, timeout=10)
    except Exception as e:
        print(f"Database connection failed: {e}")
        log_debug(f"Failed to connect DB or timeout occured.")
        return

    if USE_PARTIAL_PAYLOAD:
        
            update_partial_payloads(conn)
            log_debug("Partial payloads updated.")
        
    token = get_oauth_token()
    if not token:
        print("No token retrieved. Exiting.")
        return

    headers = {
        "Authorization": f"Bearer {token.strip()}",
        "Content-Type": "application/json",
        "SupplierKey": str(SUPPLIER_KEY).strip(),
        "User-Agent": "Microsoft PowerShell/6.0.0"
    }

    
    # DEBUG
    # construct the multiline string first
    header_preview = "\n".join(
        f"    {k}: {v if k != 'Authorization' else f'{v[:20]}...'}"
        for k, v in headers.items()
    )
    log_debug("Headers preview:\n" + header_preview)
    log_debug(f"API endpoint: {API_ENDPOINT_LA}")
    log_debug("\nFetching pending records from DB...")  
    
    cursor = conn.cursor()
    
    records = get_pending_records(cursor)
    log_debug(f"Fetched {len(records)} pending records.")  

    if not records:
        print("No pending records to send.")
        return

    print(f"Sending {len(records)} records...")
    log_debug("Beginning batch API submission...") 
    process_batches(records, headers, conn)

    conn.close()



