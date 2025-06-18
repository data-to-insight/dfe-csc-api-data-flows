import json
from api_package.config import TABLE_NAME, USE_PARTIAL_PAYLOAD


def update_api_success(cursor, person_id, uuid, timestamp):
    """
    Mark record as sent with API response and timestamp.

    Args:
        cursor: Active database cursor.
        person_id: Person identifier.
        uuid: API response reference.
        timestamp: Submission timestamp.
    """
    cursor.execute(f"""
        UPDATE {TABLE_NAME}
        SET submission_status='sent',
            api_response=?,
            submission_timestamp=?,
            previous_hash=current_hash,
            previous_json_payload=json_payload,
            row_state='unchanged'
        WHERE person_id = ?
    """, uuid, timestamp, person_id)


def update_api_failure(cursor, person_id, message):
    """
    Mark record as failed, store API error message.

    Args:
        cursor: Active database cursor.
        person_id: Person identifier.
        message: Error message from API or client.
    """
    cursor.execute(f"""
        UPDATE {TABLE_NAME}
        SET submission_status='error',
            api_response=?
        WHERE person_id = ?
    """, message[:500], person_id)


def get_pending_records(cursor):
    """
    Fetch pending/error records with non-empty payload.

    Args:
        cursor: Active database cursor.

    Returns:
        List of records with parsed JSON payload.
    """
    col = "partial_json_payload" if USE_PARTIAL_PAYLOAD else "json_payload"

    cursor.execute(f"""
        SELECT person_id, {col}
        FROM {TABLE_NAME}
        WHERE submission_status IN ('pending', 'error')
        AND {col} IS NOT NULL AND LTRIM(RTRIM({col})) <> ''
    """)

    results = []
    for pid, payload in cursor.fetchall():
        try:
            results.append({
                "person_id": pid,
                "json": json.loads(payload)
            })
        except:
            print(f"Skipping invalid JSON for person_id {pid}")

    return results