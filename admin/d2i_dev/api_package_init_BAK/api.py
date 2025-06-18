import time
import json
import logging
import requests
import re
from datetime import datetime

from api_package.config import API_ENDPOINT_LA
from api_package.db import update_api_success, update_api_failure


logger = logging.getLogger(__name__)


def get_oauth_token():
    """
    Request OAuth token using client credentials.

    Returns:
        Access token string, or None if request fails.
    """
    from .config import CLIENT_ID, CLIENT_SECRET, SCOPE, TOKEN_ENDPOINT

    payload = {
        "client_id": CLIENT_ID,
        "client_secret": CLIENT_SECRET,
        "scope": SCOPE,
        "grant_type": "client_credentials"
    }

    try:
        response = requests.post(TOKEN_ENDPOINT, data=payload)
        response.raise_for_status()
        token = response.json()["access_token"]
        logger.info("OAuth token retrieved.")
        logger.debug(f"Token (first 10 chars): {token[:10]}...")
        return token
    except Exception as e:
        logger.error(f"OAuth Token Error: {e}")
        return None


def handle_batch_failure(cursor, batch, status_code, error_message, error_detail):
    """
    Handle API batch failure by logging error messages per record.

    Args:
        cursor: Active database cursor.
        batch: List of records submitted in batch.
        status_code: HTTP status returned by API.
        error_message: General API error description.
        error_detail: Raw response detail from API.
    """
    index_matches = re.findall(r"\[(\d+)\]", error_detail)
    failed_indexes = set(index_matches)

    for i, record in enumerate(batch):
        person_id = record["person_id"]
        if str(i) in failed_indexes:
            msg = f"API error ({status_code}): {error_message} — {error_detail}"
        else:
            msg = f"API error ({status_code}): {error_message} — Record valid but batch failed"
        update_api_failure(cursor, person_id, msg)
        logger.warning(f"Logged API error for person_id {person_id}: {msg}")


def process_batches(records, headers, conn, max_retries=3):
    """
    Submit payloads in batches to API with retry logic.

    Args:
        records: List of dicts with 'person_id' and parsed JSON.
        headers: HTTP headers for API call.
        conn: Open database connection.
        max_retries: Retry count before marking as failure.
    """
    total = len(records)
    cursor = conn.cursor()

    from .config import BATCH_SIZE

    for i in range(0, total, BATCH_SIZE):
        batch = records[i:i + BATCH_SIZE]
        payload = [r["json"] for r in batch]
        payload_str = json.dumps(payload)

        retries = 0
        retry_delay = 5

        while retries < max_retries:
            try:
                resp = requests.post(API_ENDPOINT_LA, headers=headers, data=payload_str)
                raw_text = resp.text.strip()

                if resp.status_code == 200:
                    try:
                        response_items = json.loads(raw_text)
                    except Exception:
                        logger.error("Failed to parse JSON response. Logging all as failed.")
                        for rec in batch:
                            update_api_failure(cursor, rec["person_id"], f"Invalid JSON response: {raw_text}")
                        conn.commit()
                        break

                    if len(response_items) == len(batch):
                        for rec, item in zip(batch, response_items):
                            try:
                                date_part, time_part, uuid = item.split("_")
                                timestamp = datetime.strptime(f"{date_part} {time_part}", "%Y-%m-%d %H:%M:%S.%f")
                            except Exception:
                                uuid = item.split("_")[-1]
                                timestamp = datetime.now()
                            update_api_success(cursor, rec["person_id"], uuid, timestamp)
                        conn.commit()
                        break
                    else:
                        logger.warning(f"Mismatched response count: expected {len(batch)}, got {len(response_items)}")
                        for rec in batch:
                            update_api_failure(cursor, rec["person_id"], "Response count mismatch")
                        conn.commit()
                        break

                else:
                    status = resp.status_code
                    detail = resp.text
                    msg_map = {
                        204: "No content",
                        400: "Malformed Payload",
                        401: "Invalid API token",
                        403: "API access disallowed",
                        413: "Payload exceeds limit",
                        429: "Rate limit exceeded"
                    }
                    api_msg = msg_map.get(status, f"Unexpected Error: {status}")
                    logger.error(f"API error {status}: {api_msg}")

                    retryable = status in [401, 403, 429]
                    if not retryable or retries == max_retries - 1:
                        handle_batch_failure(cursor, batch, status, api_msg, detail)
                        conn.commit()
                        break
                    else:
                        logger.info(f"Retrying in {retry_delay}s (retry {retries + 1}/{max_retries})...")
                        time.sleep(retry_delay)
                        retry_delay = min(30, retry_delay * 2)
                        retries += 1

            except Exception as e:
                logger.exception(f"Request failed: {e}")
                for rec in batch:
                    update_api_failure(cursor, rec["person_id"], str(e))
                conn.commit()
                break
