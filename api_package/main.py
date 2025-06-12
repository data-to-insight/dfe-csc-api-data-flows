import pyodbc
import logging
from .config import SQL_CONN_STR, SUPPLIER_KEY, USE_PARTIAL_PAYLOAD, API_ENDPOINT_LA
from .decorators import timed_section
from .db import get_pending_records
from .api import get_oauth_token, process_batches
from .payloads import generate_partial_payload, generate_deletion_payload
from .db import update_api_failure, update_api_success
from .logging import setup_logging

logger = logging.getLogger(__name__)

@timed_section("Full Script")
def main():
    """
    Orchestrate end-to-end payload generation and API submission.
    """
    logger.info("Starting pipeline...")

    logger.info(f"Connecting to DB using: {SQL_CONN_STR}")
    try:
        conn = pyodbc.connect(SQL_CONN_STR, timeout=10)
    except pyodbc.OperationalError as e:
        logger.error("Failed to connect to SQL Server.")
        logger.error(f"Details: {e}")
        return
    except Exception as e:
        logger.error("Unexpected error during DB connection.")
        logger.exception(e)
        return

    if USE_PARTIAL_PAYLOAD:
        logger.info("Generating partial payloads...")
        from .update import update_partial_payloads  # avoid circular import
        update_partial_payloads(conn)

    token = get_oauth_token()
    if not token:
        logger.error("No token retrieved. Exiting.")
        return

    headers = {
        "Authorization": f"Bearer {token.strip()}",
        "Content-Type": "application/json",
        "SupplierKey": str(SUPPLIER_KEY).strip(),
        "User-Agent": "Microsoft PowerShell/6.0.0"
    }

    logger.info("Headers prepared.")
    logger.info(f"Final API endpoint: {API_ENDPOINT_LA}")

    cursor = conn.cursor()
    records = get_pending_records(cursor)

    if not records:
        logger.info("No pending records.")
        return

    logger.info(f"Sending {len(records)} records...")
    process_batches(records, headers, conn)

    logger.info("Done.")
    conn.close()


if __name__ == "__main__":
    main()
