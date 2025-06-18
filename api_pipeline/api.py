import json
import re
import time
from datetime import datetime
import requests

from .config import BATCH_SIZE, API_ENDPOINT_LA
from .db import update_api_success, update_api_failure
from .utils import benchmark_section, log_debug


# ---- API ----
# PEP 484 signature:
# def process_batches(records: List[Dict[str, Any]], headers: Dict[str, str], conn: pyodbc.Connection, max_retries: int = 3) -> None:
@benchmark_section("process_batches()")  # Performance monitor
def process_batches(records, headers, conn, max_retries=3):
    """
    Submit payloads in batches to API with retry logic

    Args:
        records: List of dicts with 'person_id' and parsed JSON
        headers: HTTP headers for API call
        conn: Open database connection
        max_retries: Retry count before marking as failure
    """
    total = len(records)
    cursor = conn.cursor()

    for i in range(0, total, BATCH_SIZE):
        batch = records[i:i + BATCH_SIZE]


        log_debug(f"Processing batch {i + 1} to {i + len(batch)} of {total}")  # DEBUG
        
        payload = [r["json"] for r in batch]
        payload_str = json.dumps(payload)

        retries = 0
        retry_delay = 5  # Seconds

        while retries < max_retries:
            try:
                # Submit batch to API
                resp = requests.post(API_ENDPOINT_LA, headers=headers, data=payload_str)
                raw_text = resp.text.strip()

                if resp.status_code == 200:
                    try:
                        # Parse JSON response
                        response_items = json.loads(raw_text)
                        if not isinstance(response_items, list):
                            print("Invalid API response: expected list, got", type(response_items).__name__)
                            for rec in batch:
                                update_api_failure(cursor, rec["person_id"], "Invalid JSON structure from API")
                            conn.commit()
                            break
                    except Exception:
                        # Response invalid or unreadable
                        print("Failed to parse JSON response. Logging all as failed.")
                        for rec in batch:
                            update_api_failure(cursor, rec["person_id"], f"Invalid JSON response: {raw_text}")
                        conn.commit()
                        break

                    if len(response_items) == len(batch):
                        for rec, item in zip(batch, response_items):
                            try:
                                # Parse UUID and timestamp
                                date_part, time_part, uuid = item.split("_")
                                timestamp = datetime.strptime(f"{date_part} {time_part}", "%Y-%m-%d %H:%M:%S.%f")
                            except Exception:
                                # Fallback to partial match and current time
                                uuid = item.split("_")[-1]
                                timestamp = datetime.now()

                            update_api_success(cursor, rec["person_id"], uuid, timestamp)

                        conn.commit()
                        break  # Exit retry loop

                    else:
                        # Response count mismatch
                        print(f"Mismatched response count to sent records: expected {len(batch)}, got {len(response_items)}")
                        for rec in batch:
                            update_api_failure(cursor, rec["person_id"], "Response count mismatch")
                        conn.commit()
                        break

                else:
                    status = resp.status_code
                    detail = resp.text

                    # Map known statuses to explanation
                    msg_map = {
                        204: "No content",
                        400: "Malformed Payload",
                        401: "Invalid API token",
                        403: "API access disallowed",
                        413: "Payload exceeds limit",
                        429: "Rate limit exceeded"
                    }

                    api_msg = msg_map.get(status, f"Unexpected Error: {status}")
                    print(f"API error {status}: {api_msg}")
                    print("API response (truncated):", detail[:250])

                    retryable = status in [401, 403, 429]

                    if not retryable or retries == max_retries - 1:
                        # Final failure
                        handle_batch_failure(cursor, batch, status, api_msg, detail)
                        conn.commit()
                        break
                    else:
                        # Wait and retry
                        print(f"Retrying in {retry_delay}s (retry {retries + 1}/{max_retries})...")
                        time.sleep(retry_delay)
                        retry_delay = min(30, retry_delay * 2)
                        retries += 1

            except Exception as e:
                # Network or unexpected exception
                print(f"Request failed: {e}")
                for rec in batch:
                    update_api_failure(cursor, rec["person_id"], str(e))
                conn.commit()
                break


# PEP 484 signature:
# def handle_batch_failure(cursor: pyodbc.Cursor, batch: List[Dict[str, Any]], status_code: int, error_message: str, error_detail: str) -> None:
@benchmark_section("handle_batch_failure()")  # Performance monitor
def handle_batch_failure(cursor, batch, status_code, error_message, error_detail):
    """
    Handle API batch failure by logging error messages per record

    Args:
        cursor: Active database cursor
        batch: List of records submitted in batch
        status_code: HTTP status returned by API
        error_message: General API error description
        error_detail: Raw response detail from API
    """
    # Extract failing record indexes from API response
    index_matches = re.findall(r"\[(\d+)\]", error_detail)
    failed_indexes = set(index_matches)

    for i, record in enumerate(batch):
        person_id = record["person_id"]

        # Assign message based on match to error index
        if str(i) in failed_indexes:
            msg = f"API error ({status_code}): {error_message} — {error_detail}"
        else:
            msg = f"API error ({status_code}): {error_message} — Record valid but batch failed"

        update_api_failure(cursor, person_id, msg)
        print(f"Logged API error for person_id {person_id}: {msg}")
