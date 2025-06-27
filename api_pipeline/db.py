import json

from .config import TABLE_NAME, USE_PARTIAL_PAYLOAD
from .payload import generate_partial_payload, generate_deletion_payload
from .utils import benchmark_section


# ---- DATA ----
# PEP 484 signature:
# def update_partial_payloads(conn: pyodbc.Connection) -> None:
@benchmark_section("update_partial_payloads()")
def update_partial_payloads(conn):
    """
    Update table with generated partial JSON payloads

    Args:
        conn: Open database connection
    """
    cursor = conn.cursor()

    # Select rows with both current, previous JSON
    cursor.execute(f"""
        SELECT person_id, row_state, json_payload, previous_json_payload 
        FROM {TABLE_NAME}
        WHERE 
            json_payload IS NOT NULL
            AND previous_json_payload IS NOT NULL
            AND row_state <> 'unchanged'
    """)

    updates = []

    # ---- DIAGNOSTIC COUNTERS ----
    total_checked = 0
    skipped_due_to_state = 0
    skipped_due_to_equal_json = 0
    new_record_count = 0
    deletion_count = 0
    delta_count = 0
    error_count = 0

    # ---------------------------------------

    for person_id, row_state, curr_raw, prev_raw in cursor.fetchall():
        total_checked += 1
        try:
            # ---- EARLY EXIT: skip if new or unchanged ----
            if row_state.lower() == "unchanged":
                skipped_due_to_state += 1
                continue

            # ---- EARLY EXIT: skip if identical JSON strings ----
            if curr_raw == prev_raw:
                skipped_due_to_equal_json += 1
                continue

            curr = json.loads(curr_raw)  # Parse current JSON
            prev = json.loads(prev_raw)  # Parse previous JSON

            # Generate appropriate payload by row state
            if row_state.lower() == "deleted":
                partial = generate_deletion_payload(prev)
                deletion_count += 1
            else:
                partial = generate_partial_payload(curr, prev)
                delta_count += 1

            # Serialise partial and escape quotes for SQL
            json_out = json.dumps(partial, separators=(',', ':'), ensure_ascii=False).replace("'", "''")
            updates.append((json_out, person_id))

        except Exception as e:
            print(f"Error for {person_id}: {e}")
            error_count += 1

    # Apply updates to database
    for json_out, pid in updates:
        cursor.execute(f"""
            UPDATE {TABLE_NAME}
            SET partial_json_payload = ?
            WHERE person_id = ?
        """, json_out, pid)

    conn.commit()
    print(f"Updated {len(updates)} partial_json_payload records")

    # ---- DIAGNOSTIC OUTPUT ----
    print(f"[DIAG] Checked: {total_checked}")
    print(f"[DIAG] Skipped (state): {skipped_due_to_state}")
    print(f"[DIAG] Skipped (identical JSON): {skipped_due_to_equal_json}")
    print(f"[DIAG] Deleted payloads: {deletion_count}")
    print(f"[DIAG] Delta payloads: {delta_count}")
    print(f"[DIAG] Errors: {error_count}")
    # --------------------------------------



# PEP 484 signature:
# def get_pending_records(cursor: pyodbc.Cursor) -> List[Dict[str, Any]]:
@benchmark_section("get_pending_records()")  # Performance monitor
def get_pending_records(cursor):
    """
    Fetch pending/error records with non-empty payload

    Args:
        cursor: Active database cursor

    Returns:
        List of records with parsed JSON payload.
    """
    col = "partial_json_payload" if USE_PARTIAL_PAYLOAD else "json_payload"

    # Select valid rows by status and payload content
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
                "json": json.loads(payload)  # Parse JSON safely
            })
        except:
            print(f"Skipping invalid JSON for person_id {pid}")

    return results



# ---- DB UPDATES ----
# PEP 484 signature:
# def update_api_success(cursor: pyodbc.Cursor, person_id: str, uuid: str, timestamp: str) -> None:
@benchmark_section("update_api_success()")  # Performance monitor
def update_api_success(cursor, person_id, uuid, timestamp):
    """
    Mark record as sent with API response and timestamp

    Args:
        cursor: Active database cursor
        person_id: Person identifier
        uuid: API response reference
        timestamp: Submission timestamp
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



# PEP 484 signature:
# def update_api_failure(cursor: pyodbc.Cursor, person_id: str, message: str) -> None:
@benchmark_section("update_api_failure()")  # Performance monitor
def update_api_failure(cursor, person_id, message):
    """
    Mark record as failed, store API error message

    Args:
        cursor: Active database cursor
        person_id: Person identifier
        message: Error message from API or client
    """
    cursor.execute(f"""
        UPDATE {TABLE_NAME}
        SET submission_status='error',
            api_response=?
        WHERE person_id = ?
    """, message[:500], person_id)  # Truncate to max allowed size

