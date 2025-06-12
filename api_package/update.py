import json
from .config import TABLE_NAME
from .db import update_api_failure

def update_partial_payloads(conn):
    """
    Populate partial_json_payload for records with changes.

    Args:
        conn: Active DB connection
    """
    from .payloads import generate_partial_payload, generate_deletion_payload

    cursor = conn.cursor()

    cursor.execute(f"""
        SELECT person_id, row_state, json_payload, previous_json_payload
        FROM {TABLE_NAME}
        WHERE json_payload IS NOT NULL AND previous_json_payload IS NOT NULL
    """)

    updates = []

    for person_id, row_state, curr_raw, prev_raw in cursor.fetchall():
        try:
            curr = json.loads(curr_raw)
            prev = json.loads(prev_raw)

            if row_state.lower() == "deleted":
                partial = generate_deletion_payload(prev)
            elif row_state.lower() not in ("unchanged", "new"):
                partial = generate_partial_payload(curr, prev)
            else:
                continue

            json_out = json.dumps(partial, separators=(",", ":"), ensure_ascii=False).replace("'", "''")
            updates.append((json_out, person_id))

        except Exception as e:
            update_api_failure(cursor, person_id, f"Payload generation error: {e}")

    for json_out, pid in updates:
        cursor.execute(f"""
            UPDATE {TABLE_NAME}
            SET partial_json_payload = ?
            WHERE person_id = ?
        """, json_out, pid)

    conn.commit()